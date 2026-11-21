# 灵犀拼音 · Linux 端工作区

迁自 `lingxi-windows/fcitx5-prisir`（2026-11-20），与 Android / Windows 工作区并列。

## 布局

| 路径 | 说明 |
|------|------|
| `fcitx5-prisir/` | fcitx5 addon（C++，dlopen 同源引擎） |
| `prisir_ime/` | **目录联接** → `D:\Projects\lingxi-android\prisir_ime` |

## 调试机

| 别名 | 地址 |
|------|------|
| `lingxi-sf01-lan` | `192.168.0.102`（推荐） |
| `lingxi-sf01` / Tailscale | `100.117.50.20`（`sf01`） |

## 当前包（2026-11-21）

已在 SF01 安装 **`fcitx5-prisir 0.3.0`**（Win 选择性迁移）：

- 修 IC `registerProperty`（解决 0.1.0 精简包崩溃）
- 状态区：词库 / 符号 / 手写 / 语音 / 简繁 / 关于（**无 AI 助手**）
- 引擎为当前 `prisir_ime`；`smoke_matrix` **15/15 通过**

本地产物：`dist/fcitx5-prisir_0.3.0_amd64.deb`

```bash
# 引擎：WSL 编（SF01 内存小、rustup 慢）
wsl -d Ubuntu-24.04 -- bash /mnt/d/Projects/lingxi-linux/scripts/wsl_build_engine.sh
# addon + deb：SF01
ssh lingxi-sf01-lan 'cd /root/lingxi-linux && cmake -B fcitx5-prisir/build -S fcitx5-prisir && cmake --build fcitx5-prisir/build'
# 上传 .so 后
ssh lingxi-sf01-lan 'cd /root/lingxi-linux && bash scripts/pack_deb.sh --addon fcitx5-prisir/build/prisir.so --engine dist/libprisir_ime.so --db assets/ciku.db --out dist/fcitx5-prisir_0.1.0_amd64.deb && dpkg -i dist/fcitx5-prisir_0.1.0_amd64.deb'
```

桌面端在 fcitx5 配置里加「灵犀拼音」后即可输入。

## 功能迁移取舍（对照 0.2.0 原版托盘，SF01 实测）

| 功能 | Linux 可行性 | 建议 |
|------|-------------|------|
| 拼音打字 / 候选 / 学习 | ✅ 已通（0.2.0） | 保留；P0 精简 `prisir.so` 需修 IC 属性崩溃后再升引擎 |
| 词库管理 / 符号大全 / 关于 | ✅ GTK 本机脚本，无特殊限制 | 保留 |
| 手写 | ❌ 与安卓同为自研 ONNX（ochw），精度远差于 Win **系统 Ink**；安卓已下线 | **去除** |
| 语音 | ✅ Win `lingxi_voice` = SenseVoice Small + **onnxruntime**（跨平台） | **迁移**：同模型 `sensevoice-small/`，Linux 用 sounddevice 录音 |
| AI 助手 | ❌ 外挂 PrisirAI | **去除** |
| 开放 API | ✅ `127.0.0.1:23331` | **已实现**（默认关闭） |

原则：手写不迁；**语音迁 Win 同款 SenseVoice**；AI 不进输入法。

语音模型安装（约 230MB，不打进 deb）：

```bash
mkdir -p /usr/lib/fcitx5/prisir/voice/sensevoice-small
# 从 Win 安装树复制 model.onnx + tokens.json（及 config.yaml）
pip3 install numpy onnxruntime sounddevice
```

## 后续

1. **修 P0 崩溃**：对齐 0.2.0 的 `libprisir` IC 属性用法，再挂新引擎
2. **P1**：开放 API + 简繁 + 基础配置
3. 手写/语音仅按需外挂，不阻塞主线
