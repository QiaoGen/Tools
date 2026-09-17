# DevCalc — macOS 原生计算器

替代 macOS 自带计算器的原生 app，主打**程序员计算器**。SwiftUI 实现，无任何 Web 技术。

![平台](https://img.shields.io/badge/platform-macOS%2014%2B-black) [![框架](https://img.shields.io/badge/framework-SwiftUI-orange)](src)

## 功能

### 程序员模式（核心）

- **四进制同屏**：HEX / DEC / OCT / BIN 同时显示，点击任意行切换输入进制，当前进制行高亮
- **HEX 按字节分组**（`73 BD 5A 2C`）、DEC 千位分组、OCT 三位分组、BIN 四位分组
- **位翻转面板**：64 个 bit 格子直接点击翻转（MSB 63 在左上，每字节有视觉分隔）
- **字长切换**：8 / 16 / 32 / 64 位，运算结果按字长回绕（如 8 位 `FF + 1 = 00`）
- **有符号 / 无符号**：DEC 显示按二进制补码重新解释（8 位 `FF` → `-1`）
- **位运算**：AND / OR / XOR / NOT / NAND / NOR、移位 `<<` `>>`、循环移位 RoL / RoR、Mod
- 除零错误提示，输入新数字自动恢复

### 基本模式

标准四则计算器（双精度浮点、%、±、千位分组显示）。

## 物理键盘快捷键

| 按键 | 功能 |
| --- | --- |
| `0-9` | 数字 |
| `A-F` | 十六进制（仅 HEX 进制下） |
| `+ - * /` | 加 减 乘 除 |
| `%` | 程序员模式 = Mod；基本模式 = 百分比 |
| `Enter` / `=` | 等号 |
| `Delete`（退格） | 删除末位 |
| `Fn+Delete` | CE（清除当前输入） |
| `Esc` | C（全部清除） |
| `Cmd+C` | 复制当前值 |

## 构建与运行

```bash
# 开发调试
swift build

# 单元测试（29 个）
swift test

# 生成图标（首次）
Scripts/make-icon.sh

# 组装 DevCalc.app（dist/DevCalc.app）
Scripts/make-app.sh

# 打包拖装 DMG（dist/DevCalc-0.1.0.dmg，含 Applications 链接）
Scripts/package-dmg.sh

# 本地运行
open dist/DevCalc.app
```

也可把 `dist/DevCalc.app` 拖到 `/Applications` 长期使用。

## 项目结构

```
DevCalc/
├── Package.swift                  # SPM：executableTarget + 测试
├── Sources/DevCalc/
│   ├── Models/                    # 引擎与格式化（纯逻辑，可独立测试）
│   │   ├── ProgrammerEngine.swift # 64 位位模式引擎：字长截断/进制/位运算
│   │   ├── BasicEngine.swift      # 双精度四则引擎
│   │   ├── Ops.swift              # 二元/一元运算定义
│   │   ├── WordSize.swift         # 字长：掩码/补码/循环移位
│   │   ├── BaseRadix.swift        # 进制枚举
│   │   └── CalcFormatter.swift    # 各进制分组格式化
│   ├── ViewModels/                # @Observable 状态层
│   ├── Views/                     # SwiftUI 界面
│   └── DevCalcApp.swift           # App 入口 + 全局键盘监听
├── Tests/DevCalcTests/            # 引擎单元测试
├── Scripts/                       # 打包脚本 / Info.plist / 图标生成
└── Resources/                     # AppIcon.icns
```

## 设计

界面按 macOS HIG 设计，**跟随系统明暗外观自动切换**：全部颜色为语义角色（窗口背景、按键色阶、强调色、次级文字等），通过 NSColor 动态提供者在浅色/深色下分别解析（浅色 #007AFF / 深色 #0A84FF 强调色，浅色近白数字键 / 深色石墨数字键）。数值显示用 SF Mono，界面标签用 SF Pro。

设计稿（明暗双窗口对照版）见 superdesign 项目 [DevCalc — macOS 程序员计算器](https://superdesign.dev/teams/aa77bfda-21d5-4f78-991d-ea964387f92b/projects/c0c19c40-c6b6-471c-ad25-ac10dbfe9eb6)，设计规范在仓库根目录 `.superdesign/design-system.md`。
