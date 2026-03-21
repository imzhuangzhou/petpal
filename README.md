# 🐾 PetPal — AI 宠物管家

> 通过家庭摄像头视频理解宠物行为，让你的猫咪/狗狗用 TA 自己的"性格"和你聊天。

PetPal 是一个端到端的 AI 宠物陪伴应用，包含 **iOS 客户端**（SwiftUI）和 **本地后端**（FastAPI）。上传一段家庭摄像头视频，系统会自动提取关键帧、识别宠物行为，并基于当天事件上下文生成风格化的宠物对话、日报、日记和健康提醒。

---

## ✨ 核心功能

| 功能 | 说明 |
|------|------|
| 🗣️ **宠物对话** | 基于当日行为上下文，用宠物的第一人称与你聊天 |
| 🎭 **人设定制** | 预置 3 种语言风格：傲娇猫 / 忠犬小跟班 / 话痨鹦鹉，也可自定义 |
| 📹 **视频理解** | 上传家庭摄像头视频 → 运动检测抽帧 → VLM 视觉分析 → 行为事件记录 |
| 📊 **每日简报** | 宠物第一人称生成当天生活小结 |
| 📔 **宠物日记** | 以日记体记录宠物一天的心情和经历 |
| 🏥 **健康告警** | 根据进食/饮水/如厕频次，自动检测异常并推送提醒 |
| 😰 **焦虑指数** | 量化分离焦虑（门口等待次数与时长），0-100 分打分 |
| 🎙️ **声线设置** | 预设声线选择或上传宠物原声进行克隆 |

---

## 🏗️ 技术架构

```
┌──────────────────┐         HTTP/JSON         ┌──────────────────────┐
│   iOS 客户端      │ ◄─────────────────────►  │     FastAPI 后端       │
│   (SwiftUI)      │                           │                      │
│                  │                           │  ┌─── Dialogue Engine │
│  • Welcome       │                           │  │    (人设 + 上下文)   │
│  • PetSetup      │                           │  ├─── VLM Service     │
│  • DemoUpload    │                           │  │    (Qwen-VL/Plus)  │
│  • Chat          │                           │  ├─── Video Processor │
│  • Settings      │                           │  │    (OpenCV 抽帧)    │
│                  │                           │  └─── SQLite DB       │
└──────────────────┘                           └──────────────────────┘
```

### 后端核心模块

| 模块 | 职责 |
|------|------|
| `main.py` | FastAPI 应用入口，路由注册，静态文件挂载 |
| `dialogue_engine.py` | 人设 prompt 构建、对话、日报/日记生成、健康告警、焦虑评分 |
| `vlm_service.py` | 对接阿里 DashScope（Qwen-VL-Plus / Qwen-Plus），帧描述与行为分类 |
| `video_processor.py` | OpenCV 视频处理：运动检测抽帧、均匀抽帧 |
| `database.py` | SQLite 数据库初始化与增删改查工具 |
| `routes/` | 5 个路由模块：`user` · `chat` · `events` · `features` · `media` |

### iOS 客户端结构

| 目录 | 内容 |
|------|------|
| `App/` | `PetPalDemoApp` 入口、`RootView` 根视图 |
| `Core/Environment/` | `AppEnvironment` — API 地址配置 |
| `Core/Models/` | 全部请求/响应数据模型（16 个） |
| `Core/Networking/` | `APIClient`、`Endpoint`、`MultipartFormDataBuilder` |
| `Core/State/` | `AppStore`、`SessionStore` — 本地状态管理 |
| `Features/` | 5 个页面：Welcome · PetSetup · DemoUpload · Chat · Settings |

---

## 🚀 快速开始

### 前置要求

- **Python 3.10+**
- **Xcode 15+**（含 iOS 17 Simulator）
- **阿里云 DashScope API Key**（可选，不设则 AI 功能不可用，界面仍可浏览）

### 1. 启动后端

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 可选：设置 AI 模型密钥
export DASHSCOPE_API_KEY='your_api_key'

python3 -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

后端启动后访问 http://localhost:8000 可验证服务状态。

### 2. 运行 iOS 客户端

```bash
open ios/PetPalDemo.xcodeproj
```

在 Xcode 中：

1. 选择 Scheme → `PetPalDemo`
2. 选择模拟器（如 iPhone 16）
3. `Cmd + R` 运行

---

## ⚙️ API 地址配置

iOS 客户端通过 `ios/PetPalDemo/Resources/Info.plist` 中的 `API_BASE_URL` 字段配置后端地址。

| 场景 | 地址 |
|------|------|
| Simulator 联调 | `http://localhost:8000` |
| 真机联调 | `http://192.168.x.x:8000`（替换为你的局域网 IP） |

---

## 📡 API 接口概览

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/user` | 创建用户 |
| GET | `/api/user/{user_id}` | 获取用户信息 |
| POST | `/api/pet` | 创建宠物（含人设/声线配置） |
| GET | `/api/pet/{pet_id}` | 获取宠物详情 |
| GET | `/api/pets/{user_id}` | 获取用户所有宠物 |
| POST | `/api/camera` | 创建摄像头 |
| POST | `/api/chat` | 发送消息并获取宠物回复 |
| GET | `/api/chat/history/{pet_id}` | 获取聊天历史 |
| GET | `/api/events/{pet_id}` | 获取行为事件列表 |
| GET | `/api/report/daily/{pet_id}` | 生成每日简报 |
| GET | `/api/health/alerts/{pet_id}` | 获取健康告警 |
| GET | `/api/diary/{pet_id}` | 生成宠物日记 |
| GET | `/api/anxiety/{pet_id}` | 获取焦虑指数 |
| POST | `/api/demo-video` | 上传演示视频并生成行为上下文 |
| POST | `/api/pet/{pet_id}/voice/sample` | 上传宠物原声音频 |
| POST | `/api/demo/init` | 初始化演示行为数据 |

---

## 📁 目录结构

```text
petpal/
├── backend/                        # FastAPI 后端服务
│   ├── main.py                     #   应用入口
│   ├── dialogue_engine.py          #   对话 & 内容生成引擎
│   ├── vlm_service.py              #   VLM / LLM 服务 (DashScope)
│   ├── video_processor.py          #   视频处理 (OpenCV)
│   ├── database.py                 #   SQLite 数据库
│   ├── requirements.txt            #   Python 依赖
│   └── routes/                     #   API 路由
│       ├── user.py                 #     用户 & 宠物 & 摄像头
│       ├── chat.py                 #     对话
│       ├── events.py               #     行为事件 & 演示数据
│       ├── features.py             #     日报/日记/告警/焦虑
│       └── media.py                #     视频 & 音频上传
├── ios/                            # SwiftUI iOS 客户端
│   ├── PetPalDemo.xcodeproj        #   Xcode 工程文件
│   ├── PetPalDemo/
│   │   ├── App/                    #     应用入口 & 根视图
│   │   ├── Core/                   #     环境/模型/网络/状态
│   │   ├── Features/               #     业务页面 (5 个)
│   │   └── Resources/              #     Info.plist 配置
│   └── README.md                   #   iOS 客户端说明
├── reference/                      # 参考资料（已废弃的 Web 前端）
├── LICENSE                         # GPLv3
└── README.md                       # 本文件
```

---

## 🔧 技术栈

| 层 | 技术 |
|----|------|
| iOS 客户端 | SwiftUI · URLSession · Combine |
| 后端框架 | FastAPI · Uvicorn · Pydantic |
| AI 模型 | 通义千问 Qwen-VL-Plus（视觉）· Qwen-Plus（文本）via DashScope |
| 视频处理 | OpenCV（运动检测 + 抽帧）|
| 数据库 | SQLite（WAL 模式）|
| 图像处理 | Pillow |

---

## ⚠️ 当前限制

- 摄像头绑定为**演示模式**，不支持真实 RTSP/RTMP 流
- 上传视频后行为事件由**预设时间表**生成（区分猫/狗），尚未接入真实 VLM 实时分析
- 未配置 `DASHSCOPE_API_KEY` 时，对话/日报/日记等 AI 功能无法使用，但 UI 和基础流程可正常浏览

---

## 📄 License

This project is licensed under the [GNU General Public License v3.0](./LICENSE).
