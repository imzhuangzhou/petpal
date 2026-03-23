import os
from datetime import datetime, timedelta

from fastapi import APIRouter, HTTPException

from database import execute_db, query_db
from video_processor import clip_video_segment, get_video_duration

router = APIRouter(prefix="/api", tags=["events"])

BACKEND_DIR = os.path.dirname(os.path.dirname(__file__))
UPLOADS_DIR = os.path.join(BACKEND_DIR, "uploads")
EVENT_CLIP_PRE_ROLL_SECONDS = 1.5
EVENT_CLIP_POST_ROLL_SECONDS = 1.5


CAT_DEMO_SCHEDULE = [
    (0, "sleeping", "猫咪蜷缩在猫窝里安静地睡觉", 3600),
    (65, "eating", "猫咪走到食盆前开始吃早餐", 300),
    (75, "drinking", "猫咪吃完后去喝了些水", 60),
    (90, "resting", "猫咪趴在窗台上晒太阳", 1800),
    (140, "litter_box", "猫咪使用了猫砂盆", 120),
    (150, "playing", "猫咪追着地上的玩具球跑", 600),
    (180, "sleeping", "猫咪跳上沙发，打了个哈欠睡着了", 5400),
    (280, "eating", "猫咪醒来后吃了午餐", 240),
    (290, "drinking", "猫咪在饮水机旁喝水", 45),
    (310, "playing", "猫咪突然开始在客厅疯跑", 300),
    (340, "resting", "猫咪安静地坐在书桌上看窗外的小鸟", 2400),
    (390, "sleeping", "猫咪在阳光下眯着眼睛打盹", 3600),
    (460, "drinking", "猫咪去喝了点水", 30),
    (470, "waiting", "猫咪突然走到门口，坐在玄关处望着门", 900),
    (490, "waiting", "猫咪又回到门口，来回踱步", 600),
    (520, "eating", "猫咪听到你回来的声音后先去吃了晚餐", 360),
    (530, "playing", "猫咪和你一起玩逗猫棒，跳来跳去", 900),
    (550, "drinking", "猫咪玩累了去喝水", 40),
    (570, "resting", "猫咪趴在你腿上休息", 1200),
    (600, "sleeping", "猫咪在沙发上蜷成一团睡着了", 7200),
]

DOG_DEMO_SCHEDULE = [
    (0, "sleeping", "狗狗趴在地毯上睡得很香", 3000),
    (50, "eating", "狗狗摇着尾巴吃完了早餐", 360),
    (62, "drinking", "狗狗去水盆边咕噜咕噜喝水", 70),
    (95, "playing", "狗狗叼着球在客厅里来回跑", 720),
    (135, "resting", "狗狗趴在阳台边晒太阳休息", 1500),
    (170, "waiting", "狗狗听到门外声音后守在门口", 600),
    (210, "sleeping", "狗狗换到沙发旁继续午睡", 4800),
    (300, "eating", "狗狗醒来后吃了加餐", 240),
    (320, "playing", "狗狗兴奋地追着玩具绳玩", 480),
    (360, "drinking", "狗狗运动后去补充了点水", 50),
    (395, "resting", "狗狗安静地窝在主人拖鞋旁", 1800),
    (445, "waiting", "狗狗守在门边等主人回家", 1200),
    (510, "playing", "狗狗听见你的脚步声后开心地转圈", 540),
    (530, "eating", "狗狗吃完晚饭后舔了舔鼻子", 300),
    (548, "drinking", "狗狗又喝了些水", 40),
    (575, "resting", "狗狗靠着你的腿慢慢平静下来", 1500),
    (620, "sleeping", "狗狗抱着玩具趴在窝里睡着了", 6600),
]


def get_demo_schedule(species):
    if species == "dog":
        return DOG_DEMO_SCHEDULE
    return CAT_DEMO_SCHEDULE


def seed_demo_events(pet_id, camera_id, video_name=""):
    pet = query_db("SELECT id, name, species FROM pets WHERE id = ?", (pet_id,), one=True)
    species = pet.get("species", "cat") if pet else "cat"

    execute_db("DELETE FROM events WHERE camera_id = ?", (camera_id,))

    now = datetime.now()
    today_start = now.replace(hour=7, minute=0, second=0, microsecond=0)
    schedule = get_demo_schedule(species)

    created_events = []
    for minutes_offset, event_type, description, duration in schedule:
        event_time = today_start + timedelta(minutes=minutes_offset)
        if event_time > now:
            break

        event_id = execute_db(
            """INSERT INTO events (camera_id, pet_id, timestamp, event_type, duration_seconds, description, frame_path)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (camera_id, pet_id, event_time.isoformat(), event_type, duration, description, ""),
        )
        created_events.append(
            {
                "id": event_id,
                "event_type": event_type,
                "description": description,
                "timestamp": event_time.isoformat(),
            }
        )

    context_summary = (
        f"已根据上传视频《{video_name}》生成今日演示行为上下文"
        if video_name
        else "已生成今日演示行为上下文"
    )

    return {
        "message": f"✅ Demo data initialized: {len(created_events)} events created",
        "events_count": len(created_events),
        "events": created_events,
        "context_summary": context_summary,
    }


@router.get("/events/{pet_id}")
def get_events(pet_id: int, limit: int = 50):
    events = query_db(
        "SELECT * FROM events WHERE pet_id = ? ORDER BY timestamp DESC LIMIT ?",
        (pet_id, limit),
    )
    return events


def _resolve_media_path(media_url: str) -> str:
    if not media_url.startswith("/media/"):
        raise HTTPException(status_code=400, detail="视频路径格式无效。")

    relative_path = media_url.removeprefix("/media/")
    resolved_path = os.path.realpath(os.path.join(UPLOADS_DIR, relative_path))
    uploads_root = os.path.realpath(UPLOADS_DIR)
    if not resolved_path.startswith(uploads_root + os.sep) and resolved_path != uploads_root:
        raise HTTPException(status_code=400, detail="视频路径无效。")

    return resolved_path


@router.get("/events/{event_id}/clip")
def get_event_clip(event_id: int):
    event = query_db(
        """
        SELECT e.id, e.video_start_seconds, e.video_end_seconds, c.demo_video_path
        FROM events e
        LEFT JOIN cameras c ON c.id = e.camera_id
        WHERE e.id = ?
        """,
        (event_id,),
        one=True,
    )
    if not event:
        raise HTTPException(status_code=404, detail="找不到对应事件。")

    video_start_seconds = event.get("video_start_seconds")
    video_end_seconds = event.get("video_end_seconds")
    if video_start_seconds is None or video_end_seconds is None:
        raise HTTPException(status_code=409, detail="该事件缺少视频时间范围，请重新上传并分析视频。")

    demo_video_path = (event.get("demo_video_path") or "").strip()
    if not demo_video_path:
        raise HTTPException(status_code=409, detail="该事件未关联原始视频。")

    source_video_path = _resolve_media_path(demo_video_path)
    if not os.path.exists(source_video_path):
        raise HTTPException(status_code=404, detail="原始视频不存在，请重新上传。")

    try:
        video_duration = get_video_duration(source_video_path)
        clip_start_seconds = max(float(video_start_seconds) - EVENT_CLIP_PRE_ROLL_SECONDS, 0.0)
        clip_end_seconds = float(video_end_seconds) + EVENT_CLIP_POST_ROLL_SECONDS
        if video_duration > 0:
            clip_end_seconds = min(clip_end_seconds, video_duration)

        if clip_end_seconds <= clip_start_seconds:
            raise HTTPException(status_code=409, detail="事件片段时间范围无效。")

        clip_url = clip_video_segment(source_video_path, clip_start_seconds, clip_end_seconds)
    except HTTPException:
        raise
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return {
        "event_id": event_id,
        "video_clip_url": clip_url,
    }


@router.post("/demo/init")
def init_demo_data(pet_id: int = 1, camera_id: int = 1, video_name: str = ""):
    """Initialize a species-aware day of demo events."""
    return seed_demo_events(pet_id, camera_id, video_name=video_name)
