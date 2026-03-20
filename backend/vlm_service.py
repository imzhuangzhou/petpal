import os
import base64
from openai import OpenAI

# Qwen3-VL API configuration (OpenAI-compatible)
DASHSCOPE_API_KEY = os.environ.get("DASHSCOPE_API_KEY", "")
DASHSCOPE_BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1"

VLM_MODEL = "qwen-vl-plus"
TEXT_MODEL = "qwen-plus"


def get_vlm_client():
    """Get OpenAI-compatible client for Qwen VL."""
    return OpenAI(
        api_key=DASHSCOPE_API_KEY,
        base_url=DASHSCOPE_BASE_URL,
    )


def encode_image_base64(image_path: str) -> str:
    """Read an image file and return base64-encoded string."""
    with open(image_path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


def describe_frame(image_path: str) -> str:
    """
    Use Qwen3-VL to describe a video frame in Chinese.

    Returns a natural language description of what's happening in the frame.
    """
    client = get_vlm_client()
    base64_image = encode_image_base64(image_path)

    response = client.chat.completions.create(
        model=VLM_MODEL,
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/jpeg;base64,{base64_image}"
                        },
                    },
                    {
                        "type": "text",
                        "text": (
                            "请用中文简洁描述这张家庭监控画面中发生了什么。"
                            "重点关注画面中的宠物（猫或狗）的行为动作。"
                            "描述应该包括：宠物在做什么、所在位置、周围环境。"
                            "控制在50字以内。"
                        ),
                    },
                ],
            }
        ],
        max_tokens=200,
    )

    return response.choices[0].message.content.strip()


def classify_action(image_path: str) -> dict:
    """
    Use Qwen3-VL to classify the pet action in a frame.

    Returns:
        dict with keys: "event_type", "confidence", "description"
        event_type is one of: eating, drinking, sleeping, playing, resting,
                              litter_box, zoomies, waiting, other
    """
    client = get_vlm_client()
    base64_image = encode_image_base64(image_path)

    response = client.chat.completions.create(
        model=VLM_MODEL,
        messages=[
            {
                "role": "system",
                "content": (
                    "你是一个宠物行为分析专家。请分析监控画面中宠物的行为，"
                    "并严格按照以下JSON格式回复，不要包含其他文字：\n"
                    '{"event_type": "类型", "description": "描述"}\n'
                    "event_type 必须是以下之一：\n"
                    "- eating（进食）\n"
                    "- drinking（饮水）\n"
                    "- sleeping（睡觉）\n"
                    "- playing（玩耍/跑酷）\n"
                    "- resting（休息/躺着但没睡）\n"
                    "- litter_box（使用猫砂盆/如厕）\n"
                    "- waiting（在门口等候）\n"
                    "- other（其他行为）\n"
                    "description 用中文简短描述具体行为，20字以内。"
                ),
            },
            {
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/jpeg;base64,{base64_image}"
                        },
                    },
                    {
                        "type": "text",
                        "text": "请分析这张监控画面中宠物的行为。",
                    },
                ],
            },
        ],
        max_tokens=100,
    )

    import json
    raw = response.choices[0].message.content.strip()

    # Try to parse JSON
    try:
        # Handle markdown code block wrapping
        if raw.startswith("```"):
            raw = raw.split("```")[1]
            if raw.startswith("json"):
                raw = raw[4:]
        result = json.loads(raw)
        return {
            "event_type": result.get("event_type", "other"),
            "description": result.get("description", "未知行为"),
        }
    except (json.JSONDecodeError, IndexError):
        return {
            "event_type": "other",
            "description": raw[:50],
        }


def generate_text(prompt: str, system_prompt: str = "") -> str:
    """
    Use Qwen text model for general text generation (dialogue, reports, etc.)
    """
    client = get_vlm_client()

    messages = []
    if system_prompt:
        messages.append({"role": "system", "content": system_prompt})
    messages.append({"role": "user", "content": prompt})

    response = client.chat.completions.create(
        model=TEXT_MODEL,
        messages=messages,
        max_tokens=1000,
    )

    return response.choices[0].message.content.strip()


# === Demo mode: simulated VLM responses ===

DEMO_EVENTS = [
    {"event_type": "sleeping", "description": "猫咪蜷缩在沙发上睡觉"},
    {"event_type": "eating", "description": "猫咪在食盆前吃猫粮"},
    {"event_type": "drinking", "description": "猫咪在水碗旁喝水"},
    {"event_type": "playing", "description": "猫咪在客厅追逐玩具球"},
    {"event_type": "resting", "description": "猫咪趴在窗台上晒太阳"},
    {"event_type": "sleeping", "description": "猫咪在猫窝里安静休息"},
    {"event_type": "eating", "description": "猫咪认真地吃着晚餐"},
    {"event_type": "zoomies", "description": "猫咪突然在房间里疯跑"},
    {"event_type": "waiting", "description": "猫咪坐在门口望着大门"},
    {"event_type": "drinking", "description": "猫咪优雅地舔着水面"},
    {"event_type": "litter_box", "description": "猫咪正在使用猫砂盆"},
    {"event_type": "playing", "description": "猫咪扑向逗猫棒"},
    {"event_type": "resting", "description": "猫咪躺在地毯上伸懒腰"},
    {"event_type": "sleeping", "description": "猫咪在主人床上打盹"},
    {"event_type": "eating", "description": "猫咪小口品尝零食"},
    {"event_type": "waiting", "description": "猫咪在玄关处来回踱步"},
    {"event_type": "playing", "description": "猫咪和纸箱玩得不亦乐乎"},
    {"event_type": "drinking", "description": "猫咪凑近自动饮水机喝水"},
    {"event_type": "sleeping", "description": "猫咪把头埋在爪子里睡着了"},
    {"event_type": "resting", "description": "猫咪安静地坐在书桌上观察窗外"},
]


def get_demo_event(index: int) -> dict:
    """Get a simulated event for demo mode."""
    return DEMO_EVENTS[index % len(DEMO_EVENTS)]
