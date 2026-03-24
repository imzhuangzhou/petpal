import logging
import json
import os
import shutil
import time
import uuid
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, File, Form, HTTPException, UploadFile

from database import execute_db, query_db
from dialogue_engine import invalidate_event_cache
from video_analysis_service import (
    build_clip_debug_payload,
    build_debug_payload,
    build_memory_debug_payload,
    create_video_analysis_job,
    process_video_analysis_job,
)
from video_processor import extract_uniform_frames
from vlm_service import (
    DASHSCOPE_API_KEY,
    classify_action,
    describe_frame,
    generate_pet_avatar,
)

router = APIRouter(prefix="/api", tags=["media"])

BACKEND_DIR = os.path.dirname(os.path.dirname(__file__))
UPLOADS_DIR = os.path.join(BACKEND_DIR, "uploads")
VIDEO_UPLOADS_DIR = os.path.join(UPLOADS_DIR, "videos")
AUDIO_UPLOADS_DIR = os.path.join(UPLOADS_DIR, "audio")
IMAGE_UPLOADS_DIR = os.path.join(UPLOADS_DIR, "images")
AVATAR_UPLOADS_DIR = os.path.join(UPLOADS_DIR, "avatars")

os.makedirs(VIDEO_UPLOADS_DIR, exist_ok=True)
os.makedirs(AUDIO_UPLOADS_DIR, exist_ok=True)
os.makedirs(IMAGE_UPLOADS_DIR, exist_ok=True)
os.makedirs(AVATAR_UPLOADS_DIR, exist_ok=True)

MAX_ANALYSIS_FRAMES = 10
logger = logging.getLogger(__name__)
AVATAR_JOB_STATUS_QUEUED = "queued"
AVATAR_JOB_STATUS_PROCESSING = "processing"
AVATAR_JOB_STATUS_COMPLETED = "completed"
AVATAR_JOB_STATUS_FAILED = "failed"

DEBUG_STEP_DEFINITIONS = [
    ("video_saved", "视频已保存"),
    ("frames_extracted", "抽帧完成"),
    ("frames_classified", "逐帧分类完成"),
    ("events_merged", "事件合并完成"),
    ("events_persisted", "事件入库完成"),
    ("completed", "处理完成"),
]


def save_upload_file(upload, target_dir):
    _, ext = os.path.splitext(upload.filename or "")
    file_name = f"{uuid.uuid4().hex}{ext.lower()}"
    file_path = os.path.join(target_dir, file_name)

    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(upload.file, buffer)

    return file_name, file_path


def save_generated_file(binary_data, target_dir, mime_type="image/png"):
    ext = mimetype_to_extension(mime_type)
    file_name = f"{uuid.uuid4().hex}{ext}"
    file_path = os.path.join(target_dir, file_name)

    with open(file_path, "wb") as buffer:
        buffer.write(binary_data)

    return file_name, file_path


def mimetype_to_extension(mime_type):
    mapping = {
        "image/png": ".png",
        "image/jpeg": ".jpg",
        "image/webp": ".webp",
    }
    return mapping.get(mime_type, ".png")


def _serialize_avatar_generation_job(job: dict) -> dict:
    return {
        "job_id": job["job_id"],
        "status": job.get("status", AVATAR_JOB_STATUS_QUEUED),
        "photo_url": job.get("photo_url", ""),
        "avatar_url": job.get("avatar_url", ""),
        "generation_error": job.get("error_message", "") or None,
    }


def _create_avatar_generation_job(
    *,
    job_id: str,
    species: str,
    photo_relative_path: str,
):
    execute_db(
        """
        INSERT INTO avatar_generation_jobs (
            job_id, species, photo_url, avatar_url, status, error_message, updated_at
        )
        VALUES (?, ?, ?, '', ?, '', CURRENT_TIMESTAMP)
        """,
        (
            job_id,
            species,
            photo_relative_path,
            AVATAR_JOB_STATUS_QUEUED,
        ),
    )


def _update_avatar_generation_job(
    *,
    job_id: str,
    status: str,
    avatar_relative_path: str = "",
    generation_error: str = "",
):
    execute_db(
        """
        UPDATE avatar_generation_jobs
        SET status = ?, avatar_url = ?, error_message = ?, updated_at = CURRENT_TIMESTAMP
        WHERE job_id = ?
        """,
        (
            status,
            avatar_relative_path,
            generation_error,
            job_id,
        ),
    )


def _run_avatar_generation_job(job_id: str, photo_path: str, species: str):
    generation_started_at = time.perf_counter()
    logger.info(
        "Starting avatar generation job: job_id=%s species=%s photo_path=%s",
        job_id,
        species,
        photo_path,
    )
    _update_avatar_generation_job(job_id=job_id, status=AVATAR_JOB_STATUS_PROCESSING)

    try:
        generated_image, mime_type = generate_pet_avatar(photo_path, species)
        avatar_stored_name, _ = save_generated_file(generated_image, AVATAR_UPLOADS_DIR, mime_type)
        avatar_relative_path = f"/media/avatars/{avatar_stored_name}"
        _update_avatar_generation_job(
            job_id=job_id,
            status=AVATAR_JOB_STATUS_COMPLETED,
            avatar_relative_path=avatar_relative_path,
        )
        logger.info(
            "Completed avatar generation job: job_id=%s avatar_path=%s elapsed=%.2fs",
            job_id,
            avatar_relative_path,
            time.perf_counter() - generation_started_at,
        )
    except Exception as exc:
        generation_error = str(exc)
        _update_avatar_generation_job(
            job_id=job_id,
            status=AVATAR_JOB_STATUS_FAILED,
            generation_error=generation_error,
        )
        logger.warning(
            "Avatar generation job failed: job_id=%s error=%s elapsed=%.2fs",
            job_id,
            generation_error,
            time.perf_counter() - generation_started_at,
        )


def _get_avatar_generation_job_or_404(job_id: str) -> dict:
    job = query_db(
        """
        SELECT job_id, status, photo_url, avatar_url, error_message
        FROM avatar_generation_jobs
        WHERE job_id = ?
        """,
        (job_id,),
        one=True,
    )
    if not job:
        raise HTTPException(status_code=404, detail="头像生成任务不存在")
    return job


def _relative_frame_path(frame_path: str) -> str:
    return f"/frames/{os.path.basename(frame_path)}"


def _build_event_timestamp(seconds_from_start: float, max_seconds: float) -> datetime:
    now = datetime.now()
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    base_time = max(today_start, now - timedelta(seconds=max_seconds))
    return base_time + timedelta(seconds=seconds_from_start)


def _format_video_seconds(seconds: float) -> str:
    total_seconds = max(int(seconds), 0)
    minutes = total_seconds // 60
    remaining_seconds = total_seconds % 60
    return f"{minutes:02d}:{remaining_seconds:02d}"


def _build_debug_step_states() -> list[dict]:
    return [
        {
            "id": step_id,
            "title": title,
            "state": "completed",
        }
        for step_id, title in DEBUG_STEP_DEFINITIONS
    ]


def _serialize_debug_frame(frame: dict, sequence: int) -> dict:
    return {
        "sequence": sequence,
        "frame_url": frame["frame_path"],
        "video_seconds": frame["video_seconds"],
        "video_time_text": _format_video_seconds(frame["video_seconds"]),
        "event_type": frame["event_type"],
        "description": frame["description"],
    }


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


def _load_json_list(payload: Optional[str]) -> list[dict]:
    if not payload:
        return []

    try:
        parsed = json.loads(payload)
    except json.JSONDecodeError:
        logger.warning("Invalid debug snapshot JSON payload: %s", payload[:120])
        return []

    return parsed if isinstance(parsed, list) else []


def _merge_analyzed_frames(analyzed_frames: list[dict]) -> list[dict]:
    if not analyzed_frames:
        return []

    merged: list[dict] = []
    for index, frame in enumerate(analyzed_frames):
        next_timestamp = (
            analyzed_frames[index + 1]["video_seconds"]
            if index + 1 < len(analyzed_frames)
            else frame["video_seconds"] + frame["fallback_duration"]
        )
        duration_seconds = max(10.0, next_timestamp - frame["video_seconds"])
        segment_start_seconds = frame["video_seconds"]
        segment_end_seconds = segment_start_seconds + duration_seconds

        if merged and merged[-1]["event_type"] == frame["event_type"]:
            merged[-1]["video_end_seconds"] = segment_end_seconds
            merged[-1]["duration_seconds"] = (
                merged[-1]["video_end_seconds"] - merged[-1]["video_start_seconds"]
            )
            merged[-1]["description"] = frame["description"]
            continue

        merged.append(
            {
                "event_type": frame["event_type"],
                "description": frame["description"],
                "timestamp": frame["event_time"].isoformat(),
                "duration_seconds": duration_seconds,
                "video_start_seconds": segment_start_seconds,
                "video_end_seconds": segment_end_seconds,
                "frame_path": frame["frame_path"],
            }
        )

    return merged


def _summarize_analyzed_events(events: list[dict], video_name: str) -> str:
    if not events:
        raise RuntimeError("视频解析完成，但没有生成可用事件。")

    type_labels = {
        "eating": "进食",
        "drinking": "饮水",
        "sleeping": "休息",
        "playing": "玩耍",
        "resting": "放松",
        "waiting": "等待",
        "litter_box": "如厕",
        "zoomies": "跑酷",
        "other": "活动",
    }

    unique_labels: list[str] = []
    for event in events:
        label = type_labels.get(event["event_type"], "活动")
        if label not in unique_labels:
            unique_labels.append(label)

    highlights = "、".join(unique_labels[:3])
    return f"已根据上传视频《{video_name}》识别出 {len(events)} 段行为事件，主要包括{highlights}。"


def _analyze_uploaded_video(video_path: str, original_filename: str) -> tuple[list[dict], str, list[dict]]:
    if not DASHSCOPE_API_KEY:
        raise RuntimeError("未配置 DASHSCOPE_API_KEY，暂时无法解析上传视频。")

    frames = extract_uniform_frames(video_path, num_frames=MAX_ANALYSIS_FRAMES)
    if not frames:
        raise RuntimeError("没有从视频中提取到可分析画面，请换一个更清晰的视频重试。")

    max_seconds = max(frame["timestamp"] for frame in frames)
    analyzed_frames: list[dict] = []

    for index, frame in enumerate(frames):
        classification = classify_action(frame["frame_path"])
        description = classification.get("description", "").strip()
        if not description or description == "未知行为":
            description = describe_frame(frame["frame_path"]).strip()
        if not description:
            raise RuntimeError("模型没有返回有效的视频描述。")

        if index + 1 < len(frames):
            fallback_duration = max(10.0, frames[index + 1]["timestamp"] - frame["timestamp"])
        else:
            fallback_duration = 20.0

        analyzed_frames.append(
            {
                "event_type": classification.get("event_type", "other"),
                "description": description,
                "event_time": _build_event_timestamp(frame["timestamp"], max_seconds),
                "frame_path": _relative_frame_path(frame["frame_path"]),
                "video_seconds": frame["timestamp"],
                "fallback_duration": fallback_duration,
            }
        )

    merged_events = _merge_analyzed_frames(analyzed_frames)
    context_summary = _summarize_analyzed_events(merged_events, original_filename)
    debug_frames = [
        _serialize_debug_frame(frame, sequence=index + 1)
        for index, frame in enumerate(analyzed_frames)
    ]
    return merged_events, context_summary, debug_frames


def _persist_analyzed_events(
    *,
    user_id: int,
    pet_id: int,
    camera_name: str,
    camera_id: Optional[int],
    video_relative_path: str,
    original_filename: str,
    analyzed_events: list[dict],
):
    if camera_id:
        camera = query_db(
            "SELECT id, user_id FROM cameras WHERE id = ?",
            (camera_id,),
            one=True,
        )
        if not camera:
            raise HTTPException(status_code=404, detail="Camera not found")

        execute_db(
            """UPDATE cameras
               SET name = ?, stream_url = '', is_demo = 1, status = 'ready',
                   demo_video_path = ?, demo_video_name = ?
               WHERE id = ?""",
            (camera_name, video_relative_path, original_filename, camera_id),
        )
        target_camera_id = camera_id
    else:
        target_camera_id = execute_db(
            """INSERT INTO cameras (user_id, name, stream_url, is_demo, status, demo_video_path, demo_video_name)
               VALUES (?, ?, '', 1, 'ready', ?, ?)""",
            (user_id, camera_name, video_relative_path, original_filename),
        )

    execute_db("DELETE FROM events WHERE camera_id = ?", (target_camera_id,))

    for event in analyzed_events:
        execute_db(
            """INSERT INTO events (
                   camera_id,
                   pet_id,
                   timestamp,
                   event_type,
                   duration_seconds,
                   video_start_seconds,
                   video_end_seconds,
                   description,
                   frame_path
               )
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                target_camera_id,
                pet_id,
                event["timestamp"],
                event["event_type"],
                event["duration_seconds"],
                event.get("video_start_seconds"),
                event.get("video_end_seconds"),
                event["description"],
                event["frame_path"],
            ),
        )

    invalidate_event_cache(pet_id)
    return target_camera_id


def _persist_video_analysis_debug_snapshot(
    *,
    camera_id: int,
    pet_id: int,
    demo_video_name: str,
    demo_video_url: str,
    context_summary: str,
    frames: list[dict],
):
    execute_db(
        """
        INSERT INTO video_analysis_debug_snapshots (
            camera_id,
            pet_id,
            demo_video_name,
            demo_video_url,
            context_summary,
            processing_status,
            step_states_json,
            frames_json,
            updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(camera_id) DO UPDATE SET
            pet_id = excluded.pet_id,
            demo_video_name = excluded.demo_video_name,
            demo_video_url = excluded.demo_video_url,
            context_summary = excluded.context_summary,
            processing_status = excluded.processing_status,
            step_states_json = excluded.step_states_json,
            frames_json = excluded.frames_json,
            updated_at = CURRENT_TIMESTAMP
        """,
        (
            camera_id,
            pet_id,
            demo_video_name,
            demo_video_url,
            context_summary,
            "completed",
            json.dumps(_build_debug_step_states(), ensure_ascii=False),
            json.dumps(frames, ensure_ascii=False),
        ),
    )


def _upsert_demo_camera(
    *,
    user_id: int,
    camera_name: str,
    camera_id: Optional[int],
    video_relative_path: str,
    original_filename: str,
) -> int:
    if camera_id:
        camera = query_db(
            "SELECT id, user_id FROM cameras WHERE id = ?",
            (camera_id,),
            one=True,
        )
        if not camera:
            raise HTTPException(status_code=404, detail="Camera not found")

        execute_db(
            """
            UPDATE cameras
            SET name = ?,
                stream_url = '',
                is_demo = 1,
                status = 'processing',
                demo_video_path = ?,
                demo_video_name = ?
            WHERE id = ?
            """,
            (camera_name, video_relative_path, original_filename, camera_id),
        )
        return camera_id

    return execute_db(
        """
        INSERT INTO cameras (
            user_id,
            name,
            stream_url,
            is_demo,
            status,
            demo_video_path,
            demo_video_name
        )
        VALUES (?, ?, '', 1, 'processing', ?, ?)
        """,
        (user_id, camera_name, video_relative_path, original_filename),
    )


@router.post("/pet/avatar/generate", status_code=202)
def upload_pet_reference_and_generate_avatar(
    background_tasks: BackgroundTasks,
    species: str = Form("cat"),
    image: UploadFile = File(...),
):
    request_started_at = time.perf_counter()

    if not image.content_type or not image.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="请上传图片文件")

    logger.info(
        "Received pet avatar request: species=%s filename=%s content_type=%s",
        species,
        image.filename or "",
        image.content_type or "",
    )

    stored_name, photo_path = save_upload_file(image, IMAGE_UPLOADS_DIR)
    photo_relative_path = f"/media/images/{stored_name}"
    job_id = uuid.uuid4().hex
    photo_size = os.path.getsize(photo_path)

    logger.info(
        "Stored pet reference photo: path=%s size_bytes=%s elapsed=%.2fs",
        photo_path,
        photo_size,
        time.perf_counter() - request_started_at,
    )

    _create_avatar_generation_job(
        job_id=job_id,
        species=species,
        photo_relative_path=photo_relative_path,
    )
    background_tasks.add_task(_run_avatar_generation_job, job_id, photo_path, species)

    logger.info(
        "Queued pet avatar generation job: job_id=%s total=%.2fs",
        job_id,
        time.perf_counter() - request_started_at,
    )

    return _serialize_avatar_generation_job(
        {
            "job_id": job_id,
            "status": AVATAR_JOB_STATUS_QUEUED,
            "photo_url": photo_relative_path,
            "avatar_url": "",
            "error_message": "",
        }
    )


@router.get("/pet/avatar/generate/{job_id}")
def get_pet_avatar_generation_job(job_id: str):
    job = _get_avatar_generation_job_or_404(job_id)
    return _serialize_avatar_generation_job(job)


@router.post("/demo-video")
def upload_demo_video(
    background_tasks: BackgroundTasks,
    user_id: int = Form(...),
    pet_id: int = Form(...),
    camera_name: str = Form("家庭摄像头"),
    camera_id: Optional[int] = Form(None),
    video: UploadFile = File(...),
):
    if not video.content_type or not video.content_type.startswith("video/"):
        raise HTTPException(status_code=400, detail="请上传视频文件")

    pet = query_db("SELECT id FROM pets WHERE id = ?", (pet_id,), one=True)
    if not pet:
        raise HTTPException(status_code=404, detail="Pet not found")

    stored_name, file_path = save_upload_file(video, VIDEO_UPLOADS_DIR)
    relative_path = f"/media/videos/{stored_name}"
    original_filename = video.filename or stored_name

    try:
        target_camera_id = _upsert_demo_camera(
            user_id=user_id,
            camera_name=camera_name,
            camera_id=camera_id,
            video_relative_path=relative_path,
            original_filename=original_filename,
        )
        job_id = create_video_analysis_job(
            camera_id=target_camera_id,
            pet_id=pet_id,
            source_video_path=file_path,
            source_video_name=original_filename,
            demo_video_url=relative_path,
        )
        background_tasks.add_task(process_video_analysis_job, job_id)
    except HTTPException:
        try:
            os.remove(file_path)
        except OSError:
            pass
        raise
    except Exception as exc:
        try:
            os.remove(file_path)
        except OSError:
            pass
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return {
        "camera_id": target_camera_id,
        "camera_name": camera_name,
        "demo_video_name": original_filename,
        "demo_video_url": relative_path,
        "job_id": job_id,
        "processing_status": "queued",
        "context_summary": "视频已接收，正在后台分析候选片段与宠物记忆。",
        "events_count": 0,
    }


@router.get("/debug/video-analysis/{camera_id}")
def get_video_analysis_debug(camera_id: int):
    payload = build_debug_payload(camera_id)
    if not payload:
        raise HTTPException(status_code=404, detail="Camera not found")
    return payload


@router.get("/debug/video-analysis/clips/{clip_id}")
def get_video_analysis_clip_debug(clip_id: int):
    payload = build_clip_debug_payload(clip_id)
    if not payload:
        raise HTTPException(status_code=404, detail="Clip not found")
    return payload


@router.get("/debug/memory/{pet_id}")
def get_memory_debug(pet_id: int):
    return build_memory_debug_payload(pet_id)


@router.post("/pet/{pet_id}/voice/sample")
def upload_pet_voice_sample(
    pet_id: int,
    label: str = Form("真实宠物原声"),
    audio: UploadFile = File(...),
):
    if not audio.content_type or not audio.content_type.startswith("audio/"):
        raise HTTPException(status_code=400, detail="请上传音频文件")

    pet = query_db("SELECT id FROM pets WHERE id = ?", (pet_id,), one=True)
    if not pet:
        raise HTTPException(status_code=404, detail="Pet not found")

    stored_name, _ = save_upload_file(audio, AUDIO_UPLOADS_DIR)
    relative_path = f"/media/audio/{stored_name}"

    execute_db(
        """UPDATE pets
           SET voice_type = 'clone',
               voice_key = 'custom-clone',
               voice_label = ?,
               voice_sample_path = ?
           WHERE id = ?""",
        (label, relative_path, pet_id),
    )

    return {
        "pet_id": pet_id,
        "voice_type": "clone",
        "voice_key": "custom-clone",
        "voice_label": label,
        "voice_sample_url": relative_path,
    }
