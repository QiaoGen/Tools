# CadReader

轻量、只读的本地 DWG 图纸查看器。桌面版使用 Tauri 封装，图纸通过 WebAssembly 解析并由 WebGL 渲染，不会上传到服务器。

## 功能

- 打开或拖入 `.dwg` 文件
- 鼠标滚轮放大 / 缩小
- 按住鼠标拖动图纸
- 一键适合窗口
- WebGL 渲染，DWG 解析运行在独立线程
- 纯前端运行，无后端、无账号、无上传

## 启动

macOS 可以直接双击 `启动CadReader.command`。

也可以在终端运行：

```bash
npm install
npm run dev
```

打开终端提示的本地地址即可。

> 不要直接双击源码中的 `index.html`，浏览器不能直接执行 Vite/TypeScript 项目。

## 构建

```bash
npm run build
npm run preview
```

构建产物位于 `dist` 文件夹。

## 构建 macOS 应用

```bash
npm run desktop:build
```

应用产物位于 `src-tauri/target/release/bundle/macos/CadReader.app`。

生成 DMG 安装包：

```bash
npm run desktop:dmg
```

## 使用说明

- `Ctrl/Cmd + O`：打开图纸
- `+` / `-`：放大 / 缩小
- `0`：适合窗口
- 鼠标滚轮：缩放
- 鼠标拖动：平移

## 说明

DWG 解析及渲染依赖 `@flyfish-dev/cad-viewer`，其许可证为 AGPL-3.0-only；如需闭源商用，请先评估许可证要求或替换为具备商业授权的 DWG 解析引擎。
