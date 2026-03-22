import json

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from dialogue_engine import (
    chat_with_pet,
    chat_with_pet_stream,
    generate_daily_report,
    generate_diary,
    get_health_alerts,
    get_anxiety_score,
    match_related_events,
)
from database import query_db
from proactive_chat import serialize_chat_message, trigger_pet_vocalization_message

router = APIRouter(prefix="/api", tags=["chat"])


class ChatRequest(BaseModel):
    pet_id: int
    message: str


class ProactiveVocalizationRequest(BaseModel):
    pet_id: int
    camera_id: int


@router.post("/chat")
def send_message(req: ChatRequest):
    """Original synchronous chat endpoint (backwards-compatible)."""
    try:
        response = chat_with_pet(req.pet_id, req.message)
        related = match_related_events(response, req.pet_id)
        return {"reply": response, "pet_id": req.pet_id, "related_events": related}
    except Exception as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@router.post("/chat/stream")
def send_message_stream(req: ChatRequest):
    """
    SSE streaming chat endpoint.

    Each token is sent as:
        data: {"token": "..."}\n\n

    When complete:
        data: {"done": true, "related_events": [...]}\n\n
    """
    collected: list[str] = []

    def generate():
        try:
            for token in chat_with_pet_stream(req.pet_id, req.message):
                collected.append(token)
                yield f"data: {json.dumps({'token': token}, ensure_ascii=False)}\n\n"

            full_reply = "".join(collected)
            related = match_related_events(full_reply, req.pet_id)
            yield f"data: {json.dumps({'done': True, 'related_events': related}, ensure_ascii=False)}\n\n"
        except Exception as exc:
            error_message = f"聊天服务暂时不可用：{exc}"
            yield f"data: {json.dumps({'token': error_message}, ensure_ascii=False)}\n\n"
            yield f"data: {json.dumps({'done': True, 'related_events': []}, ensure_ascii=False)}\n\n"

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@router.get("/chat/history/{pet_id}")
def get_chat_history(pet_id: int, limit: int = 50):
    history = query_db(
        "SELECT * FROM chat_history WHERE pet_id = ? ORDER BY created_at DESC LIMIT ?",
        (pet_id, limit),
    )
    history.reverse()
    return [serialize_chat_message(row) for row in history]


@router.post("/chat/proactive/vocalization")
def trigger_proactive_vocalization(req: ProactiveVocalizationRequest):
    try:
        return trigger_pet_vocalization_message(pet_id=req.pet_id, camera_id=req.camera_id)
    except RuntimeError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
