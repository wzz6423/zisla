import type { SiteContent } from '../content';

export const zhHans: SiteContent = {
  meta: {
    documentTitle: 'zisla · 动态工作空间',
    description:
      'zisla：面向 macOS 的原生动态工作空间。集中查看 Zed Agent 等 AI 任务、媒体、文件和日程，并使用键盘音效、输入统计、截图标注与复制助手。',
    ogTitle: 'zisla · 把正在发生的事放到你看得见的地方',
    ogDescription:
      '从 Zed Agent 等 AI 任务与媒体，到键盘音效、输入统计、复制助手、截图标注和桌面工具，一个按需出现的原生 macOS 工作空间。',
  },
  tagline: '原生 macOS 动态工作空间',
  header: {
    navAriaLabel: '主导航',
    brandHomeAriaLabel: 'zisla 首页',
    menuOpenLabel: '打开导航菜单',
    menuCloseLabel: '关闭导航',
    menuButtonTitle: '打开导航',
    navItems: {
      showcase: '功能',
      ai: 'AI 工作流',
      download: '下载',
      faq: 'FAQ',
      developers: '开发者',
    },
    downloadCta: '下载',
    downloadCtaAriaLabel: '跳转到下载区域',
    languageLabel: '界面语言',
  },
  hero: {
    eyebrow: '原生 MACOS 工作空间',
    title:
      'zisla<br><em>把正在发生的事<br>放到你看得<br class="hero-mobile-break">见的地方。</em>',
    lede: '把 AI 任务、媒体、文件和日程收进屏幕顶部；复制后，独立的助手提示条会在屏幕顶端预览内容并给出下一步。需要时出现，完成后收起。',
    downloadCta: '下载',
    downloadCtaAriaLabel: '下载',
    sourceCta: '查看源码',
    sourceCtaAriaLabel: '在 GitHub 上查看 zisla 源代码',
    hints: [
      '移到屏幕顶部即可展开，无需点击',
      '复制后可用 Command+N 调出智能下一步',
      '自动收起，不干扰当前工作',
    ],
    identityCaption: '屏幕顶部',
  },
  proof: {
    ariaLabel: '产品概览',
    items: {
      modules: { title: '{count} 个顶部模块', desc: '顶部工作流按需开启' },
      os: { title: 'macOS 14+', desc: '原生桌面体验' },
      displays: { title: '多显示器', desc: '刘海屏与外接屏都能使用' },
      local: { title: '本地优先', desc: 'AI 状态不读取对话正文' },
    },
  },
  showcase: {
    eyebrow: '同一入口 / 日常工作流',
    title: '常用工作流，<span>留在屏幕顶部。</span>',
    lede: '从 AI 任务到剪贴板、日程与系统状态，zisla 把分散的桌面工作流收进同一个入口。',
    ariaLabel: 'zisla 功能目录',
    summaryMono: '{modules} 个模块 / {groups} 类工作流',
    summaryLede: '从顶部工作流到本地工具，实际能完成的任务都在这里逐项写清。',
    summaryNote:
      '{modules} 个顶部模块 + {features} 项独立能力，覆盖截图、语音、媒体、下载、复制助手、AI 管理、宠物与锁屏。',
    groupNames: {
      island: '顶部工作流',
      ai: 'AI 工作流',
      daily: '日常信息',
      tools: '实用工具',
    },
    groupCount: '{count} 个模块',
    pointsAriaLabel: '{name} 的功能要点',
    modules: {
      dashboard: {
        name: '首页',
        caption: '只在有进行中的专注、AI 任务或下载时显示动态卡片，没有活动时不占用额外空间。',
        points: ['按需出现', '实时进度', '自动调整布局'],
      },
      shelf: {
        name: '中转站',
        caption:
          '将文件、音视频或链接拖到屏幕顶部触发带，放入中转站、在 Finder 中定位，或调用 macOS 系统共享菜单。',
        points: ['拖到顶部即中转', 'Finder 中定位', '系统共享菜单'],
      },
      clipboard: {
        name: '剪贴板',
        caption:
          '在灵动岛内查看剪贴板历史，并按图片、URL、路径与文件类型筛选；可将历史项发送到随记、设为常用或删除。',
        points: ['岛内历史记录', '按类型筛选', '随记与常用'],
      },
      aiMonitor: {
        name: 'AI 监控',
        caption:
          '自动识别受支持的 AI CLI、桌面端与 IDE 活动，包括 Zed Agent 线程，展示任务、状态、累计 Token 趋势和贡献热力图；只解析结构化事件，不读取对话正文。',
        points: ['多工具任务聚合', 'Token 消耗趋势', '不读取提示词与回答'],
      },
      keyboardSound: {
        name: '键盘音效',
        caption:
          '为全局按键播放 20 种内置机械键盘音色，可调音量与自然音高变化，并为支持的音色播放回弹音；开启本地输入统计后，可在岛内查看今日概览、输入趋势、历史、应用时间线和含 F1-F12 的逐键热力图。',
        points: ['20 种内置音色', '回弹音与音高变化', '输入统计可选开启'],
      },
      download: {
        name: '下载器',
        caption:
          '粘贴链接，或在开启后从剪贴板识别链接；选择视频或音频下载到默认或自选目录。支持常见视频平台与其他受支持链接，下载时显示来源图标、实时进度和完成状态。',
        points: ['视频 / 音频模式', '默认或自选目录', '来源图标与实时进度'],
      },
      agenda: {
        name: '日程与天气',
        caption:
          '展示当前位置与最多 6 个自选地点的天气；查看、新增和删除日历事件及提醒事项，并可将提醒标记完成。',
        points: ['多地天气卡片', '日历与待办管理', '提醒一键完成'],
      },
      mail: {
        name: '邮件',
        caption:
          '读取已启用的 Mail.app 账户，在岛内查看收件箱、标记已读、回复、撰写新邮件和移入废纸篓；权限不足时给出明确的授权指引。',
        points: ['Mail.app 账户', '岛内回复与撰写', '权限指引透明'],
      },
      quickNotes: {
        name: '随记',
        caption:
          '以系统「备忘录」为数据源，支持查看、编辑、新建和删除笔记，以及 Markdown 实时预览；草稿会自动写回备忘录。',
        points: ['数据来自备忘录', 'Markdown 编辑器', '草稿自动写回'],
      },
      pdf: {
        name: 'PDF 工具',
        caption:
          '在本机完成 PDF 合并、拆分、旋转、裁剪、图片/Office 转换、渲染为图片、导出文字、文字/图片水印、页码、加密、解除密码和元数据编辑等 14 项操作。',
        points: ['14 种本机工具', '按顺序合并', '全程不出本机'],
      },
      toolbox: {
        name: '小工具',
        caption:
          '将专注倒计时、保持亮屏、屏幕清理、键盘清理（清理期间屏蔽包括 F1-F12 在内的按键）、闹钟、提词器、镜子和废纸篓集中在同一页。',
        points: ['专注倒计时', '清理时屏蔽 F1-F12', '提词器与镜子'],
      },
      system: {
        name: '系统状态',
        caption:
          '查看 CPU、GPU、内存、磁盘、网络和风扇等状态，在设备支持时读取 NVMe SMART 温度，并清理可安全删除的缓存与日志。',
        points: ['芯片级监控', 'NVMe 温度（设备支持时）', '一键清理缓存'],
      },
      battery: {
        name: '电池',
        caption: '查看本机电量、健康度、循环、温度和容量等详细指标，并聚合系统可读取的附近设备电量。',
        points: ['本机健康指标', '剩余时间', '附近设备电量'],
      },
    },
  },
  extensions: {
    eyebrow: '灵动岛内外',
    title: '离开灵动岛，<span>仍有桌面能力。</span>',
    lede: '截图、语音、媒体、浏览器下载与 AI 管理按各自最顺手的方式出现。',
    ariaLabel: '独立桌面能力',
    summaryMono: '灵动岛之外',
    summaryLede: '常用能力，各在最顺手的位置。',
    summaryNote: '截图、录音、媒体、浏览器下载、复制助手、AI 管理、宠物与锁屏各自独立呈现。',
    features: {
      capture: {
        title: '截图、长截图与钉图',
        description:
          '用全局快捷键截取或钉住屏幕内容，继续标注、拼接长截图，并识别或导出表格；导出前会保留正在编辑的文字标注。',
        detail: '全局快捷键 · 标注与撤销 · 编辑内容随导出保存',
      },
      voice: {
        title: '语音输入与整理',
        description:
          '按键切换或按住说话，使用系统语音识别，再按需启用领域词库、自定义热词、结构化格式或本地 / 远端模型整理。',
        detail: '两种录音方式 · 词库与自定义热词 · 可选模型整理',
      },
      media: {
        title: '媒体与系统背景声',
        description:
          '在灵动岛顶部控制正在播放，也可选择 macOS 系统背景声；锁屏、屏保或显示器休眠时可自动关闭。',
        detail: '播放控制 · 歌词同步 · 自动停止背景声',
      },
      browserDownloads: {
        title: '浏览器下载进度',
        description:
          '识别 Safari、Chrome、Edge、Firefox、Brave、Vivaldi、Opera 与 Arc 的下载，在顶部显示来源和实时进度。',
        detail: '8 种浏览器 · 来源识别 · 完成提示',
      },
      copyAssistant: {
        title: '复制助手与智能下一步',
        description:
          '启用后，复制文本、链接、文件或图片会在独立的顶部提示条中预览，并按内容给出打开、Finder 定位、搜索、翻译、计算或保存等下一步，由你确认后执行。',
        detail: '可选开关 · 本机识别 · 默认 Command+N',
      },
      aiManagement: {
        title: 'AI CLI 与 Skills 管理',
        description:
          '在设置中检测、安装、更新和卸载常用 AI CLI，并查看和管理本机 Skills，减少在多个终端和工具之间切换。',
        detail: '检测与安装 · 更新与卸载 · 本机 Skills',
      },
      pet: {
        title: '灵动岛宠物',
        description: '选择内置的宠物形象，把它放在灵动岛的左侧或右侧；不需要时可随时关闭。',
        detail: '内置形象 · 左右位置 · 按需开启',
      },
      lockScreen: {
        title: '锁屏信息',
        description:
          '按需在 macOS 锁屏界面显示日期、状态与正在播放信息；它是独立锁屏叠层，不会出现在灵动岛的模块列表或轮播中。',
        detail: '独立锁屏叠层 · 按需开启 · 不抢焦点',
      },
    },
  },
  ai: {
    eyebrow: '没有黑箱的 AI',
    title: '看见 AI 状态，<span>不读取对话。</span>',
    lede: '任务、状态和 Token 趋势留在本机；页面只说明能力，不虚构运行中的任务画面。',
    summaryMono: '本机状态 / 明确边界',
    summaryLede: '接入常用 AI 工具，保留当前工作需要的上下文边界。',
    summaryNote: '页面只说明检测范围、数据边界和接入方式，不模拟正在运行的会话。',
    toolsHeading: '支持的 AI 工具',
    toolsLede: '自动识别受支持的 CLI、桌面端与 IDE 活动，并聚合任务状态。',
    toolsAriaLabel: '支持的 AI 工具',
    doubaoName: '豆包',
    boundariesHeading: '只记录状态边界',
    privacyPoints: [
      '只解析结构化事件中的事件类型、状态、时间、模型和会话 ID',
      '不读取提示词或回答正文',
      '协议与状态均保存在本机',
    ],
    bridgeHeading: '接入你自己的任务',
    bridgeLede: '通过 zislactl 将外部任务的结构化状态送入顶部状态条。',
    zislactlTaskTitle: '打包发布',
    copyZislactlAriaLabel: '复制 zislactl 命令',
  },
  flow: {
    eyebrow: '交互节奏',
    title: '移到顶部，<span>查看，然后收起。</span>',
    lede: '不抢焦点，查看后自动收起。',
    ariaLabel: '顶部交互节奏',
    summaryMono: '顶部状态条 / 3 步',
    summaryLede: '需要时展开，阅读完成后收回。',
    summaryNote: '由鼠标位置触发；无操作时不占用视觉空间，也不抢走当前应用焦点。',
    steps: {
      trigger: {
        phase: '触发',
        title: '移到屏幕顶部中央',
        desc: '刘海屏和外接屏使用同样的触发方式；隐藏时不运行帧循环。',
      },
      review: {
        phase: '查看',
        title: '看一眼当前状态',
        desc: '媒体、文件、AI、日程和系统工具集中在同一位置。',
      },
      dismiss: {
        phase: '收起',
        title: '继续手上的工作',
        desc: '移开鼠标后自动收起，展开时不会激活或抢走当前应用焦点。',
      },
    },
  },
  download: {
    eyebrow: '随时可用',
    title: '下载 zisla',
    copy: '适用于 Apple 芯片 Mac；版本、其他架构与校验信息均在 Release 页面。安装后可按更新通道检查新版本，Sparkle 会先验证签名，再按设置手动或自动下载、安装并重启。',
    primaryCta: '下载',
    primaryCtaAriaLabel: '下载',
    releaseCta: '查看 Release',
    releaseCtaAriaLabel: '在 GitHub 上查看发布详情',
    brewMono: 'HOMEBREW / 一条命令',
    brewNote: 'zisla 由 Sparkle 自行更新，直接执行 brew upgrade 不会替换已安装的应用；需要 Homebrew 接手时执行 brew upgrade --cask zisla。tap 只提供正式版。该 tap 属于第三方，应用也未经公证，首次打开需在“系统设置 → 隐私与安全性”中选择“仍要打开”。',
    copyBrewCommandAriaLabel: '复制 Homebrew 安装命令',
    notes: {
      system: { term: '系统', value: 'macOS 14 或更高版本 · 当前受支持配置为 Apple 芯片 Mac' },
      install: { term: '安装', value: '挂载 DMG 后拖入 Applications' },
      package: { term: '包体', value: 'Apple Silicon (arm64) · DMG' },
      architectures: { term: '其他架构', value: 'Release 页面' },
      mirror: { term: '镜像', value: 'Gitee Releases' },
    },
  },
  faq: {
    eyebrow: '几个明确的答案',
    title: '常见问题。',
    lede: '权限、隐私和兼容性说明。',
    items: {
      audience: {
        question: 'zisla 适合哪些用户？',
        answer: '适合希望集中查看 AI、媒体、文件和日程的 Mac 用户；无刘海显示器也支持。',
      },
      aiPrivacy: {
        question: 'zisla 会读取我的 AI 对话内容吗？',
        answer: '不会。AI 状态监控只读取任务状态，不读取提示词或回答正文。',
      },
      copyAssistant: {
        question: '复制助手会自动打开或上传我复制的内容吗？',
        answer:
          '不会。启用后，内容识别和预览均在本机完成；只有你点击动作或按下快速触发后，zisla 才会执行对应下一步。',
      },
      permissions: {
        question: 'zisla 需要哪些系统权限？',
        answer: `
      <p>zisla 不会在首次启动时一次性索取所有权限。只有你开启并实际使用下列功能时，macOS 才会显示对应授权：</p>
      <ul>
        <li><strong>日历与提醒事项：</strong>打开日程模块时分别请求，用于读取、创建和管理日历事件与带日期的提醒事项。</li>
        <li><strong>定位服务：</strong>选择“使用当前位置”的天气时请求；只获取一次当前位置，不会持续跟踪。手动添加城市不需要定位权限。</li>
        <li><strong>麦克风与语音识别：</strong>点击开始语音输入时请求；只在主动录音期间采集声音，只处理该次录音的转写。</li>
        <li><strong>辅助功能：</strong>自动将语音转写填入当前应用、鼠标手势快速复制、键盘清洁及部分受支持播放器控制时需要；用于定位非密码输入控件或发送必要的系统按键。</li>
        <li><strong>输入监控：</strong>键盘音效、可选的本地输入统计，以及使用单独修饰键或鼠标侧键等全局触发方式时按需使用；仅监听完成这些功能所需的全局事件，普通全局快捷键不需要这项授权。</li>
        <li><strong>屏幕录制与系统音频录制：</strong>截图、截图编辑和显示系统播放音频波形时需要。截图会读取屏幕图像；音频波形只分析当前系统音频能量，不保存或上传音频内容。</li>
        <li><strong>摄像头：</strong>只在打开镜子窗口期间使用。</li>
        <li><strong>蓝牙：</strong>只在打开电池模块时读取已连接或已配对设备公开的电量信息。</li>
        <li><strong>自动化：</strong>首次使用随记、邮件、桌面整理或直接控制受支持播放器时，macOS 会分别询问是否允许 zisla 控制“备忘录”“邮件”“访达”或相应应用。随记可读写备忘录；邮件可读取、撰写、回复、标记和删除邮件。</li>
        <li><strong>完全磁盘访问：</strong>仅在 Mail.app 未运行时仍要读取本地邮件索引以显示账户、发件人、主题、摘要、时间和已读状态时需要。</li>
        <li><strong>通知：</strong>启用番茄钟或闹钟提醒时请求，只用于在计时结束或闹钟触发时显示本机通知。</li>
      </ul>
      <p><strong>文件与下载目录不是完全磁盘访问：</strong>你通过系统文件选择器选中的中转、导入导出或下载目录，zisla 只获得该目录的访问权，不会获得整块磁盘的读取权限。</p>
      <p><strong>键盘音效与输入统计：</strong>两项功能都默认关闭，任一项开启后才会监听全局键盘事件；开启键盘音效后只处理按键事件以播放声音，开启输入统计后只保存字符数、物理键码、时间和前台应用等聚合数据，不保存输入内容。你可以在设置中分别关闭，关闭后不再记录；已保存的聚合数据留在本机数据库文件中，可自行删除。</p>
      <p>你可在应用设置中关闭对应功能，或随时在“系统设置 → 隐私与安全性”中撤销授权。撤销某一项只会停用相关功能，不会影响其他模块；不同 macOS 版本中的项目名称可能略有不同。</p>
    `.trim(),
      },
      network: {
        question: 'zisla 会联网吗？',
        answer:
          '天气、签名更新检查、主动下载和可选远端语音整理会按需联网；剪贴板链接检测只在本机识别，不会自行发起下载。',
      },
      multiDisplay: {
        question: 'zisla 支持多显示器吗？',
        answer: '支持多显示器、Spaces 和普通全屏应用，展开时不抢焦点。',
      },
      intel: {
        question: 'Intel Mac 可以使用吗？',
        answer: 'Intel 机型可能存在可用的发布包，但不保证兼容性。当前受支持配置为 Apple 芯片 Mac。',
      },
      storage: {
        question: 'zisla 的数据存储在哪里？',
        answer:
          '本地数据位于 ~/Library/Application Support/zisla/；键盘输入统计单独保存在 ~/Library/Application Support/SimuBoard/typing-stats.sqlite3；随记使用系统「备忘录」。',
      },
    },
  },
  developers: {
    eyebrow: '默认开源',
    title: '开发者资源。',
    lede: 'PolyForm Noncommercial 1.0.0 许可，仅限非商业用途，可直接使用或从源码构建。',
    docs: {
      macos: { title: 'macOS 开发指南', description: '功能、构建、测试与系统限制' },
      architecture: { title: '架构与性能设计', description: '顶部触发、窗口和性能设计' },
      cli: { title: 'CLI 接入设计', description: 'zislactl 命令与字段' },
      releasing: { title: '签名与发布设计', description: '签名、公证与发布流程' },
      contributing: { title: '贡献指南', description: '开发环境、分支、提交和 Pull Request 要求' },
    },
    quickStartMono: '快速开始 / 源码',
    quickStartHeading: '从源码运行，或接入你自己的任务。',
    copyRunCommandAriaLabel: '复制源码运行命令',
    githubRepoLabel: 'GitHub 仓库',
    giteeRepoLabel: 'Gitee 仓库',
    checksumLabel: 'SHA-256',
    performancePoints: [
      '支持多显示器、Spaces 和普通全屏应用；展开时不会激活或抢走当前应用焦点',
      '隐藏时不创建常驻透明热区窗口，也不运行帧循环；通过全局事件监听与几何判断触发展开',
      '使用单层系统材质；系统开启“降低透明度”后会自动使用实体背景',
      'macOS 26+ 使用 Liquid Glass；macOS 14/15 自动回退为系统原生材质',
      '物理刘海通过系统安全区域推断；无刘海的外接显示器使用自有覆盖层模拟状态条',
    ],
  },
  footer: {
    brandHomeAriaLabel: '回到 zisla 首页',
    previewChannelLabel: 'Preview 通道',
    tagline: '开源、原生、把控制权留在你手里。',
  },
  common: {
    copyCommandTitle: '复制命令',
    copiedAriaLabel: '已复制',
  },
  toast: {
    runCommandCopied: '源码运行命令已复制',
    zislactlCopied: 'zislactl 命令已复制',
    brewCommandCopied: 'Homebrew 安装命令已复制',
  },
};
