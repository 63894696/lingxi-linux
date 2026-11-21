# 灵犀拼音 · Linux（fcitx5）

本地中文拼音输入法（fcitx5 插件）。与 [Android](https://github.com/63894696/lingxi-android)、[Windows](https://github.com/63894696/lingxi-windows) 共用同一套 Rust 引擎，候选、整句与词库学习行为一致。

**官网下载**：https://www.babelspan.com/prisir-ime.html  
**许可证**：Apache License 2.0

## 功能概览

- **拼音输入**：全拼 / 混拼候选、整句解码、学习上屏
- **简繁切换**：本地转换（与桌面端快捷键/状态栏对齐）
- **语音输入（可选）**：本机识别浮层，不外发音频
- **个人词库**：选词自学习；词库与学习数据百分百本机自主管理
- **开放 API（可选）**：默认关闭；开启后仅监听本机 `127.0.0.1`，供本机 AI Agent / 脚本协助配置

## 隐私

严格隐私保护，完全离线无账号：

- 键入内容、候选与词库只保存在本机，不上传输入正文
- 无账号登录、无行为画像、不出售输入数据
- 输入法本身不主动发起任何网络请求
- 开放 API 默认关闭；开启后也不对外网暴露

## 仓库结构（简述）

| 目录 | 说明 |
|------|------|
| `fcitx5-prisir/` | fcitx5 addon（C++，加载同源引擎） |
| `prisir_ime/` | 同源 Rust 引擎 |
| `scripts/` | 打包与构建辅助脚本 |
| `dist/` | 本地构建产物（如 `.deb`） |

## 安装

需要已安装 **fcitx5**。从官网下载最新 `.deb`（amd64），例如：

```bash
sudo dpkg -i fcitx5-prisir_0.3.6_amd64.deb
# 若有依赖缺失：
sudo apt -f install
```

在 fcitx5 配置中添加「灵犀 / prisir」输入法并切换即可。

## 相关链接

- 官网介绍与安装包：https://www.babelspan.com/prisir-ime.html
- Android 仓：https://github.com/63894696/lingxi-android
- Windows 仓：https://github.com/63894696/lingxi-windows
- 问题反馈：https://bbs.babelspan.com/forum.html#board=browser/ime&hint=prisirai

版权所有 © 2026 BabelSpan。
