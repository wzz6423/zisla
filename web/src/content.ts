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
  '把 AI 任务、媒体、文件和日程收进屏幕顶部；复制后，独立的助手提示条会在屏幕顶端预览内容并给出下一步。需要时出现，完成后收起。';

export const heroTitle = 'zisla<br><em>把正在发生的事<br>放到你看得<br class="hero-mobile-break">见的地方。</em>';
export const heroHints = [
  '移到屏幕顶部即可展开，无需点击',
  '复制后可用 Command+N 调出智能下一步',
  '自动收起，不干扰当前工作',
];

export const proofItems = [
  { title: '12 个顶部模块', desc: '顶部工作流按需开启' },
  { title: 'macOS 14+', desc: '原生桌面体验' },
  { title: '多显示器', desc: '刘海屏与外接屏都能使用' },
  { title: '本地优先', desc: 'AI 状态不读取对话正文' },
];

/* ===== Feature showcase (each module describes an actual feature) ===== */

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
      '在灵动岛内查看剪贴板历史，并按图片、URL、路径与文件类型筛选；可将历史项发送到随记、设为常用或删除。',
    points: ['岛内历史记录', '按类型筛选', '随记与常用'],
  },
  {
    id: 'aiMonitor',
    name: 'AI 监控',
    group: 'AI 工作流',
    caption:
      '自动识别受支持的 AI CLI、桌面端与 IDE 活动，包括 Zed Agent 线程，展示任务、状态、累计 Token 趋势和贡献热力图；只解析结构化事件，不读取对话正文。',
    points: ['多工具任务聚合', 'Token 消耗趋势', '不读取提示词与回答'],
  },
  {
    id: 'download',
    name: '下载器',
    group: '实用工具',
    caption:
      '粘贴链接，或在开启后从剪贴板识别链接；选择视频或音频下载到默认或自选目录。支持常见视频平台与其他受支持链接，下载时显示来源图标、实时进度和完成状态。',
    points: ['视频 / 音频模式', '默认或自选目录', '来源图标与实时进度'],
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
      '将专注倒计时、保持亮屏、屏幕/键盘清理、F1-F12 使用统计、闹钟、提词器、镜子和废纸篓集中在同一页。',
    points: ['专注倒计时', '键盘清理与按键统计', '提词器与镜子'],
  },
  {
    id: 'system',
    name: '系统状态',
    group: '实用工具',
    caption:
      '查看 CPU、GPU、内存、磁盘、网络和风扇等状态，在设备支持时读取 NVMe SMART 温度，并清理可安全删除的缓存与日志。',
    points: ['芯片级监控', 'NVMe 温度（设备支持时）', '一键清理缓存'],
  },
  {
    id: 'battery',
    name: '电池',
    group: '日常信息',
    caption:
      '查看本机电量、健康度、循环、温度和容量等详细指标，并聚合系统可读取的附近设备电量。',
    points: ['本机健康指标', '剩余时间', '附近设备电量'],
  },
];

/* ===== AI deep dive ===== */

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
  { name: 'ZCode' },
  { name: 'TRAE' },
  { name: 'OpenCode' },
  { name: 'Harnext' },
  { name: 'WorkBuddy' },
  { name: '豆包' },
  { name: 'Pi' },
  { name: 'Zed Agent' },
];

export const privacyPoints = [
  '只解析结构化事件中的事件类型、状态、时间、模型和会话 ID',
  '不读取提示词或回答正文',
  '协议与状态均保存在本机',
];

export interface CrossModuleFeature {
  id: string;
  icon: string;
  title: string;
  description: string;
  detail: string;
}

export const crossModuleFeatures: CrossModuleFeature[] = [
  {
    id: 'capture',
    icon: 'image',
    title: '截图、长截图与钉图',
    description:
      '用全局快捷键截取或钉住屏幕内容，继续标注、拼接长截图，并识别或导出表格；导出前会保留正在编辑的文字标注。',
    detail: '全局快捷键 · 标注与撤销 · 编辑内容随导出保存',
  },
  {
    id: 'voice',
    icon: 'mic',
    title: '语音输入与整理',
    description:
      '按键切换或按住说话，使用系统语音识别，再按需启用领域词库、结构化格式或本地 / 远端模型整理。',
    detail: '两种录音方式 · 领域词库 · 可选模型整理',
  },
  {
    id: 'media',
    icon: 'waves',
    title: '媒体与系统背景声',
    description:
      '在灵动岛顶部控制正在播放，也可选择 macOS 系统背景声；锁屏、屏保或显示器休眠时可自动关闭。',
    detail: '播放控制 · 歌词同步 · 自动停止背景声',
  },
  {
    id: 'browserDownloads',
    icon: 'download',
    title: '浏览器下载进度',
    description:
      '识别 Safari、Chrome、Edge、Firefox、Brave、Vivaldi、Opera 与 Arc 的下载，在顶部显示来源和实时进度。',
    detail: '8 种浏览器 · 来源识别 · 完成提示',
  },
  {
    id: 'copyAssistant',
    icon: 'copy',
    title: '复制助手与智能下一步',
    description:
      '启用后，复制文本、链接、文件或图片会在独立的顶部提示条中预览，并按内容给出打开、Finder 定位、搜索、翻译、计算或保存等下一步，由你确认后执行。',
    detail: '可选开关 · 本机识别 · 默认 Command+N',
  },
  {
    id: 'aiManagement',
    icon: 'bot',
    title: 'AI CLI 与 Skills 管理',
    description:
      '在设置中检测、安装、更新和卸载常用 AI CLI，并查看和管理本机 Skills，减少在多个终端和工具之间切换。',
    detail: '检测与安装 · 更新与卸载 · 本机 Skills',
  },
  {
    id: 'pet',
    icon: 'sparkles',
    title: '灵动岛宠物',
    description:
      '选择内置的宠物形象，把它放在灵动岛的左侧或右侧；不需要时可随时关闭。',
    detail: '内置形象 · 左右位置 · 按需开启',
  },
  {
    id: 'lockScreen',
    icon: 'lock',
    title: '锁屏信息',
    description:
      '按需在 macOS 锁屏界面显示日期、状态与正在播放信息；它是独立锁屏叠层，不会出现在灵动岛的模块列表或轮播中。',
    detail: '独立锁屏叠层 · 按需开启 · 不抢焦点',
  },
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

/* ===== Download and system requirements ===== */

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
  version: 'v0.1.6',
  channel: 'Release',
  releasePage: 'https://github.com/wzz6423/zisla/releases/tag/release/v0.1.6',
  dmg: 'https://github.com/wzz6423/zisla/releases/download/release/v0.1.6/zisla-v0.1.6-macOS-arm64.dmg',
  zip: 'https://github.com/wzz6423/zisla/releases/download/release/v0.1.6/zisla-v0.1.6-macOS-arm64.zip',
  checksum: 'https://github.com/wzz6423/zisla/releases/download/release/v0.1.6/zisla-v0.1.6-macOS-arm64.zip.sha256',
  universalDmg: 'https://github.com/wzz6423/zisla/releases/download/release/v0.1.6/zisla-v0.1.6-macOS-universal.dmg',
  universalZip: 'https://github.com/wzz6423/zisla/releases/download/release/v0.1.6/zisla-v0.1.6-macOS-universal.zip',
  intelDmg: 'https://github.com/wzz6423/zisla/releases/download/release/v0.1.6/zisla-v0.1.6-macOS-x86_64.dmg',
  intelZip: 'https://github.com/wzz6423/zisla/releases/download/release/v0.1.6/zisla-v0.1.6-macOS-x86_64.zip',
  previewPage: 'https://github.com/wzz6423/zisla/releases/tag/preview',
};

/* ===== Developer ===== */

export const developmentSetup = {
  requirements: ['Swift 6 / Xcode 16+', 'macOS 14+', '可选：yt-dlp、ffmpeg'],
  runCommand: 'cd mac && swift run zisla',
  zislactlCommand:
    'zislactl update --id build --provider coder --title 打包发布 --progress 62',
};

export const performanceFeatures = [
  '支持多显示器、Spaces 和普通全屏应用；展开时不会激活或抢走当前应用焦点',
  '隐藏时不创建常驻透明热区窗口，也不运行帧循环；通过全局事件监听与几何判断触发展开',
  '使用单层系统材质；系统开启"降低透明度"后会自动使用实体背景',
  'macOS 26+ 使用 Liquid Glass；macOS 14/15 自动回退为系统原生材质',
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
    question: '复制助手会自动打开或上传我复制的内容吗？',
    answer: '不会。启用后，内容识别和预览均在本机完成；只有你点击动作或按下快速触发后，zisla 才会执行对应下一步。',
  },
  {
    question: 'zisla 需要哪些系统权限？',
    answer: `
      <p>zisla 不会在首次启动时一次性索取所有权限。只有你开启并实际使用下列功能时，macOS 才会显示对应授权：</p>
      <ul>
        <li><strong>日历与提醒事项：</strong>打开日程模块时分别请求，用于读取、创建和管理日历事件与带日期的提醒事项。</li>
        <li><strong>定位服务：</strong>选择“使用当前位置”的天气时请求；只获取一次当前位置，不会持续跟踪。手动添加城市不需要定位权限。</li>
        <li><strong>麦克风与语音识别：</strong>点击开始语音输入时请求；只在主动录音期间采集声音，只处理该次录音的转写。</li>
        <li><strong>辅助功能：</strong>自动将语音转写填入当前应用、鼠标手势快速复制、键盘清洁及部分受支持播放器控制时需要；用于定位非密码输入控件或发送必要的系统按键。</li>
        <li><strong>输入监控：</strong>仅在使用单独修饰键、鼠标侧键等全局触发方式，或键盘清洁时需要；普通全局快捷键不需要这项授权。</li>
        <li><strong>屏幕录制与系统音频录制：</strong>截图、截图编辑和显示系统播放音频波形时需要。截图会读取屏幕图像；音频波形只分析当前系统音频能量，不保存或上传音频内容。</li>
        <li><strong>摄像头：</strong>只在打开镜子窗口期间使用。</li>
        <li><strong>蓝牙：</strong>只在打开电池模块时读取已连接或已配对设备公开的电量信息。</li>
        <li><strong>自动化：</strong>首次使用随记、邮件、桌面整理或直接控制受支持播放器时，macOS 会分别询问是否允许 zisla 控制“备忘录”“邮件”“访达”或相应应用。随记可读写备忘录；邮件可读取、撰写、回复、标记和删除邮件。</li>
        <li><strong>完全磁盘访问：</strong>仅在 Mail.app 未运行时仍要读取本地邮件索引以显示账户、发件人、主题、摘要、时间和已读状态时需要。</li>
        <li><strong>通知：</strong>启用番茄钟或闹钟提醒时请求，只用于在计时结束或闹钟触发时显示本机通知。</li>
      </ul>
      <p><strong>文件与下载目录不是完全磁盘访问：</strong>你通过系统文件选择器选中的中转、导入导出或下载目录，zisla 只获得该目录的访问权，不会获得整块磁盘的读取权限。</p>
      <p>你可在应用设置中关闭对应功能，或随时在“系统设置 → 隐私与安全性”中撤销授权。撤销某一项只会停用相关功能，不会影响其他模块；不同 macOS 版本中的项目名称可能略有不同。</p>
    `.trim(),
  },
  {
    question: 'zisla 会联网吗？',
    answer: '天气、更新、主动下载和可选远端语音整理会按需联网；剪贴板链接检测只在本机识别，不会自行发起下载。',
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
