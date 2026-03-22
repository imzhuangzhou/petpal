# 🐾 PetPal — AI 宠物管家

> 通过家庭摄像头视频理解宠物行为，让你的猫咪/狗狗用 TA 自己的"性格"和你聊天。

PetPal 是一个端到端的 AI 宠物陪伴应用，包含 **iOS 客户端**（SwiftUI）和 **本地后端**（FastAPI）。上传一段家庭摄像头视频，系统会自动提取关键帧、识别宠物行为，并基于当天事件上下文生成风格化的宠物对话、日报、日记和健康提醒。

---

## ✨ 核心功能

| 功能 | 说明 |
|------|------|
| 🗣️ **宠物对话** | 基于当日行为上下文，用宠物的第一人称与你聊天 |
| 🎭 **人设定制** | 预置 4 种语言风格：傲娇猫 / 忠犬小跟班 / 话痨鹦鹉 / 松弛感主角，也可自定义 |
| 📹 **视频理解** | 上传演示摄像头对应的视频 → 抽帧 → VLM 视觉分析 → 行为事件记录 |
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
| `vlm_service.py` | 对接阿里 DashScope（文本/视觉理解）与 Vertex AI（宠物头像生成） |
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
- **阿里云 DashScope API Key**（必需，视频分析、对话、日报、日记等功能均依赖它）
- **Google Cloud / Vertex AI 凭据**（可选，不设则宠物头像生成功能不可用）

### 1. 启动后端

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 必需：设置 DashScope Key
export DASHSCOPE_API_KEY='your_api_key'

# 可选：设置 Vertex AI 配置
export GOOGLE_CLOUD_PROJECT='your-gcp-project-id'
export VERTEX_AI_LOCATION='global'

# 本地开发推荐：使用 ADC，不要把密钥写进代码或仓库
gcloud auth application-default login

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

## 🎬 当前演示路径

当前仓库里真实可跑通的演示路径是：

1. 用户在 iOS 客户端完成宠物信息配置，包括参考图、人格和声音设定
2. 进入“连接摄像头”页，选择一个 **假摄像头**
3. 每个假摄像头会对应一段 **假视频**，客户端会生成并上传这段联调视频
4. 后端对上传视频进行抽帧，并调用 VLM 分析生成行为事件
5. 用户进入聊天页后，可以自然语言和宠物对话；界面展示的“实时画面”本质上是这段联调视频及其分析结果

也就是说，当前版本重点演示的是“视频上下文驱动的宠物对话体验”，而不是实际接入真实家庭摄像头硬件。

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
| 图像处理 | Pillow · Vertex AI Imagen |

---

## ⚠️ 当前限制

- 必须配置 `DASHSCOPE_API_KEY`，否则视频分析、聊天、日报、日记等主流程无法使用
- 摄像头绑定为**演示模式**，当前不支持真实 RTSP/RTMP 流接入
- iOS 端展示的是“假摄像头 + 假视频”的联调方案，不是真实实时监控流
- 上传视频后行为事件由 **抽帧 + VLM 分析** 生成，不再使用固定时间表生成演示事件
- 未配置 Vertex AI 凭据时，宠物头像生成功能会失败，但其他功能不受影响

---

## Vertex AI 安全配置

PetPal 现在通过 **Vertex AI** 生成宠物头像。这里不建议使用“把 API Key 塞进代码或 `.env` 文件并提交仓库”的方式，而是优先使用 **Google Cloud ADC（Application Default Credentials）**。

### 本地开发

1. 安装并初始化 gcloud

```bash
gcloud init
```

2. 登录并生成本机 ADC 凭据

```bash
gcloud auth application-default login
```

3. 只在当前终端会话里设置项目与区域

```bash
export GOOGLE_CLOUD_PROJECT='your-gcp-project-id'
export VERTEX_AI_LOCATION='global'
```

这样做的好处是：

- 凭据保存在你本机的 Google Cloud ADC 目录，不进代码仓库
- 代码里只读取运行环境，不保存任何密钥值
- 你可以随时通过 `gcloud auth application-default revoke` 撤销本机凭据

### 生产环境

生产环境更推荐这两种方式：

- Cloud Run / GCE / GKE：直接给运行服务绑定专用 **Service Account**
- 自建服务器：把服务账号 JSON 放在仓库外的安全目录，并通过环境变量引用

自建服务器示例：

```bash
export GOOGLE_APPLICATION_CREDENTIALS='/opt/petpal/secrets/vertex-sa.json'
export GOOGLE_CLOUD_PROJECT='your-gcp-project-id'
export VERTEX_AI_LOCATION='global'
```

注意：

- 不要把 `vertex-sa.json` 放进仓库
- 不要把密钥内容写进代码、`README` 示例值、日志或截图
- 建议给这个服务账号只授予调用 Vertex AI 所需的最小权限

---

## 📄 License

This project is licensed under the [GNU General Public License v3.0](./LICENSE).
