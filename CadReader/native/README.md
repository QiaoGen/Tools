# CadReader Native for macOS

原生 macOS DWG/DXF 只读查看器：

- AppKit 原生窗口
- `LibreDWG` C 本地解析 DWG
- Metal GPU 线条渲染
- 后台线程打开图纸
- 支持拖入、滚轮缩放、鼠标拖动、双击适配
- 无浏览器、无本地服务器、无文件上传

## 构建运行

双击 `构建并运行.command`，或者执行：

```bash
cmake -S . -B build -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
open build/CadReader.app
```

构建脚本需要 Homebrew 的 `libredwg`：`brew install libredwg`。

## 许可证

`LibreDWG` 使用 GPL-3.0-or-later。若需要闭源商业发布，建议换用 ODA Drawings SDK。
