# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PetPal is an AI pet companion app with iOS SwiftUI client and FastAPI backend. It uploads home camera video, extracts frames, analyzes pet behavior via VLM, and generates personalized pet dialogues, daily reports, diaries, and health alerts.

**Current demo mode**: Uses "fake cameras" with pre-recorded demo videos instead of real RTSP/RTMP streams.

---

## Running the Backend

**Prerequisites:** `ffmpeg` is required for audio extraction and video processing (macOS: `brew install ffmpeg`).

```bash
cd backend

# Create venv (first time)
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Required: DashScope API key
export DASHSCOPE_API_KEY='your_api_key'

# Optional: Vertex AI for avatar generation (uses ADC, not file-based credentials)
export GOOGLE_CLOUD_PROJECT='your-gcp-project-id'
export VERTEX_AI_LOCATION='global'

# Run (./start.sh auto-activates venv, installs deps, and sets env defaults)
./start.sh
```

Backend runs at http://localhost:8000

---

## Running iOS Client

```bash
open ios/PetPalDemo.xcodeproj
# Select PetPalDemo scheme + iOS 17 simulator, Cmd+R
```

API base URL is configured in `ios/PetPalDemo/Resources/Info.plist` (`API_BASE_URL`).

---

## Running Tests

```bash
cd backend
source .venv/bin/activate
pytest tests/ -v
```

Single test: `pytest tests/test_vlm_service.py -v`

---

## Architecture

### Backend (FastAPI)

```
backend/
├── main.py                   # App entry, CORS, static file mounts (frames/, media/)
├── database.py               # SQLite (WAL mode) with helpers: init_db, query_db, execute_db
├── dialogue_engine.py        # Persona prompts, chat, reports, diaries, health alerts, anxiety scoring
├── vlm_service.py            # DashScope (Qwen-VL-Plus for vision, Qwen-Plus for text) + Vertex AI Imagen
├── video_processor.py        # OpenCV: motion-detection frame extraction, uniform frame sampling
├── video_analysis_service.py # Async pipeline: job queue, clip extraction, VLM analysis, memory storage
├── memory_service.py         # Daily memories, pet profile memories, timeline aggregation
├── proactive_chat.py         # Proactive chat trigger logic
├── range_static_files.py     # Range request support for video streaming
├── routes/
│   ├── user.py               # /api/user, /api/pet, /api/camera
│   ├── chat.py               # /api/chat, /api/chat/history
│   ├── events.py             # /api/events, /api/demo/init
│   ├── features.py           # /api/report, /api/diary, /api/health/alerts, /api/anxiety
│   └── media.py              # /api/demo-video, /api/pet/{id}/voice/sample
```

Database schema: `users → pets → cameras → events`, `chat_history`, plus async job tables (`video_analysis_jobs`, `candidate_clips`, `clip_memories`, `daily_memories`, `pet_profile_memories`). Uses `ensure_column()` for schema migrations.

### iOS (SwiftUI)

```
ios/PetPalDemo/
├── App/                 # PetPalDemoApp (entry), RootView (navigation)
├── Core/
│   ├── Environment/     # AppEnvironment (API_BASE_URL config), SpeechRecognizer
│   ├── Models/          # 16 Pydantic-equivalent Swift models
│   ├── Networking/       # APIClient (URLSession), Endpoint, MultipartFormDataBuilder
│   └── State/           # AppStore, SessionStore
└── Features/
    ├── Welcome/          # WelcomeView
    ├── PetSetup/         # PetSetupView (photo, persona config)
    ├── DemoUpload/       # DemoVideoUploadView (fake camera selection + video upload)
    ├── Chat/             # ChatView (large, main chat UI with voice/image support)
    └── Settings/         # SettingsView
```

---

## Key Constraints

- **DASHSCOPE_API_KEY is required** — all video analysis, chat, reports, and diaries fail without it.
- **ffmpeg is required** — for audio extraction and video processing; install via `brew install ffmpeg`.
- Vertex AI (avatar generation) is optional — gracefully degrades if not configured (uses Google Cloud ADC, not file-based credentials).
- Current demo uses fake cameras and pre-recorded demo videos — not real RTSP/RTMP streams.
- Video processing is async: `video_analysis_jobs` table tracks queue state; client polls or waits for completion.
- SQLite database (`petpal.db`) uses WAL mode; migrations add columns via `ensure_column()` pattern.
- iOS client sends demo video via multipart form upload; backend processes with OpenCV → VLM → events.
