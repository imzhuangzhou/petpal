# PetPal

An AI pet companion demo that turns home pet activity into first-person conversations, daily reports, health alerts, and playful diary entries.

PetPal is designed as a product-style prototype rather than a pure hackathon mock. The current version implements the full user flow for onboarding, pet profile setup, voice selection, demo video upload, contextual chat, and settings management. The only mocked part is the camera binding and video understanding pipeline: uploaded demo videos are currently used to seed structured daily events instead of running a full real-world vision pipeline end to end.

---

## 中文介绍

PetPal 是一个“宠物 AI 管家”产品原型。它希望把“我不在家时宠物在做什么”这件事，变成一种更自然、更有陪伴感的交互方式。

用户可以先创建宠物档案，选择宠物种类、聊天人格和声音风格，再上传一段演示视频作为当天的行为上下文。随后，系统会围绕这段上下文生成可对话的宠物形象，让用户通过聊天获取：

- 宠物第一人称回复
- 每日简报
- 健康告警
- 焦虑指数
- 宠物日记

当前版本中，摄像头绑定与视频理解链路仍为演示模式：
- 可以上传演示视频
- 设置页中可以更换视频
- 聊天和功能页会基于该视频对应的 mock 行为事件生成内容

也就是说，产品流程已经尽可能接近真实产品，但视频分析本身仍是 mock 数据驱动。

### 核心功能

- 宠物档案创建：支持猫 / 狗两种宠物种类
- 宠物人格设定：选择不同聊天风格
- 声音设定：支持预设声音试听，也支持录制真实宠物声音样本
- 演示视频上传：上传后自动进入主页，并建立当日上下文
- 聊天主页：围绕上下文事件进行自然语言对话
- 附加能力：每日简报、健康告警、焦虑指数、宠物日记
- 设置页：查看声音配置、回放样本、替换演示视频

### 技术栈

- Frontend: React 19, Vite, React Router
- Backend: FastAPI, SQLite
- AI integration: DashScope OpenAI-compatible API
- Media: Browser MediaRecorder, local file upload

### 快速启动

#### 方式一：一键启动

```bash
./start-dev.sh
```

如果你已经有 DashScope / 阿里云百炼 API Key，可以先设置环境变量：

```bash
export DASHSCOPE_API_KEY='your_api_key'
```

启动后默认地址：

- Frontend: `http://localhost:5173`
- Backend: `http://localhost:8000`

#### 方式二：分别启动

后端：

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements.txt
export DASHSCOPE_API_KEY='your_api_key'
python3 -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

前端：

```bash
cd frontend
npm install
npm run dev -- --host 0.0.0.0 --port 5173
```

### 演示流程

1. 输入用户昵称
2. 创建宠物档案，选择种类、人格和声音
3. 可选：录一段真实宠物声音样本
4. 上传一段演示视频作为当天上下文
5. 进入聊天主页，体验聊天、简报、日记、焦虑指数和健康告警
6. 在设置页中替换当前演示视频

### 当前限制

- 真正的 RTSP / 家庭摄像头接入尚未完成
- 上传视频后当前使用 mock 事件时间线生成上下文
- 录音样本已保存并纳入产品流程，但尚未接入真实声纹克隆 / TTS

### 目录结构

```text
petpal/
├── backend/        # FastAPI backend, data models, routes, AI orchestration
├── frontend/       # React + Vite frontend
├── start-dev.sh    # One-command local startup script
├── README.md
└── LICENSE
```

---

## English

PetPal is an AI pet companion prototype that turns home pet activity into a more emotional and conversational product experience.

Users can create a pet profile, choose the pet type, chat persona, and voice style, then upload a demo video as the context for the day. Based on that context, the app provides a pet-facing conversational interface with:

- First-person pet chat replies
- Daily summaries
- Health alerts
- Separation anxiety scoring
- Pet diary generation

In the current version, the camera-binding and video-understanding pipeline is still in demo mode:

- You can upload a demo video
- You can replace that video later in Settings
- The chat and reports are generated from structured mock daily events seeded for that video

So the product flow is intentionally close to a real product, while the camera/video intelligence layer is still mocked.

### Features

- Pet onboarding with two species options: cat and dog
- Pet persona selection for different conversation styles
- Voice setup with preset voice previews
- Optional real pet voice sample recording
- Demo video upload for contextual chat
- Context-aware chat interface
- Daily report, health alerts, anxiety score, and diary features
- Settings screen for managing voice and replacing the demo video

### Tech Stack

- Frontend: React 19, Vite, React Router
- Backend: FastAPI, SQLite
- AI integration: DashScope OpenAI-compatible API
- Media: Browser MediaRecorder, local file uploads

### Quick Start

#### Option 1: one-command startup

```bash
./start-dev.sh
```

If you already have a DashScope API key:

```bash
export DASHSCOPE_API_KEY='your_api_key'
```

Default local URLs:

- Frontend: `http://localhost:5173`
- Backend: `http://localhost:8000`

#### Option 2: run frontend and backend separately

Backend:

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements.txt
export DASHSCOPE_API_KEY='your_api_key'
python3 -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Frontend:

```bash
cd frontend
npm install
npm run dev -- --host 0.0.0.0 --port 5173
```

### Limitations

- Real RTSP / home camera integration is not implemented yet
- Uploaded videos currently seed mock daily events instead of full video analysis
- Recorded pet voice samples are stored in the product flow, but real voice cloning / TTS is not connected yet

## License

This project is licensed under the GNU General Public License v3.0. See the [LICENSE](./LICENSE) file for details.
