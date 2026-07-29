import { CadViewer } from '@flyfish-dev/cad-viewer';
import '@flyfish-dev/cad-viewer/style.css';
import './styles.css';

const icons = {
  open: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3.5 6.5h6l2 2h9v9.25A2.25 2.25 0 0 1 18.25 20H5.75a2.25 2.25 0 0 1-2.25-2.25V6.5Z"/><path d="M3.5 10h17"/></svg>',
  plus: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
  minus: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14"/></svg>',
  fit: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 3H3v5M16 3h5v5M8 21H3v-5M16 21h5v-5"/><path d="m3 8 5-5m8 0 5 5M3 16l5 5m8 0 5-5"/></svg>',
  close: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6 6 12 12M18 6 6 18"/></svg>',
  file: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 2.75h7l5 5v13.5H6V2.75Z"/><path d="M13 2.75v5h5"/><path d="M8.75 16.75h6.5M8.75 13.5h6.5"/></svg>',
  cad: '<svg viewBox="0 0 32 32" aria-hidden="true"><path d="M5 25.5 16 5l11 20.5H5Z"/><path d="m10.5 21 5.5-10 5.5 10h-11Z"/><circle cx="16" cy="21" r="2.2"/></svg>'
};

document.querySelector<HTMLDivElement>('#app')!.innerHTML = `
  <main class="app-shell">
    <header class="topbar">
      <div class="brand" aria-label="CadReader">
        <span class="brand-mark">${icons.cad}</span>
        <span class="brand-name">CadReader</span>
        <span class="brand-rule"></span>
        <span class="brand-subtitle">DWG VIEWER</span>
      </div>

      <div class="file-summary" id="fileSummary" hidden>
        <span class="file-summary-icon">${icons.file}</span>
        <span class="file-summary-copy">
          <strong id="fileName"></strong>
          <small id="fileMeta"></small>
        </span>
        <button class="icon-button file-close" id="closeFile" type="button" aria-label="关闭图纸" title="关闭图纸">
          ${icons.close}
        </button>
      </div>

      <button class="open-button" id="openButton" type="button">
        ${icons.open}
        <span>打开 DWG</span>
      </button>
      <input id="fileInput" type="file" accept=".dwg,application/acad,application/x-acad" hidden />
    </header>

    <section class="workspace" id="workspace">
      <div class="viewer" id="viewer" aria-label="CAD 图纸区域"></div>
      <div class="blueprint-grid" aria-hidden="true"></div>

      <div class="empty-state" id="emptyState">
        <div class="empty-graphic" aria-hidden="true">
          <span class="corner corner-tl"></span>
          <span class="corner corner-tr"></span>
          <span class="corner corner-bl"></span>
          <span class="corner corner-br"></span>
          <span class="drawing-icon">${icons.cad}</span>
          <span class="axis axis-x">X</span>
          <span class="axis axis-y">Y</span>
        </div>
        <p class="eyebrow">LOCAL DRAWING VIEWER</p>
        <h1>把图纸放到这里</h1>
        <p class="empty-help">拖入 DWG 文件，或从本机选择</p>
        <button class="empty-open-button" id="emptyOpenButton" type="button">选择 DWG 文件</button>
        <div class="privacy-note"><span></span> 文件仅在当前浏览器中读取，不会上传</div>
      </div>

      <div class="loading-panel" id="loadingPanel" hidden>
        <div class="loading-spinner"></div>
        <div class="loading-copy">
          <strong id="loadingTitle">正在读取图纸</strong>
          <span id="loadingMessage">准备解析引擎…</span>
        </div>
        <div class="loading-track"><span id="loadingProgress"></span></div>
      </div>

      <div class="error-toast" id="errorToast" role="alert" hidden>
        <span class="error-code">!</span>
        <span id="errorMessage"></span>
        <button id="dismissError" type="button" aria-label="关闭提示">${icons.close}</button>
      </div>

      <nav class="view-controls" id="viewControls" aria-label="视图控制" hidden>
        <button type="button" id="zoomIn" aria-label="放大" title="放大">${icons.plus}</button>
        <button type="button" id="zoomOut" aria-label="缩小" title="缩小">${icons.minus}</button>
        <span></span>
        <button type="button" id="fitView" aria-label="适合窗口" title="适合窗口">${icons.fit}</button>
      </nav>

      <footer class="statusbar">
        <span class="status-left"><i id="statusDot"></i><b id="statusText">等待图纸</b></span>
        <span class="status-hint" id="statusHint">滚轮缩放 · 按住鼠标拖动</span>
        <span class="status-zoom" id="zoomText">100%</span>
      </footer>
    </section>
  </main>
`;

const elements = {
  workspace: getElement<HTMLDivElement>('workspace'),
  viewer: getElement<HTMLDivElement>('viewer'),
  input: getElement<HTMLInputElement>('fileInput'),
  openButton: getElement<HTMLButtonElement>('openButton'),
  emptyOpenButton: getElement<HTMLButtonElement>('emptyOpenButton'),
  emptyState: getElement<HTMLDivElement>('emptyState'),
  fileSummary: getElement<HTMLDivElement>('fileSummary'),
  fileName: getElement<HTMLElement>('fileName'),
  fileMeta: getElement<HTMLElement>('fileMeta'),
  closeFile: getElement<HTMLButtonElement>('closeFile'),
  loadingPanel: getElement<HTMLDivElement>('loadingPanel'),
  loadingTitle: getElement<HTMLElement>('loadingTitle'),
  loadingMessage: getElement<HTMLElement>('loadingMessage'),
  loadingProgress: getElement<HTMLElement>('loadingProgress'),
  errorToast: getElement<HTMLDivElement>('errorToast'),
  errorMessage: getElement<HTMLElement>('errorMessage'),
  dismissError: getElement<HTMLButtonElement>('dismissError'),
  viewControls: getElement<HTMLElement>('viewControls'),
  zoomIn: getElement<HTMLButtonElement>('zoomIn'),
  zoomOut: getElement<HTMLButtonElement>('zoomOut'),
  fitView: getElement<HTMLButtonElement>('fitView'),
  statusDot: getElement<HTMLElement>('statusDot'),
  statusText: getElement<HTMLElement>('statusText'),
  statusHint: getElement<HTMLElement>('statusHint'),
  zoomText: getElement<HTMLElement>('zoomText')
};

const viewer = new CadViewer({
  container: elements.viewer,
  renderer: 'auto',
  wasmPath: new URL('wasm/', document.baseURI).href,
  workerUrl: new URL('wasm/dwg-worker.js', document.baseURI).href,
  useWorker: true,
  transferInputBuffer: true,
  autoFit: true,
  canvasOptions: {
    background: '#0b0e0c',
    foreground: '#d9e7dd',
    fitMode: 'auto',
    contrastMode: 'adaptive',
    minColorContrast: 2.6,
    showPageBounds: true,
    showUnsupportedMarkers: false,
    enableSpatialIndex: true,
    spatialIndexCellCount: 64,
    maxVerticesPerBatch: 65536,
    maxCurveSegments: 36,
    maxVisibleTextLabels: 1200,
    textMinPixelHeight: 5,
    powerPreference: 'high-performance',
    antialias: false,
    preserveDrawingBuffer: false
  },
  onLoadProgress(progress) {
    elements.loadingMessage.textContent = progressMessage(progress.phase);
    if (typeof progress.percent === 'number') {
      elements.loadingProgress.style.width = `${Math.max(4, progress.percent)}%`;
    }
  },
  onViewChange(event) {
    elements.zoomText.textContent = `${Math.round(event.zoomPercent)}%`;
  }
});

let currentFile: File | null = null;
const engineReady = viewer.preloadDwg().catch(() => undefined);

elements.openButton.addEventListener('click', openPicker);
elements.emptyOpenButton.addEventListener('click', openPicker);
elements.input.addEventListener('change', () => {
  const file = elements.input.files?.[0];
  if (file) void loadDrawing(file);
});
elements.closeFile.addEventListener('click', clearDrawing);
elements.zoomIn.addEventListener('click', () => viewer.zoomIn());
elements.zoomOut.addEventListener('click', () => viewer.zoomOut());
elements.fitView.addEventListener('click', () => {
  viewer.fit();
});
elements.viewer.addEventListener('dblclick', () => viewer.fit());
elements.dismissError.addEventListener('click', () => hide(elements.errorToast));

for (const eventName of ['dragenter', 'dragover']) {
  elements.workspace.addEventListener(eventName, (event) => {
    event.preventDefault();
    elements.workspace.classList.add('is-dragging');
  });
}

for (const eventName of ['dragleave', 'drop']) {
  elements.workspace.addEventListener(eventName, (event) => {
    event.preventDefault();
    if (eventName === 'dragleave' && event.target !== elements.workspace) return;
    elements.workspace.classList.remove('is-dragging');
  });
}

elements.workspace.addEventListener('drop', (event) => {
  const file = event.dataTransfer?.files[0];
  if (!file) return;
  if (!file.name.toLowerCase().endsWith('.dwg')) {
    showError('请选择 .dwg 格式的图纸文件');
    return;
  }
  void loadDrawing(file);
});

window.addEventListener('keydown', (event) => {
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'o') {
    event.preventDefault();
    openPicker();
  }
  if (!currentFile) return;
  if (event.key === '+' || event.key === '=') viewer.zoomIn();
  if (event.key === '-') viewer.zoomOut();
  if (event.key === '0') viewer.fit();
});

window.addEventListener('beforeunload', () => viewer.destroy());

function getElement<T extends HTMLElement>(id: string): T {
  const element = document.getElementById(id);
  if (!element) throw new Error(`缺少页面元素：${id}`);
  return element as T;
}

function openPicker(): void {
  elements.input.value = '';
  elements.input.click();
}

async function loadDrawing(file: File): Promise<void> {
  if (!file.name.toLowerCase().endsWith('.dwg')) {
    showError('请选择 .dwg 格式的图纸文件');
    return;
  }

  hide(elements.errorToast);
  show(elements.loadingPanel);
  elements.loadingTitle.textContent = `正在读取 ${file.name}`;
  elements.loadingMessage.textContent = '准备本地解析引擎…';
  elements.loadingProgress.style.width = '4%';
  elements.workspace.classList.add('is-loading');
  setStatus('正在读取', 'loading');
  const startedAt = performance.now();
  const loadingTimer = window.setInterval(() => {
    const elapsedSeconds = Math.max(1, Math.round((performance.now() - startedAt) / 1000));
    elements.loadingTitle.textContent = `正在读取 ${file.name} · ${elapsedSeconds}秒`;
  }, 1000);

  try {
    await engineReady;
    await viewer.loadFile(file);
    currentFile = file;
    const elapsedSeconds = (performance.now() - startedAt) / 1000;
    elements.fileName.textContent = file.name;
    elements.fileMeta.textContent = `${formatBytes(file.size)} · 读取 ${elapsedSeconds.toFixed(1)}秒 · 本地只读`;
    hide(elements.emptyState);
    show(elements.fileSummary);
    show(elements.viewControls);
    elements.statusHint.textContent = '滚轮缩放 · 按住鼠标拖动 · 双击适配';
    setStatus('图纸已就绪', 'ready');
  } catch (error) {
    viewer.clear();
    currentFile = null;
    show(elements.emptyState);
    hide(elements.fileSummary);
    hide(elements.viewControls);
    setStatus('读取失败', 'error');
    showError(readableError(error));
  } finally {
    window.clearInterval(loadingTimer);
    hide(elements.loadingPanel);
    elements.workspace.classList.remove('is-loading');
  }
}

function clearDrawing(): void {
  viewer.clear();
  currentFile = null;
  elements.input.value = '';
  show(elements.emptyState);
  hide(elements.fileSummary);
  hide(elements.viewControls);
  hide(elements.errorToast);
  elements.zoomText.textContent = '100%';
  elements.statusHint.textContent = '滚轮缩放 · 按住鼠标拖动';
  setStatus('等待图纸', 'idle');
}

function showError(message: string): void {
  elements.errorMessage.textContent = message;
  show(elements.errorToast);
}

function readableError(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  if (/unsupported|version/i.test(message)) return '该 DWG 版本或图元暂不受支持，请尝试另存为较常见的 DWG 版本。';
  if (/memory|allocation/i.test(message)) return '图纸过大，浏览器内存不足，建议关闭其他页面后重试。';
  return `无法读取此图纸：${message}`;
}

function progressMessage(phase: string): string {
  const messages: Record<string, string> = {
    read: '正在读取本地文件…',
    detect: '正在识别 DWG 版本…',
    'worker-start': '正在启动后台解析线程…',
    'worker-ready': '后台解析线程已就绪…',
    'wasm-init': '正在加载 DWG 解析引擎…',
    parse: '正在解析图层和图元…',
    normalize: '正在整理图纸数据，大图纸可能需要 20–60 秒…',
    render: '正在构建高性能视图…',
    done: '图纸读取完成'
  };
  return messages[phase] ?? '正在处理图纸…';
}

function setStatus(text: string, state: 'idle' | 'loading' | 'ready' | 'error'): void {
  elements.statusText.textContent = text;
  elements.statusDot.dataset.state = state;
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

function show(element: HTMLElement): void {
  element.hidden = false;
}

function hide(element: HTMLElement): void {
  element.hidden = true;
}
