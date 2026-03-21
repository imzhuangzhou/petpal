# PetPal

PetPal 现已收敛为一个仅保留 iOS 客户端的项目形态。仓库中不再包含 Web 前端，唯一客户端实现位于 `ios/`，并继续通过 `backend/` 提供本地开发时所需的 API 服务。

## 当前仓库内容

- `ios/`: SwiftUI iOS 客户端工程
- `backend/`: FastAPI 本地开发后端
- `README.md`: 仓库总说明
- `LICENSE`: 许可证

## iOS 客户端能力

iOS 客户端当前覆盖的主流程包括：

- 欢迎页与用户创建
- 宠物创建
- 演示视频上传
- 聊天
- 每日简报
- 健康告警
- 焦虑指数
- 宠物日记
- 设置页替换演示视频

说明：
- 摄像头绑定与真实视频理解仍为演示模式
- 上传后的视频当前仍用于生成 mock 行为上下文
- 未配置 `DASHSCOPE_API_KEY` 时，界面与基础流程可打开，但依赖模型的能力会失败

## 本地运行

### 1. 启动后端

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements.txt
export DASHSCOPE_API_KEY='your_api_key'
python3 -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

如果只是验证界面或非模型链路，可以不设置 `DASHSCOPE_API_KEY`。

### 2. 打开 iOS 工程

```bash
open ios/PetPalDemo.xcodeproj
```

然后在 Xcode 中：

1. 选择 Scheme: `PetPalDemo`
2. 选择一个 Simulator，例如 `iPhone 16`
3. 点击 Run，或按 `Cmd + R`

## API 地址配置

iOS 客户端通过 `Info.plist` 中的 `API_BASE_URL` 读取后端地址，文件位置：

- `ios/PetPalDemo/Resources/Info.plist`

默认值：

```text
http://localhost:8000
```

适用场景：

- 使用 iPhone Simulator 联调本机后端时，可直接使用 `http://localhost:8000`
- 使用真机联调时，请改成你电脑的局域网 IP，例如 `http://192.168.x.x:8000`

## 目录结构

```text
petpal/
├── backend/                    # FastAPI 本地开发后端
├── ios/                        # SwiftUI iOS 客户端
│   ├── PetPalDemo/
│   ├── PetPalDemo.xcodeproj
│   └── README.md
├── README.md
└── LICENSE
```

## License

This project is licensed under the GNU General Public License v3.0. See [LICENSE](./LICENSE) for details.
