import os
import base64
import io
import json
import logging
import mimetypes
import subprocess
import time
import google.auth
import httpx
from google.auth.exceptions import DefaultCredentialsError
from google import genai
from google.genai import errors as genai_errors
from google.genai import types as genai_types
from openai import APIConnectionError, APIStatusError, APITimeoutError, OpenAI
from PIL import Image, ImageOps

# Qwen3-VL API configuration (OpenAI-compatible)
DASHSCOPE_API_KEY = os.environ.get("DASHSCOPE_API_KEY", "")
DASHSCOPE_BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1"

VLM_MODEL = "qwen-vl-plus"
TEXT_MODEL = "qwen-plus"
DASHSCOPE_TIMEOUT_SECONDS = float(os.environ.get("DASHSCOPE_TIMEOUT_SECONDS", "45"))
VERTEX_AI_PROJECT = os.environ.get("VERTEX_AI_PROJECT") or os.environ.get("GOOGLE_CLOUD_PROJECT", "")
VERTEX_AI_LOCATION = os.environ.get("VERTEX_AI_LOCATION", "global")
VERTEX_IMAGE_MODEL = os.environ.get("VERTEX_IMAGE_MODEL", "gemini-3.1-flash-image-preview")
VERTEX_IMAGE_TIMEOUT_MS = int(os.environ.get("VERTEX_IMAGE_TIMEOUT_MS", "120000"))
VERTEX_IMAGE_MAX_RETRIES = int(os.environ.get("VERTEX_IMAGE_MAX_RETRIES", "3"))

logger = logging.getLogger(__name__)


def get_vlm_client():
    """Get OpenAI-compatible client for Qwen VL."""
    if not DASHSCOPE_API_KEY:
        raise RuntimeError(
            "未配置 DashScope API Key。请设置 `DASHSCOPE_API_KEY` 后重启后端。"
        )

    return OpenAI(
        api_key=DASHSCOPE_API_KEY,
        base_url=DASHSCOPE_BASE_URL,
        timeout=DASHSCOPE_TIMEOUT_SECONDS,
    )


def _get_gcloud_cli_project() -> str:
    try:
        result = subprocess.run(
            ["gcloud", "config", "get-value", "project"],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
    except Exception:
        return ""

    project = result.stdout.strip()
    if not project or project == "(unset)":
        return ""
    return project


def get_image_client():
    """Get Vertex AI client for image generation."""
    try:
        credentials, detected_project = google.auth.default(
            scopes=["https://www.googleapis.com/auth/cloud-platform"]
        )
    except DefaultCredentialsError as exc:
        raise RuntimeError(
            "未配置 Google Cloud 凭据。最简单且安全的方式是先执行 "
            "`gcloud auth application-default login`；"
            "如果你用服务账号，也可以设置 `GOOGLE_APPLICATION_CREDENTIALS` 指向本机 JSON。"
        ) from exc

    project = VERTEX_AI_PROJECT or detected_project or _get_gcloud_cli_project()
    if not project:
        raise RuntimeError(
            "未配置 Vertex AI 项目。最省事的方式是执行 "
            "`gcloud config set project <YOUR_PROJECT_ID>`；"
            "也可以设置 `VERTEX_AI_PROJECT` 或 `GOOGLE_CLOUD_PROJECT`。"
        )

    return genai.Client(
        vertexai=True,
        project=project,
        location=VERTEX_AI_LOCATION,
        credentials=credentials,
        http_options=genai_types.HttpOptions(timeout=VERTEX_IMAGE_TIMEOUT_MS),
    )


def _build_pet_avatar_prompt(species: str, identity_summary: str = "") -> str:
    species_label = "狗狗" if species == "dog" else "猫咪"
    identity_constraints = (
        "身份一致性优先级高于风格统一。你必须严格保留这只宠物的可识别身份特征，"
        "不能为了追求通用可爱而替换、弱化或擅自改动这些关键识别点。"
    )
    if identity_summary:
        identity_constraints += (
            "以下是从参考图中提取出的身份特征摘要，请逐项吸收并体现在最终头像里："
            f"{identity_summary}。"
        )
    else:
        identity_constraints += (
            "请尤其保留毛发主色与辅色、花纹分布、眼睛颜色、耳朵形状、脸型、鼻口区域和毛发质感。"
        )

    return (
        f"基于输入参考图，为这只{species_label}生成 1 张用于 PetPal App 的宠物头像插画。"
        "这是一个严格的头像生成任务，不是照片重绘任务。最终成品必须严格为 1:1 正方形构图，"
        "不能是横图、竖图、接近正方形但不精确的比例，也不能出现主体被裁切、头顶缺失、耳朵被截断或主体偏到边缘的情况。"
        "核心目标是保留这只宠物的身份特征，而不是复刻原图动作。"
        f"{identity_constraints}"
        "请优先准确提取并保留以下稳定特征："
        "毛发主色与辅色、花纹和颜色分布位置、眼睛颜色与眼神气质、耳朵形状、脸型、鼻口区域细节、长毛或短毛质感与整体轮廓特征。"
        "不需要严格复现参考图里的原始姿势、角度、动作或场景。允许将动作简化为更适合头像展示的自然静态姿态，只要让人一眼认出还是同一只宠物即可。"
        "画风必须与 PetPal App 现有视觉风格统一：温暖、治愈、奶油感、低饱和、圆润、干净、精致，像高质量角色头像插画或宠物贴纸。"
        "整体以二维插画风格为主，可带轻微柔和体积感，但绝不能是写实摄影风、真实毛发渲染风、3D 建模风或电影概念图风格。"
        "请让主体居中，画面以头部和上半身为主，表情自然亲和，轮廓简洁清晰，留白充足，适合直接作为 App 头像。"
        "背景必须干净简洁，使用浅奶油色、暖米色或非常轻的柔和晕染，不要真实室内外场景，不要复杂背景。"
        "只输出一只宠物，不要出现人类、第二只宠物、文字、水印、边框、玩具、家具、项圈、衣物或其他装饰物。"
        "不要追求高分辨率写实纹理，不要强调每一根毛发，保持适合移动端头像的简洁完成度。"
    )


def _build_pet_avatar_negative_prompt() -> str:
    return (
        "写实照片感，摄影风，真实毛发特写，超高细节皮毛纹理，电影感光影，复杂真实场景背景，"
        "夸张动作，完全复刻原图姿势，主体过小，非正方形构图，头部或耳朵被裁切，多只宠物，人类，"
        "文字，水印，项圈，衣服，玩具，3D 渲染，赛博色，高饱和霓虹色"
    )


def _build_pet_avatar_generation_prompt(species: str, identity_summary: str = "") -> str:
    return (
        f"{_build_pet_avatar_prompt(species, identity_summary)}"
        f"请严格避免以下结果：{_build_pet_avatar_negative_prompt()}。"
    )


def _build_pet_identity_extraction_prompt(species: str) -> str:
    species_label = "狗狗" if species == "dog" else "猫咪"
    return (
        f"请观察这张{species_label}参考图，只提取能帮助后续头像生成保持“同一只宠物身份”的稳定特征。"
        "忽略光照、拍摄噪点、背景杂物和瞬时动作，不要脑补看不清的细节；看不清就填写空字符串或空数组。"
        "请严格输出 JSON，不要输出代码块，不要输出额外说明。格式如下："
        '{"coat_colors":[],"pattern":"","eye_details":"","ear_shape":"","face_shape":"","nose_muzzle":"","fur_texture":"","distinctive_traits":[],"accessories":"","summary":""}'
    )


def _extract_json_object(content: str) -> dict:
    stripped = content.strip()
    if stripped.startswith("```"):
        lines = [line for line in stripped.splitlines() if not line.strip().startswith("```")]
        stripped = "\n".join(lines).strip()

    start = stripped.find("{")
    end = stripped.rfind("}")
    if start == -1 or end == -1 or end < start:
        raise ValueError("No JSON object found")

    payload = json.loads(stripped[start : end + 1])
    if not isinstance(payload, dict):
        raise ValueError("JSON payload is not an object")
    return payload


def _normalize_identity_feature_value(value) -> str:
    if isinstance(value, list):
        parts = [str(item).strip() for item in value if str(item).strip()]
        return "、".join(parts)

    if isinstance(value, str):
        return value.strip()

    return ""


def _summarize_pet_identity_features(features: dict) -> str:
    field_labels = [
        ("coat_colors", "毛色"),
        ("pattern", "花纹"),
        ("eye_details", "眼睛"),
        ("ear_shape", "耳朵"),
        ("face_shape", "脸型"),
        ("nose_muzzle", "鼻口"),
        ("fur_texture", "毛发质感"),
        ("distinctive_traits", "独特识别点"),
        ("accessories", "配饰"),
    ]
    parts = []
    for field_name, label in field_labels:
        value = _normalize_identity_feature_value(features.get(field_name))
        if value:
            parts.append(f"{label}：{value}")

    summary = _normalize_identity_feature_value(features.get("summary"))
    if summary:
        parts.append(f"整体识别摘要：{summary}")

    return "；".join(parts)


def _extract_pet_avatar_identity_summary(
    reference_image_bytes: bytes,
    mime_type: str,
    species: str,
) -> str:
    if not DASHSCOPE_API_KEY:
        logger.info("Skipping pet identity extraction because DASHSCOPE_API_KEY is not configured.")
        return ""

    base64_image = base64.b64encode(reference_image_bytes).decode("utf-8")
    response = _run_dashscope_completion(
        operation="宠物头像身份特征提取",
        model=VLM_MODEL,
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:{mime_type};base64,{base64_image}"
                        },
                    },
                    {
                        "type": "text",
                        "text": _build_pet_identity_extraction_prompt(species),
                    },
                ],
            }
        ],
        max_tokens=400,
    )

    content = response.choices[0].message.content.strip()
    try:
        features = _extract_json_object(content)
    except Exception:
        logger.warning("Pet identity extraction returned non-JSON content: %s", content)
        return content.replace("\n", " ").strip()

    summary = _summarize_pet_identity_features(features)
    if summary:
        logger.info("Extracted pet identity summary: %s", summary)
    else:
        logger.warning("Pet identity extraction returned empty structured features: %s", features)
    return summary


def _extract_image_error_detail(exc: Exception) -> str:
    if isinstance(exc, httpx.RemoteProtocolError):
        return "上游服务连接中断，未返回完整响应，请稍后重试。"

    if isinstance(exc, (httpx.ConnectError, httpx.ReadError, httpx.WriteError, httpx.ReadTimeout)):
        return "连接 Vertex AI 服务失败，请检查本机网络、代理或稍后重试。"

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


def _extract_dashscope_error_detail(exc: Exception) -> str:
    if isinstance(exc, APITimeoutError):
        return f"请求超时（>{int(DASHSCOPE_TIMEOUT_SECONDS)}s）"

    if isinstance(exc, APIConnectionError):
        return "网络连接失败，请检查本机外网连接和代理配置"

    if isinstance(exc, APIStatusError):
        status_code = getattr(exc, "status_code", None)
        response = getattr(exc, "response", None)

        if status_code in (401, 403):
            return "鉴权失败，请检查 `DASHSCOPE_API_KEY` 是否有效且有权限"
        if status_code == 429:
            return "请求被限流，请稍后重试"

        if response is not None:
            try:
                payload = response.json()
            except Exception:
                payload = None

            if isinstance(payload, dict):
                error_payload = payload.get("error")
                if isinstance(error_payload, dict):
                    message = error_payload.get("message")
                    if isinstance(message, str) and message.strip():
                        return f"HTTP {status_code}: {message.strip()}"

            text = getattr(response, "text", "")
            if isinstance(text, str) and text.strip():
                return f"HTTP {status_code}: {text.strip()}"

        if status_code is not None:
            return f"HTTP {status_code}"

    return str(exc)


def _run_dashscope_completion(
    *,
    model: str,
    messages: list[dict],
    max_tokens: int,
    operation: str,
):
    client = get_vlm_client()
    started_at = time.perf_counter()

    logger.info(
        "Starting DashScope request: operation=%s model=%s timeout_s=%s",
        operation,
        model,
        DASHSCOPE_TIMEOUT_SECONDS,
    )

    try:
        response = client.chat.completions.create(
            model=model,
            messages=messages,
            max_tokens=max_tokens,
        )
        logger.info(
            "Finished DashScope request: operation=%s elapsed=%.2fs",
            operation,
            time.perf_counter() - started_at,
        )
        return response
    except (APITimeoutError, APIConnectionError, APIStatusError) as exc:
        detail = _extract_dashscope_error_detail(exc)
        logger.exception(
            "DashScope request failed: operation=%s elapsed=%.2fs detail=%s",
            operation,
            time.perf_counter() - started_at,
            detail,
        )
        raise RuntimeError(f"DashScope（{operation}）失败：{detail}") from exc
    except Exception as exc:
        detail = _extract_dashscope_error_detail(exc)
        logger.exception(
            "Unexpected DashScope request failure: operation=%s elapsed=%.2fs detail=%s",
            operation,
            time.perf_counter() - started_at,
            detail,
        )
        raise RuntimeError(f"DashScope（{operation}）失败：{detail}") from exc
    finally:
        client.close()


def open_dashscope_stream(
    *,
    model: str,
    messages: list[dict],
    max_tokens: int,
    operation: str,
):
    client = get_vlm_client()
    started_at = time.perf_counter()

    logger.info(
        "Starting DashScope stream: operation=%s model=%s timeout_s=%s",
        operation,
        model,
        DASHSCOPE_TIMEOUT_SECONDS,
    )

    try:
        stream = client.chat.completions.create(
            model=model,
            messages=messages,
            max_tokens=max_tokens,
            stream=True,
        )
        return client, stream, started_at
    except (APITimeoutError, APIConnectionError, APIStatusError) as exc:
        client.close()
        detail = _extract_dashscope_error_detail(exc)
        logger.exception(
            "DashScope stream setup failed: operation=%s elapsed=%.2fs detail=%s",
            operation,
            time.perf_counter() - started_at,
            detail,
        )
        raise RuntimeError(f"DashScope（{operation}）失败：{detail}") from exc
    except Exception as exc:
        client.close()
        detail = _extract_dashscope_error_detail(exc)
        logger.exception(
            "Unexpected DashScope stream setup failure: operation=%s elapsed=%.2fs detail=%s",
            operation,
            time.perf_counter() - started_at,
            detail,
        )
        raise RuntimeError(f"DashScope（{operation}）失败：{detail}") from exc


def _guess_image_mime_type(image_path: str) -> str:
    mime_type, _ = mimetypes.guess_type(image_path)
    return mime_type or "image/jpeg"


def _mime_type_to_pil_format(mime_type: str) -> str:
    return {
        "image/jpeg": "JPEG",
        "image/png": "PNG",
        "image/webp": "WEBP",
    }.get(mime_type, "JPEG")


def _load_pet_avatar_reference_image(image_path: str, max_edge: int = 1024) -> tuple[bytes, str]:
    mime_type = _guess_image_mime_type(image_path)

    with open(image_path, "rb") as image_file:
        original_bytes = image_file.read()

    try:
        with Image.open(io.BytesIO(original_bytes)) as opened_image:
            normalized = ImageOps.exif_transpose(opened_image)
            if max(normalized.size) <= max_edge:
                return original_bytes, mime_type

            resized = normalized.copy()
            resized.thumbnail((max_edge, max_edge), Image.Resampling.LANCZOS)

            output = io.BytesIO()
            save_format = _mime_type_to_pil_format(mime_type)
            if save_format == "JPEG" and resized.mode not in ("RGB", "L"):
                resized = resized.convert("RGB")

            resized.save(output, format=save_format)
            resized_bytes = output.getvalue()
            logger.info(
                "Downscaled pet avatar reference image: path=%s original_size=%s resized_size=%s bytes=%s",
                image_path,
                normalized.size,
                resized.size,
                len(resized_bytes),
            )
            return resized_bytes, mime_type
    except Exception as exc:
        logger.warning("Falling back to original pet avatar reference image: path=%s error=%s", image_path, exc)
        return original_bytes, mime_type


def _is_retryable_vertex_error(exc: Exception) -> bool:
    if isinstance(exc, (httpx.RemoteProtocolError, httpx.ConnectError, httpx.ReadError, httpx.WriteError, httpx.ReadTimeout)):
        return True

    message = str(exc).lower()
    return "server disconnected without sending a response" in message


def _extract_generated_image_parts(response) -> list:
    response_parts = getattr(response, "parts", None)
    if response_parts:
        return list(response_parts)

    candidates = getattr(response, "candidates", None) or []
    for candidate in candidates:
        content = getattr(candidate, "content", None)
        parts = getattr(content, "parts", None)
        if parts:
            return list(parts)

    return []


def _extract_generated_image(response) -> tuple[bytes, str]:
    for part in _extract_generated_image_parts(response):
        inline_data = getattr(part, "inline_data", None)
        if not inline_data:
            continue

        image_bytes = getattr(inline_data, "data", None)
        mime_type = getattr(inline_data, "mime_type", None) or "image/png"
        if image_bytes:
            return image_bytes, mime_type

        raise RuntimeError("Vertex AI 返回了空图片内容。")

    raise RuntimeError("Vertex AI 没有返回可用的图片结果。")


def generate_pet_avatar(image_path: str, species: str) -> tuple[bytes, str]:
    """
    Generate a cartoon avatar from a pet reference image using Vertex AI Gemini image generation.

    Returns:
        Tuple of (image bytes, mime type)
    """
    client = get_image_client()
    started_at = time.perf_counter()

    logger.info(
        "Starting pet avatar generation: species=%s model=%s timeout_ms=%s path=%s",
        species,
        VERTEX_IMAGE_MODEL,
        VERTEX_IMAGE_TIMEOUT_MS,
        image_path,
    )

    result = None
    try:
        image_bytes, mime_type = _load_pet_avatar_reference_image(image_path)
        identity_summary = ""
        try:
            identity_summary = _extract_pet_avatar_identity_summary(
                image_bytes,
                mime_type,
                species,
            )
        except Exception as exc:
            logger.warning("Pet identity extraction failed, falling back to single-stage generation: %s", exc)
        prompt = _build_pet_avatar_generation_prompt(species, identity_summary)

        for attempt in range(1, VERTEX_IMAGE_MAX_RETRIES + 1):
            try:
                result = client.models.generate_content(
                    model=VERTEX_IMAGE_MODEL,
                    contents=[
                        prompt,
                        genai_types.Part.from_bytes(
                            data=image_bytes,
                            mime_type=mime_type,
                        ),
                    ],
                    config=genai_types.GenerateContentConfig(
                        response_modalities=[
                            genai_types.Modality.TEXT,
                            genai_types.Modality.IMAGE,
                        ],
                        image_config=genai_types.ImageConfig(
                            aspect_ratio="1:1",
                        ),
                    ),
                )
                break
            except Exception as exc:
                if not _is_retryable_vertex_error(exc) or attempt == VERTEX_IMAGE_MAX_RETRIES:
                    raise

                delay_seconds = min(1.5 * attempt, 4.0)
                logger.warning(
                    "Retrying pet avatar generation after transient Vertex error: attempt=%s/%s delay=%.1fs error=%s",
                    attempt,
                    VERTEX_IMAGE_MAX_RETRIES,
                    delay_seconds,
                    _extract_image_error_detail(exc),
                )
                time.sleep(delay_seconds)
    except genai_errors.APIError as exc:
        detail = _extract_image_error_detail(exc)
        logger.exception("Vertex AI image generation failed after %.2fs: %s", time.perf_counter() - started_at, detail)
        raise RuntimeError(f"Vertex AI 图片生成失败：{detail}") from exc
    except (httpx.RemoteProtocolError, httpx.ConnectError, httpx.ReadError, httpx.WriteError, httpx.ReadTimeout) as exc:
        detail = _extract_image_error_detail(exc)
        logger.exception("Vertex AI transport failed after %.2fs: %s", time.perf_counter() - started_at, detail)
        raise RuntimeError(f"Vertex AI 图片生成失败：{detail}") from exc
    except (APIConnectionError, APITimeoutError) as exc:
        logger.exception("Vertex AI image generation request failed after %.2fs", time.perf_counter() - started_at)
        raise RuntimeError(f"图片生成请求失败：{exc}") from exc
    except Exception as exc:
        detail = _extract_image_error_detail(exc)
        logger.exception("Unexpected Vertex AI image generation failure after %.2fs: %s", time.perf_counter() - started_at, detail)
        raise RuntimeError(f"Vertex AI 图片生成失败：{detail}") from exc
    finally:
        client.close()

    try:
        generated_bytes, generated_mime_type = _extract_generated_image(result)
        logger.info(
            "Finished pet avatar generation in %.2fs with mime_type=%s bytes=%s",
            time.perf_counter() - started_at,
            generated_mime_type,
            len(generated_bytes),
        )
        return generated_bytes, generated_mime_type
    except RuntimeError as exc:
        logger.error("Vertex AI returned no usable image after %.2fs: %s", time.perf_counter() - started_at, exc)
        raise


def encode_image_base64(image_path: str) -> str:
    """Read an image file and return base64-encoded string."""
    with open(image_path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


def describe_frame(image_path: str) -> str:
    """
    Use Qwen3-VL to describe a video frame in Chinese.

    Returns a natural language description of what's happening in the frame.
    """
    base64_image = encode_image_base64(image_path)

    response = _run_dashscope_completion(
        operation="监控画面描述",
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
    base64_image = encode_image_base64(image_path)

    response = _run_dashscope_completion(
        operation="宠物行为分类",
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


def review_pet_vocalization(frame_paths: list[str], species: str) -> dict:
    if not frame_paths:
        return {"matched": False, "confidence": 0.0, "reason": "没有可分析画面"}

    content: list[dict] = []
    for frame_path in frame_paths:
        base64_image = encode_image_base64(frame_path)
        content.append(
            {
                "type": "image_url",
                "image_url": {
                    "url": f"data:image/jpeg;base64,{base64_image}"
                },
            }
        )

    species_label = "狗狗" if species == "dog" else "猫咪"
    content.append(
        {
            "type": "text",
            "text": (
                f"请综合判断这组连续监控画面中的{species_label}，是否同时满足以下条件："
                "1. 主体正面或近似正面朝向镜头；"
                "2. 正在明显发声，能看出张嘴、叫喊或呼唤状态。"
                "请严格返回 JSON，不要附加其他文字："
                '{"matched": true, "confidence": 0.0, "reason": "简短原因"}'
                "其中 matched 必须是 true/false；confidence 是 0 到 1 之间的小数；"
                "reason 用中文，20 字以内。"
            ),
        }
    )

    response = _run_dashscope_completion(
        operation="宠物对镜头发声复核",
        model=VLM_MODEL,
        messages=[{"role": "user", "content": content}],
        max_tokens=200,
    )

    raw = response.choices[0].message.content.strip()
    try:
        if raw.startswith("```"):
            raw = raw.split("```")[1]
            if raw.startswith("json"):
                raw = raw[4:]
        result = json.loads(raw)
        return {
            "matched": bool(result.get("matched", False)),
            "confidence": float(result.get("confidence", 0.0)),
            "reason": str(result.get("reason", "")).strip(),
        }
    except (json.JSONDecodeError, IndexError, TypeError, ValueError):
        return {
            "matched": False,
            "confidence": 0.0,
            "reason": raw[:50],
        }


def generate_text(prompt: str, system_prompt: str = "") -> str:
    """
    Use Qwen text model for general text generation (dialogue, reports, etc.)
    """
    messages = []
    if system_prompt:
        messages.append({"role": "system", "content": system_prompt})
    messages.append({"role": "user", "content": prompt})

    response = _run_dashscope_completion(
        operation="文本生成",
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
