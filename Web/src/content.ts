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
  '把 AI 任务、媒体控制、文件中转和日程信息集中到屏幕顶部。需要时展开查看，移开后自动收起。';

export const heroTitle = 'zisla<br><em>把正在发生的事<br>放到你看得见的地方。</em>';
export const heroHints = [
  '移到屏幕顶部即可展开，无需点击',
  '自动收起，不干扰当前工作',
  '刘海屏与外接显示器都支持',
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
  'dashboard',
  'aiAgent',
  'download',
  'aiMonitor',
  'clipboard',
  'agenda',
  'quickNotes',
  'pdf',
  'system',
  'battery',
  'toolbox',
  'lockScreen',
  'mail',
  'shelf',
];

/* ===== 正在播放（界面示意数据） ===== */

export const nowPlaying = {
  title: '微光时刻',
  artist: '晚风电台',
  subtitle: '吹过晚风的手 · 歌词同步',
  currentSeconds: 54,
  durationSeconds: 228,
};

export const islandUptime = '开机时间：1天4小时12分钟';

export const islandMetrics = [
  { label: 'CPU', value: 18, tone: 'good' as const },
  { label: 'GPU', value: 32, tone: 'normal' as const },
  { label: 'RAM', value: 45, tone: 'normal' as const },
  { label: 'Disk', value: 28, tone: 'good' as const },
];

/* ===== AI 监控模块（界面示意数据） ===== */

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
    name: '整理组件使用文档',
    provider: 'CLAUDE',
    detail: '设计系统 · UI Library',
    effort: 'high',
    meta: '开始 09:30 · 会话 A1',
    elapsedSeconds: 60,
    status: 'spinner',
  },
  {
    name: '检查搜索结果排序',
    provider: 'GPT',
    detail: '官网重构 · Search',
    effort: 'max',
    meta: '开始 09:15 · 会话 B2',
    elapsedSeconds: 459,
    status: 'dot',
  },
  {
    name: '调整产品展示文案',
    provider: 'CODEX',
    detail: '落地页改版 · Showcase',
    effort: 'high',
    meta: '开始 09:25 · 会话 C3',
    elapsedSeconds: 226,
    status: 'spinner',
  },
  {
    name: '验证下载队列状态',
    provider: 'GEMINI',
    detail: '发布流水线 · Queue',
    effort: 'medium',
    meta: '开始 09:20 · 会话 D4',
    elapsedSeconds: 235,
    status: 'dot',
  },
  {
    name: '生成本周发布说明',
    provider: 'QWEN',
    detail: '版本归档 · Docs',
    effort: 'low',
    meta: '开始 09:00 · 会话 E5',
    elapsedSeconds: 873,
    status: 'spinner',
  },
];

export const tokenTrend = {
  yLabels: ['1M', '10M', '100M', '1B'],
  xLabels: ['周一', '周二', '周三', '周四', '周五', '周六', '周日'],
  // 对数刻度下的归一化值（1M=0.05, 1B=1.0），呈上升趋势
  points: [0.08, 0.14, 0.12, 0.28, 0.42, 0.66, 0.94],
  lastValue: '947M',
};

/* ===== 剪贴板模块（界面示意数据） ===== */

export const clipboardMeta = {
  total: 12,
  tabs: ['全部', '常用', '非常用'],
  filters: [
    { label: '全部', count: 12 },
    { label: '文件夹', count: 1 },
    { label: '图片', count: 3 },
    { label: 'URL', count: 2 },
    { label: '视频', count: 0 },
    { label: '文档', count: 4 },
    { label: '压缩包', count: 0 },
    { label: '代码', count: 1 },
    { label: '其他', count: 1 },
  ],
  actions: ['随记', 'AI', '常用', '删除'],
};

export const clipboardItems = [
  { kind: 'image' as const, title: '首页设计稿.png', meta: 'PNG · 324.5 KB' },
  {
    kind: 'code' as const,
    title: 'npm run test',
    meta: '代码',
  },
  {
    kind: 'url' as const,
    title: 'https://example.com/documentation',
    meta: 'URL',
  },
  {
    kind: 'text' as const,
    title: '下周三下午同步评审方案',
    meta: '文本',
  },
];

/* ===== 中转站模块（界面示意数据） ===== */

export const shelfMeta = {
  count: 3,
  filters: ['全部', '文件夹', '图片', '视频', '音频', '文档', '压缩包', '代码', '其他'],
  previews: [
    { name: '播客封面.png', meta: 'PNG · 484.0 KB', kind: 'image' },
    { name: '需求评审资料.pdf', meta: 'PDF · 1.2 MB', kind: 'document' },
    { name: '原型素材.zip', meta: 'ZIP · 8.6 MB', kind: 'archive' },
  ],
};

/* ===== 下载模块（产品界面示意数据） ===== */

export const downloadMeta = {
  placeholder: '视频或音频链接',
  folder: '下载',
  status: '准备就绪',
  clipboardToggle: '剪贴板检测已开启',
};

/* ===== 日程模块（界面示意数据） ===== */

export const weatherCities = [
  {
    region: '杭州市 · 中心区',
    icon: 'sun',
    condition: '晴 · 体感 26°',
    temp: '24°',
    sun: '06:12 / 19:28',
    rain: '0.0mm',
    humidity: '5% / 0.0mm',
  },
  {
    region: '杭州市 · 湖畔区',
    icon: 'cloud',
    condition: '多云 · 体感 22°',
    temp: '21°',
    sun: '06:25 / 19:45',
    rain: '0.0mm',
    humidity: '78% / 1.2mm',
  },
];

export const agendaEmptyText = '今天没有待办事项';

/* ===== 随记模块（界面示意数据） ===== */

export const notesMeta = {
  count: 4,
  wordCount: '86 字',
  list: [
    { title: '周会提纲', meta: '刚刚', selected: true },
    { title: '下周待办', meta: '2 小时前' },
    { title: '读书摘要', meta: '昨天' },
    { title: '灵感记录', meta: '上周' },
  ],
  body:
    '用随记收集灵感、整理待办，或把手边的文字和文件继续发给 AI Agent。内容保存在系统「备忘录」中。',
};

/* ===== 邮件模块（界面示意数据） ===== */

export const mailMeta = {
  account: '个人邮箱',
  unread: 2,
  messages: [
    {
      sender: '产品协作',
      title: '本周体验清单',
      preview: '初稿已准备好，请查看附件。',
      time: '09:42',
      unread: true,
      selected: true,
    },
    {
      sender: '设计协作',
      title: '新版交互说明',
      preview: '切换动效与间距已同步。',
      time: '08:18',
      unread: true,
      selected: false,
    },
    {
      sender: '日历通知',
      title: '下次评审时间',
      preview: '下周三下午进行产品评审。',
      time: '昨天',
      unread: false,
      selected: false,
    },
  ],
  detail: {
    sender: '产品协作 <team@zisla.app>',
    title: '本周体验清单',
    date: '今天 09:42',
    body: '初稿已准备好。本次重点查看顶部展开、模块切换和多屏显示。',
  },
};

/* ===== PDF 工具模块（产品界面示意数据） ===== */

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
  { label: '编辑元数据' },
];

export const pdfActiveTitle = '合并 PDF';
export const pdfActiveDesc = '按选择顺序合并多个 PDF';

/* ===== 系统状态模块（界面示意数据） ===== */

export const systemCards = {
  cpu: {
    chip: 'Apple M3 Pro',
    temp: '52.8°C',
    cores: '12核 · 6性能 · 6能效',
    legend: [
      { label: '用户', value: '18%', color: '#0a84ff' },
      { label: '系统', value: '12%', color: '#ff453a' },
      { label: '闲置', value: '70%', color: '#e8e8ed' },
    ],
  },
  gpu: {
    chip: 'Apple M3 Pro',
    temp: '48.5°C',
    cores: '18核',
    legend: [
      { label: '利用率', value: '32%', color: '#0a84ff' },
      { label: '渲染', value: '28%', color: '#ff453a' },
      { label: 'Tiler', value: '24%', color: '#5ac8fa' },
    ],
  },
  memory: {
    pressure: '45%',
    available: '20.2 GB',
    total: '36.0 GB',
    action: '释放',
  },
  disk: {
    name: '系统磁盘',
    available: '512.8 GB',
    total: '1.0 TB',
    read: '2.4 MB/s',
    write: '1.8 MB/s',
    action: '清理',
  },
  fans: ['3,200 RPM', '3,450 RPM'],
  network: {
    down: '125 KB/s',
    up: '48 KB/s',
    lan: '192.0.2.10',
    wan: '203.0.113.42',
  },
};

export const dashboardMeta = {
  focus: { clock: '24:18', phase: '进行中' },
  ai: { title: '整理需求文档', provider: 'CODEX', progress: 68 },
  download: { title: '发布会素材.zip', progress: 42, speed: '3.2 MB/s', eta: '剩余 18 秒' },
};

export const agentMeta = {
  project: '官方网站',
  thread: '新建产品评审',
  model: 'GLM-4.7',
  messages: [
    { role: '你', body: '把这份提纲整理成三个重点。' },
    { role: 'AI', body: '已整理：顶部工作流、本地优先、按需出现。' },
  ],
};

export const toolboxMeta = {
  clock: '25:00',
  mode: '专注',
  toggles: ['保持亮屏', '显示秒数'],
  actions: ['清理屏幕', '清理键盘', '闹钟', '提词器', '镜子', '废纸篓'],
};

export const batteryMeta = {
  status: '使用电池',
  level: 78,
  remaining: '约 6 小时 20 分',
  metrics: [
    { label: '健康度', value: '96%' },
    { label: '循环次数', value: '128' },
    { label: '温度', value: '34.2°C' },
    { label: '最大容量', value: '6,820 mAh' },
    { label: '设计容量', value: '7,100 mAh' },
    { label: '当前电量', value: '5,320 mAh' },
  ],
  devices: [
    { name: 'AirPods Pro', level: 64, symbol: 'airplay' },
    { name: 'Magic Keyboard', level: 82, symbol: 'battery-charging' },
  ],
};

export const lockScreenMeta = {
  weather: '24° · 晴',
  lunar: '农历七月初三',
  message: '“专注当下，给重要的事留出空间。”',
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
    id: 'dashboard',
    name: '首页',
    group: '顶部工作流',
    caption:
      '只在有进行中的专注、AI 任务或下载时显示动态卡片，没有活动时不占用额外空间。',
    points: ['按需出现', '实时进度', '自动调整布局'],
  },
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
      '可选记录剪贴板历史，并按图片、URL 与文件类型筛选；链接检测可独立开关，开启后仅在本机识别新链接并提示。',
    points: ['按类型筛选', '常用标记', '链接检测可独立开关'],
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
    id: 'aiAgent',
    name: 'AI Agent',
    group: 'AI 工作流',
    caption:
      '在岛内管理本地项目和统一对话历史，添加文件、Skills 与应用上下文，并切换本地或远端模型。',
    points: ['项目化对话', '文件与应用上下文', '本地 / 远端模型'],
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
      '在本机完成 PDF 合并、拆分、旋转、裁剪、图片/Office 转换、渲染为图片、导出文字、文字/图片水印、页码、加密、解除密码和元数据编辑等 14 项操作。',
    points: ['14 种本机工具', '按顺序合并', '全程不出本机'],
  },
  {
    id: 'toolbox',
    name: '小工具',
    group: '实用工具',
    caption:
      '将专注倒计时、保持亮屏、屏幕/键盘清理、闹钟、提词器、镜子和废纸篓集中在同一页。',
    points: ['专注倒计时', '屏幕与键盘清理', '提词器与镜子'],
  },
  {
    id: 'system',
    name: '系统状态',
    group: '实用工具',
    caption:
      '查看 CPU、GPU、内存、磁盘、网络和风扇等状态，并清理可安全删除的缓存与日志。',
    points: ['芯片级监控', '一键清理缓存', '风扇与网络详情'],
  },
  {
    id: 'battery',
    name: '电池',
    group: '日常信息',
    caption:
      '查看本机电量、健康度、循环、温度和容量等详细指标，并聚合系统可读取的附近设备电量。',
    points: ['本机健康指标', '剩余时间', '附近设备电量'],
  },
  {
    id: 'lockScreen',
    name: '锁屏',
    group: '日常信息',
    caption:
      '在锁屏信息模块中集中显示公历、农历、天气、电量和自定义短句，保持信息简短易读。',
    points: ['公历与农历', '天气与电量', '自定义锁屏文字'],
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
  version: 'v0.1.3',
  channel: 'Release',
  releasePage: 'https://github.com/wzz6423/zisla/releases/tag/release/v0.1.3',
  dmg: 'https://github.com/wzz6423/zisla/releases/download/release/v0.1.3/zisla-v0.1.3-macOS-universal.dmg',
  zip: 'https://github.com/wzz6423/zisla/releases/download/release/v0.1.3/zisla-v0.1.3-macOS-universal.zip',
  checksum: 'https://github.com/wzz6423/zisla/releases/download/release/v0.1.3/zisla-v0.1.3-macOS-universal.zip.sha256',
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
