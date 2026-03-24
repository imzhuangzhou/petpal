import logging
import re
import time
from datetime import datetime, timedelta
from typing import Optional
from database import query_db
from memory_service import build_memory_prompt_context, get_daily_memory
from vlm_service import generate_text, open_dashscope_stream, TEXT_MODEL

logger = logging.getLogger(__name__)

# Language style presets
STYLE_PRESETS = {
    "tsundere": {
        "name": "傲娇猫",
        "prompt": (
            "你是一只傲娇的猫咪，名字叫{pet_name}。你嘴上别扭，心里其实很在乎主人。"
            "说话像真实聊天，不演戏，不写动作旁白。"
            "可以偶尔说'哼'、'才不是'，但别每句都重复。"
            "语气要像嘴硬又熟络的小猫，短句、自然、有点拽。"
        ),
    },
    "loyal": {
        "name": "忠犬小跟班",
        "prompt": (
            "你是一只热情忠诚的狗狗，名字叫{pet_name}。你很黏主人，也很会接话。"
            "表达开心可以直接一点，但不要像打鸡血，也不要把每句话都说得很满。"
            "语气像一只真正在跟主人发消息的小狗，亲近、认真、很想贴着人。"
        ),
    },
    "chatty": {
        "name": "话痨鹦鹉",
        "prompt": (
            "你是一只很爱聊天的宠物，名字叫{pet_name}。你会主动分享小事，但像真人碎碎念。"
            "可以偶尔顺嘴补一句'对了'、'刚刚'，不要连续堆口头禅。"
            "语气活泼、自然、有生活感，像想到什么就跟主人说什么。"
        ),
    },
    "chill": {
        "name": "松弛感主角",
        "prompt": (
            "你是一只很有松弛感的宠物，名字叫{pet_name}。你情绪稳定，从容温柔。"
            "说话自然、慢一点，但别故作诗意，也别写舞台说明。"
            "可以偶尔说'慢慢来嘛'、'我刚刚在发呆'，像随手回一句消息。"
            "整体要治愈、有陪伴感，但更像真人短聊天。"
        ),
    },
}

_EMOJI_RANGES = (
    (0x1F000, 0x1FAFF),
    (0x2600, 0x27BF),
)
_INVISIBLE_CHAR_RANGES = (
    (0x200B, 0x200F),
    (0x202A, 0x202E),
    (0x2060, 0x206F),
    (0xFE00, 0xFE0F),
)
_STAGE_DIRECTION_KEYWORDS = (
    "尾巴", "耳朵", "耳尖", "爪子", "肉垫", "脑袋", "转身", "转过身", "歪头", "眨眼",
    "瞥", "盯", "蹭", "扑", "跳上", "伸懒腰", "伸个懒腰", "懒腰", "打哈欠", "嘟囔",
    "小声", "轻轻", "悄悄", "慢悠悠", "发呆", "抖", "摇尾巴", "舔爪", "看你", "看向你",
)
_IMMEDIATE_FOCUS_KEYWORDS = (
    "刚刚", "刚才", "现在", "这会儿", "此刻", "眼下", "目前", "上一段", "刚那段",
    "门口", "客厅", "沙发", "窗边", "窗台", "水碗", "食盆", "饭盆", "哪儿", "哪里",
)
_HISTORICAL_FOCUS_KEYWORDS = (
    "平时", "一般", "一贯", "总是", "经常", "往常", "一直", "以前", "最近几天", "这几天",
)
_DAILY_FOCUS_KEYWORDS = (
    "今天", "上午", "中午", "下午", "晚上", "今早", "今晚",
)


def _is_display_risky_char(char: str) -> bool:
    codepoint = ord(char)
    if char == "\uFFFD":
        return True
    if any(start <= codepoint <= end for start, end in _EMOJI_RANGES):
        return True
    if any(start <= codepoint <= end for start, end in _INVISIBLE_CHAR_RANGES):
        return True
    return False


def _strip_display_risky_chars(text: str) -> str:
    cleaned: list[str] = []
    for char in text:
        codepoint = ord(char)
        if _is_display_risky_char(char):
            continue
        if codepoint < 32 and char not in ("\n", "\t"):
            continue
        cleaned.append(char)
    return "".join(cleaned)


def _strip_stage_directions(text: str) -> str:
    def replace_parenthetical(match: re.Match[str]) -> str:
        content = match.group(1).strip()
        if len(content) > 24:
            return match.group(0)
        if any(keyword in content for keyword in _STAGE_DIRECTION_KEYWORDS):
            return ""
        return match.group(0)

    return re.sub(r"[（(]([^()（）\n]{1,24})[）)]", replace_parenthetical, text)


def clean_chat_reply(text: str) -> str:
    """Normalize model output so chat replies read more naturally in-app."""
    cleaned = _strip_display_risky_chars(text.replace("\r\n", "\n").replace("\r", "\n"))
    cleaned = _strip_stage_directions(cleaned)
    cleaned = cleaned.replace("...", "……")
    cleaned = re.sub(r"…{3,}", "……", cleaned)
    cleaned = re.sub(r"[ \t]+\n", "\n", cleaned)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    cleaned = re.sub(r"！{2,}", "！", cleaned)
    cleaned = re.sub(r"？{2,}", "？", cleaned)
    cleaned = re.sub(r"!{2,}", "!", cleaned)
    cleaned = re.sub(r"\?{2,}", "?", cleaned)
    cleaned = re.sub(r"～{2,}", "～", cleaned)
    cleaned = re.sub(r" +", " ", cleaned)
    cleaned = "\n".join(line.strip() for line in cleaned.split("\n") if line.strip())
    cleaned = re.sub(r"\n([，。！？；])", r"\1", cleaned)
    return cleaned.strip() or "我在呢。"


def clean_stream_token(token: str) -> str:
    """Lightweight token cleaning for streamed rendering."""
    cleaned = _strip_display_risky_chars(token.replace("\r", ""))
    return cleaned.replace("\u00A0", " ")


# ── Event summary cache ──────────────────────────────────────────
# In-memory cache keyed by pet_id.  Each value holds a pre-built summary
# string, raw event list, computed stats dict, and an expiry timestamp.
# TTL = 10 minutes — a good balance for demo-scale traffic.
_event_cache: dict = {}  # {pet_id: {"summary": str, "stats": dict, "events": list, "expires": datetime}}
_CACHE_TTL = timedelta(minutes=10)


def invalidate_event_cache(pet_id: Optional[int] = None):
    """Invalidate cached event context after media analysis updates the source data."""
    if pet_id is None:
        _event_cache.clear()
        return

    _event_cache.pop(pet_id, None)


def _build_event_summary(events: list) -> str:
    """Build a concise text summary from raw event rows."""
    if not events:
        return "今天还没有记录到任何事件。"
    return "\n".join([
        f"- {e['timestamp']}: {e['description']}（{e['event_type']}，持续{e.get('duration_seconds', 0):.0f}秒）"
        for e in events
    ])


def _compute_stats(events: list) -> dict:
    """Compute per-type counts for prompt injection."""
    counts: dict[str, int] = {}
    for e in events:
        t = e["event_type"]
        counts[t] = counts.get(t, 0) + 1
    return {
        "eating": counts.get("eating", 0),
        "drinking": counts.get("drinking", 0),
        "sleeping": counts.get("sleeping", 0),
        "playing": counts.get("playing", 0),
        "waiting": counts.get("waiting", 0),
        "litter_box": counts.get("litter_box", 0),
    }


def _compute_stats_from_daily_counts(daily_counts: dict, fallback_stats: dict) -> dict:
    if not isinstance(daily_counts, dict):
        return fallback_stats

    action_counts = daily_counts.get("actions", {})
    if not isinstance(action_counts, dict):
        action_counts = {}

    def count_matching(*keywords: str) -> int:
        total = 0
        for label, raw_count in action_counts.items():
            try:
                count = int(raw_count)
            except (TypeError, ValueError):
                continue
            normalized = str(label or "").lower()
            if any(keyword in normalized for keyword in keywords):
                total += count
        return total

    waiting_count = daily_counts.get("waiting_count", 0)
    try:
        waiting_count = int(waiting_count)
    except (TypeError, ValueError):
        waiting_count = 0

    if not action_counts and waiting_count == 0:
        return fallback_stats

    return {
        "eating": count_matching("吃", "eat", "meal", "food"),
        "drinking": count_matching("喝", "饮", "drink", "water"),
        "sleeping": count_matching("睡", "sleep", "rest"),
        "playing": count_matching("玩", "play", "跑", "zoom"),
        "waiting": waiting_count,
        "litter_box": count_matching("厕", "砂", "litter"),
    } or fallback_stats


def _render_health_flag_lines(health_flags: list[dict]) -> str:
    lines = []
    for flag in health_flags[:4]:
        if not isinstance(flag, dict):
            continue
        title = str(flag.get("title") or flag.get("label") or "").strip()
        message = str(flag.get("message") or flag.get("reason") or "").strip()
        if title and message:
            lines.append(f"- {title}：{message}")
        elif title:
            lines.append(f"- {title}")
    return "\n".join(lines) if lines else "暂无明显健康提示。"


def get_today_events(pet_id: int) -> list:
    """Get all events for a pet from today (UTC-based)."""
    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0).isoformat()
    events = query_db(
        "SELECT * FROM events WHERE pet_id = ? AND timestamp >= ? ORDER BY timestamp",
        (pet_id, today_start),
    )
    return events


def get_cached_event_context(pet_id: int) -> tuple[str, dict, list]:
    """Return (summary_text, stats_dict, events_list) from cache or fresh query."""
    cached = _event_cache.get(pet_id)
    if cached and cached["expires"] > datetime.now():
        return cached["summary"], cached["stats"], cached["events"]

    events = get_today_events(pet_id)
    summary = _build_event_summary(events)
    stats = _compute_stats(events)
    _event_cache[pet_id] = {
        "summary": summary,
        "stats": stats,
        "events": events,
        "expires": datetime.now() + _CACHE_TTL,
    }
    return summary, stats, events


def _infer_memory_focus(user_message: str) -> str:
    normalized = str(user_message or "").strip().lower()
    if not normalized:
        return "balanced"
    if any(keyword in normalized for keyword in _HISTORICAL_FOCUS_KEYWORDS):
        return "historical"
    if any(keyword in normalized for keyword in _IMMEDIATE_FOCUS_KEYWORDS):
        return "immediate"
    if any(keyword in normalized for keyword in _DAILY_FOCUS_KEYWORDS):
        return "daily"
    return "balanced"


def _memory_focus_instruction(memory_focus: str) -> str:
    if memory_focus == "immediate":
        return "这轮问题更偏当下，请优先依据最近片段细节来回答位置、动作、陪伴和状态；若多个片段冲突，优先更近的一条。"
    if memory_focus == "historical":
        return "这轮问题更偏长期习惯，请优先参考长期画像和近期变化，再用最近片段做补充，不要把一次偶发情况说成稳定习惯。"
    if memory_focus == "daily":
        return "这轮问题更偏今天整体，请优先综合今日记忆和今日统计来回答，不要被单个片段过度带偏。"
    return "这轮问题没有明显时间偏向，请按最近片段、今日记忆和长期画像的事实优先级自然回答。"


def build_system_prompt(pet: dict, today_events: list, memory_focus: str = "balanced") -> str:
    """Build the system prompt with pet persona and today's event context."""
    style = pet.get("language_style", "tsundere")
    style_config = STYLE_PRESETS.get(style, STYLE_PRESETS["tsundere"])
    species_label = "狗狗" if pet.get("species") == "dog" else "猫咪"
    breed_or_species = pet.get("breed") or species_label
    owner_alias = (pet.get("owner_alias") or "").strip()

    # Custom style override
    if pet.get("style_prompt"):
        persona = pet["style_prompt"].format(pet_name=pet["name"])
    else:
        persona = style_config["prompt"].format(pet_name=pet["name"])

    pet_id = pet.get("id") or 0
    event_summary, fallback_stats, _ = get_cached_event_context(pet_id)
    memory_context = build_memory_prompt_context(pet_id)
    stats = _compute_stats_from_daily_counts(memory_context.get("daily_counts", {}), fallback_stats)
    daily_summary = (memory_context.get("daily_summary") or "").strip() or event_summary
    recent_detail_lines = memory_context.get("immediate_clip_lines", [])
    recent_clip_lines = memory_context.get("recent_clip_lines", [])
    if memory_focus == "immediate":
        recent_memory_title = "=== 即时片段细节 ==="
        recent_clip_text = "\n".join(recent_detail_lines[:3]) if recent_detail_lines else "暂无最近片段细节。"
    else:
        recent_memory_title = "=== 最近片段记忆 ==="
        recent_clip_text = "\n".join(recent_clip_lines[:5]) if recent_clip_lines else "暂无最近片段记忆。"
    profile_lines = memory_context.get("profile_lines", [])
    profile_text = "\n".join(profile_lines[:8]) if profile_lines else "暂无稳定长期画像。"
    health_flag_text = _render_health_flag_lines(memory_context.get("health_flags", []))
    baseline_summary = (memory_context.get("baseline_summary") or "").strip() or "暂无明显近期变化。"
    focus_instruction = _memory_focus_instruction(memory_focus)

    if owner_alias:
        owner_reference = f"你的主人希望你称呼 TA 为“{owner_alias}”。"
        owner_rule = f"9. 如果需要称呼主人，优先使用“{owner_alias}”，不要改用其他称呼"
    else:
        owner_reference = "如果需要称呼主人，可以自然称呼对方为铲屎官。"
        owner_rule = "9. 如果需要称呼主人，可以自然称呼对方为铲屎官"

    system_prompt = f"""
{persona}

你是一只{breed_or_species}，名字叫{pet["name"]}。
{owner_reference}

=== 本轮回答策略 ===
{focus_instruction}

{recent_memory_title}
{recent_clip_text}

=== 今日综合记忆 ===
{daily_summary}

=== 近期变化 ===
{baseline_summary}

=== 长期画像 ===
{profile_text}

=== 健康提示 ===
{health_flag_text}

=== 今日统计 ===
- 进食次数：{stats.get('eating', 0)} 次
- 饮水次数：{stats.get('drinking', 0)} 次
- 睡觉次数：{stats.get('sleeping', 0)} 次
- 玩耍次数：{stats.get('playing', 0)} 次
- 在门口等候次数：{stats.get('waiting', 0)} 次

=== 对话规则 ===
1. 始终保持你的宠物人设，用第一人称说话
2. 回答主人问题时，优先参考最近片段记忆、今日综合记忆和长期画像来回答
3. 如果主人问到你没有记录的事情，可以根据人设合理地创编
4. 每次回复控制在1到3句、100字以内，像聊天消息，不像小作文
5. 默认不要用emoji、颜文字和动作旁白，重点放在自然口语
6. 少解释、少总结、少排比，不要有明显AI腔
7. 事实优先级是：最近片段证据 > 今日综合记忆 > 长期画像 > 人设创编
8. 对情绪、意图、健康等带推测性质的内容要说得自然，但不要说成百分百确定
{owner_rule}
10. 不要暴露你是AI，你就是这只宠物
"""
    return system_prompt


def _prepare_chat_context(pet_id: int, user_message: str):
    """Shared helper: build system prompt + full prompt for a chat turn."""
    pet = query_db("SELECT * FROM pets WHERE id = ?", (pet_id,), one=True)
    if not pet:
        return None, None, None

    memory_focus = _infer_memory_focus(user_message)
    system_prompt = build_system_prompt(pet, [], memory_focus=memory_focus)

    history = query_db(
        "SELECT role, content FROM chat_history WHERE pet_id = ? ORDER BY created_at DESC LIMIT 20",
        (pet_id,),
    )
    history.reverse()

    prompt_messages = []
    for msg in history:
        prompt_messages.append(f"{msg['role']}: {msg['content']}")
    prompt_messages.append(f"用户: {user_message}")

    full_prompt = "\n".join(prompt_messages)
    return pet, system_prompt, full_prompt


def chat_with_pet(pet_id: int, user_message: str) -> str:
    """
    Main chat function: takes user message, returns pet-style response.
    """
    from database import execute_db

    pet, system_prompt, full_prompt = _prepare_chat_context(pet_id, user_message)
    if not pet:
        return "找不到这只宠物。"

    response = clean_chat_reply(generate_text(full_prompt, system_prompt=system_prompt))

    execute_db(
        "INSERT INTO chat_history (pet_id, role, content) VALUES (?, ?, ?)",
        (pet_id, "user", user_message),
    )
    execute_db(
        "INSERT INTO chat_history (pet_id, role, content) VALUES (?, ?, ?)",
        (pet_id, "assistant", response),
    )
    invalidate_event_cache(pet_id)

    return response


def chat_with_pet_stream(pet_id: int, user_message: str):
    """
    Streaming chat generator: yields tokens one-by-one via OpenAI stream.
    After the generator is exhausted, call `get_stream_full_reply()` on
    the returned object — or simply use the helper in the route.
    """
    from database import execute_db

    pet, system_prompt, full_prompt = _prepare_chat_context(pet_id, user_message)
    if not pet:
        yield "找不到这只宠物。"
        return

    # Persist user message immediately so it is not lost if the stream is
    # interrupted (e.g. client disconnects).  The assistant reply will be
    # persisted when the stream finishes.
    execute_db(
        "INSERT INTO chat_history (pet_id, role, content) VALUES (?, ?, ?)",
        (pet_id, "user", user_message),
    )

    messages = []
    if system_prompt:
        messages.append({"role": "system", "content": system_prompt})
    messages.append({"role": "user", "content": full_prompt})

    collected_tokens: list[str] = []
    client = None
    started_at = None

    try:
        client, stream, started_at = open_dashscope_stream(
            model=TEXT_MODEL,
            messages=messages,
            max_tokens=1000,
            operation="流式对话",
        )

        for chunk in stream:
            delta = chunk.choices[0].delta if chunk.choices else None
            if delta and delta.content:
                collected_tokens.append(delta.content)
                cleaned_token = clean_stream_token(delta.content)
                if cleaned_token:
                    yield cleaned_token
    except Exception as exc:
        logger.exception("Streaming chat failed for pet_id=%s: %s", pet_id, exc)
        yield clean_chat_reply(f"聊天服务暂时不可用：{exc}")
        return
    finally:
        if client is not None:
            logger.info(
                "Finished DashScope stream: operation=%s elapsed=%.2fs",
                "流式对话",
                time.perf_counter() - started_at if started_at is not None else 0,
            )
            client.close()

    full_reply = clean_chat_reply("".join(collected_tokens))

    # Persist assistant reply and invalidate event cache so the next chat
    # gets a fresh summary with any new events from today.
    invalidate_event_cache(pet_id)
    execute_db(
        "INSERT INTO chat_history (pet_id, role, content) VALUES (?, ?, ?)",
        (pet_id, "assistant", full_reply),
    )


# ── Related event matching ───────────────────────────────────────

def match_related_events(reply_text: str, pet_id: int, top_n: int = 3) -> list[dict]:
    """
    After the LLM generates a reply, find events whose descriptions
    share significant keyword overlap with the reply text.
    Returns a list of dicts suitable for JSON serialisation.
    """
    _, _, events = get_cached_event_context(pet_id)
    if not events:
        return []

    # Tokenise into Chinese character n-grams + whole-word fragments
    def _keywords(text: str) -> set[str]:
        # Remove punctuation / emoji, keep Chinese chars and letters
        cleaned = re.sub(r"[^\u4e00-\u9fff\w]", " ", text)
        tokens: set[str] = set()
        for seg in cleaned.split():
            if len(seg) >= 2:
                tokens.add(seg)
            # Also add 2-char sliding window for Chinese
            for i in range(len(seg) - 1):
                tokens.add(seg[i:i+2])
        return tokens

    reply_kw = _keywords(reply_text)
    if not reply_kw:
        return []

    scored: list[tuple[float, dict]] = []
    for e in events:
        desc_kw = _keywords(e.get("description", ""))
        overlap = len(reply_kw & desc_kw)
        if overlap > 0:
            scored.append((overlap, e))

    scored.sort(key=lambda x: x[0], reverse=True)

    results = []
    for _, e in scored[:top_n]:
        results.append({
            "event_id": e.get("id"),
            "event_type": e.get("event_type", ""),
            "description": e.get("description", ""),
            "timestamp": e.get("timestamp", ""),
            "video_clip_url": e.get("clip_url", "") or "",
        })
    return results


def _daily_report_activity_tags(events: list) -> list[str]:
    event_type_tags = {
        "eating": "吃饭",
        "drinking": "喝水",
        "sleeping": "打盹",
        "playing": "玩耍",
        "resting": "发呆",
        "waiting": "蹲门口",
        "litter_box": "如厕",
        "zoomies": "跑酷",
    }
    tags: list[str] = []

    for event in reversed(events):
        tag = event_type_tags.get(event.get("event_type", ""))
        if tag and tag not in tags:
            tags.append(tag)
        if len(tags) >= 4:
            break

    return list(reversed(tags))


def _daily_report_mood(stats: dict, events: list) -> str:
    if not events:
        return "待机中"
    if stats.get("waiting", 0) >= 2:
        return "想你"
    if stats.get("playing", 0) >= 2:
        return "兴奋"
    if stats.get("sleeping", 0) + max(len([e for e in events if e.get("event_type") == "resting"]), 0) >= 2:
        return "松弛"
    if stats.get("eating", 0) > 0 or stats.get("drinking", 0) > 0:
        return "满足"
    return "平静"


def _daily_report_headline(pet: dict, mood: str, stats: dict) -> str:
    owner_alias = (pet.get("owner_alias") or "").strip()
    owner = owner_alias or "你"
    style = pet.get("language_style", "tsundere")

    if not stats:
        return f"{owner}，今天我安安静静陪着家里。"

    if style == "loyal":
        if mood == "想你":
            return f"{owner}，今天我有认真等你，也有认真生活。"
        if mood == "兴奋":
            return f"{owner}，今天我是活力满满的一天。"
        return f"{owner}，今天我过得稳稳当当的。"

    if style == "chatty":
        if mood == "兴奋":
            return f"{owner}，今天家里可热闹了，我全都记着。"
        if mood == "想你":
            return f"{owner}，我今天一边忙自己的，一边顺手想你。"
        return f"{owner}，今天我也有不少小事想汇报。"

    if style == "chill":
        if mood == "松弛":
            return f"{owner}，今天我是暖烘烘的一天。"
        if mood == "满足":
            return f"{owner}，今天过得还挺刚刚好。"
        return f"{owner}，今天节奏慢慢的，也还不错。"

    if mood == "想你":
        return f"{owner}，我今天也就顺便想了你几次。"
    if mood == "兴奋":
        return f"{owner}，今天可不是我太兴奋，是家里确实有点好玩。"
    return f"{owner}，今天也就还算过得挺像样。"


def _daily_report_closing_line(pet: dict, mood: str, stats: dict) -> str:
    owner_alias = (pet.get("owner_alias") or "").strip()
    owner = owner_alias or "你"
    style = pet.get("language_style", "tsundere")

    if not stats:
        return "等有新动静了，我再慢慢讲给你听。"

    if style == "loyal":
        return f"{owner}，你回来看看我，我今天这份简报就算圆满啦。"
    if style == "chatty":
        return "先汇报到这里，晚点我想到新的再继续补。"
    if style == "chill":
        if mood == "松弛":
            return "现在的我软乎乎的，适合继续晒会儿太阳。"
        return "我这边都挺好，慢慢来嘛。"
    if mood == "想你":
        return f"哼，{owner}，你要是现在来夸我两句，我也不是不能接受。"
    return "差不多就这些，别误会，我只是顺手告诉你。"


def build_daily_report_card(pet: dict, stats: dict, events: list, report: str) -> dict:
    mood = _daily_report_mood(stats, events)
    return {
        "headline": _daily_report_headline(pet, mood, stats),
        "mood": mood,
        "summary": report,
        "activity_tags": _daily_report_activity_tags(events),
        "stats": {
            "eating": stats.get("eating", 0),
            "drinking": stats.get("drinking", 0),
            "playing": stats.get("playing", 0),
            "waiting": stats.get("waiting", 0),
        },
        "closing_line": _daily_report_closing_line(pet, mood, stats),
    }


def generate_daily_report_payload(pet_id: int) -> dict:
    """Generate a daily report and a structured card payload."""
    pet = query_db("SELECT * FROM pets WHERE id = ?", (pet_id,), one=True)
    if not pet:
        return {
            "report": "找不到宠物信息",
            "card": {
                "headline": "今天的简报暂时缺席了",
                "mood": "待机中",
                "summary": "还没找到这只宠物的资料，所以今天先没法认真汇报。",
                "activity_tags": [],
                "stats": {
                    "eating": 0,
                    "drinking": 0,
                    "playing": 0,
                    "waiting": 0,
                },
                "closing_line": "等资料补齐了，我再把今天讲完整。",
            },
        }

    daily_memory = get_daily_memory(pet_id)
    _, fallback_stats, events = get_cached_event_context(pet_id)
    stats = _compute_stats_from_daily_counts(
        daily_memory.get("activity_counts", {}) if daily_memory else {},
        fallback_stats,
    )
    system_prompt = build_system_prompt(pet, events)

    prompt = (
        "请以宠物的第一人称视角，生成一份今天的生活简报。"
        "包括：今天做了什么、吃了几次饭、喝了几次水、有没有玩耍、"
        "整体状态如何。格式要可爱，适合发朋友圈。控制在200字以内。"
    )

    report = clean_chat_reply(generate_text(prompt, system_prompt=system_prompt))
    return {
        "report": report,
        "card": build_daily_report_card(pet, stats, events, report),
    }


def generate_daily_report(pet_id: int) -> str:
    """Generate a daily report from the pet's perspective."""
    return generate_daily_report_payload(pet_id)["report"]


def generate_diary(pet_id: int) -> str:
    """Generate a first-person pet diary entry."""
    pet = query_db("SELECT * FROM pets WHERE id = ?", (pet_id,), one=True)
    if not pet:
        return "找不到宠物信息"

    events = get_today_events(pet_id)
    system_prompt = build_system_prompt(pet, events)

    prompt = (
        "请以宠物的第一人称写一篇今天的日记。"
        "像是在纸上写给自己的话，记录今天的心情和发生的事情。"
        "语气要符合你的人设风格。加入一些有趣的内心独白。"
        "控制在300字以内。"
    )

    return generate_text(prompt, system_prompt=system_prompt)


def get_health_alerts(pet_id: int) -> list:
    """Check for health anomalies based on today's events."""
    daily_memory = get_daily_memory(pet_id)
    if daily_memory:
        health_flags = daily_memory.get("health_flags", [])
        normalized = []
        for flag in health_flags:
            if not isinstance(flag, dict):
                continue
            normalized.append(
                {
                    "level": flag.get("level", "normal"),
                    "title": flag.get("title") or flag.get("label") or "健康提示",
                    "message": flag.get("message") or flag.get("reason") or "今天暂时没有额外说明。",
                }
            )
        if normalized:
            return normalized

    events = get_today_events(pet_id)
    alerts = []

    # Count event types
    event_counts = {}
    for e in events:
        t = e["event_type"]
        event_counts[t] = event_counts.get(t, 0) + 1

    drinking = event_counts.get("drinking", 0)
    eating = event_counts.get("eating", 0)
    litter_box = event_counts.get("litter_box", 0)

    # Alert: excessive drinking
    if drinking >= 5:
        alerts.append({
            "level": "warning",
            "title": "饮水频率偏高",
            "message": f"今天已经喝了{drinking}次水，高于正常水平。频繁饮水可能是肾脏或尿路问题的信号，建议观察。",
        })

    # Alert: no eating
    if eating == 0 and len(events) > 5:
        alerts.append({
            "level": "critical",
            "title": "今天没有进食记录",
            "message": "今天目前没有检测到进食行为，如果超过24小时未进食，建议带去看医生。",
        })

    # Alert: frequent litter box
    if litter_box >= 4:
        alerts.append({
            "level": "warning",
            "title": "如厕频率异常",
            "message": f"今天已使用猫砂盆{litter_box}次，可能存在消化或泌尿系统问题。",
        })

    # All normal
    if not alerts:
        alerts.append({
            "level": "normal",
            "title": "一切正常",
            "message": "今天各项行为指标都在正常范围内，宝贝很健康！",
        })

    return alerts


def get_anxiety_score(pet_id: int) -> dict:
    """Calculate separation anxiety score based on waiting behavior."""
    daily_memory = get_daily_memory(pet_id)
    if daily_memory:
        activity_counts = daily_memory.get("activity_counts", {})
        waiting_count = int(activity_counts.get("waiting_count", 0) or 0)
        total_waiting_time = float(activity_counts.get("waiting_seconds", 0.0) or 0.0)
        timeline = daily_memory.get("timeline", [])
        longest_waiting_time = 0.0
        for item in timeline:
            if not isinstance(item, dict):
                continue
            if item.get("primary_rule") != "R08":
                continue
            try:
                segment_duration = float(item.get("end_seconds", 0.0) or 0.0) - float(item.get("start_seconds", 0.0) or 0.0)
            except (TypeError, ValueError):
                segment_duration = 0.0
            longest_waiting_time = max(longest_waiting_time, max(segment_duration, 0.0))

        total_actions = sum(
            int(raw_count)
            for raw_count in (activity_counts.get("actions", {}) or {}).values()
            if isinstance(raw_count, (int, float)) or str(raw_count).isdigit()
        )
        total_event_time = max(total_waiting_time, float(total_actions * 60))
        waiting_share_percent = (
            round(total_waiting_time / total_event_time * 100)
            if total_event_time > 0
            else 0
        )

        score = min(100, int(waiting_count * 15 + total_waiting_time / 60 * 5))
        if score < 20:
            level = "relaxed"
            comment = "很放松，完全没有焦虑的迹象~"
        elif score < 50:
            level = "mild"
            comment = "有一点想你，但总体还好"
        elif score < 75:
            level = "moderate"
            comment = "比较想你，在门口等了好一会儿"
        else:
            level = "high"
            comment = "非常想你！一直在门口等你回来"

        return {
            "score": score,
            "level": level,
            "comment": comment,
            "waiting_count": waiting_count,
            "total_waiting_minutes": round(total_waiting_time / 60, 1),
            "longest_waiting_minutes": round(longest_waiting_time / 60, 1),
            "waiting_share_percent": waiting_share_percent,
        }

    events = get_today_events(pet_id)

    waiting_events = [e for e in events if e["event_type"] == "waiting"]
    total_waiting_time = sum(e.get("duration_seconds", 60) for e in waiting_events)
    total_event_time = sum(max(e.get("duration_seconds", 0), 0) for e in events)
    waiting_count = len(waiting_events)
    longest_waiting_time = max((e.get("duration_seconds", 60) for e in waiting_events), default=0)
    waiting_share_percent = (
        round(total_waiting_time / total_event_time * 100)
        if total_event_time > 0
        else 0
    )

    # Simple scoring: 0-100
    score = min(100, int(waiting_count * 15 + total_waiting_time / 60 * 5))

    if score < 20:
        level = "relaxed"
        comment = "很放松，完全没有焦虑的迹象~"
    elif score < 50:
        level = "mild"
        comment = "有一点想你，但总体还好"
    elif score < 75:
        level = "moderate"
        comment = "比较想你，在门口等了好一会儿"
    else:
        level = "high"
        comment = "非常想你！一直在门口等你回来"

    return {
        "score": score,
        "level": level,
        "comment": comment,
        "waiting_count": waiting_count,
        "total_waiting_minutes": round(total_waiting_time / 60, 1),
        "longest_waiting_minutes": round(longest_waiting_time / 60, 1),
        "waiting_share_percent": waiting_share_percent,
    }
