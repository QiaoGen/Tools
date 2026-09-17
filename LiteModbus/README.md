# LiteModbus — Modbus TCP 主从站调试工具

macOS 原生 Modbus TCP 调试工具，**Master（主站）与 Slave（从站仿真）集成在一个 app**。SwiftUI 实现，跟随系统明暗外观，无第三方依赖，所有数据本地 JSON 存储。

![平台](https://img.shields.io/badge/platform-macOS%2014%2B-black) ![Swift](https://img.shields.io/badge/Swift-5.10-orange)

## 功能

### 主站（Master）

- **连接**：TCP 连接任意从站（主机 / 端口 / Unit ID / 超时均可配置）
- **点位表**：变量名称自定义；地址支持 `40001` 式 5 位编号与 `400101` 式 6 位扩展编号；**位细分**（如 `40001.1`，bit0 = 最低位）；数据类型 Bool / Int16 / UInt16 / Int32 / UInt32 / Float32 / Int64 / UInt64 / Float64；多寄存器类型支持四种字节序 ABCD / CDAB / BADC / DCBA
- **轮询引擎**：可调间隔自动轮询，相邻地址自动合并批量读（单帧最多 125 寄存器 / 2000 位，不做间隙填充以免严格设备报异常 02）；显示周期耗时、Tx/Rx/Err 计数；数值变化 flash 提示
- **手动写入**：单线圈 / 单寄存器 / 多寄存器；寄存器位写入自动读-改-写；支持 0x 十六进制输入
- **看板**：勾选关键点位提取成卡片大屏，实时大字显示，适合盯数与投屏
- **配方**：把一组点位 + 目标值存成配方（JSON），支持「从点位表捕获当前值」「应用到设备」一键批量下写、导入 / 导出
- **报文日志**：每一帧 TX/RX 的功能码、摘要、HEX 原文、异常与超时标记；过滤 / 暂停 / 导出

### 从站（Slave）

- **仿真服务**：监听任意端口（<1024 需管理员权限），支持 01/02/03/04/05/06/0F/10 功能码，异常码自动应答（非法功能 / 非法地址 / 非法值）
- **多格式寄存器表**：对照 Modbus Slave 软件的「附加格式」——Word / Hex / 无符号 / 有符号 / Float(AB CD) 同屏显示；**双击修改**、线圈开关、16 位格点击翻转（bit0 在右）
- **变量名称**：从站侧同样可给每个地址命名
- **调试辅助**：Unit ID 白名单 / 区间（如 `1-247`）、模拟响应延迟（调主站超时）、活动连接 / 请求数 / 异常数 / 每秒请求统计
- **内存快照**：寄存器状态导出 / 导入 JSON，场景可复现

## 构建

```bash
cd LiteModbus
swift build                  # 调试构建
swift test                   # 30 个单元/集成测试（含主从 TCP 回环）
Scripts/make-app.sh          # 打包 build/LiteModbus.app
open build/LiteModbus.app
```

图标重新生成：`Scripts/make-icon.sh`。

## 数据存储

所有数据自动保存在 `~/Library/Application Support/LiteModbus/`：

| 文件 | 内容 |
| --- | --- |
| `master.json` | 连接配置 + 点位表（名称/地址/位/类型/字节序/看板标记） |
| `recipes.json` | 配方列表（名称 + 条目 + 值） |
| `slave.json` | 从站监听配置 + 变量名 + 内存快照 |

## 地址约定

- `00001`–`09999` 线圈（0x），`10001`–`19999` 离散输入（1x），`30001`–`39999` 输入寄存器（3x），`40001`–`49999` 保持寄存器（4x）
- 六位扩展编号：`400101` = 保持寄存器偏移 100，最大 `465536`
- 位细分：`40001.0`–`40001.15`，**bit0 为最低位（LSB）**
- 字节序（多寄存器类型）：`ABCD` 大端（标准）· `CDAB` 字交换 · `BADC` 字内交换 · `DCBA` 小端

## 结构

```
Sources/LiteModbus/
├── Models/            # 协议编解码、Master 客户端、Slave 服务端、点位模型、JSON 持久化
├── ViewModels/        # 主站（连接/轮询/写入）、从站仿真、配方仓库
└── Views/             # SwiftUI：边栏导航、点位表、看板、配方、报文日志、从站寄存器表
```

界面设计稿（明暗双窗口对照）见 superdesign 画布项目「LiteModbus — Modbus TCP 主从站调试工具」，设计规范见 [design-system.md](design-system.md)。
