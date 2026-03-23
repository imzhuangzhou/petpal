from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Literal, Optional
from database import execute_db, query_db

router = APIRouter(prefix="/api", tags=["user"])


class CreateUserRequest(BaseModel):
    nickname: str
    avatar_url: Optional[str] = ""


class CreatePetRequest(BaseModel):
    user_id: int
    name: str
    breed: Optional[str] = ""
    species: Literal["cat", "dog"] = "cat"
    photo_url: Optional[str] = ""
    avatar_url: Optional[str] = ""
    uses_default_avatar: bool = False
    language_style: Optional[str] = "tsundere"
    style_prompt: Optional[str] = ""
    owner_alias: Optional[str] = ""
    voice_type: Optional[str] = "preset"
    voice_key: Optional[str] = "cat-soft"
    voice_label: Optional[str] = "奶呼噜"
    voice_sample_path: Optional[str] = ""


class UpdatePetRequest(BaseModel):
    name: str
    species: Literal["cat", "dog"] = "cat"
    photo_url: Optional[str] = ""
    avatar_url: Optional[str] = ""
    uses_default_avatar: bool = False
    language_style: Optional[str] = "tsundere"
    style_prompt: Optional[str] = ""
    owner_alias: Optional[str] = ""


class CreateCameraRequest(BaseModel):
    user_id: int
    name: Optional[str] = "客厅"
    stream_url: Optional[str] = ""
    is_demo: Optional[bool] = False


def _validate_pet_avatar_payload(uses_default_avatar: bool, photo_url: Optional[str]):
    if not uses_default_avatar and (not photo_url or not photo_url.strip()):
        raise HTTPException(status_code=400, detail="请先上传宠物参考照片")


def _serialize_pet_response(pet: dict):
    return {
        "id": pet["id"],
        "name": pet["name"],
        "species": pet["species"],
        "photo_url": pet.get("photo_url", ""),
        "avatar_url": pet.get("avatar_url", ""),
        "owner_alias": pet.get("owner_alias", ""),
        "language_style": pet.get("language_style", "tsundere"),
        "voice_type": pet.get("voice_type", "preset"),
        "voice_key": pet.get("voice_key", "cat-soft"),
        "voice_label": pet.get("voice_label", "奶呼噜"),
    }


@router.post("/user")
def create_user(req: CreateUserRequest):
    user_id = execute_db(
        "INSERT INTO users (nickname, avatar_url) VALUES (?, ?)",
        (req.nickname, req.avatar_url),
    )
    return {"id": user_id, "nickname": req.nickname}


@router.get("/user/{user_id}")
def get_user(user_id: int):
    user = query_db("SELECT * FROM users WHERE id = ?", (user_id,), one=True)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


@router.post("/pet")
def create_pet(req: CreatePetRequest):
    _validate_pet_avatar_payload(req.uses_default_avatar, req.photo_url)

    pet_id = execute_db(
        """INSERT INTO pets (
               user_id, name, breed, species, photo_url, avatar_url,
               language_style, style_prompt, owner_alias, voice_type, voice_key, voice_label, voice_sample_path
           )
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (req.user_id, req.name, req.breed, req.species,
         req.photo_url, req.avatar_url, req.language_style, req.style_prompt,
         req.owner_alias, req.voice_type, req.voice_key, req.voice_label, req.voice_sample_path),
    )
    pet = query_db("SELECT * FROM pets WHERE id = ?", (pet_id,), one=True)
    if not pet:
        pet = {
            "id": pet_id,
            "name": req.name,
            "species": req.species,
            "photo_url": req.photo_url,
            "avatar_url": req.avatar_url,
            "owner_alias": req.owner_alias,
            "language_style": req.language_style,
            "voice_type": req.voice_type,
            "voice_key": req.voice_key,
            "voice_label": req.voice_label,
        }
    return _serialize_pet_response(pet)


@router.get("/pet/{pet_id}")
def get_pet(pet_id: int):
    pet = query_db("SELECT * FROM pets WHERE id = ?", (pet_id,), one=True)
    if not pet:
        raise HTTPException(status_code=404, detail="Pet not found")
    return pet


@router.patch("/pet/{pet_id}")
def update_pet(pet_id: int, req: UpdatePetRequest):
    existing_pet = query_db("SELECT * FROM pets WHERE id = ?", (pet_id,), one=True)
    if not existing_pet:
        raise HTTPException(status_code=404, detail="Pet not found")

    _validate_pet_avatar_payload(req.uses_default_avatar, req.photo_url)

    execute_db(
        """UPDATE pets
           SET name = ?, species = ?, photo_url = ?, avatar_url = ?,
               language_style = ?, style_prompt = ?, owner_alias = ?
           WHERE id = ?""",
        (
            req.name,
            req.species,
            req.photo_url or "",
            req.avatar_url or "",
            req.language_style or "tsundere",
            req.style_prompt or "",
            req.owner_alias or "",
            pet_id,
        ),
    )

    pet = query_db("SELECT * FROM pets WHERE id = ?", (pet_id,), one=True)
    return _serialize_pet_response(pet)


@router.get("/pets/{user_id}")
def get_user_pets(user_id: int):
    pets = query_db("SELECT * FROM pets WHERE user_id = ?", (user_id,))
    return pets


@router.post("/camera")
def create_camera(req: CreateCameraRequest):
    camera_id = execute_db(
        "INSERT INTO cameras (user_id, name, stream_url, is_demo, status) VALUES (?, ?, ?, ?, ?)",
        (req.user_id, req.name, req.stream_url, 1 if req.is_demo else 0, "connected"),
    )
    return {"id": camera_id, "name": req.name, "status": "connected"}


@router.get("/cameras/{user_id}")
def get_user_cameras(user_id: int):
    cameras = query_db("SELECT * FROM cameras WHERE user_id = ?", (user_id,))
    return cameras
