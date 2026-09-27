# 豆包 API 助手 (YuanbaoApi)

把豆包（Doubao）网页版的登录态与对话能力，转换成 OpenAI 兼容的 API 服务，直接在安卓手机上运行。任何支持 OpenAI 协议的客户端 / AI Agent 都可连接本机使用。

## 功能

- OpenAI 兼容 API 服务：在 App 内启动 HTTP 服务器，暴露 /v1/* 端点
- 多模态对话：三模式（快速/思考/专家），SSE 流式 + 非流式
- 图片/视频/音乐生成：/v1/images/generations、/v1/video/generations、/v1/audio/generations
- 登录豆包：应用内网页登录，自动保持登录态
- 悬浮球：其它应用上快速呼出
- 后台保活：前台服务 + 忽略电池优化
- 请求日志：实时查看 API 调用

## 端点

GET /health - 健康检查
GET /v1/models - 模型列表
POST /v1/chat/completions - 对话补全（OpenAI 格式）
POST /v1/images/generations - 图片生成
POST /v1/video/generations - 视频生成
POST /v1/audio/generations - 音乐生成
GET /auth/status - 登录状态

## 使用

1. 安装 App，打开后点击「启动服务」
2. 在「设置 -> 登录豆包账号」中登录
3. 其它设备用 http://手机IP:9090/v1 作为 Base URL 调用

## 原理

复刻 doubao2api：
- 在隐藏 WebView 中加载豆包网页，复用其 JS 完成 a_bogus / msToken 签名
- 通过注入的 JS 在页面上下文发起 /samantha/chat/completion 请求
- Dart 侧解析 SSE 事件（event_type / content_type），转换为 OpenAI 格式

## 构建

flutter pub get
flutter build apk --debug

产物：build/app/outputs/flutter-apk/app-debug.apk
