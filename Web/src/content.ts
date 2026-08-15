export interface NavItem {
  label: string;
  href: string;
}

export interface DownloadLink {
  platform: string;
  url: string;
  label: string;
}

export interface FAQItem {
  question: string;
  answer: string;
}

export const navItems: NavItem[] = [
  { label: '功能', href: '#showcase' },
  { label: 'AI 工作流', href: '#ai' },
  { label: '下载', href: '#download' },
  { label: 'FAQ', href: '#faq' },
  { label: '开发者', href: '#developers' },
];

export const productTitle = 'zisla';
export const productTagline = '原生 macOS 动态工作空间';
export const productDescription =
  '把 AI 进度、媒体、文件和日程放到屏幕顶部，需要时展开，移开后收起。';

export const heroTitle = '把正在发生的事，放到你<em>看得见</em>的地方。';
export const heroHints = [
  '鼠标移到屏幕顶部中央即可展开',
  '移开后自动收起，不抢当前应用焦点',
  '无刘海显示器同样可用',
];

export const proofItems = [
  { title: '14 个功能模块', desc: '媒体、文件、AI、日程与系统工具按需开启' },
  { title: 'macOS 14+', desc: '原生 Swift / AppKit / SwiftUI 实现' },
  { title: '多显示器', desc: '刘海屏与外接屏都能使用' },
  { title: '本地优先', desc: 'AI 状态不读取对话正文' },
];

/* ===== 真实灵动岛：模块工具栏（与 mac/Sources/Zisla/AppModel.swift 的 IslandModule 一致） ===== */

export interface IslandModuleMeta {
  id: string;
  name: string;
  icon: string;
}

export const islandModules: IslandModuleMeta[] = [
  { id: 'dashboard', name: '首页', icon: 'grid-2x2' },
  { id: 'shelf', name: '中转', icon: 'inbox' },
  { id: 'clipboard', name: '剪贴板', icon: 'clipboard' },
  { id: 'aiMonitor', name: 'AI 监控', icon: 'chart-line' },
  { id: 'aiAgent', name: 'AI Agent', icon: 'sparkles' },
  { id: 'download', name: '下载', icon: 'download' },
  { id: 'agenda', name: '日程', icon: 'calendar-days' },
  { id: 'mail', name: '邮件', icon: 'mail' },
  { id: 'quickNotes', name: '随记', icon: 'notebook-pen' },
  { id: 'pdf', name: 'PDF', icon: 'scan-text' },
  { id: 'toolbox', name: '小工具', icon: 'wrench' },
  { id: 'system', name: '系统', icon: 'gauge' },
  { id: 'battery', name: '电池', icon: 'battery-charging' },
  { id: 'lockScreen', name: '锁屏', icon: 'lock' },
];

export const heroCycleModules = [
  'download',
  'aiMonitor',
  'clipboard',
  'agenda',
  'quickNotes',
  'pdf',
  'system',
  'mail',
  'shelf',
];

/* ===== 正在播放（真实界面数据） ===== */

export const nowPlaying = {
  title: '刻在我心底的名字',
  artist: '卢广仲',
  subtitle: '歌词即将开始',
  currentSeconds: 12,
  durationSeconds: 326,
};

export const islandUptime = '开机时间：2天22小时41分钟';

export const islandMetrics = [
  { label: 'CPU', value: 50, tone: 'normal' as const },
  { label: 'GPU', value: 59, tone: 'normal' as const },
  { label: 'RAM', value: 63, tone: 'normal' as const },
  { label: 'Disk', value: 22, tone: 'good' as const },
];

/* ===== AI 监控模块（真实界面数据） ===== */

export interface AITaskRow {
  name: string;
  provider: 'GPT' | 'CLAUDE' | 'CODEX' | 'GEMINI' | 'QWEN' | 'KIMI';
  detail: string;
  effort: string;
  meta: string;
  elapsedSeconds: number;
  status: 'spinner' | 'dot';
}

// Provider 色值来自 mac 端 DesignSystem.swift 的 ProviderBrand.color(for:)
export const providerColors: Record<AITaskRow['provider'], string> = {
  GPT: '#6bd1b8',
  CLAUDE: '#f27a57',
  CODEX: '#5ce6a8',
  GEMINI: '#80adff',
  QWEN: '#7a9eff',
  KIMI: '#4ac2bd',
};

export const aiTasks: AITaskRow[] = [
  {
    name: '重构灵动岛布局引擎',
    provider: 'CLAUDE',
    detail: 'zisla/mac · IslandRootView',
    effort: 'high',
    meta: '2026-08-15 08:31 · PID 20416',
    elapsedSeconds: 60,
    status: 'spinner',
  },
  {
    name: '修复剪贴板过滤失效',
    provider: 'GPT',
    detail: 'zisla/mac · ClipboardHistoryModuleView',
    effort: 'max',
    meta: '2026-08-15 08:24 · PID 19872',
    elapsedSeconds: 459,
    status: 'dot',
  },
  {
    name: '官网模块展示页重排',
    provider: 'CODEX',
    detail: 'zisla/Web · showcase gallery',
    effort: 'high',
    meta: '2026-08-15 08:28 · PID 21749',
    elapsedSeconds: 226,
    status: 'spinner',
  },
  {
    name: '下载器队列稳定性回归',
    provider: 'GEMINI',
    detail: 'zisla/mac · DownloadModuleView',
    effort: 'medium',
    meta: '2026-08-15 08:27 · PID 20115',
    elapsedSeconds: 235,
    status: 'dot',
  },
  {
    name: '生成 v0.1.2 发布说明',
    provider: 'QWEN',
    detail: 'zisla · release notes',
    effort: 'low',
    meta: '2026-08-15 08:17 · PID 19230',
    elapsedSeconds: 873,
    status: 'spinner',
  },
];

export const tokenTrend = {
  yLabels: ['1M', '10M', '100M', '1B'],
  xLabels: ['08/09', '08/10', '08/11', '08/12', '08/13', '08/14', '08/15'],
  // 对数刻度下的归一化值（1M=0.05, 1B=1.0），呈上升趋势
  points: [0.08, 0.14, 0.12, 0.28, 0.42, 0.66, 0.94],
  lastValue: '947M',
};

/* ===== 剪贴板模块（真实界面数据） ===== */

export const clipboardMeta = {
  total: 641,
  tabs: ['全部', '常用', '非常用'],
  filters: [
    { label: '全部', count: 641 },
    { label: '文件夹', count: 0 },
    { label: '图片', count: 138 },
    { label: 'URL', count: 16 },
    { label: '视频', count: 0 },
    { label: '文档', count: 487 },
    { label: '压缩包', count: 0 },
    { label: '代码', count: 0 },
    { label: '其他', count: 0 },
  ],
  actions: ['随记', 'AI', '常用', '删除'],
};

export const clipboardItems = [
  { kind: 'image' as const, title: '图片', meta: 'PNG · 484.0 KB' },
  {
    kind: 'code' as const,
    title: 'swift build -c release --package-path mac',
    meta: '代码',
  },
  {
    kind: 'url' as const,
    title: 'https://github.com/wzz6423/zisla/releases',
    meta: 'URL',
  },
  {
    kind: 'text' as const,
    title: '灵动岛展开时不能激活或抢走当前应用焦点',
    meta: '文本',
  },
];

/* ===== 中转站模块（真实界面数据） ===== */

export const shelfMeta = {
  count: 0,
  filters: ['全部', '文件夹', '图片', '视频', '音频', '文档', '压缩包', '代码', '其他'],
  previews: [
    { name: 'image.png', meta: 'PNG · 484.0 KB' },
    { name: 'image.png', meta: 'PNG · 462.5 KB' },
  ],
};

/* ===== 下载模块（真实界面数据） ===== */

export const downloadMeta = {
  placeholder: '视频或音频链接',
  folder: '下载',
  status: '准备就绪',
  clipboardToggle: '剪贴板检测已开启',
};

/* ===== 日程模块（真实界面数据） ===== */

export const weatherCities = [
  {
    region: '陕西省西安市',
    icon: 'sun',
    condition: '晴 · 体感 28°',
    temp: '23°',
    sun: '06:05 / 19:32',
    rain: '0.0mm',
    humidity: '2% / 0.0mm',
  },
  {
    region: '甘肃省兰州市',
    icon: 'cloud',
    condition: '阴 · 体感 21°',
    temp: '23°',
    sun: '06:33 / 20:00',
    rain: '0.0mm',
    humidity: '94% / 1.7mm',
  },
];

export const agendaEmptyText = '当天暂无事项';

/* ===== 随记模块（真实界面数据） ===== */

export const notesMeta = {
  count: 5,
  wordCount: '316字',
  list: [
    { title: '朋友，看这里。', meta: '内置说明', selected: true },
    { title: '随记', meta: '14小时前' },
    { title: 'To Do', meta: '5月18日' },
    { title: '随笔', meta: '3月31日' },
    { title: '随记', meta: '11月16日' },
    { title: '随记', meta: '11月2日' },
  ],
  body:
    '从现在开始，你可以在记事本中写记事了。随时随地在记事本写上一笔，并设置日历提醒，事情不再错过。读书感悟、生活体验、团队计划等等，你都可以放进记事本里。',
};

/* ===== 邮件模块（真实界面数据） ===== */

export const mailMeta = {
  errorTitle: '无法读取邮件',
  errorBody:
    '无法访问 Mail 的本地邮件索引。请在「系统设置 → 隐私与安全性 → 完全磁盘访问」中允许 zisla，然后重新读取。',
  actions: ['重新读取', '授权磁盘访问'],
  emptyText: '选择一封邮件',
};

/* ===== PDF 工具模块（真实界面数据） ===== */

export const pdfTools = [
  { label: '合并 PDF', active: true },
  { label: '拆分页面' },
  { label: '旋转页面' },
  { label: '图片转 PDF' },
  { label: 'Office 转 PDF' },
  { label: 'PDF 转图片' },
  { label: '导出文字' },
  { label: '文字水印', group: '格式' },
  { label: '图片水印' },
  { label: '添加页码' },
  { label: '裁剪页面' },
  { label: '加密 PDF' },
  { label: '解除密码' },
];

export const pdfActiveTitle = '合并 PDF';
export const pdfActiveDesc = '按选择顺序合并多个 PDF';

/* ===== 系统状态模块（真实界面数据） ===== */

export const systemCards = {
  cpu: {
    chip: 'Apple M5 Pro',
    temp: '76.2°C',
    cores: '15核 · 5性能 · 10能效',
    legend: [
      { label: '用户', value: '0%', color: '#0a84ff' },
      { label: '系统', value: '0%', color: '#ff453a' },
      { label: '闲置', value: '100%', color: '#e8e8ed' },
    ],
  },
  gpu: {
    chip: 'Apple M5 Pro',
    temp: '68.1°C',
    cores: '16核',
    legend: [
      { label: '利用率', value: '45%', color: '#0a84ff' },
      { label: '温度', value: '45%', color: '#ff453a' },
      { label: '功耗', value: '39%', color: '#5ac8fa' },
    ],
  },
  memory: {
    pressure: '64%',
    available: '16.8 GB',
    total: '48.0 GB',
    action: '释放',
  },
  disk: {
    name: 'Macintosh HD',
    available: '774.59 GB',
    total: '994.61 GB',
    read: '0 KB/s',
    write: '0 KB/s',
    action: '清理',
  },
  fans: ['4,641 RPM', '5,016 RPM'],
  network: {
    down: '40 KB/s',
    up: '10 KB/s',
    lan: '192.168.31.214',
    wan: '1.88.167.67',
  },
};

/* ===== 功能展示区（每个模块对应真实功能说明） ===== */

export interface ShowcaseModule {
  id: string;
  name: string;
  group: string;
  caption: string;
  points: string[];
}

export const showcaseGroups = ['顶部工作流', 'AI 工作流', '日常信息', '实用工具'];

export const showcaseModules: ShowcaseModule[] = [
  {
    id: 'shelf',
    name: '中转站',
    group: '顶部工作流',
    caption:
      '将文件、音视频或链接拖到屏幕顶部触发带，放入中转站、在 Finder 中定位，或调用 macOS 系统共享菜单。',
    points: ['拖到顶部即中转', 'Finder 中定位', '系统共享菜单'],
  },
  {
    id: 'clipboard',
    name: '剪贴板',
    group: '顶部工作流',
    caption:
      '可选记录剪贴板历史，并按图片、URL 与文件类型筛选；链接检测默认关闭，开启后仅在本机识别新链接并提示。',
    points: ['按类型筛选', '常用标记', '链接检测默认关闭'],
  },
  {
    id: 'aiMonitor',
    name: 'AI 监控',
    group: 'AI 工作流',
    caption:
      '自动识别受支持的 AI CLI 与桌面工具，展示任务列表、状态、实时 Token 趋势和贡献热力图；只解析结构化事件，不读取对话正文。',
    points: ['多工具任务聚合', 'Token 消耗趋势', '不读取提示词与回答'],
  },
  {
    id: 'download',
    name: '下载器',
    group: '实用工具',
    caption:
      '粘贴链接后使用 yt-dlp 下载到默认或自选目录；没有 ffmpeg 时可使用 AVFoundation 原生封装兼容的音视频轨。',
    points: ['视频 / 音频两种模式', '自选下载目录', '剪贴板检测可选'],
  },
  {
    id: 'agenda',
    name: '日程与天气',
    group: '日常信息',
    caption:
      '展示当前位置与最多 6 个自选地点的天气；查看、新增和删除日历事件及提醒事项，并可将提醒标记完成。',
    points: ['多地天气卡片', '日历与待办管理', '提醒一键完成'],
  },
  {
    id: 'mail',
    name: '邮件',
    group: '日常信息',
    caption:
      '读取已启用的 Mail.app 账户，在岛内查看收件箱、标记已读、回复、撰写新邮件和移入废纸篓；权限不足时给出明确的授权指引。',
    points: ['Mail.app 账户', '岛内回复与撰写', '权限指引透明'],
  },
  {
    id: 'quickNotes',
    name: '随记',
    group: '日常信息',
    caption:
      '以系统「备忘录」为数据源，支持查看、编辑、新建和删除笔记，以及 Markdown 实时预览；草稿会自动写回备忘录。',
    points: ['数据来自备忘录', 'Markdown 编辑器', '草稿自动写回'],
  },
  {
    id: 'pdf',
    name: 'PDF 工具',
    group: '实用工具',
    caption:
      '在本机完成 PDF 合并、拆分、旋转、裁剪、图片/Office 转换、渲染为图片、加水印、页码、加密和元数据编辑。',
    points: ['13 种本机工具', '按顺序合并', '全程不出本机'],
  },
  {
    id: 'system',
    name: '系统状态',
    group: '实用工具',
    caption:
      '查看 CPU、GPU、内存、磁盘、网络和风扇等状态，并清理可安全删除的缓存与日志。',
    points: ['芯片级监控', '一键清理缓存', '风扇与网络详情'],
  },
];

/* ===== AI 深入区 ===== */

// 与 mac/Sources/ZislaCore/AIModels.swift 的 AIProvider 枚举一一对应
export const supportedAITools = [
  { name: 'Claude Code' },
  { name: 'Codex' },
  { name: 'ChatGPT' },
  { name: 'Gemini' },
  { name: 'Grok' },
  { name: 'GitHub Copilot' },
  { name: 'Kimi Code' },
  { name: 'Qwen Code' },
  { name: 'Qoder' },
  { name: 'TRAE' },
  { name: 'OpenCode' },
  { name: 'Harnext' },
  { name: '豆包' },
];

export const privacyPoints = [
  '只解析结构化事件中的事件类型、状态、时间、模型和会话 ID',
  '不读取提示词或回答正文',
  '协议与状态均保存在本机',
];

export const flowSteps = [
  {
    step: '01 / 触发',
    title: '移到屏幕顶部中央',
    desc: '刘海屏和外接屏使用同样的触发方式；隐藏时不运行帧循环。',
  },
  {
    step: '02 / 查看',
    title: '看一眼当前状态',
    desc: '媒体、文件、AI、日程和系统工具集中在同一位置。',
  },
  {
    step: '03 / 收起',
    title: '继续手上的工作',
    desc: '移开鼠标后自动收起，展开时不会激活或抢走当前应用焦点。',
  },
];

/* ===== 下载与系统要求 ===== */

export const systemRequirements = {
  os: 'macOS 14 或更高版本',
  platform: '当前受支持配置为 Apple 芯片 Mac',
  note: 'Intel 机型可能存在可用的发布包，但不保证兼容性。macOS 14 以下版本不受支持。',
};

export const downloadLinks: DownloadLink[] = [
  {
    platform: 'GitHub',
    url: 'https://github.com/wzz6423/zisla/releases',
    label: 'GitHub Releases',
  },
  {
    platform: 'Gitee',
    url: 'https://gitee.com/wzz6423/zisla/releases',
    label: 'Gitee Releases',
  },
];

export const latestRelease = {
  version: 'v0.1.2',
  channel: 'Release',
  releasePage: 'https://github.com/wzz6423/zisla/releases/tag/release/v0.1.2',
  dmg: 'https://github.com/wzz6423/zisla/releases/download/release/v0.1.2/zisla-v0.1.2-macOS-universal.dmg',
  zip: 'https://github.com/wzz6423/zisla/releases/download/release/v0.1.2/zisla-v0.1.2-macOS-universal.zip',
  checksum: 'https://github.com/wzz6423/zisla/releases/download/release/v0.1.2/zisla-v0.1.2-macOS-universal.zip.sha256',
  previewPage: 'https://github.com/wzz6423/zisla/releases/tag/preview',
};

/* ===== 开发者 ===== */

export const developmentSetup = {
  requirements: ['Swift 6 / Xcode 16+', 'macOS 14+', '可选：yt-dlp、ffmpeg'],
  runCommand: 'cd mac && swift run zisla',
  zislactlCommand:
    'zislactl update --id build --provider coder --title 打包发布 --progress 62',
};

export const performanceFeatures = [
  '支持多显示器、Spaces 和普通全屏应用；展开时不会激活或抢走当前应用焦点',
  '隐藏时不创建常驻透明热区窗口，也不运行帧循环；通过全局事件监听与几何判断触发展开',
  '使用单层系统材质；系统开启“降低透明度”后会自动使用实体背景',
  '物理刘海通过系统安全区域推断；无刘海的外接显示器使用自有覆盖层模拟状态条',
];

export const faqItems: FAQItem[] = [
  {
    question: 'zisla 适合哪些用户？',
    answer: '适合希望集中查看 AI、媒体、文件和日程的 Mac 用户；无刘海显示器也支持。',
  },
  {
    question: 'zisla 会读取我的 AI 对话内容吗？',
    answer: '不会。AI 状态监控只读取任务状态，不读取提示词或回答正文。',
  },
  {
    question: 'zisla 需要哪些系统权限？',
    answer: '仅在启用相关功能时请求权限，并可随时在设置中撤销。',
  },
  {
    question: 'zisla 会联网吗？',
    answer: '天气、更新和主动下载会联网；剪贴板链接检测默认关闭。',
  },
  {
    question: 'zisla 支持多显示器吗？',
    answer: '支持多显示器、Spaces 和普通全屏应用，展开时不抢焦点。',
  },
  {
    question: 'Intel Mac 可以使用吗？',
    answer: 'Intel 机型可能存在可用的发布包，但不保证兼容性。当前受支持配置为 Apple 芯片 Mac。',
  },
  {
    question: 'zisla 的数据存储在哪里？',
    answer: '本地数据位于 ~/Library/Application Support/zisla/；随记使用系统「备忘录」。',
  },
];

export const documentationLinks = [
  {
    title: 'macOS 开发指南',
    url: 'https://github.com/wzz6423/zisla/blob/main/mac/README.md',
    description: '功能、构建、测试与系统限制',
  },
  {
    title: '架构与性能设计',
    url: 'https://github.com/wzz6423/zisla/blob/main/mac/Docs/architecture.md',
    description: '顶部触发、窗口和性能设计',
  },
  {
    title: 'CLI 接入设计',
    url: 'https://github.com/wzz6423/zisla/blob/main/mac/Docs/cli-reference.md',
    description: 'zislactl 命令与字段',
  },
  {
    title: '签名与发布设计',
    url: 'https://github.com/wzz6423/zisla/blob/main/mac/Docs/releasing.md',
    description: '签名、公证与发布流程',
  },
  {
    title: '贡献指南',
    url: 'https://github.com/wzz6423/zisla/blob/main/CONTRIBUTING.md',
    description: '开发环境、分支、提交和 Pull Request 要求',
  },
];

export const license = 'MIT';

export const repositoryLinks = {
  github: 'https://github.com/wzz6423/zisla',
  gitee: 'https://gitee.com/wzz6423/zisla',
};
