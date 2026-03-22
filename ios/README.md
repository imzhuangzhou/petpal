# PetPal iOS Demo

这是当前仓库中唯一保留的客户端实现。工程基于 SwiftUI，覆盖用户创建、宠物创建、演示视频上传、聊天、日报/告警/焦虑指数/日记、设置替换视频等主流程。

## 目录

- `PetPalDemo.xcodeproj`: iOS 工程文件
- `PetPalDemo/App`: App 入口和根视图
- `PetPalDemo/Core`: 环境、网络、模型、状态
- `PetPalDemo/Features`: 业务页面
- `PetPalDemo/Resources`: `Info.plist`

## 如何在 Xcode 打开

1. 打开 Xcode
2. 选择 `Open a project or file`
3. 打开 `petpal/ios/PetPalDemo.xcodeproj`

如果你的机器只装了 Command Line Tools，而没有完整 Xcode，先在 App Store 安装 Xcode。

## 如何修改 API Base URL

当前值写在：

- `PetPalDemo/Resources/Info.plist`

键名是：

- `API_BASE_URL`

代码读取位置在：

- `PetPalDemo/Core/Environment/AppEnvironment.swift`

代码不会再回退到内置的 `localhost` 默认值；如果这个配置为空或非法，App 会在启动时直接暴露配置问题。

例如本机联调可以写成：

```text
http://127.0.0.1:8000
```

如果后端跑在局域网机器上，可以改成：

```text
http://192.168.x.x:8000
```

## 当前状态

- 已有 SwiftUI App 入口
- 已有页面目录、网络目录、模型目录、状态目录
- 已有基础本地状态 `AppSession`
- 已有可配置 `API base URL`
- 已接入当前仓库内 `backend/` 的核心接口
- 当前保留为唯一客户端，不再维护 Web 前端
