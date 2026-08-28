# Aidroid - 手机智能助手

Aidroid 是一款 Android 端智能助手，集成多模型 AI 对话、手机操控、Agent 自动化等能力。

## 功能

### AI 对话
- 支持 **DeepSeek**、**OpenAI GPT**、**Anthropic Claude**、**Google Gemini**、**智谱 GLM** 等主流模型
- 支持自定义厂商（兼容 OpenAI Chat Completions 格式）
- 流式输出，实时显示思考过程
- 图片识别（支持多模态模型）

### 手机操控
- **Root 模式** — 通过 `su` 命令执行截图、点击、滑动等操作
- **无障碍模式** — 通过 AccessibilityService 实现 UI 交互
- **Shizuku 模式** — 通过 Shizuku API 执行命令
- 自动解析屏幕 UI 树，智能识别可交互元素

### Agent 自动化
- 自动规划执行步骤，完成复杂任务
- 屏幕视觉分析（截图 + OCR + UI 树解析）
- 浏览器自动化（WebView 内操作）
- 知识库检索（自进化经验库）
- 工具权限管理（剪贴板、短信、通知等）

### 其他
- 隐私模式（隐藏敏感内容）
- 对话历史管理（重命名、导出、分支）
- 场景快捷入口（20+ 预设场景）
- 手动记忆管理
- 悬浮窗操控
- 语音输入

## 环境要求

- **Android 9+** (API 29+)
- Root 权限 / Shizuku / 无障碍服务（操控功能需要至少一种）

## 快速开始

1. 下载 APK 安装
2. 在设置中配置至少一个 AI 厂商的 API Key
3. 开始对话，或开启 Agent 模式执行自动化任务

## 技术栈

- **Flutter** — 跨平台 UI 框架
- **Dart** — 业务逻辑
- **Kotlin** — Android 原生桥接（Shizuku、无障碍、悬浮窗等）
- **Dio** — HTTP 客户端（流式 SSE 请求）
- **Provider** — 状态管理

## 项目结构

```
lib/
├── main.dart                  # 入口
├── app.dart                   # 应用根组件
├── constants.dart             # 常量
├── models/
│   ├── ai_provider.dart       # AI 厂商模型
│   ├── conversation.dart      # 对话数据模型
│   └── custom_ai_provider.dart # 自定义厂商配置
├── providers/
│   └── chat_provider.dart     # 状态管理
├── screens/
│   ├── chat_screen.dart       # 聊天界面
│   ├── new_settings_screen.dart # 设置页
│   ├── custom_provider_screen.dart # 自定义厂商表单
│   ├── history_drawer.dart    # 历史抽屉
│   ├── onboarding_screen.dart # 首次引导
│   └── tos_screen.dart        # 服务协议
├── services/
│   ├── ai_chat_service.dart   # AI 对话 API 调用
│   ├── phone_agent_service.dart # Agent 自动化
│   ├── phone_control_service.dart # 手机操控
│   ├── shizuku_service.dart   # Shizuku 桥接
│   ├── native_bridge.dart     # 原生方法桥接
│   ├── conversation_service.dart # 对话持久化
│   ├── ui_tree_parser.dart    # UI 树解析
│   ├── ocr_service.dart       # OCR 文字识别
│   ├── vision_service.dart    # 视觉分析
│   ├── browser_service.dart   # 浏览器自动化
│   ├── knowledge_search.dart  # 知识库搜索
│   ├── experience_service.dart # 自进化知识库
│   ├── manual_memory_service.dart # 手动记忆
│   ├── tool_permission_service.dart # 工具权限
│   ├── web_search_service.dart # 网页搜索
│   ├── device_scan_service.dart # 设备扫描
│   ├── device_file_service.dart # 文件系统
│   ├── action_recorder.dart   # 操作录制
│   ├── log_service.dart       # 日志
│   └── blind_screen_navigator.dart # 盲屏导航
└── widgets/
    ├── chat_message_bubble.dart # 消息气泡
    ├── model_selector.dart    # 模型选择器
    ├── glass_widgets.dart     # 毛玻璃组件
    ├── image_picker_button.dart # 图片选择
    └── scenario_selector.dart # 场景选择器
```

## 开源协议

本项目基于 MIT 协议开源。