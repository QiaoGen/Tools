# LiteS7

LiteS7 是一个面向 macOS 的轻量 S7 调试工具，使用原生 SwiftUI 和直接实现的 S7comm / ISO-on-TCP 通讯，不依赖第三方运行时。

## 功能

- 连接 S7-300/400/1200/1500（TCP 102，Rack/Slot 可配置）
- 读取 DB、M、I、Q 区域
- 写入 DB、M 区域（I/Q 在本工具中保持只读）
- BOOL、BYTE、INT、WORD、DINT、DWORD、REAL 数据解析
- 100 ms～5 s 连续轮询
- 最近 80 条操作历史，可点击复用
- 显示 S7 协议 TX/RX 十六进制帧

## 构建与运行

```bash
cd /Users/drogonz/development/gitee/tools/LiteS7
swift run
```

生成可双击运行的应用：

```bash
./Scripts/build-app.sh
open dist/LiteS7.app
```

生成带图标的安装镜像：

```bash
./Scripts/package-dmg.sh
open dist/LiteS7-0.1.0.dmg
```

## 地址示例

| 地址 | 类型 | 含义 |
|---|---|---|
| `DB1.DBX0.0` | BOOL | DB1 第 0 字节第 0 位 |
| `DB1.DBB0` | BYTE | DB1 第 0 字节 |
| `DB1.DBW2` | INT / WORD | DB1 从第 2 字节开始 |
| `DB1.DBD4` | DINT / DWORD / REAL | DB1 从第 4 字节开始 |
| `M0.0` / `MB0` / `MW0` / `MD0` | 对应类型 | M 区 |
| `IB0` / `IW0` / `ID0` | 对应类型 | 输入区，只读 |
| `QB0` / `QW0` / `QD0` | 对应类型 | 输出区，只读 |

S7-1200/1500 通常需要在 TIA Portal 中关闭目标 DB 的“优化的块访问”，并允许来自远程对象的 PUT/GET 通信。
