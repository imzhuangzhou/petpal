from fastapi import APIRouter
from dialogue_engine import (
    generate_daily_report,
    generate_diary,
    get_health_alerts,
    get_anxiety_score,
)

router = APIRouter(prefix="/api", tags=["features"])


@router.get("/report/daily/{pet_id}")
def daily_report(pet_id: int):
    report = generate_daily_report(pet_id)
    return {"report": report, "pet_id": pet_id}


@router.get("/health/alerts/{pet_id}")
def health_alerts(pet_id: int):
    alerts = get_health_alerts(pet_id)
    return {"alerts": alerts, "pet_id": pet_id}


@router.get("/diary/{pet_id}")
def pet_diary(pet_id: int):
    diary = generate_diary(pet_id)
    return {"diary": diary, "pet_id": pet_id}


@router.get("/anxiety/{pet_id}")
def anxiety_score(pet_id: int):
    result = get_anxiety_score(pet_id)
    return {**result, "pet_id": pet_id}
