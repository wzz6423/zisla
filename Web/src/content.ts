export interface NavItem {
  label: string;
  href: string;
}

export interface FeatureCard {
  title: string;
  description: string;
  icon?: string;
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
  { label: '功能', href: '#features' },
  { label: '下载', href: '#download' },
  { label: 'FAQ', href: '#faq' },
  { label: '开发者', href: '#developers' },
];

export const productTitle = 'zisla';
export const productTagline = '原生 macOS 动态工作空间';
export const productDescription =
  '把 AI、媒体、文件和日程放到屏幕顶部，需要时展开，移开后收起。';

export const coreFeatures: FeatureCard[] = [
  {
    title: '信息在需要时出现',
    description: '移到屏幕顶部展开，移开即收起。',
  },
  {
    title: '把工作流留在桌面顶部',
    description: '媒体、文件、日程和系统状态集中在顶部。',
  },
  {
    title: '看见 AI 的实际工作状态',
    description: '显示 AI 任务、状态和 Token 趋势，不读取对话正文。',
  },
  {
    title: '保留你的控制权',
    description: '模块独立开关，权限按需申请。',
  },
];

export const topWorkflowFeatures: FeatureCard[] = [
  {
    title: '正在播放',
    description: '查看封面、标题和进度，并控制播放。',
  },
  {
    title: '文件中转与共享',
    description: '拖到顶部即可中转、定位或共享文件。',
  },
  {
    title: '剪贴板',
    description: '按需保存历史；链接检测默认关闭。',
  },
  {
    title: '状态与通知',
    description: '折叠状态显示 AI、下载、专注和邮件提醒。',
  },
  {
    title: '桌面宠物',
    description: '可选在顶部显示桌面宠物。',
  },
];

export const aiWorkflowFeatures: FeatureCard[] = [
  {
    title: 'AI 状态监控',
    description: '显示支持工具的运行任务、状态和 Token 趋势。',
  },
  {
    title: '多工具聚合',
    description: '集中查看 Claude、Codex、Gemini 等工具。',
  },
  {
    title: 'AI Agent 工作区',
    description: '管理对话、模型、自动化、Skills 和会话。',
  },
  {
    title: '语音输入',
    description: '全局快捷键录音、转写和整理文本。',
  },
];

export const dailyInfoFeatures: FeatureCard[] = [
  {
    title: '天气、日历与提醒事项',
    description: '查看天气、日历和提醒事项。',
  },
  {
    title: '邮件',
    description: '在顶部查看、回复和撰写邮件。',
  },
  {
    title: 'Markdown 随记',
    description: '编辑 Markdown，并同步到系统「备忘录」。',
  },
  {
    title: '锁屏信息',
    description: '显示锁屏文字、农历和状态信息。',
  },
];

export const utilityFeatures: FeatureCard[] = [
  {
    title: '视频与音频下载',
    description: '粘贴链接，下载视频或音频。',
  },
  {
    title: 'PDF 工具',
    description: '在本机合并、拆分、转换和编辑 PDF。',
  },
  {
    title: '专注与演示',
    description: '番茄钟、提词器、亮屏和摄像头镜子。',
  },
  {
    title: '系统状态与清理',
    description: '查看系统状态，清理缓存和日志。',
  },
];

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

export const installationSteps = [
  '从 GitHub Releases 或 Gitee Releases 下载最新 DMG',
  '挂载 DMG 后将 zisla.app 拖入 Applications',
  '首次启动后，将鼠标移到当前屏幕顶部中央即可展开',
  '非公证的预览包首次打开时，可能需要在"系统设置 > 隐私与安全性"中选择"仍要打开"',
];

export const developmentSetup = {
  requirements: ['Swift 6 / Xcode 16+', 'macOS 14+', '可选：yt-dlp、ffmpeg'],
  runCommand: 'cd mac && swift run zisla',
  buildCommand: 'Scripts/build-app.sh',
};

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

export const supportedAITools = [
  { name: 'Claude', cli: 'Claude Code', desktop: true },
  { name: 'Codex', cli: 'Codex CLI', desktop: true },
  { name: 'ChatGPT', cli: true, desktop: true },
  { name: 'Gemini', cli: 'Gemini CLI', desktop: false },
  { name: 'Grok', cli: 'Grok CLI', desktop: false },
  { name: 'Qoder', cli: 'Qoder CLI', desktop: true },
  { name: '千问', cli: 'Qwen Code', desktop: false },
];

export const performanceFeatures = [
  '支持多显示器、Spaces 和普通全屏应用；展开时不会激活或抢走当前应用焦点',
  '隐藏时不创建常驻透明热区窗口，也不运行帧循环；通过全局事件监听与几何判断触发展开',
  '使用单层系统材质；系统开启"降低透明度"后会自动使用实体背景',
  '物理刘海通过系统安全区域推断；无刘海的外接显示器使用自有覆盖层模拟状态条',
];

export const license = 'MIT';

export const repositoryLinks = {
  github: 'https://github.com/wzz6423/zisla',
  gitee: 'https://gitee.com/wzz6423/zisla',
};

export const latestRelease = {
  version: 'v0.1.3',
  channel: 'Release',
  releasePage: 'https://github.com/wzz6423/zisla/releases/tag/release/v0.1.3',
  dmg: 'https://github.com/wzz6423/zisla/releases/download/release/v0.1.3/zisla-v0.1.3-macOS-universal.dmg',
  zip: 'https://github.com/wzz6423/zisla/releases/download/release/v0.1.3/zisla-v0.1.3-macOS-universal.zip',
  checksum: 'https://github.com/wzz6423/zisla/releases/download/release/v0.1.3/zisla-v0.1.3-macOS-universal.zip.sha256',
  previewPage: 'https://github.com/wzz6423/zisla/releases/tag/preview',
};
