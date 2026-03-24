# PetPal — AI Pet Companion

> Understand your pet's behavior through home camera video, and chat with your cat/dog using their own "personality".

**[English](./README.md)** | **[中文](./README-zh.md)**

PetPal is an end-to-end AI pet companion app featuring an **iOS client** (SwiftUI) and **local backend** (FastAPI). Upload a home camera video, and the system automatically extracts key frames, identifies pet behaviors, and generates styled pet dialogues, daily reports, diaries, and health alerts based on the day's event context.

---

## Features

| Feature | Description |
|---------|-------------|
| **Pet Dialogue** | Chat with your pet in first person, based on daily behavior context |
| **Persona Customization** | 4 preset language styles: Tsundere Cat / Loyal Pup / Chatty Parrot / Laid-back Star, or custom |
| **Video Understanding** | Upload demo camera video → frame extraction → VLM visual analysis → behavior events |
| **Daily Report** | Pet-generated first-person summary of the day's activities |
| **Pet Diary** | Diary-style record of the pet's mood and experiences throughout the day |
| **Health Alerts** | Automatic anomaly detection based on eating/drinking/toilet frequency |
| **Anxiety Index** | Quantified separation anxiety (door-waiting count and duration), scored 0-100 |
| **Voice Settings** | Preset voice selection or upload pet's original voice for cloning |

---

## Architecture

```
┌──────────────────┐         HTTP/JSON         ┌──────────────────────┐
│   iOS Client     │ ◄─────────────────────►  │     FastAPI Backend   │
│   (SwiftUI)      │                           │                      │
│                  │                           │  ┌─── Dialogue Engine │
│  • Welcome       │                           │  │    (Persona+Context)│
│  • PetSetup      │                           │  ├─── VLM Service     │
│  • DemoUpload    │                           │  │    (Qwen-VL/Plus)  │
│  • Chat          │                           │  ├─── Video Processor │
│  • Settings      │                           │  │    (OpenCV frames) │
│                  │                           │  └─── SQLite DB       │
└──────────────────┘                           └──────────────────────┘
```

### Backend Core Modules

| Module | Responsibility |
|--------|----------------|
| `main.py` | FastAPI entry, route registration, static file mounting |
| `dialogue_engine.py` | Persona prompt building, chat, reports/diary generation, health alerts, anxiety scoring |
| `vlm_service.py` | DashScope (text/vision) + Vertex AI (pet avatar generation) |
| `video_processor.py` | OpenCV video processing: motion detection frame extraction, uniform sampling |
| `video_analysis_service.py` | Async pipeline: job queue, clip extraction, VLM analysis, memory storage |
| `memory_service.py` | Daily memories, pet profile memories, timeline aggregation |
| `database.py` | SQLite database initialization and CRUD utilities |
| `routes/` | 5 route modules: `user` · `chat` · `events` · `features` · `media` |

### iOS Client Structure

| Directory | Content |
|-----------|---------|
| `App/` | `PetPalDemoApp` entry, `RootView` navigation |
| `Core/Environment/` | `AppEnvironment` — API URL configuration |
| `Core/Models/` | All request/response data models (16) |
| `Core/Networking/` | `APIClient`, `Endpoint`, `MultipartFormDataBuilder` |
| `Core/State/` | `AppStore`, `SessionStore` — local state management |
| `Features/` | 5 pages: Welcome · PetSetup · DemoUpload · Chat · Settings |

---

## Quick Start

### Prerequisites

- **Python 3.10+**
- **Xcode 15+** (with iOS 17 Simulator)
- **ffmpeg** (required for audio extraction and video processing; macOS: `brew install ffmpeg`)
- **Alibaba Cloud DashScope API Key** (required for video analysis, chat, reports, diaries)
- **Google Cloud / Vertex AI Credentials** (optional; required only for pet avatar generation)

### 1. Start Backend

```bash
cd backend

# Create venv (first time)
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Required: Set DashScope Key
export DASHSCOPE_API_KEY='your_api_key'

# Optional: Vertex AI configuration (uses ADC, not file-based credentials)
export GOOGLE_CLOUD_PROJECT='your-gcp-project-id'
export VERTEX_AI_LOCATION='global'

# For local dev, use ADC instead of embedding keys in code
gcloud auth application-default login

# Run
./start.sh
# Or directly:
python3 -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Verify backend is running at http://localhost:8000

### 2. Run iOS Client

```bash
open ios/PetPalDemo.xcodeproj
```

In Xcode:
1. Select Scheme → `PetPalDemo`
2. Select simulator (e.g., iPhone 16)
3. `Cmd + R` to run

---

## API URL Configuration

The iOS client configures the backend URL via `API_BASE_URL` in `ios/PetPalDemo/Resources/Info.plist`.

| Scenario | URL |
|----------|-----|
| Default Demo Config | `http://MacBook-Air.local:8000` |
| Alternative | `http://192.168.x.x:8000` (replace with your LAN IP) |

**Recommended for demos/interviews:**

1. Enable personal hotspot on iPhone
2. Connect Mac to this hotspot
3. Start backend on Mac: `cd /Users/justin/Documents/demo/petpal/backend && ./start.sh`
4. Run App on iPhone — connects via `http://MacBook-Air.local:8000`

---

## Current Demo Flow

The working demo path in this repository:

1. User completes pet profile in iOS client (photo + persona settings)
2. Go to "Connect Camera" page, select a **fake camera**
3. Each fake camera corresponds to a **demo video** — client generates and uploads this video
4. Backend extracts frames and calls VLM to analyze and generate behavior events
5. In chat page, user can chat naturally with the pet; the "live feed" shown is actually this demo video and its analysis

**Note:** Current version demonstrates "video context-driven pet dialogue experience", not real home camera hardware integration.

---

## API Overview

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/user` | Create user |
| GET | `/api/user/{user_id}` | Get user info |
| POST | `/api/pet` | Create pet (with persona config) |
| GET | `/api/pet/{pet_id}` | Get pet details |
| GET | `/api/pets/{user_id}` | Get all pets for user |
| POST | `/api/camera` | Create camera |
| POST | `/api/chat` | Send message and get pet response |
| GET | `/api/chat/history/{pet_id}` | Get chat history |
| GET | `/api/events/{pet_id}` | Get behavior event list |
| GET | `/api/report/daily/{pet_id}` | Generate daily report |
| GET | `/api/health/alerts/{pet_id}` | Get health alerts |
| GET | `/api/diary/{pet_id}` | Generate pet diary |
| GET | `/api/anxiety/{pet_id}` | Get anxiety index |
| POST | `/api/demo-video` | Upload demo video and generate behavior context |
| POST | `/api/pet/{pet_id}/voice/sample` | Upload pet voice audio (legacy compatible) |
| POST | `/api/demo/init` | Initialize demo behavior data |

---

## Directory Structure

```
petpal/
├── backend/                           # FastAPI backend service
│   ├── main.py                        #   Application entry
│   ├── dialogue_engine.py             #   Dialogue & content generation engine
│   ├── vlm_service.py                 #   VLM/LLM service (DashScope)
│   ├── video_processor.py             #   Video processing (OpenCV)
│   ├── video_analysis_service.py      #   Async video analysis pipeline
│   ├── memory_service.py              #   Daily & profile memory management
│   ├── proactive_chat.py              #   Proactive chat trigger logic
│   ├── database.py                    #   SQLite database
│   ├── requirements.txt               #   Python dependencies
│   └── routes/                        #   API routes
│       ├── user.py                    #     User, pet & camera
│       ├── chat.py                    #     Chat
│       ├── events.py                  #     Behavior events & demo data
│       ├── features.py                #     Reports/diary/alerts/anxiety
│       └── media.py                   #     Video & audio upload
├── ios/                               # SwiftUI iOS client
│   ├── PetPalDemo.xcodeproj           #   Xcode project file
│   ├── PetPalDemo/
│   │   ├── App/                       #     App entry & root view
│   │   ├── Core/                      #     Environment/models/networking/state
│   │   ├── Features/                  #     Business pages (5)
│   │   └── Resources/                 #     Info.plist configuration
│   └── README.md                      #   iOS client README
├── reference/                         # Reference materials (deprecated web frontend)
├── scripts/                           # Utility scripts (art generation)
├── LICENSE                            # GPLv3
└── README.md                          # This file
```

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| iOS Client | SwiftUI · URLSession · Combine |
| Backend | FastAPI · Uvicorn · Pydantic |
| AI Models | Qwen-VL-Plus (vision) · Qwen-Plus (text) via DashScope |
| Video Processing | OpenCV (motion detection + frame extraction) |
| Database | SQLite (WAL mode) |
| Image Generation | Pillow · Vertex AI Gemini 3.1 Flash Image |

---

## Current Limitations

- **`DASHSCOPE_API_KEY` is required** — video analysis, chat, reports, diaries won't work without it
- Camera is in **demo mode** — real RTSP/RTMP streams are not supported
- iOS shows "fake camera + fake video" integration, not real-time surveillance
- Behavior events are generated via **frame extraction + VLM analysis**, not fixed schedules
- Without Vertex AI credentials, pet avatar generation fails, but other features work fine

---

## Vertex AI Security Configuration

PetPal uses **Vertex AI `gemini-3.1-flash-image-preview`** for pet avatar generation. Instead of embedding API keys in code or `.env` files, use **Google Cloud ADC (Application Default Credentials)**.

### Local Development

1. Install and initialize gcloud

```bash
gcloud init
```

2. Login and generate local ADC credentials

```bash
gcloud auth application-default login
```

3. Set project and region in current terminal session

```bash
export GOOGLE_CLOUD_PROJECT='your-gcp-project-id'
export VERTEX_AI_LOCATION='global'
```

Benefits:
- Credentials saved in local Google Cloud ADC directory, not in code
- Code only reads runtime environment, no hardcoded secrets
- Revoke anytime with `gcloud auth application-default revoke`

### Production

For production, use one of:

- **Cloud Run / GCE / GKE**: Bind a dedicated Service Account to the service
- **Self-hosted server**: Place service account JSON outside repo in a secure directory, reference via environment variable

Self-hosted example:

```bash
export GOOGLE_APPLICATION_CREDENTIALS='/opt/petpal/secrets/vertex-sa.json'
export GOOGLE_CLOUD_PROJECT='your-gcp-project-id'
export VERTEX_AI_LOCATION='global'
```

**Important:**
- Never commit `vertex-sa.json` to repo
- Never write key content in code, README examples, logs, or screenshots
- Grant only minimum required permissions for Vertex AI

---

## Regenerating Static Artwork

To batch regenerate PetPal's App Icon and default cat/dog avatars, use the script in the repo:

```bash
python3 -m pip install --user google-genai google-auth
export GOOGLE_CLOUD_PROJECT='your-gcp-project-id'
export VERTEX_AI_LOCATION='global'
gcloud auth application-default login

bash scripts/generate_petpal_art.sh all
```

The script will:
- Call Vertex `gemini-3.1-flash-image-preview` to generate 1024x1024 master images
- Output masters to `output/vertex-gemini-image/petpal/masters/`
- Automatically overwrite iOS-sized PNGs for `AppIcon.appiconset` and `ArtPet*` resources

To regenerate individual resources:

```bash
bash scripts/generate_petpal_art.sh AppIcon
bash scripts/generate_petpal_art.sh ArtPetCat ArtPetDog
```

---

## License

This project is licensed under the [GNU General Public License v3.0](./LICENSE).
