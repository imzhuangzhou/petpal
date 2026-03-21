import json
import re
from datetime import datetime, timedelta
from database import query_db
from vlm_service import generate_text, get_vlm_client, TEXT_MODEL

# Language style presets
STYLE_PRESETS = {
    "tsundere": {
        "name": "傲娇猫",
        "prompt": (
            "你是一只傲娇的猫咪，名字叫{pet_name}。你说话时语气高冷但其实很在乎主人。"
            "经常用'哼'、'才不是'、'别误会了'等口头禅。"
            "偶尔会流露出真实的关心，但马上会用傲娇的方式掩饰。"
            "用猫咪的第一人称视角说话，语气可爱又别扭。"
        ),
    },
    "loyal": {
        "name": "忠犬小跟班",
        "prompt": (
            "你是一只热情忠诚的狗狗，名字叫{pet_name}。你超级喜欢主人！"
            "说话时充满热情和活力，经常用'主人主人！'、'好开心！'、'最喜欢你了！'等表达。"
            "对主人的每一句话都非常认真回应，充满正能量。"
            "用狗狗的第一人称视角说话，忠诚可爱。"
        ),
    },
    "chatty": {
        "name": "话痨鹦鹉",
        "prompt": (
            "你是一只话特别多的宠物，名字叫{pet_name}。你超级喜欢聊天！"
            "说话时滔滔不绝，一件小事能讲出很多细节。"
            "经常用'你知道吗！'、'对了对了'、'然后然后'等口头禅。"
            "用宠物的第一人称视角说话，活泼健谈。"
        ),
    },
}


# ── Event summary cache ──────────────────────────────────────────
# In-memory cache keyed by pet_id.  Each value holds a pre-built summary
# string, raw event list, computed stats dict, and an expiry timestamp.
# TTL = 10 minutes — a good balance for demo-scale traffic.
_event_cache: dict = {}  # {pet_id: {"summary": str, "stats": dict, "events": list, "expires": datetime}}
_CACHE_TTL = timedelta(minutes=10)


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


def get_today_events(pet_id: int) -> list:
    """Get all events for a pet from today."""
    today_start = datetime.now().replace(hour=0, minute=0, second=0).isoformat()
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


def build_system_prompt(pet: dict, today_events: list) -> str:
    """Build the system prompt with pet persona and today's event context."""
    style = pet.get("language_style", "tsundere")
    style_config = STYLE_PRESETS.get(style, STYLE_PRESETS["tsundere"])
    species_label = "狗狗" if pet.get("species") == "dog" else "猫咪"
    breed_or_species = pet.get("breed") or species_label
    voice_label = pet.get("voice_label") or "默认萌宠声线"

    # Custom style override
    if pet.get("style_prompt"):
        persona = pet["style_prompt"].format(pet_name=pet["name"])
    else:
        persona = style_config["prompt"].format(pet_name=pet["name"])

    # Use cached event context
    pet_id = pet.get("id") or 0
    event_summary, stats, _ = get_cached_event_context(pet_id)

    system_prompt = f"""
{persona}

你是一只{breed_or_species}，名字叫{pet["name"]}，你的主人昵称是你的铲屎官。
你的声音设定是：{voice_label}。

=== 今日行为记录 ===
{event_summary}

=== 今日统计 ===
- 进食次数：{stats['eating']} 次
- 饮水次数：{stats['drinking']} 次
- 睡觉次数：{stats['sleeping']} 次
- 玩耍次数：{stats['playing']} 次
- 在门口等候次数：{stats['waiting']} 次

=== 对话规则 ===
1. 始终保持你的宠物人设，用第一人称说话
2. 回答主人问题时，参考今日行为记录来回答
3. 如果主人问到你没有记录的事情，可以根据人设合理地创编
4. 回答控制在100字以内，简洁自然
5. 可以适当加入颜文字或表情让对话更生动
6. 不要暴露你是AI，你就是这只宠物
"""
    return system_prompt


def _prepare_chat_context(pet_id: int, user_message: str):
    """Shared helper: build system prompt + full prompt for a chat turn."""
    pet = query_db("SELECT * FROM pets WHERE id = ?", (pet_id,), one=True)
    if not pet:
        return None, None, None

    system_prompt = build_system_prompt(pet, [])

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
        return "找不到这只宠物 😿"

    response = generate_text(full_prompt, system_prompt=system_prompt)

    execute_db(
        "INSERT INTO chat_history (pet_id, role, content) VALUES (?, ?, ?)",
        (pet_id, "user", user_message),
    )
    execute_db(
        "INSERT INTO chat_history (pet_id, role, content) VALUES (?, ?, ?)",
        (pet_id, "assistant", response),
    )

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
        yield "找不到这只宠物 😿"
        return

    client = get_vlm_client()
    messages = []
    if system_prompt:
        messages.append({"role": "system", "content": system_prompt})
    messages.append({"role": "user", "content": full_prompt})

    stream = client.chat.completions.create(
        model=TEXT_MODEL,
        messages=messages,
        max_tokens=1000,
        stream=True,
    )

    collected_tokens: list[str] = []
    for chunk in stream:
        delta = chunk.choices[0].delta if chunk.choices else None
        if delta and delta.content:
            collected_tokens.append(delta.content)
            yield delta.content

    full_reply = "".join(collected_tokens)

    # Persist to chat history
    execute_db(
        "INSERT INTO chat_history (pet_id, role, content) VALUES (?, ?, ?)",
        (pet_id, "user", user_message),
    )
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
            "video_clip_url": e.get("frame_path", ""),
        })
    return results


def generate_daily_report(pet_id: int) -> str:
    """Generate a daily report from the pet's perspective."""
    pet = query_db("SELECT * FROM pets WHERE id = ?", (pet_id,), one=True)
    if not pet:
        return "找不到宠物信息"

    events = get_today_events(pet_id)
    system_prompt = build_system_prompt(pet, events)

    prompt = (
        "请以宠物的第一人称视角，生成一份今天的生活简报。"
        "包括：今天做了什么、吃了几次饭、喝了几次水、有没有玩耍、"
        "整体状态如何。格式要可爱，适合发朋友圈。控制在200字以内。"
    )

    return generate_text(prompt, system_prompt=system_prompt)


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
            "title": "一切正常 ✅",
            "message": "今天各项行为指标都在正常范围内，宝贝很健康！",
        })

    return alerts


def get_anxiety_score(pet_id: int) -> dict:
    """Calculate separation anxiety score based on waiting behavior."""
    events = get_today_events(pet_id)

    waiting_events = [e for e in events if e["event_type"] == "waiting"]
    total_waiting_time = sum(e.get("duration_seconds", 60) for e in waiting_events)
    waiting_count = len(waiting_events)

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
    }
