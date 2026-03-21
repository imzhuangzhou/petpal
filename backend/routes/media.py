import os
import shutil
import uuid
from typing import Optional

from fastapi import APIRouter, File, Form, HTTPException, UploadFile

from database import execute_db, query_db
from routes.events import seed_demo_events
from vlm_service import generate_pet_avatar

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

    stored_name, file_path = save_upload_file(video, VIDEO_UPLOADS_DIR)
    relative_path = f"/media/videos/{stored_name}"

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
            (camera_name, relative_path, video.filename or stored_name, camera_id),
        )
        target_camera_id = camera_id
    else:
        target_camera_id = execute_db(
            """INSERT INTO cameras (user_id, name, stream_url, is_demo, status, demo_video_path, demo_video_name)
               VALUES (?, ?, '', 1, 'ready', ?, ?)""",
            (user_id, camera_name, relative_path, video.filename or stored_name),
        )

    demo_result = seed_demo_events(
        pet_id=pet_id,
        camera_id=target_camera_id,
        video_name=video.filename or stored_name,
    )

    return {
        "camera_id": target_camera_id,
        "camera_name": camera_name,
        "demo_video_name": video.filename or stored_name,
        "demo_video_url": relative_path,
        "context_summary": demo_result["context_summary"],
        "events_count": demo_result["events_count"],
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
