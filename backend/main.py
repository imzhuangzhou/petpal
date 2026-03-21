import os
import sys

# Add backend directory to path
sys.path.insert(0, os.path.dirname(__file__))

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from database import init_db
from routes.user import router as user_router
from routes.chat import router as chat_router
from routes.features import router as features_router
from routes.events import router as events_router
from routes.media import router as media_router

app = FastAPI(
    title="PetPal API",
    description="宠物 AI 管家后端服务",
    version="1.0.0",
)

# CORS kept permissive for local iOS development and simulator/device testing
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount static files for frames
FRAMES_DIR = os.path.join(os.path.dirname(__file__), "frames")
os.makedirs(FRAMES_DIR, exist_ok=True)
app.mount("/frames", StaticFiles(directory=FRAMES_DIR), name="frames")

UPLOADS_DIR = os.path.join(os.path.dirname(__file__), "uploads")
os.makedirs(UPLOADS_DIR, exist_ok=True)
app.mount("/media", StaticFiles(directory=UPLOADS_DIR), name="media")

# Include routers
app.include_router(user_router)
app.include_router(chat_router)
app.include_router(features_router)
app.include_router(events_router)
app.include_router(media_router)


@app.on_event("startup")
def startup():
    init_db()
    print("🐾 PetPal API is ready!")


@app.get("/")
def root():
    return {"message": "🐾 PetPal API", "status": "running"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
