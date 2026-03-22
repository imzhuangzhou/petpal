import os
import shutil
import uuid
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, File, Form, HTTPException, UploadFile

from database import execute_db, query_db
from dialogue_engine import invalidate_event_cache
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


def _relative_frame_path(frame_path: str) -> str:
    return f"/frames/{os.path.basename(frame_path)}"


def _build_event_timestamp(seconds_from_start: float, max_seconds: float) -> datetime:
    now = datetime.now()
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    base_time = max(today_start, now - timedelta(seconds=max_seconds))
    return base_time + timedelta(seconds=seconds_from_start)


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

        if merged and merged[-1]["event_type"] == frame["event_type"]:
            merged[-1]["duration_seconds"] += duration_seconds
            merged[-1]["description"] = frame["description"]
            continue

        merged.append(
            {
                "event_type": frame["event_type"],
                "description": frame["description"],
                "timestamp": frame["event_time"].isoformat(),
                "duration_seconds": duration_seconds,
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


def _analyze_uploaded_video(video_path: str, original_filename: str) -> tuple[list[dict], str]:
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
    return merged_events, context_summary


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
            """INSERT INTO events (camera_id, pet_id, timestamp, event_type, duration_seconds, description, frame_path)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (
                target_camera_id,
                pet_id,
                event["timestamp"],
                event["event_type"],
                event["duration_seconds"],
                event["description"],
                event["frame_path"],
            ),
        )

    invalidate_event_cache(pet_id)
    return target_camera_id


@router.post("/pet/avatar/generate")
def upload_pet_reference_and_generate_avatar(
    species: str = Form("cat"),
    image: UploadFile = File(...),
):
    if not image.content_type or not image.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="请上传图片文件")

    stored_name, photo_path = save_upload_file(image, IMAGE_UPLOADS_DIR)
    photo_relative_path = f"/media/images/{stored_name}"
    avatar_relative_path = ""
    generation_error = None

    try:
        generated_image, mime_type = generate_pet_avatar(photo_path, species)
        avatar_stored_name, _ = save_generated_file(generated_image, AVATAR_UPLOADS_DIR, mime_type)
        avatar_relative_path = f"/media/avatars/{avatar_stored_name}"
    except Exception as exc:
        generation_error = str(exc)

    return {
        "photo_url": photo_relative_path,
        "avatar_url": avatar_relative_path,
        "generation_error": generation_error,
    }


@router.post("/demo-video")
def upload_demo_video(
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
        analyzed_events, context_summary = _analyze_uploaded_video(file_path, original_filename)
        target_camera_id = _persist_analyzed_events(
            user_id=user_id,
            pet_id=pet_id,
            camera_name=camera_name,
            camera_id=camera_id,
            video_relative_path=relative_path,
            original_filename=original_filename,
            analyzed_events=analyzed_events,
        )
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
        "context_summary": context_summary,
        "events_count": len(analyzed_events),
    }


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
