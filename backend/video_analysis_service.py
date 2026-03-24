import json
import os
import uuid
from datetime import date, datetime, timedelta
from typing import Optional

from database import execute_db, query_db
from memory_service import (
    build_daily_memory_payload,
    refresh_profile_memories,
    today_memory_date,
    upsert_daily_memory,
)
from video_processor import (
    CLIPS_DIR,
    capture_frame_at,
    clip_video_segment,
    detect_candidate_segments,
    extract_representative_frames,
    get_video_duration,
)
from vlm_service import analyze_clip_memory, classify_clip_route_hints

STEP_DEFINITIONS = [
    ("video_saved", "视频已保存"),
    ("coarse_scan_completed", "粗扫完成"),
    ("candidate_clips_created", "候选片段已生成"),
    ("route_hints_completed", "路由提示完成"),
    ("clip_memories_completed", "片段记忆完成"),
    ("daily_memory_completed", "日记忆完成"),
    ("profile_memory_completed", "长期画像完成"),
    ("events_projected", "兼容事件投影完成"),
    ("completed", "处理完成"),
]

RULE_LABELS = {
    "R01": "进入画面",
    "R03": "高运动爆发",
    "R05": "食盆停留候选",
    "R06": "水盆停留候选",
    "R08": "门口等待候选",
    "R10": "长时间静止休息",
    "R12": "人宠互动候选",
    "R18": "未知但值得看",
}


def _now_iso() -> str:
    return datetime.now().isoformat()


def _relative_frame_url(frame_path: str) -> str:
    return f"/frames/{os.path.basename(frame_path)}" if frame_path else ""


def _build_step_states(
    *,
    completed: Optional[set[str]] = None,
    running: Optional[str] = None,
    failed: Optional[str] = None,
) -> list[dict]:
    completed = completed or set()
    states = []
    for step_id, title in STEP_DEFINITIONS:
        state = "pending"
        if step_id in completed:
            state = "completed"
        elif running == step_id:
            state = "running"
        elif failed == step_id:
            state = "failed"
        states.append({"id": step_id, "title": title, "state": state})
    return states


def create_video_analysis_job(
    *,
    camera_id: int,
    pet_id: int,
    source_video_path: str,
    source_video_name: str,
    demo_video_url: str,
) -> str:
    job_id = uuid.uuid4().hex
    execute_db(
        """
        INSERT INTO video_analysis_jobs (
            job_id,
            camera_id,
            pet_id,
            status,
            error_message,
            source_video_path,
            source_video_name,
            progress_step,
            created_at
        )
        VALUES (?, ?, ?, 'queued', '', ?, ?, 'queued', CURRENT_TIMESTAMP)
        """,
        (job_id, camera_id, pet_id, source_video_path, source_video_name),
    )
    _upsert_debug_snapshot(
        camera_id=camera_id,
        pet_id=pet_id,
        job_id=job_id,
        demo_video_name=source_video_name,
        demo_video_url=demo_video_url,
        context_summary="视频已接收，正在后台分析候选片段与宠物记忆。",
        processing_status="queued",
        step_states=_build_step_states(running="video_saved"),
        frames=[],
        candidate_clips=[],
    )
    return job_id


def process_video_analysis_job(job_id: str):
    job = query_db(
        """
        SELECT job_id, camera_id, pet_id, source_video_path, source_video_name
        FROM video_analysis_jobs
        WHERE job_id = ?
        LIMIT 1
        """,
        (job_id,),
        one=True,
    )
    if not job:
        return

    camera_id = int(job["camera_id"])
    pet_id = int(job["pet_id"])
    source_video_path = job["source_video_path"]
    source_video_name = job["source_video_name"]
    camera = query_db("SELECT demo_video_path FROM cameras WHERE id = ?", (camera_id,), one=True) or {}
    demo_video_url = (camera.get("demo_video_path") or "").strip()

    try:
        execute_db(
            """
            UPDATE video_analysis_jobs
            SET status = 'running',
                progress_step = 'coarse_scan_completed',
                started_at = CURRENT_TIMESTAMP
            WHERE job_id = ?
            """,
            (job_id,),
        )

        segments = detect_candidate_segments(source_video_path)
        _upsert_debug_snapshot(
            camera_id=camera_id,
            pet_id=pet_id,
            job_id=job_id,
            demo_video_name=source_video_name,
            demo_video_url=demo_video_url,
            context_summary="已完成粗扫，正在裁剪候选片段。",
            processing_status="running",
            step_states=_build_step_states(
                completed={"video_saved", "coarse_scan_completed"},
                running="candidate_clips_created",
            ),
            frames=[],
            candidate_clips=[],
        )

        _clear_previous_analysis(camera_id=camera_id, pet_id=pet_id)

        clip_debug_payloads: list[dict] = []
        debug_frames: list[dict] = []
        for index, segment in enumerate(segments, start=1):
            clip_record = _analyze_segment(
                camera_id=camera_id,
                pet_id=pet_id,
                job_id=job_id,
                segment=segment,
                source_video_path=source_video_path,
                sequence=index,
            )
            clip_debug_payloads.append(clip_record["candidate_debug"])
            debug_frames.append(clip_record["frame_debug"])

        _upsert_debug_snapshot(
            camera_id=camera_id,
            pet_id=pet_id,
            job_id=job_id,
            demo_video_name=source_video_name,
            demo_video_url=demo_video_url,
            context_summary="片段路由和结构化记忆已生成，正在聚合日记忆。",
            processing_status="running",
            step_states=_build_step_states(
                completed={
                    "video_saved",
                    "coarse_scan_completed",
                    "candidate_clips_created",
                    "route_hints_completed",
                    "clip_memories_completed",
                },
                running="daily_memory_completed",
            ),
            frames=debug_frames,
            candidate_clips=clip_debug_payloads,
        )

        daily_payload = _refresh_daily_memory(
            pet_id=pet_id,
            memory_date=today_memory_date(),
        )
        profiles = refresh_profile_memories(pet_id)
        projected_events = _project_events(camera_id=camera_id, pet_id=pet_id)
        try:
            from dialogue_engine import invalidate_event_cache

            invalidate_event_cache(pet_id)
        except Exception:
            pass

        context_summary = daily_payload.get("daily_summary", "")
        if not context_summary:
            context_summary = f"已识别 {len(projected_events)} 段宠物片段记忆。"

        execute_db(
            """
            UPDATE video_analysis_jobs
            SET status = 'completed',
                progress_step = 'completed',
                completed_at = CURRENT_TIMESTAMP
            WHERE job_id = ?
            """,
            (job_id,),
        )
        execute_db(
            "UPDATE cameras SET status = 'ready' WHERE id = ?",
            (camera_id,),
        )
        _upsert_debug_snapshot(
            camera_id=camera_id,
            pet_id=pet_id,
            job_id=job_id,
            demo_video_name=source_video_name,
            demo_video_url=demo_video_url,
            context_summary=context_summary,
            processing_status="completed",
            step_states=_build_step_states(
                completed={step_id for step_id, _ in STEP_DEFINITIONS},
            ),
            frames=debug_frames,
            candidate_clips=clip_debug_payloads,
        )
    except Exception as exc:
        execute_db(
            """
            UPDATE video_analysis_jobs
            SET status = 'failed',
                progress_step = 'failed',
                error_message = ?,
                completed_at = CURRENT_TIMESTAMP
            WHERE job_id = ?
            """,
            (str(exc), job_id),
        )
        execute_db(
            "UPDATE cameras SET status = 'error' WHERE id = ?",
            (camera_id,),
        )
        _upsert_debug_snapshot(
            camera_id=camera_id,
            pet_id=pet_id,
            job_id=job_id,
            demo_video_name=source_video_name,
            demo_video_url=demo_video_url,
            context_summary=f"分析失败：{exc}",
            processing_status="failed",
            step_states=_build_step_states(
                completed={"video_saved"},
                failed="clip_memories_completed",
            ),
            frames=[],
            candidate_clips=[],
        )
        raise


def build_debug_payload(camera_id: int) -> Optional[dict]:
    camera = query_db(
        "SELECT id, name, status, demo_video_path, demo_video_name FROM cameras WHERE id = ?",
        (camera_id,),
        one=True,
    )
    if not camera:
        return None

    snapshot = query_db(
        """
        SELECT camera_id, pet_id, job_id, demo_video_name, demo_video_url, context_summary,
               processing_status, step_states_json, frames_json, candidate_clips_json, updated_at
        FROM video_analysis_debug_snapshots
        WHERE camera_id = ?
        """,
        (camera_id,),
        one=True,
    )
    events = query_db(
        """
        SELECT id, pet_id, event_type, description, timestamp, duration_seconds,
               video_start_seconds, video_end_seconds, frame_path
        FROM events
        WHERE camera_id = ?
        ORDER BY timestamp DESC
        """,
        (camera_id,),
    )

    if not snapshot:
        return {
            "camera_id": camera_id,
            "pet_id": None,
            "job_id": "",
            "demo_video_name": camera.get("demo_video_name") or "",
            "demo_video_url": camera.get("demo_video_path") or "",
            "context_summary": "",
            "processing_status": "not_available",
            "step_states": [],
            "frames": [],
            "candidate_clips": [],
            "events": [_serialize_debug_event(row) for row in events],
            "last_updated_at": None,
        }

    return {
        "camera_id": snapshot["camera_id"],
        "pet_id": snapshot.get("pet_id"),
        "job_id": snapshot.get("job_id", ""),
        "demo_video_name": snapshot.get("demo_video_name", ""),
        "demo_video_url": snapshot.get("demo_video_url", ""),
        "context_summary": snapshot.get("context_summary", ""),
        "processing_status": snapshot.get("processing_status", "not_available"),
        "step_states": _load_json_list(snapshot.get("step_states_json")),
        "frames": _load_json_list(snapshot.get("frames_json")),
        "candidate_clips": _load_json_list(snapshot.get("candidate_clips_json")),
        "events": [_serialize_debug_event(row) for row in events],
        "last_updated_at": snapshot.get("updated_at"),
    }


def build_memory_debug_payload(pet_id: int) -> dict:
    from memory_service import get_latest_daily_memory, get_profile_memories

    daily_memory = get_latest_daily_memory(pet_id)
    return {
        "pet_id": pet_id,
        "daily_memory": daily_memory or {},
        "profile_memories": {
            "active": get_profile_memories(pet_id, status="active"),
            "stale": get_profile_memories(pet_id, status="stale"),
        },
    }


def _refresh_daily_memory(pet_id: int, memory_date: str) -> dict:
    clip_rows = query_db(
        """
        SELECT
            cm.*,
            cc.id AS clip_id,
            cc.primary_rule,
            cc.secondary_rules_json,
            cc.source_video_start_seconds,
            cc.source_video_end_seconds,
            cc.clip_url,
            cc.thumbnail_url,
            cc.created_at AS clip_created_at
        FROM clip_memories cm
        INNER JOIN candidate_clips cc ON cc.id = cm.clip_id
        WHERE cc.pet_id = ?
        ORDER BY cc.source_video_start_seconds ASC, cc.created_at ASC
        """,
        (pet_id,),
    )
    recent_daily_memories = query_db(
        """
        SELECT activity_counts_json
        FROM daily_memories
        WHERE pet_id = ? AND memory_date < ?
        ORDER BY memory_date DESC
        LIMIT 7
        """,
        (pet_id, memory_date),
    )
    payload = build_daily_memory_payload(
        pet_id=pet_id,
        memory_date=memory_date,
        clip_rows=clip_rows,
        recent_daily_memories=recent_daily_memories,
    )
    upsert_daily_memory(pet_id, memory_date, payload)
    return payload


def _analyze_segment(
    *,
    camera_id: int,
    pet_id: int,
    job_id: str,
    segment: dict,
    source_video_path: str,
    sequence: int,
) -> dict:
    start_seconds = float(segment["start_seconds"])
    end_seconds = float(segment["end_seconds"])
    signal_summary = segment.get("signal_summary", {})
    clip_url = clip_video_segment(source_video_path, start_seconds, end_seconds)
    clip_path = os.path.join(CLIPS_DIR, os.path.basename(clip_url))
    thumbnail_path = capture_frame_at(
        source_video_path,
        at_seconds=(start_seconds + end_seconds) / 2.0,
        prefix="frame_candidate_thumb",
    )
    frame_paths = extract_representative_frames(
        source_video_path,
        start_seconds=start_seconds,
        end_seconds=end_seconds,
        num_frames=4,
        prefix="frame_candidate",
    )
    route_hints = classify_clip_route_hints(frame_paths, signal_summary=signal_summary)
    primary_rule, secondary_rules = _assign_rules(route_hints, signal_summary)

    clip_id = execute_db(
        """
        INSERT INTO candidate_clips (
            camera_id,
            pet_id,
            job_id,
            rule_id,
            primary_rule,
            secondary_rules_json,
            source_video_start_seconds,
            source_video_end_seconds,
            clip_url,
            thumbnail_url,
            router_hints_json,
            analysis_status
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'running')
        """,
        (
            camera_id,
            pet_id,
            job_id,
            primary_rule,
            RULE_LABELS.get(primary_rule, primary_rule),
            json.dumps(secondary_rules, ensure_ascii=False),
            start_seconds,
            end_seconds,
            clip_url,
            _relative_frame_url(thumbnail_path),
            json.dumps(route_hints, ensure_ascii=False),
        ),
    )

    try:
        memory = analyze_clip_memory(
            clip_path,
            route_hints=route_hints,
            frame_paths=frame_paths,
            signal_summary=signal_summary,
        )
    except Exception:
        memory = _build_fallback_memory(route_hints, signal_summary, start_seconds, end_seconds)

    execute_db(
        """
        INSERT INTO clip_memories (
            clip_id,
            summary,
            actions_json,
            body_state_json,
            appearance_json,
            interaction_json,
            environment_json,
            mood_hypothesis_json,
            intent_hypothesis_json,
            health_signals_json,
            novelty_signals_json,
            evidence_json,
            confidence_json,
            updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        """,
        (
            clip_id,
            memory.get("clip_summary", ""),
            json.dumps(memory.get("actions", []), ensure_ascii=False),
            json.dumps(memory.get("body_state", {}), ensure_ascii=False),
            json.dumps(memory.get("appearance", {}), ensure_ascii=False),
            json.dumps(memory.get("companions", {}), ensure_ascii=False),
            json.dumps(memory.get("environment", {}), ensure_ascii=False),
            json.dumps(memory.get("mood_hypothesis", {}), ensure_ascii=False),
            json.dumps(memory.get("intent_hypothesis", {}), ensure_ascii=False),
            json.dumps(memory.get("health_signals", []), ensure_ascii=False),
            json.dumps(memory.get("novelty_signals", []), ensure_ascii=False),
            json.dumps(memory.get("evidence", {}), ensure_ascii=False),
            json.dumps(memory.get("confidence", {}), ensure_ascii=False),
        ),
    )

    execute_db(
        "UPDATE candidate_clips SET analysis_status = 'completed' WHERE id = ?",
        (clip_id,),
    )

    event_type, description = _project_event_shape(primary_rule, memory)
    return {
        "candidate_debug": {
            "id": clip_id,
            "sequence": sequence,
            "rule_id": primary_rule,
            "primary_rule": RULE_LABELS.get(primary_rule, primary_rule),
            "secondary_rules": secondary_rules,
            "clip_url": clip_url,
            "thumbnail_url": _relative_frame_url(thumbnail_path),
            "start_seconds": start_seconds,
            "end_seconds": end_seconds,
            "analysis_status": "completed",
            "summary": memory.get("clip_summary", ""),
            "event_type": event_type,
        },
        "frame_debug": {
            "sequence": sequence,
            "frame_url": _relative_frame_url(thumbnail_path),
            "video_seconds": round(start_seconds, 1),
            "video_time_text": _format_video_seconds(start_seconds),
            "event_type": event_type,
            "description": description,
        },
    }


def _assign_rules(route_hints: dict, signal_summary: dict) -> tuple[str, list[str]]:
    zone_guess = str(route_hints.get("zone_guess", "") or "").lower()
    behavior_tags = {str(tag).lower() for tag in route_hints.get("behavior_tags", [])}
    body_state_hint = str(route_hints.get("body_state_hint", "") or "").lower()
    secondary: list[str] = []

    if route_hints.get("contains_person"):
        primary = "R12"
    elif zone_guess in {"food", "food_area", "feeder", "bowl_food"} or {"eating", "food"} & behavior_tags:
        primary = "R05"
    elif zone_guess in {"water", "water_area", "water_bowl", "drinking_fountain"} or {"drinking", "water"} & behavior_tags:
        primary = "R06"
    elif zone_guess in {"door", "entry", "entrance"} or {"waiting", "door"} & behavior_tags:
        primary = "R08"
    elif body_state_hint in {"resting", "sleeping"} or signal_summary.get("rest_candidate"):
        primary = "R10"
    elif signal_summary.get("max_motion", 0.0) >= 0.018 or signal_summary.get("max_speed", 0.0) >= 0.12 or {"playing", "running", "jumping", "zoomies"} & behavior_tags:
        primary = "R03"
    elif route_hints.get("pet_visible") and signal_summary.get("max_edge_bias", 0.0) >= 0.5 and signal_summary.get("max_novelty", 0.0) >= 0.01:
        primary = "R01"
    else:
        primary = "R18"

    for candidate in ("R12", "R05", "R06", "R08", "R10", "R03", "R01"):
        if candidate == primary:
            continue
        if candidate == "R12" and route_hints.get("contains_person"):
            secondary.append(candidate)
        elif candidate == "R05" and (zone_guess in {"food", "food_area", "feeder", "bowl_food"} or "eating" in behavior_tags):
            secondary.append(candidate)
        elif candidate == "R06" and (zone_guess in {"water", "water_area", "water_bowl", "drinking_fountain"} or "drinking" in behavior_tags):
            secondary.append(candidate)
        elif candidate == "R08" and (zone_guess in {"door", "entry", "entrance"} or "waiting" in behavior_tags):
            secondary.append(candidate)
        elif candidate == "R10" and body_state_hint in {"resting", "sleeping"}:
            secondary.append(candidate)
        elif candidate == "R03" and (
            signal_summary.get("max_motion", 0.0) >= 0.018 or {"playing", "running", "jumping", "zoomies"} & behavior_tags
        ):
            secondary.append(candidate)
        elif candidate == "R01" and route_hints.get("pet_visible") and signal_summary.get("max_edge_bias", 0.0) >= 0.5:
            secondary.append(candidate)

    return primary, secondary


def _build_fallback_memory(route_hints: dict, signal_summary: dict, start_seconds: float, end_seconds: float) -> dict:
    behavior_tags = route_hints.get("behavior_tags", [])
    zone_guess = route_hints.get("zone_guess", "unknown")
    summary = route_hints.get("reason") or "监控中捕捉到一段需要后续确认的宠物片段。"
    novelty = []
    if signal_summary.get("max_novelty", 0.0) >= 0.01:
        novelty.append({"label": "画面变化明显", "confidence": 0.5})
    return {
        "clip_summary": summary,
        "actions": [{"label": str(tag), "confidence": 0.45} for tag in behavior_tags[:3]],
        "body_state": {"state": route_hints.get("body_state_hint", "unknown")},
        "appearance": {},
        "companions": {"contains_person": bool(route_hints.get("contains_person"))},
        "environment": {"zone_guess": zone_guess},
        "mood_hypothesis": {"label": "unknown", "is_hypothesis": True},
        "intent_hypothesis": {"label": "unknown", "is_hypothesis": True},
        "health_signals": [],
        "novelty_signals": novelty,
        "evidence": {
            "route_hints": route_hints,
            "signal_summary": signal_summary,
            "time_range": {"start_seconds": start_seconds, "end_seconds": end_seconds},
        },
        "confidence": {
            "analysis": 0.35,
            "route": 0.45,
            "input_mode": "fallback",
        },
    }


def _project_events(camera_id: int, pet_id: int) -> list[dict]:
    execute_db("DELETE FROM events WHERE camera_id = ?", (camera_id,))
    rows = query_db(
        """
        SELECT
            cm.summary,
            cm.actions_json,
            cm.body_state_json,
            cc.id AS clip_id,
            cc.primary_rule,
            cc.source_video_start_seconds,
            cc.source_video_end_seconds,
            cc.clip_url,
            cc.thumbnail_url
        FROM clip_memories cm
        INNER JOIN candidate_clips cc ON cc.id = cm.clip_id
        WHERE cc.camera_id = ? AND cc.pet_id = ?
        ORDER BY cc.source_video_start_seconds ASC
        """,
        (camera_id, pet_id),
    )

    duration = 0.0
    camera = query_db("SELECT demo_video_path FROM cameras WHERE id = ?", (camera_id,), one=True) or {}
    if camera.get("demo_video_path"):
        source_path = _resolve_upload_path(camera["demo_video_path"])
        if os.path.exists(source_path):
            duration = get_video_duration(source_path)

    events = []
    for row in rows:
        memory = {
            "clip_summary": row.get("summary", ""),
            "actions": _load_json_list(row.get("actions_json")),
            "body_state": _load_json_object(row.get("body_state_json")),
        }
        event_type, description = _project_event_shape(row.get("primary_rule", "R18"), memory)
        timestamp = _build_event_timestamp(float(row.get("source_video_start_seconds") or 0.0), duration)
        event_id = execute_db(
            """
            INSERT INTO events (
                camera_id,
                pet_id,
                timestamp,
                event_type,
                duration_seconds,
                video_start_seconds,
                video_end_seconds,
                description,
                clip_url,
                frame_path
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                camera_id,
                pet_id,
                timestamp.isoformat(),
                event_type,
                max(float(row.get("source_video_end_seconds") or 0.0) - float(row.get("source_video_start_seconds") or 0.0), 0.0),
                row.get("source_video_start_seconds"),
                row.get("source_video_end_seconds"),
                description,
                row.get("clip_url", ""),
                row.get("thumbnail_url", ""),
            ),
        )
        events.append(
            {
                "id": event_id,
                "event_type": event_type,
                "description": description,
                "timestamp": timestamp.isoformat(),
            }
        )
    return events


def _project_event_shape(primary_rule: str, memory: dict) -> tuple[str, str]:
    summary = (memory.get("clip_summary") or "").strip() or "记录到一段宠物片段"
    body_state = memory.get("body_state", {}) if isinstance(memory.get("body_state"), dict) else {}
    actions_text = json.dumps(memory.get("actions", []), ensure_ascii=False)

    if primary_rule == "R05":
        return "eating", summary
    if primary_rule == "R06":
        return "drinking", summary
    if primary_rule == "R08":
        return "waiting", summary
    if primary_rule == "R10":
        body_label = str(body_state.get("state", "") or "").lower()
        return ("sleeping" if body_label == "sleeping" else "resting"), summary
    if primary_rule == "R03":
        return ("zoomies" if "跑" in actions_text or "zoom" in actions_text.lower() else "playing"), summary
    if primary_rule == "R12":
        return ("playing" if "玩" in actions_text or "互动" in summary else "other"), summary
    if primary_rule == "R01":
        return "other", summary
    return "other", summary


def _clear_previous_analysis(*, camera_id: int, pet_id: int):
    clip_rows = query_db(
        "SELECT id FROM candidate_clips WHERE camera_id = ? OR pet_id = ?",
        (camera_id, pet_id),
    )
    for row in clip_rows:
        execute_db("DELETE FROM clip_memories WHERE clip_id = ?", (row["id"],))
    execute_db("DELETE FROM candidate_clips WHERE camera_id = ? OR pet_id = ?", (camera_id, pet_id))
    execute_db("DELETE FROM daily_memories WHERE pet_id = ?", (pet_id,))
    execute_db("DELETE FROM pet_profile_memories WHERE pet_id = ?", (pet_id,))
    execute_db("DELETE FROM events WHERE camera_id = ?", (camera_id,))


def _upsert_debug_snapshot(
    *,
    camera_id: int,
    pet_id: int,
    job_id: str,
    demo_video_name: str,
    demo_video_url: str,
    context_summary: str,
    processing_status: str,
    step_states: list[dict],
    frames: list[dict],
    candidate_clips: list[dict],
):
    execute_db(
        """
        INSERT INTO video_analysis_debug_snapshots (
            camera_id,
            pet_id,
            job_id,
            demo_video_name,
            demo_video_url,
            context_summary,
            processing_status,
            step_states_json,
            frames_json,
            candidate_clips_json,
            updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(camera_id) DO UPDATE SET
            pet_id = excluded.pet_id,
            job_id = excluded.job_id,
            demo_video_name = excluded.demo_video_name,
            demo_video_url = excluded.demo_video_url,
            context_summary = excluded.context_summary,
            processing_status = excluded.processing_status,
            step_states_json = excluded.step_states_json,
            frames_json = excluded.frames_json,
            candidate_clips_json = excluded.candidate_clips_json,
            updated_at = CURRENT_TIMESTAMP
        """,
        (
            camera_id,
            pet_id,
            job_id,
            demo_video_name,
            demo_video_url,
            context_summary,
            processing_status,
            json.dumps(step_states, ensure_ascii=False),
            json.dumps(frames, ensure_ascii=False),
            json.dumps(candidate_clips, ensure_ascii=False),
        ),
    )


def _build_event_timestamp(seconds_from_start: float, max_seconds: float) -> datetime:
    now = datetime.now()
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    if max_seconds > 0:
        base_time = max(today_start, now - timedelta(seconds=max_seconds))
    else:
        base_time = today_start
    return base_time + timedelta(seconds=seconds_from_start)


def _format_video_seconds(seconds: float) -> str:
    total_seconds = max(int(seconds), 0)
    minutes = total_seconds // 60
    remaining_seconds = total_seconds % 60
    return f"{minutes:02d}:{remaining_seconds:02d}"


def _load_json_list(payload: Optional[str]) -> list[dict]:
    try:
        value = json.loads(payload or "[]")
    except json.JSONDecodeError:
        return []
    return value if isinstance(value, list) else []


def _load_json_object(payload: Optional[str]) -> dict:
    try:
        value = json.loads(payload or "{}")
    except json.JSONDecodeError:
        return {}
    return value if isinstance(value, dict) else {}


def _resolve_upload_path(media_url: str) -> str:
    if not media_url.startswith("/media/"):
        return media_url
    uploads_root = os.path.realpath(os.path.join(os.path.dirname(__file__), "uploads"))
    relative_path = media_url.removeprefix("/media/")
    return os.path.realpath(os.path.join(uploads_root, relative_path))


def _serialize_debug_event(event: dict) -> dict:
    return {
        "id": event.get("id"),
        "event_type": event.get("event_type", ""),
        "description": event.get("description", ""),
        "timestamp": event.get("timestamp", ""),
        "duration_seconds": event.get("duration_seconds", 0),
        "video_start_seconds": event.get("video_start_seconds"),
        "video_end_seconds": event.get("video_end_seconds"),
        "frame_url": event.get("frame_path", ""),
    }
