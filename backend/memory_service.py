import json
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta
from typing import Any, Optional

from database import execute_db, query_db


def _load_json(payload: Optional[str], default):
    if not payload:
        return default
    try:
        value = json.loads(payload)
    except (TypeError, json.JSONDecodeError):
        return default
    return value


def _dump_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False)


def today_memory_date() -> str:
    return date.today().isoformat()


def _normalize_text(value: Any) -> str:
    return str(value or "").strip()


def _normalize_list(value: Any) -> list:
    if isinstance(value, list):
        return value
    if value in (None, ""):
        return []
    return [value]


def _first_confidence(confidence_map: dict, *keys: str) -> float:
    for key in keys:
        raw = confidence_map.get(key)
        try:
            if raw is not None:
                return float(raw)
        except (TypeError, ValueError):
            continue
    return 0.0


def _load_clip_memory_row(row: dict) -> dict:
    actions = _normalize_list(_load_json(row.get("actions_json"), []))
    body_state = _load_json(row.get("body_state_json"), {})
    appearance = _load_json(row.get("appearance_json"), {})
    interaction = _load_json(row.get("interaction_json"), {})
    environment = _load_json(row.get("environment_json"), {})
    mood = _load_json(row.get("mood_hypothesis_json"), {})
    intent = _load_json(row.get("intent_hypothesis_json"), {})
    health = _normalize_list(_load_json(row.get("health_signals_json"), []))
    novelty = _normalize_list(_load_json(row.get("novelty_signals_json"), []))
    evidence = _load_json(row.get("evidence_json"), {})
    confidence = _load_json(row.get("confidence_json"), {})
    secondary_rules = _normalize_list(_load_json(row.get("secondary_rules_json"), []))

    return {
        **row,
        "actions": actions,
        "body_state": body_state if isinstance(body_state, dict) else {},
        "appearance": appearance if isinstance(appearance, dict) else {},
        "interaction": interaction if isinstance(interaction, dict) else {},
        "environment": environment if isinstance(environment, dict) else {},
        "mood_hypothesis": mood if isinstance(mood, dict) else {},
        "intent_hypothesis": intent if isinstance(intent, dict) else {},
        "health_signals": health,
        "novelty_signals": novelty,
        "evidence": evidence if isinstance(evidence, dict) else {},
        "confidence": confidence if isinstance(confidence, dict) else {},
        "secondary_rules": secondary_rules,
    }


def get_recent_clip_memories(pet_id: int, limit: int = 6) -> list[dict]:
    rows = query_db(
        """
        SELECT
            cm.*,
            cc.id AS clip_id,
            cc.rule_id,
            cc.primary_rule,
            cc.secondary_rules_json,
            cc.source_video_start_seconds,
            cc.source_video_end_seconds,
            cc.clip_url,
            cc.thumbnail_url,
            cc.router_hints_json,
            cc.analysis_status,
            cc.created_at AS clip_created_at
        FROM clip_memories cm
        INNER JOIN candidate_clips cc ON cc.id = cm.clip_id
        WHERE cc.pet_id = ?
        ORDER BY cc.created_at DESC, cc.source_video_start_seconds DESC
        LIMIT ?
        """,
        (pet_id, limit),
    )
    return [_load_clip_memory_row(row) for row in rows]


def get_daily_memory(pet_id: int, memory_date: Optional[str] = None) -> Optional[dict]:
    target_date = memory_date or today_memory_date()
    row = query_db(
        """
        SELECT *
        FROM daily_memories
        WHERE pet_id = ? AND memory_date = ?
        LIMIT 1
        """,
        (pet_id, target_date),
        one=True,
    )
    if not row:
        return None
    return _load_daily_memory_row(row)


def get_latest_daily_memory(pet_id: int) -> Optional[dict]:
    row = query_db(
        """
        SELECT *
        FROM daily_memories
        WHERE pet_id = ?
        ORDER BY memory_date DESC, updated_at DESC
        LIMIT 1
        """,
        (pet_id,),
        one=True,
    )
    if not row:
        return None
    return _load_daily_memory_row(row)


def get_profile_memories(pet_id: int, status: Optional[str] = None) -> list[dict]:
    query = "SELECT * FROM pet_profile_memories WHERE pet_id = ?"
    args: list[Any] = [pet_id]
    if status:
        query += " AND status = ?"
        args.append(status)
    query += " ORDER BY confidence DESC, last_confirmed_at DESC, created_at DESC"
    rows = query_db(query, tuple(args))
    result = []
    for row in rows:
        value = _load_json(row.get("value_json"), {})
        result.append({**row, "value": value})
    return result


def _load_daily_memory_row(row: dict) -> dict:
    return {
        **row,
        "timeline": _normalize_list(_load_json(row.get("timeline_json"), [])),
        "activity_counts": _load_json(row.get("activity_counts_json"), {}),
        "mood_overview": _load_json(row.get("mood_overview_json"), {}),
        "health_flags": _normalize_list(_load_json(row.get("health_flags_json"), [])),
        "appearance_of_day": _load_json(row.get("appearance_of_day_json"), {}),
        "social_summary": _load_json(row.get("social_summary_json"), {}),
        "change_vs_recent_baseline": _load_json(row.get("change_vs_recent_baseline_json"), {}),
    }


def _first_action_label(actions: list) -> str:
    for action in actions:
        if isinstance(action, dict):
            label = _normalize_text(action.get("label") or action.get("name") or action.get("type"))
        else:
            label = _normalize_text(action)
        if label:
            return label
    return ""


def _extract_waiting_metrics(clips: list[dict]) -> tuple[int, float]:
    waiting_count = 0
    waiting_seconds = 0.0
    for clip in clips:
        primary_rule = clip.get("primary_rule", "")
        actions = json.dumps(clip.get("actions", []), ensure_ascii=False)
        if primary_rule == "R08" or "等待" in actions or "守门" in actions:
            waiting_count += 1
            waiting_seconds += max(
                float(clip.get("source_video_end_seconds", 0)) - float(clip.get("source_video_start_seconds", 0)),
                0.0,
            )
    return waiting_count, waiting_seconds


def build_daily_memory_payload(
    pet_id: int,
    memory_date: str,
    clip_rows: list[dict],
    recent_daily_memories: Optional[list[dict]] = None,
) -> dict:
    loaded_clips = [_load_clip_memory_row(row) for row in clip_rows]
    timeline: list[dict] = []
    action_counter: Counter[str] = Counter()
    mood_counter: Counter[str] = Counter()
    zone_counter: Counter[str] = Counter()
    outfit_counter: Counter[str] = Counter()
    person_interaction_count = 0
    health_flags: list[dict] = []
    seen_health_flag_keys: set[str] = set()

    for clip in loaded_clips:
        primary_action = _first_action_label(clip["actions"])
        if primary_action:
            action_counter[primary_action] += 1

        mood_label = _normalize_text(
            clip["mood_hypothesis"].get("label")
            or clip["mood_hypothesis"].get("primary")
            or clip["mood_hypothesis"].get("name")
        )
        if mood_label:
            mood_counter[mood_label] += 1

        zone_label = _normalize_text(
            clip["environment"].get("zone_guess")
            or clip["environment"].get("primary_zone")
            or clip["environment"].get("location")
        )
        if zone_label:
            zone_counter[zone_label] += 1

        outfit_label = _normalize_text(
            clip["appearance"].get("outfit")
            or clip["appearance"].get("clothing")
            or clip["appearance"].get("wearing")
        )
        if outfit_label:
            outfit_counter[outfit_label] += 1

        if clip["interaction"].get("contains_person") or clip["interaction"].get("people"):
            person_interaction_count += 1

        for flag in clip["health_signals"]:
            if isinstance(flag, dict):
                title = _normalize_text(flag.get("title") or flag.get("label") or flag.get("name"))
                if not title:
                    continue
                key = f"{title}:{_normalize_text(flag.get('level'))}"
                if key in seen_health_flag_keys:
                    continue
                seen_health_flag_keys.add(key)
                health_flags.append(flag)

        timeline.append(
            {
                "clip_id": clip["clip_id"],
                "primary_rule": clip.get("primary_rule", ""),
                "summary": clip.get("summary", ""),
                "clip_url": clip.get("clip_url", ""),
                "thumbnail_url": clip.get("thumbnail_url", ""),
                "start_seconds": clip.get("source_video_start_seconds"),
                "end_seconds": clip.get("source_video_end_seconds"),
                "actions": clip["actions"],
                "mood": clip["mood_hypothesis"],
            }
        )

    timeline.sort(key=lambda item: (item.get("start_seconds") or 0, item.get("clip_id") or 0))
    waiting_count, waiting_seconds = _extract_waiting_metrics(loaded_clips)

    activity_counts = {
        "clip_count": len(loaded_clips),
        "actions": dict(action_counter),
        "waiting_count": waiting_count,
        "waiting_seconds": round(waiting_seconds, 1),
        "human_interaction_count": person_interaction_count,
    }

    top_mood = mood_counter.most_common(1)[0][0] if mood_counter else ""
    top_zone = zone_counter.most_common(1)[0][0] if zone_counter else ""
    top_outfit = outfit_counter.most_common(1)[0][0] if outfit_counter else ""
    highlight_actions = "、".join(label for label, _ in action_counter.most_common(3))
    summary_parts = []
    if highlight_actions:
        summary_parts.append(f"今天主要出现了{highlight_actions}")
    if top_mood:
        summary_parts.append(f"整体状态偏{top_mood}")
    if top_zone:
        summary_parts.append(f"最常待在{top_zone}")
    daily_summary = "，".join(summary_parts) + "。" if summary_parts else "今天还没有足够的片段记忆。"

    baseline_change = _build_change_vs_recent_baseline(
        pet_id=pet_id,
        current_memory_date=memory_date,
        current_counts=activity_counts,
        recent_daily_memories=recent_daily_memories,
    )

    if not health_flags:
        health_flags = [
            {
                "level": "normal",
                "title": "暂无明显异常",
                "message": "今天的片段里没有看到需要单独提醒的健康线索。",
            }
        ]

    return {
        "timeline": timeline,
        "activity_counts": activity_counts,
        "daily_summary": daily_summary,
        "mood_overview": {
            "primary": top_mood,
            "distribution": dict(mood_counter),
        },
        "health_flags": health_flags,
        "appearance_of_day": {
            "top_outfit": top_outfit,
            "distribution": dict(outfit_counter),
        },
        "social_summary": {
            "human_interaction_count": person_interaction_count,
            "top_zone": top_zone,
        },
        "change_vs_recent_baseline": baseline_change,
    }


def _build_change_vs_recent_baseline(
    *,
    pet_id: int,
    current_memory_date: str,
    current_counts: dict,
    recent_daily_memories: Optional[list[dict]] = None,
) -> dict:
    recent_rows = recent_daily_memories
    if recent_rows is None:
        recent_rows = query_db(
            """
            SELECT activity_counts_json
            FROM daily_memories
            WHERE pet_id = ? AND memory_date < ?
            ORDER BY memory_date DESC
            LIMIT 7
            """,
            (pet_id, current_memory_date),
        )

    if not recent_rows:
        return {
            "summary": "暂无足够历史基线",
            "action_deltas": {},
        }

    aggregate_counts: defaultdict[str, float] = defaultdict(float)
    samples = 0
    for row in recent_rows:
        counts = row if isinstance(row, dict) and "actions" in row else _load_json(row.get("activity_counts_json"), {})
        action_counts = counts.get("actions", {}) if isinstance(counts, dict) else {}
        if not isinstance(action_counts, dict):
            continue
        for action, count in action_counts.items():
            try:
                aggregate_counts[action] += float(count)
            except (TypeError, ValueError):
                continue
        samples += 1

    if samples == 0:
        return {
            "summary": "暂无足够历史基线",
            "action_deltas": {},
        }

    deltas: dict[str, float] = {}
    current_actions = current_counts.get("actions", {}) if isinstance(current_counts, dict) else {}
    for action, count in current_actions.items():
        baseline = aggregate_counts.get(action, 0.0) / samples
        deltas[action] = round(float(count) - baseline, 2)

    if not deltas:
        summary = "今天的行为和最近几天差不多。"
    else:
        action, delta = max(deltas.items(), key=lambda item: abs(item[1]))
        if delta > 0:
            summary = f"今天的{action}比最近几天更频繁。"
        elif delta < 0:
            summary = f"今天的{action}比最近几天更少。"
        else:
            summary = "今天的行为和最近几天差不多。"

    return {
        "summary": summary,
        "action_deltas": deltas,
    }


def upsert_daily_memory(pet_id: int, memory_date: str, payload: dict):
    execute_db(
        """
        INSERT INTO daily_memories (
            pet_id,
            memory_date,
            timeline_json,
            activity_counts_json,
            daily_summary,
            mood_overview_json,
            health_flags_json,
            appearance_of_day_json,
            social_summary_json,
            change_vs_recent_baseline_json,
            updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(pet_id, memory_date) DO UPDATE SET
            timeline_json = excluded.timeline_json,
            activity_counts_json = excluded.activity_counts_json,
            daily_summary = excluded.daily_summary,
            mood_overview_json = excluded.mood_overview_json,
            health_flags_json = excluded.health_flags_json,
            appearance_of_day_json = excluded.appearance_of_day_json,
            social_summary_json = excluded.social_summary_json,
            change_vs_recent_baseline_json = excluded.change_vs_recent_baseline_json,
            updated_at = CURRENT_TIMESTAMP
        """,
        (
            pet_id,
            memory_date,
            _dump_json(payload.get("timeline", [])),
            _dump_json(payload.get("activity_counts", {})),
            payload.get("daily_summary", ""),
            _dump_json(payload.get("mood_overview", {})),
            _dump_json(payload.get("health_flags", [])),
            _dump_json(payload.get("appearance_of_day", {})),
            _dump_json(payload.get("social_summary", {})),
            _dump_json(payload.get("change_vs_recent_baseline", {})),
        ),
    )


def _extract_profile_candidates(clips: list[dict]) -> dict[str, dict]:
    grouped: dict[str, dict] = {}
    for clip in clips:
        clip_date = _normalize_text(clip.get("clip_created_at"))[:10] or today_memory_date()
        confidence = clip.get("confidence", {})

        candidates: list[tuple[str, str, dict, float]] = []
        zone = _normalize_text(
            clip["environment"].get("zone_guess")
            or clip["environment"].get("primary_zone")
            or clip["environment"].get("location")
        )
        if zone:
            candidates.append(
                (
                    f"preferred_zone:{zone}",
                    "preferred_zone",
                    {"label": zone},
                    _first_confidence(confidence, "environment", "zone", "route"),
                )
            )

        action = _first_action_label(clip["actions"])
        if action:
            candidates.append(
                (
                    f"typical_action:{action}",
                    "typical_action",
                    {"label": action},
                    _first_confidence(confidence, "actions", "action"),
                )
            )

        outfit = _normalize_text(
            clip["appearance"].get("outfit")
            or clip["appearance"].get("clothing")
            or clip["appearance"].get("wearing")
        )
        if outfit:
            candidates.append(
                (
                    f"common_outfit:{outfit}",
                    "common_outfit",
                    {"label": outfit},
                    _first_confidence(confidence, "appearance", "outfit"),
                )
            )

        mood = _normalize_text(
            clip["mood_hypothesis"].get("label")
            or clip["mood_hypothesis"].get("primary")
            or clip["mood_hypothesis"].get("name")
        )
        if mood:
            candidates.append(
                (
                    f"typical_mood:{mood}",
                    "typical_mood",
                    {"label": mood},
                    _first_confidence(confidence, "mood", "mood_hypothesis"),
                )
            )

        for memory_key, memory_type, value, score in candidates:
            bucket = grouped.setdefault(
                memory_key,
                {
                    "memory_key": memory_key,
                    "memory_type": memory_type,
                    "value": value,
                    "scores": [],
                    "clip_dates": set(),
                    "clip_count": 0,
                    "last_confirmed_at": clip.get("clip_created_at") or datetime.now().isoformat(),
                    "first_confirmed_at": clip.get("clip_created_at") or datetime.now().isoformat(),
                },
            )
            bucket["scores"].append(score)
            bucket["clip_dates"].add(clip_date)
            bucket["clip_count"] += 1
            bucket["last_confirmed_at"] = max(bucket["last_confirmed_at"], clip.get("clip_created_at") or "")
            bucket["first_confirmed_at"] = min(bucket["first_confirmed_at"], clip.get("clip_created_at") or "")
    return grouped


def refresh_profile_memories(pet_id: int) -> list[dict]:
    clips = get_recent_clip_memories(pet_id, limit=500)
    grouped = _extract_profile_candidates(clips)
    now = datetime.now()
    active_keys: set[str] = set()
    upserted: list[dict] = []

    for memory_key, bucket in grouped.items():
        avg_confidence = (
            sum(score for score in bucket["scores"] if score is not None) / len(bucket["scores"])
            if bucket["scores"]
            else 0.0
        )
        evidence_days = len(bucket["clip_dates"])
        evidence_clips = bucket["clip_count"]
        qualifies = evidence_days >= 3 and evidence_clips >= 5 and avg_confidence >= 0.7
        status = "active" if qualifies else "stale"
        if qualifies:
            active_keys.add(memory_key)

        execute_db(
            """
            INSERT INTO pet_profile_memories (
                pet_id,
                memory_key,
                memory_type,
                value_json,
                confidence,
                evidence_days,
                evidence_clips,
                first_confirmed_at,
                last_confirmed_at,
                status,
                updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(pet_id, memory_key) DO UPDATE SET
                memory_type = excluded.memory_type,
                value_json = excluded.value_json,
                confidence = excluded.confidence,
                evidence_days = excluded.evidence_days,
                evidence_clips = excluded.evidence_clips,
                first_confirmed_at = excluded.first_confirmed_at,
                last_confirmed_at = excluded.last_confirmed_at,
                status = excluded.status,
                updated_at = CURRENT_TIMESTAMP
            """,
            (
                pet_id,
                memory_key,
                bucket["memory_type"],
                _dump_json(bucket["value"]),
                round(avg_confidence, 3),
                evidence_days,
                evidence_clips,
                bucket["first_confirmed_at"] or now.isoformat(),
                bucket["last_confirmed_at"] or now.isoformat(),
                status,
            ),
        )
        upserted.append(
            {
                "memory_key": memory_key,
                "memory_type": bucket["memory_type"],
                "value": bucket["value"],
                "confidence": round(avg_confidence, 3),
                "evidence_days": evidence_days,
                "evidence_clips": evidence_clips,
                "status": status,
            }
        )

    stale_before = (now - timedelta(days=14)).isoformat()
    execute_db(
        """
        UPDATE pet_profile_memories
        SET status = 'stale',
            updated_at = CURRENT_TIMESTAMP
        WHERE pet_id = ?
          AND last_confirmed_at IS NOT NULL
          AND last_confirmed_at < ?
        """,
        (pet_id, stale_before),
    )

    if active_keys:
        placeholders = ",".join("?" for _ in active_keys)
        execute_db(
            f"""
            UPDATE pet_profile_memories
            SET status = 'stale',
                updated_at = CURRENT_TIMESTAMP
            WHERE pet_id = ?
              AND memory_key NOT IN ({placeholders})
              AND last_confirmed_at IS NOT NULL
              AND last_confirmed_at >= ?
            """,
            (pet_id, *sorted(active_keys), stale_before),
        )
    else:
        execute_db(
            """
            UPDATE pet_profile_memories
            SET status = 'stale',
                updated_at = CURRENT_TIMESTAMP
            WHERE pet_id = ?
            """,
            (pet_id,),
        )

    return upserted


def build_memory_prompt_context(pet_id: int, clip_limit: int = 5) -> dict:
    recent_clips = get_recent_clip_memories(pet_id, limit=clip_limit)
    daily_memory = get_daily_memory(pet_id) or get_latest_daily_memory(pet_id)
    active_profiles = get_profile_memories(pet_id, status="active")

    clip_lines = []
    for clip in recent_clips:
        start_seconds = clip.get("source_video_start_seconds", 0) or 0
        end_seconds = clip.get("source_video_end_seconds", 0) or 0
        clip_lines.append(
            f"- {start_seconds:.1f}s-{end_seconds:.1f}s：{clip.get('summary', '')}"
        )

    daily_text = ""
    daily_counts = {}
    health_flags = []
    if daily_memory:
        daily_text = daily_memory.get("daily_summary", "")
        daily_counts = daily_memory.get("activity_counts", {})
        health_flags = daily_memory.get("health_flags", [])

    profile_lines = []
    for memory in active_profiles[:8]:
        label = _normalize_text(memory["value"].get("label"))
        if label:
            profile_lines.append(f"- {memory['memory_type']}：{label}")

    return {
        "recent_clip_lines": clip_lines,
        "daily_memory": daily_memory,
        "daily_summary": daily_text,
        "daily_counts": daily_counts,
        "health_flags": health_flags,
        "profile_lines": profile_lines,
    }
