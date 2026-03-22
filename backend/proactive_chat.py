import os
from typing import Optional

from database import execute_db, query_db
from video_processor import detect_pet_vocalization_clip

BACKEND_DIR = os.path.dirname(__file__)
UPLOADS_DIR = os.path.join(BACKEND_DIR, "uploads")


def serialize_chat_message(row: Optional[dict]) -> Optional[dict]:
    if not row:
        return None

    return {
        "id": str(row.get("id", "")),
        "role": row.get("role", "assistant"),
        "content": row.get("content", ""),
        "message_type": row.get("message_type", "text") or "text",
        "media_kind": row.get("media_kind", "") or "",
        "media_url": row.get("media_url", "") or "",
        "trigger_source": row.get("trigger_source", "chat") or "chat",
        "created_at": row.get("created_at", ""),
        "related_events": [],
    }


def persist_chat_message(
    *,
    pet_id: int,
    role: str,
    content: str,
    message_type: str = "text",
    media_kind: str = "",
    media_url: str = "",
    trigger_source: str = "chat",
) -> dict:
    message_id = execute_db(
        """INSERT INTO chat_history (
               pet_id, role, content, message_type, media_kind, media_url, trigger_source
           ) VALUES (?, ?, ?, ?, ?, ?, ?)""",
        (pet_id, role, content, message_type, media_kind, media_url, trigger_source),
    )

    row = query_db("SELECT * FROM chat_history WHERE id = ?", (message_id,), one=True)
    return serialize_chat_message(row) or {}


def trigger_pet_vocalization_message(*, pet_id: int, camera_id: int) -> dict:
    pet = query_db("SELECT id, species FROM pets WHERE id = ?", (pet_id,), one=True)
    if not pet:
        raise RuntimeError("找不到对应宠物。")

    camera = query_db(
        "SELECT id, demo_video_path FROM cameras WHERE id = ?",
        (camera_id,),
        one=True,
    )
    if not camera:
        raise RuntimeError("找不到对应摄像头。")

    demo_video_path = (camera.get("demo_video_path") or "").strip()
    if not demo_video_path:
        raise RuntimeError("请先上传一段陪伴视频，再使用这个功能。")

    video_path = _resolve_media_path(demo_video_path)
    if not os.path.exists(video_path):
        raise RuntimeError("当前绑定的视频文件不存在，请重新上传。")

    species = pet.get("species", "cat") or "cat"
    label = "汪言汪语" if species == "dog" else "猫言猫语"
    detection = detect_pet_vocalization_clip(video_path=video_path, species=species)

    if detection.get("matched"):
        content = _choose_matched_copy(
            species=species,
            anchor_seconds=detection.get("anchor_seconds", 0.0),
        )
        message = persist_chat_message(
            pet_id=pet_id,
            role="assistant",
            content=content,
            message_type="video",
            media_kind="video",
            media_url=detection.get("clip_url", ""),
            trigger_source="proactive_vocalization",
        )
        return {
            "matched": True,
            "message": message,
            "notification_title": label,
            "notification_body": content,
        }

    content = _choose_unmatched_copy(species)
    message = persist_chat_message(
        pet_id=pet_id,
        role="assistant",
        content=content,
        trigger_source="proactive_vocalization",
    )
    return {
        "matched": False,
        "message": message,
        "notification_title": "",
        "notification_body": "",
    }


def _resolve_media_path(media_url: str) -> str:
    if not media_url.startswith("/media/"):
        raise RuntimeError("视频路径格式无效。")

    return os.path.join(UPLOADS_DIR, media_url.removeprefix("/media/"))


def _choose_matched_copy(*, species: str, anchor_seconds: float) -> str:
    templates = {
        "cat": [
            "猫言猫语：主人，我想你啦",
            "猫言猫语：我刚刚对着镜头叫你，你有听见吗",
            "猫言猫语：想你想到忍不住冲着镜头喵喵啦",
            "猫言猫语：主人快回来，我在认真呼叫你呢",
        ],
        "dog": [
            "汪言汪语：主人，我想你啦",
            "汪言汪语：我刚刚朝着镜头汪汪叫你了",
            "汪言汪语：快看看我，我一直在等你回应呀",
            "汪言汪语：我对着镜头喊了你好几声呢",
        ],
    }

    options = templates["dog" if species == "dog" else "cat"]
    return options[int(max(anchor_seconds, 0)) % len(options)]


def _choose_unmatched_copy(species: str) -> str:
    if species == "dog":
        return "汪言汪语：这次我还没有对着镜头汪到能发给你看呢。"
    return "猫言猫语：这次我还没有对着镜头撒娇到能发给你看呢。"
