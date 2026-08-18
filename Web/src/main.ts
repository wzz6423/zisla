import {
  Airplay,
  AlignLeft,
  ArrowDownToLine,
  ArrowUpRight,
  BatteryCharging,
  Bot,
  Bold,
  CalendarCheck,
  CalendarDays,
  ChartLine,
  Check,
  ChevronDown,
  Clipboard,
  ClipboardPaste,
  Clock,
  Cloud,
  Code2,
  Copy,
  Download,
  ExternalLink,
  Fan,
  FileText,
  Film,
  Files,
  Folder,
  Gauge,
  Globe,
  Grid2x2,
  HardDrive,
  Heart,
  Image,
  Info,
  Inbox,
  Italic,
  Link,
  Link2,
  List,
  ListChecks,
  ListMusic,
  ListOrdered,
  Lock,
  Mail,
  MapPin,
  Menu,
  NotebookPen,
  Pause,
  Pencil,
  Pin,
  Plus,
  RefreshCw,
  ScanText,
  Search,
  Settings,
  Share2,
  Shield,
  Smile,
  Sparkles,
  SkipBack,
  SkipForward,
  Star,
  Strikethrough,
  Sun,
  Trash2,
  TrendingUp,
  TriangleAlert,
  Underline,
  Volume2,
  Wrench,
  X,
  createIcons,
} from 'lucide';
import {
  agendaEmptyText,
  agentMeta,
  aiTasks,
  batteryMeta,
  clipboardItems,
  clipboardMeta,
  dashboardMeta,
  developmentSetup,
  documentationLinks,
  downloadLinks,
  downloadMeta,
  faqItems,
  flowSteps,
  heroCycleModules,
  heroHints,
  heroTitle,
  islandMetrics,
  islandModules,
  islandUptime,
  latestRelease,
  license,
  lockScreenMeta,
  mailMeta,
  navItems,
  notesMeta,
  nowPlaying,
  pdfActiveDesc,
  pdfActiveTitle,
  pdfTools,
  performanceFeatures,
  privacyPoints,
  productDescription,
  productTagline,
  proofItems,
  providerColors,
  repositoryLinks,
  shelfMeta,
  showcaseGroups,
  showcaseModules,
  supportedAITools,
  systemCards,
  systemRequirements,
  tokenTrend,
  toolboxMeta,
  weatherCities,
} from './content';
import './styles.css';

// backdrop-filter: url(#svg) 目前只有 Chromium 真正渲染，检测后加类启用液态折射；
// 其余浏览器走 CSS 里的 blur/saturate 兜底，不影响可用性。
if (/Chrom(e|ium)/.test(navigator.userAgent) && !/Mobile|Android|iPhone|iPad/.test(navigator.userAgent)) {
  document.documentElement.classList.add('lg-refract');
}

const app = document.querySelector<HTMLDivElement>('#app');

if (!app) {
  throw new Error('找不到官网挂载节点');
}

const icon = (name: string, size = 16) =>
  `<i data-lucide="${name}" width="${size}" height="${size}" aria-hidden="true"></i>`;

const siteIcons = {
  Airplay,
  AlignLeft,
  ArrowDownToLine,
  ArrowUpRight,
  BatteryCharging,
  Bot,
  Bold,
  CalendarCheck,
  CalendarDays,
  ChartLine,
  Check,
  ChevronDown,
  Clipboard,
  ClipboardPaste,
  Clock,
  Cloud,
  Code2,
  Copy,
  Download,
  ExternalLink,
  Fan,
  FileText,
  Film,
  Files,
  Folder,
  Gauge,
  Globe,
  Grid2x2,
  HardDrive,
  Heart,
  Image,
  Info,
  Inbox,
  Italic,
  Link,
  Link2,
  List,
  ListChecks,
  ListMusic,
  ListOrdered,
  Lock,
  Mail,
  MapPin,
  Menu,
  NotebookPen,
  Pause,
  Pencil,
  Pin,
  Plus,
  RefreshCw,
  ScanText,
  Search,
  Settings,
  Share2,
  Shield,
  Smile,
  Sparkles,
  SkipBack,
  SkipForward,
  Star,
  Strikethrough,
  Sun,
  Trash2,
  TrendingUp,
  TriangleAlert,
  Underline,
  Volume2,
  Wrench,
  X,
};

const formatClock = (seconds: number) =>
  `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;

const renderCrown = (activeModule: string) => `
  <div class="crown">
    <div class="crown-media">
      <div class="np">
        <div class="np-art" aria-hidden="true"><span class="np-art-disc"></span></div>
        <div class="np-info">
          <div class="np-title">${nowPlaying.title}<span class="np-artist"> · ${nowPlaying.artist}</span></div>
          <div class="np-subtitle">${nowPlaying.subtitle}</div>
          <div class="np-progress">
            <span class="np-time" data-np-time>${formatClock(nowPlaying.currentSeconds)}</span>
            <span class="np-bar"><span class="np-fill" data-np-fill style="transform: scaleX(${(
              nowPlaying.currentSeconds / nowPlaying.durationSeconds
            ).toFixed(3)})"></span></span>
            <span class="np-duration">${formatClock(nowPlaying.durationSeconds)}</span>
          </div>
        </div>
        <div class="np-side">
          <div class="np-uptime">${islandUptime}</div>
          <div class="np-controls">
            <span class="np-viz" aria-hidden="true">${Array.from(
              { length: 8 },
              (_, i) => `<i style="--d: ${i * 0.12}s"></i>`,
            ).join('')}</span>
            <span class="np-btn" title="播放列表">${icon('list-music', 13)}</span>
            <span class="np-btn" title="收藏">${icon('heart', 13)}</span>
            <span class="np-btn" title="输出设备">${icon('airplay', 13)}</span>
            <span class="np-btn" title="上一首">${icon('skip-back', 13)}</span>
            <span class="np-btn np-play" title="播放">${icon('pause', 13)}</span>
            <span class="np-btn" title="下一首">${icon('skip-forward', 13)}</span>
          </div>
        </div>
      </div>
    </div>
    <div class="crown-toolbar">
      <div class="crown-tools" role="tablist" aria-label="功能模块">
        ${islandModules
          .map(
            (module) => `
          <button type="button" class="crown-tool${module.id === activeModule ? ' is-active' : ''}"
            data-tool="${module.id}" title="${module.name}" aria-label="${module.name}">
            ${icon(module.icon, 14)}
          </button>`,
          )
          .join('')}
      </div>
      <div class="crown-end">
        <div class="crown-metrics" aria-label="系统资源占用">
          ${islandMetrics
            .map(
              (metric) => `
            <span class="metric${metric.tone === 'good' ? ' is-good' : ''}">
              <b>${metric.value}%</b><span>${metric.label}</span>
            </span>`,
            )
            .join('')}
        </div>
        <span class="crown-action" title="置顶">${icon('pin', 12)}</span>
        <span class="crown-action" title="设置">${icon('settings', 12)}</span>
      </div>
    </div>
  </div>
`;

/* ================= 模块面板渲染（按真实界面还原） ================= */

const smoothPath = (points: [number, number][]) => {
  if (points.length < 2) return '';
  let path = `M ${points[0][0]},${points[0][1]}`;
  for (let i = 0; i < points.length - 1; i += 1) {
    const p0 = points[Math.max(0, i - 1)];
    const p1 = points[i];
    const p2 = points[i + 1];
    const p3 = points[Math.min(points.length - 1, i + 2)];
    const c1x = p1[0] + (p2[0] - p0[0]) / 6;
    const c1y = p1[1] + (p2[1] - p0[1]) / 6;
    const c2x = p2[0] - (p3[0] - p1[0]) / 6;
    const c2y = p2[1] - (p3[1] - p1[1]) / 6;
    path += ` C ${c1x.toFixed(1)},${c1y.toFixed(1)} ${c2x.toFixed(1)},${c2y.toFixed(1)} ${p2[0]},${p2[1].toFixed(1)}`;
  }
  return path;
};

const renderTokenChart = () => {
  const width = 320;
  const height = 104;
  const padX = 34;
  const padTop = 12;
  const padBottom = 18;
  const y = (v: number) => padTop + (1 - v) * (height - padTop - padBottom);
  const xs = tokenTrend.points.map(
    (_, i) => padX + (i * (width - padX - 8)) / (tokenTrend.points.length - 1),
  );
  const ys = tokenTrend.points.map((v) => y(v));
  const pts = xs.map((x, i) => [x, ys[i]] as [number, number]);
  const line = smoothPath(pts);
  const area = `${line} L ${xs[xs.length - 1]},${height - padBottom} L ${xs[0]},${height - padBottom} Z`;
  const gridYs = [0.05, 0.36, 0.68, 1].map((v) => y(v));
  return `
    <svg viewBox="0 0 ${width} ${height}" class="token-chart" role="img" aria-label="Token 消耗趋势折线图">
      <defs>
        <linearGradient id="tokenFill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#0a84ff" stop-opacity="0.35"/>
          <stop offset="100%" stop-color="#0a84ff" stop-opacity="0"/>
        </linearGradient>
      </defs>
      ${gridYs
        .map(
          (gy, i) => `
        <line x1="${padX}" y1="${gy.toFixed(1)}" x2="${width - 8}" y2="${gy.toFixed(1)}" class="chart-grid"/>
        <text x="${padX - 6}" y="${(gy + 3).toFixed(1)}" class="chart-label" text-anchor="end">${tokenTrend.yLabels[i]}</text>`,
        )
        .join('')}
      ${tokenTrend.xLabels
        .map(
          (label, i) =>
            `<text x="${xs[i].toFixed(1)}" y="${height - 4}" class="chart-label" text-anchor="${i === 0 ? 'start' : i === tokenTrend.xLabels.length - 1 ? 'end' : 'middle'}">${label}</text>`,
        )
        .join('')}
      <path d="${area}" fill="url(#tokenFill)"/>
      <path d="${line}" class="chart-line"/>
      <circle cx="${xs[xs.length - 1]}" cy="${ys[ys.length - 1].toFixed(1)}" r="3" class="chart-dot"/>
      <circle cx="${xs[xs.length - 1]}" cy="${ys[ys.length - 1].toFixed(1)}" r="6" class="chart-dot-halo"/>
    </svg>
  `;
};

const heatmapIntensity = (col: number, row: number) => {
  const base = Math.abs(Math.sin(col * 12.9898 + row * 78.233) * 43758.5453) % 1;
  const weekend = row === 0 || row === 6;
  const recent = col > 18;
  let v = base * 0.5 + (recent ? 0.35 : 0) - (weekend ? 0.28 : 0);
  if (col < 3) v -= 0.25;
  return Math.max(0.04, Math.min(1, v));
};

const renderHeatmap = () => {
  const weeks = 26;
  const now = new Date();
  const monthLabels: string[] = [];
  let lastMonth = -1;
  for (let col = 0; col < weeks; col += 1) {
    const date = new Date(now);
    date.setDate(date.getDate() - (weeks - 1 - col) * 7);
    if (date.getMonth() !== lastMonth) {
      lastMonth = date.getMonth();
      monthLabels.push(`<span style="grid-column: ${col + 1} / span 3">${lastMonth + 1}月</span>`);
    }
  }
  const cells = Array.from({ length: weeks * 7 }, (_, i) => {
    const col = Math.floor(i / 7);
    const row = i % 7;
    return `<i style="--v: ${heatmapIntensity(col, row).toFixed(2)}; animation-delay: ${(col * 7 + row) * 4}ms"></i>`;
  }).join('');
  return `
    <div class="hm-months">${monthLabels.join('')}</div>
    <div class="hm-grid" style="--cols: ${weeks}">${cells}</div>
    <div class="hm-legend"><span>少</span>${[0.15, 0.35, 0.55, 0.75, 1]
      .map((v) => `<i style="--v: ${v}"></i>`)
      .join('')}<span>多</span></div>
  `;
};

const formatElapsed = (seconds: number) =>
  `${String(Math.floor(seconds / 3600)).padStart(2, '0')}:${String(
    Math.floor((seconds % 3600) / 60),
  ).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;

const renderDashboardPanel = () => `
  <div class="panel panel-dashboard">
    <div class="dashboard-grid">
      <article class="dashboard-card dashboard-focus">
        <div class="dashboard-label">${icon('clock', 12)}<span>专注倒计时</span></div>
        <div class="dashboard-focus-row">
          <b>${dashboardMeta.focus.clock}</b>
          <span>${dashboardMeta.focus.phase}</span>
        </div>
      </article>
      <article class="dashboard-card dashboard-ai">
        <div class="dashboard-label">${icon('sparkles', 12)}<span>AI 工作</span></div>
        <div class="dashboard-task-row">
          <span class="dashboard-mascot">${icon('sparkles', 13)}</span>
          <span class="dashboard-task-copy">
            <b>${dashboardMeta.ai.title}</b>
            <i><span style="width: ${dashboardMeta.ai.progress}%"></span></i>
          </span>
          <strong>${dashboardMeta.ai.progress}%</strong>
        </div>
      </article>
      <article class="dashboard-card dashboard-transfer">
        <div class="dashboard-label">${icon('download', 12)}<span>下载进度</span></div>
        <div class="dashboard-transfer-head">
          <b>${dashboardMeta.download.progress}%</b>
          <span>${dashboardMeta.download.speed} · ${dashboardMeta.download.eta}</span>
        </div>
        <div class="dashboard-progress"><span style="width: ${dashboardMeta.download.progress}%"></span></div>
        <div class="dashboard-file">${dashboardMeta.download.title}</div>
      </article>
    </div>
  </div>
`;

const renderAIMonitorPanel = () => `
  <div class="panel panel-ai">
    <div class="ai-tasks">
      <div class="panel-head">${icon('list', 13)}<span>运行任务</span><b>${aiTasks.length}</b></div>
      <div class="ai-task-list">
        ${aiTasks
          .map(
            (task) => `
          <div class="ai-task" data-elapsed="${task.elapsedSeconds}" style="--ai-provider-color: ${providerColors[task.provider]}">
            <div class="ai-task-top">
              <span class="ai-task-name">${task.name}</span>
              <span class="ai-tag">${task.provider}</span>
              <span class="ai-status${
                task.status === 'spinner' ? ' is-spinner' : ' is-dot'
              }" aria-hidden="true"></span>
            </div>
            <div class="ai-task-model">${task.detail} · effort ${task.effort}</div>
            <div class="ai-task-meta">${task.meta} · 运行 <span class="elapsed">${formatElapsed(
              task.elapsedSeconds,
            )}</span></div>
          </div>`,
          )
          .join('')}
      </div>
    </div>
    <div class="ai-usage">
      <div class="panel-head">${icon('chart-line', 13)}<span>Token 消耗趋势</span></div>
      ${renderTokenChart()}
      <div class="ai-heatmap">
        ${renderHeatmap()}
      </div>
    </div>
  </div>
`;

const renderAIAgentPanel = () => `
  <div class="panel panel-agent">
    <div class="panel-head agent-head">
      ${icon('sparkles', 13)}<span>AI Agent</span>
      <span class="head-action">${icon('refresh-cw', 12)}</span>
    </div>
    <div class="agent-layout">
      <aside class="agent-history">
        <div class="agent-history-head"><b>统一历史</b><span>${icon('plus', 11)}</span></div>
        <button type="button" class="agent-project-add">${icon('folder', 11)}<span>添加项目</span>${icon('chevron-down', 9)}</button>
        <span class="agent-group-label">未归类</span>
        <button type="button" class="agent-thread is-active">
          ${icon('sparkles', 11)}<span>${agentMeta.thread}</span>
        </button>
        <span class="agent-group-label">项目</span>
        <button type="button" class="agent-thread">
          ${icon('folder', 11)}<span>${agentMeta.project}</span>
        </button>
      </aside>
      <section class="agent-chat">
        <div class="agent-messages">
          ${agentMeta.messages
            .map(
              (message) => `
            <div class="agent-message${message.role === '你' ? ' is-user' : ''}">
              <span>${message.role}</span>
              <p>${message.body}</p>
            </div>`,
            )
            .join('')}
          <div class="agent-thinking"><i></i><span>正在思考</span></div>
        </div>
        <div class="agent-composer">
          <div class="agent-composer-input">
            <span class="agent-add">${icon('plus', 12)}</span>
            <span class="agent-placeholder">发送消息</span>
            <span class="agent-model">${agentMeta.model} ${icon('chevron-down', 9)}</span>
            <span class="agent-send">${icon('arrow-up-right', 12)}</span>
          </div>
        </div>
      </section>
    </div>
  </div>
`;

const renderClipboardPanel = () => `
  <div class="panel panel-clipboard">
    <div class="panel-head">
      ${icon('clipboard', 13)}<span>剪贴板</span><b>${clipboardMeta.total}</b>
      <span class="head-action">${icon('trash-2', 13)}</span>
    </div>
    <div class="cl-tabs">
      <button type="button" class="cl-tab is-active">全部</button>
      <button type="button" class="cl-tab">${icon('star', 11)}常用</button>
      <button type="button" class="cl-tab">${icon('clock', 11)}非常用</button>
    </div>
    <div class="cl-filters">
      ${clipboardMeta.filters
        .map(
          (filter, i) =>
            `<button type="button" class="cl-filter${i === 0 ? ' is-active' : ''}">${filter.label}${
              filter.label === '全部' ? '' : ` ${filter.count}`
            }</button>`,
        )
        .join('')}
    </div>
    <div class="cl-search">${icon('search', 12)}<span>搜索</span></div>
    <div class="cl-list">
      ${clipboardItems
        .map(
          (item) => `
        <div class="cl-item">
          <span class="cl-thumb cl-thumb-${item.kind}">${
            item.kind === 'image'
              ? icon('image', 14)
              : item.kind === 'code'
                ? icon('code-2', 13)
                : item.kind === 'url'
                  ? icon('link', 13)
                  : icon('file-text', 13)
          }</span>
          <span class="cl-body">
            <span class="cl-title">${item.title}</span>
            <span class="cl-meta">${item.meta}</span>
          </span>
          <span class="cl-actions">
            ${clipboardMeta.actions
              .map(
                (action) =>
                  `<button type="button" class="cl-action">${action}</button>`,
              )
              .join('')}
          </span>
        </div>`,
        )
        .join('')}
    </div>
  </div>
`;

const renderShelfPanel = () => `
  <div class="panel panel-shelf">
    <div class="shelf-rail">
      <button type="button" class="rail-item">${icon('share-2', 13)}<span>共享</span></button>
      <button type="button" class="rail-item is-active">${icon('clipboard-paste', 13)}<span>粘贴</span></button>
    </div>
    <div class="shelf-main">
      <div class="panel-head">
        ${icon('inbox', 13)}<span>中转站</span><b>${shelfMeta.count}</b>
        <button type="button" class="head-button">${icon('clipboard-paste', 11)}粘贴</button>
      </div>
      <div class="cl-filters">
        ${shelfMeta.filters
          .map(
            (label, i) =>
              `<button type="button" class="cl-filter${i === 0 ? ' is-active' : ''}">${label} 0</button>`,
          )
          .join('')}
      </div>
      <div class="cl-search">${icon('search', 12)}<span>搜索文件名</span></div>
      <div class="shelf-items">
        ${shelfMeta.previews
          .map(
            (file) => `
          <div class="shelf-file">
            <span class="shelf-file-thumb">${icon(
              file.kind === 'image' ? 'image' : file.kind === 'archive' ? 'files' : 'file-text',
              18,
            )}</span>
            <span class="shelf-file-name">${file.name}</span>
            <span class="shelf-file-meta">${file.meta}</span>
          </div>`,
          )
          .join('')}
      </div>
    </div>
  </div>
`;

const renderDownloadPanel = () => `
  <div class="panel panel-download">
    <div class="dl-input">
      ${icon('link', 14)}
      <span class="dl-placeholder">${downloadMeta.placeholder}</span>
      <span class="dl-paste">${icon('clipboard-paste', 13)}</span>
    </div>
    <div class="dl-row">
      <div class="dl-modes">
        <button type="button" class="dl-mode is-active">${icon('film', 12)}<span>视频</span></button>
        <button type="button" class="dl-mode">${icon('volume-2', 12)}<span>音频</span></button>
      </div>
      <button type="button" class="dl-folder">${icon('folder', 12)}<span>${downloadMeta.folder}</span>${icon('chevron-down', 10)}</button>
      <button type="button" class="dl-start">${icon('download', 12)}<span>下载</span></button>
    </div>
    <div class="dl-status">
      <span class="dl-state">${icon('info', 12)}${downloadMeta.status}</span>
      <span class="dl-toggle">${icon('check', 11)}${downloadMeta.clipboardToggle}</span>
    </div>
  </div>
`;

const renderAgendaPanel = () => {
  const now = new Date();
  const weekdays = ['日', '一', '二', '三', '四', '五', '六'];
  const days: string[] = [];
  for (let offset = 8; offset >= -5; offset -= 1) {
    const date = new Date(now);
    date.setDate(date.getDate() - offset);
    const isToday = offset === 0;
    days.push(
      `<span class="week-day${isToday ? ' is-today' : ''}"><i>${weekdays[date.getDay()]}</i><b>${date.getDate()}</b></span>`,
    );
  }
  return `
  <div class="panel panel-agenda">
    <div class="agenda-weather">
      <div class="panel-head">${icon('sun', 13)}<span>天气</span><span class="head-action">${icon('refresh-cw', 12)}</span></div>
      ${weatherCities
        .map(
          (city) => `
        <div class="weather-card">
          <div class="weather-top">
            <span class="weather-region">${city.region}</span>
            <span class="weather-condition">${city.icon === 'sun' ? icon('sun', 15) : icon('cloud', 15)}${city.condition}</span>
          </div>
          <div class="weather-temp">${city.temp}</div>
          <div class="weather-detail">
            <span>日出日落 ${city.sun}</span>
            <span>当前降水量 ${city.rain}</span>
            <span>今日湿度 ${city.humidity}</span>
          </div>
        </div>`,
        )
        .join('')}
    </div>
    <div class="agenda-calendar">
      <div class="panel-head">
        ${icon('calendar-days', 13)}<span>日历与待办</span>
        <span class="head-action">${icon('plus', 13)}</span>
        <span class="agenda-date">${now.getMonth() + 1}月${now.getDate()}日</span>
      </div>
      <div class="week-strip">${days.join('')}</div>
      <div class="agenda-empty">
        ${icon('calendar-check', 26)}
        <span>${agendaEmptyText}</span>
      </div>
    </div>
  </div>
`;
};

const renderNotesPanel = () => `
  <div class="panel panel-notes">
    <div class="notes-list">
      <div class="panel-head">
        ${icon('notebook-pen', 13)}<span>随记</span><b>${notesMeta.count}</b>
        <span class="head-action">${icon('refresh-cw', 12)}</span>
        <span class="head-action">${icon('plus', 13)}</span>
      </div>
      <div class="notes-items">
        ${notesMeta.list
          .map(
            (note) => `
          <div class="note-item${note.selected ? ' is-active' : ''}">
            <span class="note-title">${note.title}</span>
            <span class="note-meta">${note.meta}</span>
          </div>`,
          )
          .join('')}
      </div>
    </div>
    <div class="notes-editor">
      <div class="notes-title">
        ${icon('file-text', 13)}<span>${notesMeta.list[0]?.title ?? ''}</span>
        <button type="button" class="notes-size">大小 ${icon('chevron-down', 10)}</button>
      </div>
      <div class="notes-toolbar">
        ${icon('bold', 12)}${icon('italic', 12)}${icon('underline', 12)}${icon('strikethrough', 12)}${icon('smile', 12)}
        <span class="toolbar-gap"></span>
        ${icon('list', 12)}${icon('list-ordered', 12)}${icon('list-checks', 12)}${icon('link-2', 12)}${icon('align-left', 12)}
        <span class="toolbar-gap"></span>
        ${icon('share-2', 12)}
      </div>
      <div class="notes-body">
        <p>${notesMeta.body}</p>
        <p class="notes-more">……</p>
      </div>
      <div class="notes-count">${notesMeta.wordCount}</div>
    </div>
  </div>
`;

const renderMailPanel = () => `
  <div class="panel panel-mail">
    <div class="mail-list">
      <div class="mail-list-head">
        <b>邮件</b><span>${mailMeta.unread}</span>
        <button type="button" title="筛选">${icon('list', 11)}</button>
        <i></i>
        <button type="button" title="发邮件">${icon('pencil', 11)}</button>
        <button type="button" title="刷新">${icon('refresh-cw', 11)}</button>
      </div>
      <div class="mail-account">${mailMeta.account}${icon('chevron-down', 9)}</div>
      <div class="mail-messages">
        ${mailMeta.messages
          .map(
            (message) => `
          <button type="button" class="mail-row${message.selected ? ' is-active' : ''}">
            <span class="mail-row-top">${message.unread ? '<i></i>' : ''}<b>${message.sender}</b><time>${message.time}</time></span>
            <span class="mail-row-title">${message.title}</span>
            <span class="mail-row-preview">${message.preview}</span>
          </button>`,
          )
          .join('')}
      </div>
    </div>
    <div class="mail-detail">
      <div class="mail-detail-head">
        <span>
          <b>${mailMeta.detail.title}</b>
          <small>${mailMeta.detail.sender}</small>
          <small>${mailMeta.account} · ${mailMeta.detail.date}</small>
        </span>
        <button type="button">${icon('arrow-up-right', 11)}回复</button>
        <button type="button" title="其他操作">${icon('menu', 11)}</button>
      </div>
      <div class="mail-detail-body">${mailMeta.detail.body}</div>
    </div>
  </div>
`;

const renderPDFPanel = () => `
  <div class="panel panel-pdf">
    <div class="pdf-rail">
      ${pdfTools
        .map(
          (tool) => `
        ${tool.group ? `<div class="pdf-group">${tool.group}</div>` : ''}
        <button type="button" class="pdf-item${tool.active ? ' is-active' : ''}">
          ${icon(tool.active ? 'files' : 'file-text', 12)}<span>${tool.label}</span>
        </button>`,
        )
        .join('')}
    </div>
    <div class="pdf-main">
      <div class="pdf-title">
        ${icon('scan-text', 15)}<b>${pdfActiveTitle}</b><span>${pdfActiveDesc}</span>
      </div>
      <div class="pdf-drop">
        ${icon('folder', 22)}
        <b>选择多个文件</b>
        <span>尚未选择文件</span>
      </div>
      <div class="pdf-footer">
        <span class="pdf-add">${icon('plus', 13)}</span>
        <span class="pdf-ghost">${icon('image', 13)}</span>
        <span class="pdf-ghost">${icon('share-2', 13)}</span>
        <span class="pdf-spacer"></span>
        <button type="button" class="pdf-run">开始处理</button>
      </div>
    </div>
  </div>
`;

const renderSystemPanel = () => {
  const cpuChart = (() => {
    const width = 260;
    const height = 74;
    const userPts: [number, number][] = [];
    const sysPts: [number, number][] = [];
    for (let i = 0; i <= 24; i += 1) {
      const x = (i * width) / 24;
      const wave = Math.abs(Math.sin(i * 0.7)) * 10 + Math.abs(Math.sin(i * 0.31)) * 6;
      userPts.push([x, height - 10 - wave]);
      sysPts.push([x, height - 6 - wave * 0.4]);
    }
    const userArea = `${smoothPath(userPts)} L ${width},${height} L 0,${height} Z`;
    return `
      <svg viewBox="0 0 ${width} ${height}" class="sys-chart" role="img" aria-label="CPU 占用趋势">
        <path d="${userArea}" fill="#0a84ff" fill-opacity="0.18"/>
        <path d="${smoothPath(userPts)}" stroke="#0a84ff" fill="none" stroke-width="1.5"/>
        <path d="${smoothPath(sysPts)}" stroke="#ff453a" fill="none" stroke-width="1" stroke-opacity="0.7"/>
      </svg>`;
  })();
  const gpuChart = (() => {
    const width = 260;
    const height = 74;
    const mk = (mult: number, phase: number) => {
      const pts: [number, number][] = [];
      for (let i = 0; i <= 24; i += 1) {
        const x = (i * width) / 24;
        const v = (Math.sin(i * 0.5 + phase) * 0.5 + 0.5) * height * 0.62 * mult + 6;
        pts.push([x, height - v]);
      }
      return smoothPath(pts);
    };
    return `
      <svg viewBox="0 0 ${width} ${height}" class="sys-chart" role="img" aria-label="GPU 利用率、温度与功耗曲线">
        <path d="${mk(1, 0)}" stroke="#0a84ff" fill="none" stroke-width="1.5"/>
        <path d="${mk(0.72, 1.7)}" stroke="#ff453a" fill="none" stroke-width="1"/>
        <path d="${mk(0.5, 3.1)}" stroke="#5ac8fa" fill="none" stroke-width="1"/>
      </svg>`;
  })();
  const legend = (items: { label: string; value: string; color: string }[]) =>
    items
      .map(
        (item) =>
          `<span class="sys-legend"><i style="background: ${item.color}"></i>${item.label} ${item.value}</span>`,
      )
      .join('');
  return `
  <div class="panel panel-system">
    <div class="sys-main">
      <div class="sys-card sys-cpu">
        <div class="sys-card-head">
          <b>CPU</b><span>${systemCards.cpu.chip}</span>
          <span class="sys-temp">${systemCards.cpu.temp}</span>
        </div>
        <div class="sys-sub">${systemCards.cpu.cores}</div>
        ${cpuChart}
        <div class="sys-legends">${legend(systemCards.cpu.legend)}</div>
      </div>
      <div class="sys-card sys-gpu">
        <div class="sys-card-head">
          <b>GPU</b><span>${systemCards.gpu.chip}</span>
          <span class="sys-temp">${systemCards.gpu.temp}</span>
        </div>
        <div class="sys-sub">${systemCards.gpu.cores}</div>
        ${gpuChart}
        <div class="sys-legends">${legend(systemCards.gpu.legend)}</div>
      </div>
    </div>
    <div class="sys-side">
      <div class="sys-card">
        <div class="sys-card-head"><b>内存</b><span class="sys-temp">压力 ${systemCards.memory.pressure}</span></div>
        <div class="sys-sub">可用 ${systemCards.memory.available} / 共 ${systemCards.memory.total}</div>
        <div class="sys-bar"><span style="width: 64%; background: #ff9f0a"></span></div>
        <button type="button" class="sys-action">${systemCards.memory.action}</button>
      </div>
      <div class="sys-card">
        <div class="sys-card-head"><b>${systemCards.disk.name}</b>${icon('hard-drive', 12)}</div>
        <div class="sys-sub">可用 ${systemCards.disk.available} / 共 ${systemCards.disk.total}</div>
        <div class="sys-bar"><span style="width: 22%; background: #30d158"></span></div>
        <div class="sys-io">R ${systemCards.disk.read} · W ${systemCards.disk.write}</div>
        <button type="button" class="sys-action">${systemCards.disk.action}</button>
      </div>
      <div class="sys-card sys-fans">
        <div class="sys-card-head"><b>风扇</b>${icon('fan', 12)}</div>
        <div class="fan-vals">
          ${systemCards.fans.map((rpm) => `<span>${rpm}</span>`).join('')}
        </div>
      </div>
      <div class="sys-card">
        <div class="sys-card-head"><b>网络</b>${icon('globe', 12)}<span class="head-action">${icon('refresh-cw', 11)}</span></div>
        <div class="net-vals">
          <span>${icon('download', 11)}${systemCards.network.down}</span>
          <span>${icon('arrow-up-right', 11)}${systemCards.network.up}</span>
        </div>
        <div class="sys-io">内网 ${systemCards.network.lan}</div>
        <div class="sys-io">公网 ${systemCards.network.wan}</div>
      </div>
    </div>
  </div>
`;
};

const renderToolboxPanel = () => `
  <div class="panel panel-toolbox">
    <section class="toolbox-focus">
      <div class="toolbox-mode">${toolboxMeta.mode}</div>
      <div class="toolbox-clock" data-toolbox-clock>${toolboxMeta.clock}</div>
      <div class="toolbox-controls">
        <button type="button" class="is-primary">开始</button>
        <button type="button">重置</button>
      </div>
    </section>
    <section class="toolbox-actions">
      <div class="toolbox-toggles">
        ${toolboxMeta.toggles
          .map(
            (label, index) => `
          <span>${label}<i class="toolbox-switch${index === 0 ? ' is-on' : ''}"><b></b></i></span>`,
          )
          .join('')}
      </div>
      <div class="toolbox-grid">
        ${toolboxMeta.actions
          .map((label, index) => {
            const symbols = ['scan-text', 'settings', 'clock', 'file-text', 'image', 'trash-2'];
            return `<button type="button">${icon(symbols[index], 14)}<span>${label}</span></button>`;
          })
          .join('')}
      </div>
    </section>
  </div>
`;

const renderBatteryPanel = () => `
  <div class="panel panel-battery">
    <section class="battery-local">
      <div class="battery-head">
        <span>${icon('battery-charging', 14)}<b>本机电池</b></span>
        <small>${batteryMeta.status}</small>
        <strong>${batteryMeta.level}%</strong>
      </div>
      <div class="battery-flow">
        <span class="battery-device">${icon('battery-charging', 18)}<b>Mac</b></span>
        <i><b style="width: ${batteryMeta.level}%"></b></i>
        <span class="battery-level"><b>${batteryMeta.level}%</b><small>${batteryMeta.remaining}</small></span>
      </div>
      <div class="battery-metrics">
        ${batteryMeta.metrics
          .map(
            (metric) => `
          <span><small>${metric.label}</small><b>${metric.value}</b></span>`,
          )
          .join('')}
      </div>
    </section>
    <section class="battery-devices">
      <div class="battery-device-head">
        <span>${icon('airplay', 13)}<b>设备电量</b></span>
        <button type="button" title="刷新">${icon('refresh-cw', 11)}</button>
      </div>
      <div class="battery-device-list">
        ${batteryMeta.devices
          .map(
            (device) => `
          <div class="battery-device-row">
            <span class="battery-device-icon">${icon(device.symbol, 17)}</span>
            <span><b>${device.name}</b><small>已连接</small></span>
            <i><b style="width: ${device.level}%"></b></i>
            <strong>${device.level}%</strong>
          </div>`,
          )
          .join('')}
      </div>
    </section>
  </div>
`;

const renderLockScreenPanel = () => {
  const date = new Date();
  const dateText = new Intl.DateTimeFormat('zh-CN', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    weekday: 'short',
  }).format(date);
  return `
  <div class="panel panel-lock-screen">
    <div class="lock-date">
      <b>${dateText}</b>
      <span>${lockScreenMeta.lunar}</span>
    </div>
    <div class="lock-battery">
      ${icon('battery-charging', 14)}
      <span><small>电量</small><b>${batteryMeta.level}% · ${batteryMeta.status}</b></span>
    </div>
    <div class="lock-status">
      <span class="lock-weather">${icon('sun', 15)}<i><small>示例位置</small><b>${lockScreenMeta.weather}</b></i></span>
      <span class="lock-divider"></span>
      <p>${lockScreenMeta.message}</p>
    </div>
  </div>`;
};

const panelRenderers: Record<string, () => string> = {
  dashboard: renderDashboardPanel,
  aiMonitor: renderAIMonitorPanel,
  aiAgent: renderAIAgentPanel,
  clipboard: renderClipboardPanel,
  shelf: renderShelfPanel,
  download: renderDownloadPanel,
  agenda: renderAgendaPanel,
  quickNotes: renderNotesPanel,
  mail: renderMailPanel,
  pdf: renderPDFPanel,
  toolbox: renderToolboxPanel,
  system: renderSystemPanel,
  battery: renderBatteryPanel,
  lockScreen: renderLockScreenPanel,
};

const renderPanels = (ids: string[]) =>
  ids
    .filter((id) => panelRenderers[id])
    .map(
      (id, index) =>
        `<div class="zi-panel${index === 0 ? ' is-active' : ''}" data-panel="${id}">${panelRenderers[id]()}</div>`,
    )
    .join('');

/* ================= 页面区块 ================= */

const now = new Date();
const menuDateFormatter = new Intl.DateTimeFormat('zh-CN', {
  month: 'numeric',
  day: 'numeric',
  weekday: 'short',
});
const menuTimeFormatter = new Intl.DateTimeFormat('zh-CN', {
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});

const showcaseRailMarkup = showcaseGroups
  .map(
    (group) => `
    <div class="rail-group">
      <span class="rail-group-label">${group}</span>
      ${showcaseModules
        .filter((module) => module.group === group)
        .map(
          (module) => `
        <button type="button" class="rail-button" data-target="${module.id}">${module.name}</button>`,
        )
        .join('')}
    </div>`,
  )
  .join('');

const toolMarkup = supportedAITools
  .map((tool) => `<span class="tool-chip"><span class="tool-chip-dot"></span>${tool.name}</span>`)
  .join('');

const docsMarkup = documentationLinks
  .slice(0, 4)
  .map(
    (doc) => `
    <a class="doc-link reveal" href="${doc.url}" target="_blank" rel="noreferrer">
      <span>
        <span class="mono-label">${doc.title}</span>
        <span class="doc-description">${doc.description}</span>
      </span>
      ${icon('arrow-up-right', 16)}
    </a>`,
  )
  .join('');

const faqMarkup = faqItems
  .map(
    (item) => `
    <details class="faq-item reveal">
      <summary>${item.question}${icon('plus', 18)}</summary>
      <div class="faq-answer">${item.answer}</div>
    </details>`,
  )
  .join('');

app.innerHTML = `
  <main>
    <section class="hero" id="top">
      <header class="site-header">
        <a class="brand" href="#top" aria-label="zisla 首页">
          <img class="brand-mark" src="./assets/zisla-icon.png" alt="" />
          <span>zisla <span class="brand-subtitle">/ ${productTagline}</span></span>
        </a>
        <button class="menu-toggle" type="button" aria-label="打开导航菜单" aria-expanded="false" title="打开导航">${icon('menu', 18)}</button>
        <nav class="nav" aria-label="主导航">
          ${navItems.map((item) => `<a class="nav-link" href="${item.href}">${item.label}</a>`).join('')}
          <a class="header-cta" href="#download" aria-label="跳转到下载区域">下载 ${latestRelease.version}${icon('arrow-down-to-line', 14)}</a>
        </nav>
      </header>

      <div class="section-wrap hero-inner">
        <div class="hero-copy">
          <p class="eyebrow">NATIVE MACOS WORKSPACE / ${latestRelease.version}</p>
          <h1 class="hero-title">${heroTitle}</h1>
          <p class="hero-lede">${productDescription}</p>
          <div class="hero-actions">
            <a class="button button-primary" href="${latestRelease.dmg}" download aria-label="下载 zisla ${latestRelease.version} DMG 安装包">${icon('download', 16)}下载 macOS 版</a>
            <a class="button button-ghost" href="${repositoryLinks.github}" target="_blank" rel="noreferrer" aria-label="在 GitHub 上查看 zisla 源代码">${icon('code-2', 15)}查看源码</a>
          </div>
          <ul class="hero-hints">
            ${heroHints.map((hint) => `<li>${icon('check', 13)}<span>${hint}</span></li>`).join('')}
          </ul>
        </div>

        <div class="hero-stage">
          <div class="desktop-window" id="desktopWindow">
            <div class="menubar" aria-hidden="true">
              <span class="menubar-side">
                <span class="menubar-apple"></span>
                <span class="menubar-app">zisla</span>
              </span>
              <span class="menubar-side menubar-right">
                <span class="menubar-icon">${icon('battery-charging', 12)}</span>
                <span class="menubar-icon">${icon('gauge', 12)}</span>
                <span class="menubar-clock" data-menu-date>${menuDateFormatter.format(now)}</span>
                <span class="menubar-clock" data-menu-time>${menuTimeFormatter.format(now)}</span>
              </span>
            </div>
            <div class="desktop-body">
              <div class="island" id="heroIsland" data-state="collapsed">
                <button type="button" class="island-collapsed" data-collapsed aria-label="展开灵动岛">
                  <img class="island-pet" src="./assets/duck.png" alt="" />
                  <img class="island-logo" src="./assets/zisla-icon.png" alt="" />
                  <span class="island-live"><i></i><b>5</b></span>
                </button>
                <div class="island-expanded" data-expanded>
                  ${renderCrown(heroCycleModules[0])}
                  <div class="zi-panels" data-panels>
                    ${renderPanels(heroCycleModules)}
                  </div>
                  <div class="island-caption" data-island-caption>下载</div>
                </div>
              </div>
            </div>
            <div class="desktop-dock" aria-hidden="true">
              ${['grid-2x2', 'inbox', 'clipboard', 'chart-line', 'download', 'calendar-days', 'mail', 'notebook-pen', 'scan-text', 'gauge']
                .map((name, i) => `<span class="dock-icon${i === 0 ? ' is-first' : ''}">${icon(name, 13)}</span>`)
                .join('')}
            </div>
          </div>
          <div class="hero-stage-actions">
            <button type="button" class="demo-replay" id="replayDemo">${icon('refresh-cw', 12)}重播展开演示</button>
          </div>
        </div>
      </div>
    </section>

    <section class="proof-band" aria-label="产品概览">
      <div class="section-wrap proof-grid">
        ${proofItems
          .map(
            (item) =>
              `<div class="proof-item"><strong>${item.title}</strong><span>${item.desc}</span></div>`,
          )
          .join('')}
      </div>
    </section>

    <section class="section" id="showcase">
      <div class="section-wrap">
        <div class="section-heading reveal">
          <div>
            <p class="eyebrow">ONE PLACE / EVERYDAY FLOW</p>
            <h2 class="section-title">常用工作流，<span>都在屏幕顶部。</span></h2>
          </div>
          <p class="section-lede">从 AI 任务到剪贴板、日程与系统状态，zisla 把分散的桌面工作流收进同一个入口。</p>
        </div>
        <div class="showcase reveal">
          <div class="showcase-rail" role="tablist" aria-label="功能模块">${showcaseRailMarkup}</div>
          <div class="showcase-main">
            <div class="showcase-desktop">
              <div class="showcase-menubar" aria-hidden="true">
                <span>zisla</span>
                <span>${icon('battery-charging', 11)}${icon('gauge', 11)}<b>09:41</b></span>
              </div>
              <div class="zi-frame" id="showcaseFrame">
                ${renderCrown(showcaseModules[0]?.id ?? 'shelf')}
                <div class="zi-panels" data-panels>
                  ${renderPanels(showcaseModules.map((module) => module.id))}
                </div>
              </div>
            </div>
            <div class="showcase-caption" id="showcaseCaption">
              <div class="caption-head">
                <span class="mono-label" data-caption-module>MODULE / ${showcaseModules[0]?.name ?? ''}</span>
              </div>
              <p data-caption-text>${showcaseModules[0]?.caption ?? ''}</p>
              <div class="caption-points" data-caption-points>
                ${(showcaseModules[0]?.points ?? [])
                  .map((point) => `<span class="capability-tag">${point}</span>`)
                  .join('')}
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>

    <section class="section dark-section" id="ai">
      <div class="section-wrap signal-layout">
        <div class="signal-panel reveal" aria-label="AI 工作侧边通知">
          <div class="side-notice">
            <div class="sn-head">${icon('sparkles', 13)}AI 工作</div>
            <div class="sn-item">
              <span class="sn-logo sn-gpt">${icon('bot', 14)}</span>
              <span class="sn-body"><b>ChatGPT</b><span>正在运行</span></span>
              <span class="sn-spinner"></span>
            </div>
            <div class="sn-item">
              <span class="sn-logo sn-claude">${icon('sun', 14)}</span>
              <span class="sn-body"><b>Claude</b><span>正在运行</span></span>
              <span class="sn-spinner sn-spinner-orange"></span>
            </div>
            <div class="sn-hint">收起状态下，AI 活动以侧边通知与状态点呈现</div>
          </div>
          <div class="signal-mini">
            <div class="signal-mini-row">
              <span class="mono-label">zislactl update</span>
              <span>把自己的任务接入顶部状态条</span>
            </div>
            <div class="command-box"><code>${developmentSetup.zislactlCommand}</code><button id="copyZislactl" type="button" aria-label="复制 zislactl 命令" title="复制命令">${icon('copy', 15)}</button></div>
          </div>
        </div>
        <div class="signal-copy">
          <p class="eyebrow">AI WITHOUT THE BLACK BOX</p>
          <h2 class="section-title">看见 AI 状态，<span>不读取对话。</span></h2>
          <p>查看任务、状态和 Token 趋势，数据留在本机。</p>
          <div class="tool-list" aria-label="支持的 AI 工具">${toolMarkup}</div>
          <ul class="privacy-list">
            ${privacyPoints
              .map((point) => `<li>${icon('shield', 15)}<span>${point}</span></li>`)
              .join('')}
          </ul>
        </div>
      </div>
    </section>

    <section class="section flow-section" id="how-it-works">
      <div class="section-wrap">
        <div class="section-heading reveal">
          <div>
            <p class="eyebrow">THE RHYTHM</p>
            <h2 class="section-title">移到顶部，<span>查看，然后收起。</span></h2>
          </div>
          <p class="section-lede">不抢焦点，查看后自动收起。</p>
        </div>
        <div class="flow-grid">
          ${flowSteps
            .map(
              (step) => `
          <article class="flow-step reveal">
            <span class="flow-step-number">${step.step}</span>
            <h3>${step.title}</h3>
            <p>${step.desc}</p>
          </article>`,
            )
            .join('')}
        </div>
      </div>
    </section>

    <section class="download-section" id="download">
      <div class="section-wrap download-layout">
        <div>
          <p class="eyebrow">READY WHEN YOU ARE</p>
          <h2 class="download-title">立即下载 zisla</h2>
          <p class="download-copy">${latestRelease.version} · macOS Universal · DMG / ZIP</p>
          <div class="download-actions">
            <a class="button button-light" href="${latestRelease.dmg}" download aria-label="下载 zisla ${latestRelease.version} DMG 安装包">${icon('download', 16)}下载 DMG</a>
            <a class="button button-ghost-dark" href="${latestRelease.zip}" download aria-label="下载 zisla ${latestRelease.version} ZIP 压缩包">下载 ZIP</a>
            <a class="button button-ghost-dark" href="${latestRelease.releasePage}" target="_blank" rel="noreferrer" aria-label="在 GitHub 上查看 ${latestRelease.version} 发布详情">${icon('external-link', 16)}查看 Release</a>
          </div>
        </div>
        <dl class="download-notes">
          <div class="download-note"><dt>系统</dt><dd>${systemRequirements.os} · ${systemRequirements.platform}</dd></div>
          <div class="download-note"><dt>安装</dt><dd>挂载 DMG 后拖入 Applications</dd></div>
          <div class="download-note"><dt>包体</dt><dd>Universal · DMG / ZIP</dd></div>
          <div class="download-note"><dt>镜像</dt><dd><a href="${downloadLinks[1]?.url ?? repositoryLinks.gitee + '/releases'}" target="_blank" rel="noreferrer">Gitee Releases</a></dd></div>
        </dl>
      </div>
    </section>

    <section class="section faq-section" id="faq">
      <div class="section-wrap">
        <div class="section-heading reveal">
          <div>
            <p class="eyebrow">A FEW CLEAR ANSWERS</p>
            <h2 class="section-title">常见问题。</h2>
          </div>
          <p class="section-lede">权限、隐私和兼容性说明。</p>
        </div>
        <div class="faq-list">${faqMarkup}</div>
      </div>
    </section>

    <section class="section developers-section" id="developers">
      <div class="section-wrap">
        <div class="section-heading reveal">
          <div>
            <p class="eyebrow">OPEN BY DEFAULT</p>
            <h2 class="section-title">开发者资源。</h2>
          </div>
          <p class="section-lede">MIT License，可直接使用或从源码构建。</p>
        </div>
        <div class="docs-grid">${docsMarkup}</div>
        <div class="docs-detail reveal">
          <div>
            <span class="mono-label">QUICK START / SOURCE</span>
            <h3>从源码运行，或接入你自己的任务。</h3>
            <div class="command-box"><code>${developmentSetup.runCommand}</code><button id="copyCommand" type="button" aria-label="复制源码运行命令" title="复制命令">${icon('copy', 15)}</button></div>
            <div class="developer-actions">
              <a href="${repositoryLinks.github}" target="_blank" rel="noreferrer">${icon('code-2', 14)}GitHub 仓库</a>
              <a href="${repositoryLinks.gitee}" target="_blank" rel="noreferrer">${icon('code-2', 14)}Gitee 仓库</a>
              <a href="${latestRelease.checksum}" target="_blank" rel="noreferrer">${icon('check', 14)}SHA-256</a>
            </div>
          </div>
          <ul class="performance-list">${performanceFeatures.map((item) => `<li>${icon('check', 14)}<span>${item}</span></li>`).join('')}</ul>
        </div>
      </div>
    </section>
  </main>

  <footer class="site-footer">
    <div class="section-wrap">
      <div class="footer-top">
        <a class="brand" href="#top" aria-label="回到 zisla 首页"><img class="brand-mark" src="./assets/zisla-icon.png" alt="" /><span>zisla</span></a>
        <div class="footer-links">
          <a href="${repositoryLinks.github}" target="_blank" rel="noreferrer">GitHub</a>
          <a href="${repositoryLinks.gitee}" target="_blank" rel="noreferrer">Gitee</a>
          <a href="${latestRelease.previewPage}" target="_blank" rel="noreferrer">Preview channel</a>
          <a href="${documentationLinks[4]?.url ?? repositoryLinks.github}" target="_blank" rel="noreferrer">贡献指南</a>
        </div>
      </div>
      <div class="footer-bottom"><span>开源、原生、把控制权留在你手里。</span><span class="footer-meta">${license} · ${latestRelease.version} · macOS</span></div>
    </div>
  </footer>

  <div class="toast" id="toast" role="status" aria-live="polite"></div>
`;

createIcons({ icons: siteIcons });

/* ================= 交互逻辑 ================= */

const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/* 菜单栏时钟 */
const updateMenuClocks = () => {
  const current = new Date();
  const dateText = menuDateFormatter.format(current);
  const timeText = menuTimeFormatter.format(current);
  document.querySelectorAll<HTMLElement>('[data-menu-date]').forEach((el) => {
    el.textContent = dateText;
  });
  document.querySelectorAll<HTMLElement>('[data-menu-time]').forEach((el) => {
    el.textContent = timeText;
  });
};
updateMenuClocks();
window.setInterval(updateMenuClocks, 30_000);

/* 正在播放进度 */
let mediaSeconds = nowPlaying.currentSeconds;
const tickMedia = () => {
  if (document.hidden) return;
  mediaSeconds = (mediaSeconds + 1) % nowPlaying.durationSeconds;
  const ratio = (mediaSeconds / nowPlaying.durationSeconds).toFixed(3);
  document.querySelectorAll<HTMLElement>('[data-np-time]').forEach((el) => {
    el.textContent = formatClock(mediaSeconds);
  });
  document.querySelectorAll<HTMLElement>('[data-np-fill]').forEach((el) => {
    el.style.transform = `scaleX(${ratio})`;
  });
};
window.setInterval(tickMedia, 1000);

/* AI 任务运行时长 */
const tickElapsed = () => {
  if (document.hidden) return;
  document.querySelectorAll<HTMLElement>('[data-elapsed]').forEach((el) => {
    const next = Number(el.getAttribute('data-elapsed')) + 1;
    el.setAttribute('data-elapsed', String(next));
    const label = el.querySelector('.elapsed');
    if (label) label.textContent = formatElapsed(next);
  });
};
window.setInterval(tickElapsed, 1000);

/* 灵动岛：收起 → 展开 */
const heroIsland = document.querySelector<HTMLElement>('#heroIsland');
const expandIsland = () => heroIsland?.setAttribute('data-state', 'expanded');
const collapseIsland = () => heroIsland?.setAttribute('data-state', 'collapsed');

document.querySelector('[data-collapsed]')?.addEventListener('click', expandIsland);

if (!prefersReducedMotion) {
  window.setTimeout(expandIsland, 1300);
} else {
  expandIsland();
}

document.querySelector('#replayDemo')?.addEventListener('click', () => {
  collapseIsland();
  window.setTimeout(expandIsland, prefersReducedMotion ? 150 : 850);
});

/* 英雄区模块自动轮播 */
const heroPanels = document.querySelectorAll('#heroIsland [data-panel]');
const heroCaption = document.querySelector<HTMLElement>('[data-island-caption]');
const heroTools = document.querySelectorAll('#heroIsland [data-tool]');
let heroIndex = 0;
let heroTimer: number | undefined;
let heroInView = true;

const moduleName = (id: string) => islandModules.find((m) => m.id === id)?.name ?? id;

const setHeroModule = (id: string) => {
  heroPanels.forEach((panel) => {
    panel.classList.toggle('is-active', panel.getAttribute('data-panel') === id);
  });
  heroTools.forEach((tool) => {
    tool.classList.toggle('is-active', tool.getAttribute('data-tool') === id);
  });
  if (heroCaption) heroCaption.textContent = moduleName(id);
};

const startHeroCycle = () => {
  if (heroTimer) window.clearInterval(heroTimer);
  heroTimer = undefined;
  if (prefersReducedMotion || document.hidden || !heroInView) return;
  heroTimer = window.setInterval(() => {
    heroIndex = (heroIndex + 1) % heroCycleModules.length;
    setHeroModule(heroCycleModules[heroIndex]);
  }, 4200);
};

const stopHeroCycle = () => {
  if (heroTimer) window.clearInterval(heroTimer);
  heroTimer = undefined;
};

const syncHeroCycle = () => {
  if (prefersReducedMotion || document.hidden || !heroInView) {
    stopHeroCycle();
    return;
  }
  startHeroCycle();
};

heroTools.forEach((tool) => {
  tool.addEventListener('click', () => {
    const id = tool.getAttribute('data-tool');
    if (!id || !heroCycleModules.includes(id)) return;
    heroIndex = heroCycleModules.indexOf(id);
    setHeroModule(id);
    syncHeroCycle();
  });
});

setHeroModule(heroCycleModules[0]);

const heroSection = document.querySelector<HTMLElement>('.hero');
if (heroSection) {
  new IntersectionObserver(
    ([entry]) => {
      heroInView = entry?.isIntersecting ?? false;
      syncHeroCycle();
    },
    { threshold: 0.08 },
  ).observe(heroSection);
} else {
  syncHeroCycle();
}

const motionSurfaces = document.querySelectorAll<HTMLElement>(
  '.desktop-window, .zi-frame, .signal-panel',
);
const motionObserver = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      entry.target.classList.toggle('motion-paused', !entry.isIntersecting);
    });
  },
  { rootMargin: '120px 0px', threshold: 0.01 },
);
motionSurfaces.forEach((surface) => motionObserver.observe(surface));

const syncPageMotion = () => {
  document.documentElement.classList.toggle('page-hidden', document.hidden);
  syncHeroCycle();
};
document.addEventListener('visibilitychange', syncPageMotion);
syncPageMotion();

/* 展示区：模块切换 */
const showcasePanels = document.querySelectorAll('#showcaseFrame [data-panel]');
const showcaseTools = document.querySelectorAll('#showcaseFrame [data-tool]');
const railButtons = document.querySelectorAll('.rail-button');
const captionModule = document.querySelector<HTMLElement>('[data-caption-module]');
const captionText = document.querySelector<HTMLElement>('[data-caption-text]');
const captionPoints = document.querySelector<HTMLElement>('[data-caption-points]');

const setShowcaseModule = (id: string) => {
  const meta = showcaseModules.find((module) => module.id === id);
  if (!meta) return;
  showcasePanels.forEach((panel) => {
    panel.classList.toggle('is-active', panel.getAttribute('data-panel') === id);
  });
  showcaseTools.forEach((tool) => {
    tool.classList.toggle('is-active', tool.getAttribute('data-tool') === id);
  });
  railButtons.forEach((button) => {
    button.classList.toggle('is-active', button.getAttribute('data-target') === id);
  });
  if (captionModule) captionModule.textContent = `MODULE / ${meta.name}`;
  if (captionText) captionText.textContent = meta.caption;
  if (captionPoints) {
    captionPoints.innerHTML = meta.points
      .map((point) => `<span class="capability-tag">${point}</span>`)
      .join('');
  }
};

railButtons.forEach((button) => {
  button.addEventListener('click', () => {
    setShowcaseModule(button.getAttribute('data-target') ?? '');
  });
});

showcaseTools.forEach((tool) => {
  tool.addEventListener('click', () => {
    setShowcaseModule(tool.getAttribute('data-tool') ?? '');
  });
});

setShowcaseModule(showcaseModules[0]?.id ?? 'shelf');

/* 导航菜单 */
const menuToggle = document.querySelector<HTMLButtonElement>('.menu-toggle');
const nav = document.querySelector<HTMLElement>('.nav');

menuToggle?.addEventListener('click', () => {
  const isOpen = nav?.classList.toggle('is-open') ?? false;
  document.body.classList.toggle('is-locked', isOpen);
  menuToggle.setAttribute('aria-expanded', String(isOpen));
  menuToggle.setAttribute('aria-label', isOpen ? '关闭导航' : '打开导航');
  menuToggle.innerHTML = icon(isOpen ? 'x' : 'menu', 18);
  createIcons({ icons: siteIcons });
});

nav?.querySelectorAll('a').forEach((link) => {
  link.addEventListener('click', () => {
    nav.classList.remove('is-open');
    document.body.classList.remove('is-locked');
    menuToggle?.setAttribute('aria-expanded', 'false');
    if (menuToggle) {
      menuToggle.setAttribute('aria-label', '打开导航');
      menuToggle.innerHTML = icon('menu', 18);
      createIcons({ icons: siteIcons });
    }
  });
});

/* 复制命令与提示 */
const toast = document.querySelector<HTMLElement>('#toast');
let toastTimer: number | undefined;

const showToast = (message: string) => {
  if (!toast) return;
  toast.textContent = message;
  toast.classList.add('is-visible');
  if (toastTimer) window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => toast.classList.remove('is-visible'), 2400);
};

const copyText = async (text: string, message: string) => {
  try {
    await navigator.clipboard.writeText(text);
    showToast(message);
  } catch {
    const input = document.createElement('textarea');
    input.value = text;
    input.setAttribute('readonly', 'true');
    input.style.position = 'fixed';
    input.style.opacity = '0';
    document.body.append(input);
    input.select();
    document.execCommand('copy');
    input.remove();
    showToast(message);
  }
};

document
  .querySelector('#copyCommand')
  ?.addEventListener('click', () => copyText(developmentSetup.runCommand, '源码运行命令已复制'));
document
  .querySelector('#copyZislactl')
  ?.addEventListener('click', () => copyText(developmentSetup.zislactlCommand, 'zislactl 命令已复制'));

/* 滚动进度条 */
const progressBar = document.createElement('div');
progressBar.className = 'scroll-progress';
document.body.append(progressBar);

/* 滚动浮现 */
const revealItems = document.querySelectorAll('.reveal');
if (!prefersReducedMotion) {
  const revealObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('visible');
          revealObserver.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.08, rootMargin: '0px 0px -60px 0px' },
  );
  document.documentElement.classList.add('reveal-ready');
  revealItems.forEach((el) => revealObserver.observe(el));
}

/* 平滑滚动 */
document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
  anchor.addEventListener('click', (event) => {
    const href = anchor.getAttribute('href');
    if (!href || href === '#') return;
    const target = document.getElementById(href.substring(1));
    if (!target) return;
    event.preventDefault();
    const y = target.getBoundingClientRect().top + window.pageYOffset - 76;
    window.scrollTo({ top: y, behavior: prefersReducedMotion ? 'auto' : 'smooth' });
  });
});
