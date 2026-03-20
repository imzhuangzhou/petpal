from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from dialogue_engine import (
    chat_with_pet,
    generate_daily_report,
    generate_diary,
    get_health_alerts,
    get_anxiety_score,
)
from database import query_db

router = APIRouter(prefix="/api", tags=["chat"])


class ChatRequest(BaseModel):
    pet_id: int
    message: str


@router.post("/chat")
def send_message(req: ChatRequest):
    response = chat_with_pet(req.pet_id, req.message)
    return {"reply": response, "pet_id": req.pet_id}


@router.get("/chat/history/{pet_id}")
def get_chat_history(pet_id: int, limit: int = 50):
    history = query_db(
        "SELECT * FROM chat_history WHERE pet_id = ? ORDER BY created_at DESC LIMIT ?",
        (pet_id, limit),
    )
    history.reverse()
    return history
