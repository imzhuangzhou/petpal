import os
import base64
import mimetypes
import google.auth
from google.auth.exceptions import DefaultCredentialsError
from google import genai
from google.genai import errors as genai_errors
from google.genai import types as genai_types
from openai import APIConnectionError, APIStatusError, APITimeoutError, OpenAI

# Qwen3-VL API configuration (OpenAI-compatible)
DASHSCOPE_API_KEY = os.environ.get("DASHSCOPE_API_KEY", "")
DASHSCOPE_BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1"

VLM_MODEL = "qwen-vl-plus"
TEXT_MODEL = "qwen-plus"
VERTEX_AI_PROJECT = os.environ.get("VERTEX_AI_PROJECT") or os.environ.get("GOOGLE_CLOUD_PROJECT", "")
VERTEX_AI_LOCATION = os.environ.get("VERTEX_AI_LOCATION", "global")
VERTEX_IMAGE_MODEL = os.environ.get("VERTEX_IMAGE_MODEL", "imagen-3.0-capability-001")


def get_vlm_client():
    """Get OpenAI-compatible client for Qwen VL."""
    return OpenAI(
        api_key=DASHSCOPE_API_KEY,
        base_url=DASHSCOPE_BASE_URL,
    )


def get_image_client():
    """Get Vertex AI client for image generation."""
    try:
        credentials, detected_project = google.auth.default(
            scopes=["https://www.googleapis.com/auth/cloud-platform"]
        )
    except DefaultCredentialsError as exc:
        raise RuntimeError(
            "未配置 Google Cloud 凭据。请先执行 "
            "`gcloud auth application-default login`，"
            "或设置 `GOOGLE_APPLICATION_CREDENTIALS` 指向本机服务账号 JSON。"
        ) from exc

    project = VERTEX_AI_PROJECT or detected_project
    if not project:
        raise RuntimeError(
            "未配置 Vertex AI 项目。请设置 `VERTEX_AI_PROJECT` 或 "
            "`GOOGLE_CLOUD_PROJECT`。"
        )

    return genai.Client(
        vertexai=True,
        project=project,
        location=VERTEX_AI_LOCATION,
        credentials=credentials,
    )


def _build_pet_avatar_prompt(species: str) -> str:
    species_label = "狗狗" if species == "dog" else "猫咪"
    return (
        f"基于输入参考图，为这只{species_label}生成 1 张动漫卡通头像。"
        "必须保留原宠物的花色、耳朵形状、脸型、毛发纹理、眼神与整体神态特征。"
        "只输出一只宠物，不要出现人类，不要增加第二只宠物。"
        "构图居中，主体清晰，背景干净简洁，适合作为 App 头像。"
        "输出比例为 1:1，整体风格温暖、可爱、精致。"
    )


def _extract_image_error_detail(exc: Exception) -> str:
    if isinstance(exc, genai_errors.APIError):
        if exc.message:
            return exc.message
        return f"HTTP {exc.status}"

    if isinstance(exc, APIStatusError):
        response = getattr(exc, "response", None)
        if response is None:
            return str(exc)

        try:
            payload = response.json()
        except Exception:
            payload = None

        if isinstance(payload, dict):
            error_payload = payload.get("error")
            if isinstance(error_payload, dict):
                message = error_payload.get("message")
                if isinstance(message, str) and message.strip():
                    return message

        text = getattr(response, "text", "")
        if isinstance(text, str) and text.strip():
            return text.strip()

    return str(exc)


def _guess_image_mime_type(image_path: str) -> str:
    mime_type, _ = mimetypes.guess_type(image_path)
    return mime_type or "image/jpeg"


def generate_pet_avatar(image_path: str, species: str) -> tuple[bytes, str]:
    """
    Generate a cartoon avatar from a pet reference image using Vertex AI image editing.

    Returns:
        Tuple of (image bytes, mime type)
    """
    client = get_image_client()
    prompt = _build_pet_avatar_prompt(species)
    mime_type = _guess_image_mime_type(image_path)

    try:
        with open(image_path, "rb") as image_file:
            result = client.models.edit_image(
                model=VERTEX_IMAGE_MODEL,
                prompt=prompt,
                reference_images=[
                    genai_types.RawReferenceImage(
                        reference_image=genai_types.Image(
                            image_bytes=image_file.read(),
                            mime_type=mime_type,
                        )
                    )
                ],
                config=genai_types.EditImageConfig(
                    number_of_images=1,
                    aspect_ratio="1:1",
                    output_mime_type="image/png",
                    edit_mode=genai_types.EditMode.EDIT_MODE_CONTROLLED_EDITING,
                ),
            )
    except genai_errors.APIError as exc:
        detail = _extract_image_error_detail(exc)
        raise RuntimeError(f"Vertex AI 图片生成失败：{detail}") from exc
    except (APIConnectionError, APITimeoutError) as exc:
        raise RuntimeError(f"图片生成请求失败：{exc}") from exc
    except Exception as exc:
        detail = _extract_image_error_detail(exc)
        raise RuntimeError(f"Vertex AI 图片生成失败：{detail}") from exc

    if not result.generated_images:
        raise RuntimeError("Vertex AI 没有返回可用的图片结果。")

    first_image = result.generated_images[0].image
    if not first_image:
        raise RuntimeError("Vertex AI 没有返回可用的图片结果。")

    if first_image.image_bytes:
        return first_image.image_bytes, first_image.mime_type or "image/png"

    raise RuntimeError("Vertex AI 返回了空图片内容。")


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
