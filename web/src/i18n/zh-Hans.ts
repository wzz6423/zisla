import type { SiteContent } from '../content';

export const zhHans: SiteContent = {
  meta: {
    documentTitle: 'zisla · 动态工作空间',
    description:
      'zisla 是原生 macOS 动态工作空间，集中呈现 AI 任务与每日简报，支持录屏剪辑、自定义宠物、截图和集中权限管理。',
    ogTitle: 'zisla · 把正在发生的事放到你看得见的地方',
    ogDescription:
      '把 AI 任务和日常活动放到看得见的地方；在 Mac 上录屏剪辑、导入宠物，并集中管理权限。',
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
      changelog: '更新日志',
      faq: 'FAQ',
      developers: '开发者',
    },
    downloadCta: '下载',
    downloadCtaAriaLabel: '跳转到下载区域',
    languageLabel: '界面语言',
    themeLabel: '外观模式',
    themeModes: { auto: '自动（跟随系统）', light: '日间模式', dark: '夜间模式' },
  },
  hero: {
    eyebrow: '原生 MACOS 工作空间',
    title:
      'zisla<br><em>把正在发生的事<br>放到你看得见的地方。</em>',
    lede: '把 AI 任务、媒体、文件和日程收进屏幕顶部；复制后，独立的快捷操作提示条会在屏幕顶端预览内容并给出下一步。需要时出现，完成后收起。',
    downloadCta: '下载',
    downloadCtaAriaLabel: '下载',
    sourceCta: '查看源码',
    sourceCtaAriaLabel: '在 GitHub 上查看 zisla 源代码',
    hints: [
      '移到屏幕顶部即可展开，无需点击',
      '复制后可用 Command+N 调出智能下一步',
      '自动收起，不干扰当前工作',
    ],
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
      '{modules} 个顶部模块 + {features} 项独立能力，从窗口预览、截图与 AI 管理，到推荐应用。',
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
        caption: '只在有进行中的专注、AI 任务或下载时显示动态卡片，没有活动时不占用额外空间。首页将运行中的 AI 任务按应用聚合。',
        points: ['按需出现', '实时进度', '自动调整布局'],
      },
      shelf: {
        name: '中转站',
        caption:
          '将文件、音视频或链接拖到屏幕顶部暂存，按名称搜索、筛选和多选，批量复制、分享或发送到随记。图片可转 PDF 或识别文字后发送到随记，视频可送入录屏工作室编辑，也能随时在 Finder 中定位文件。',
        points: ['搜索筛选与批量操作', '图片转 PDF 与随记', '视频送入录屏工作室'],
      },
      clipboard: {
        name: '剪贴板',
        caption:
          '在灵动岛内查看剪贴板历史，按图片、URL、路径与文件类型筛选，并显示每条记录的复制时间；可将历史项发送到随记、设为常用或删除。可选自动删除超过 7、15 或 30 天的历史记录，保留常用项；默认不自动删除。',
        points: ['岛内历史记录', '按类型筛选', '随记与常用'],
      },
      aiMonitor: {
        name: 'AI 监控',
        caption:
          '汇总 AI CLI、桌面端与 IDE 的任务和状态。可靠数值用量生成 Token 趋势与贡献热力图，选择日期可查看按供应商和模型拆分的输入、输出及总 Token。可在设置查看、导出全部历史为 .xlsx 或清空历史。显示真实账户剩余额度、重置时间和低额度提醒，按可用数据展示 5h/7d 窗口与 Cursor 美元预算；不读取提示词和回答正文。',
        points: ['跨工具查看 AI 任务', '模型历史与 .xlsx 导出', '账户额度与重置时间'],
      },
      keyboardSound: {
        name: '键盘音效',
        caption:
          '为全局按键播放 20 种内置机械键盘音色，可调音量与自然音高变化，并为支持的音色播放回弹音；开启本地输入统计后，可在岛内查看今日概览、输入趋势、历史、应用时间线和含 F1-F12 的逐键热力图。语音输入总量、听写时长、速度和节省时间也集中在键盘信息页。新配置默认启用音效与输入统计，两项可分别关闭。',
        points: ['20 种内置音色', '回弹音与音高变化', '输入统计可单独开关'],
      },
      download: {
        name: '下载器',
        caption:
          '粘贴链接，或在开启后从剪贴板识别链接；可选择可用的视频或音频格式，抖音下载需要时可使用已安装浏览器的 Cookies。下载到默认或自选目录时，显示来源图标、实时进度和完成状态。在「设置 → 保存位置」单独选择下载目录，截图与录屏各用独立目录。Bilibili 链接按所选分 P 下载。',
        points: ['选择视频或音频格式', '抖音浏览器 Cookies', '来源图标与实时进度'],
      },
      agenda: {
        name: '日程与天气',
        caption:
          '查看当前位置及最多 6 个自选地点的天气，查看、新增、删除日历事件和提醒，并标记提醒完成。有会议链接的事件会在开始前 10 分钟显示倒计时，可一键加入；支持新建会议便签，或关联、解除关联已有位置便签。',
        points: ['天气与日历', '会前 10 分钟倒计时', '加入会议与关联便签'],
      },
      mail: {
        name: '邮件',
        caption:
          '读取系统 Mail 中已启用的账户，在岛内查看收件箱、标记单封或全部收件箱邮件已读、回复、撰写并移到废纸篓。撰写时可选择附件；缺少权限时提供明确指引。',
        points: ['Mail.app 账户', '岛内回复与撰写', '权限指引透明'],
      },
      quickNotes: {
        name: '随记',
        caption:
          '以系统「备忘录」为数据源，支持查看、编辑、新建和删除笔记，以及 Markdown 实时预览，并可用 Command+1 到 9 直接切换前九条笔记；草稿会自动写回备忘录。可预览手写附件，并编辑其前后文字，保留原始附件。',
        points: ['数据来自备忘录', 'Markdown 编辑器', '草稿自动写回'],
      },
      volumeMixer: {
        name: '应用音量混音器',
        caption: '分别调节正在播放声音的应用音量，或单独静音。需要 macOS 14.4 或更高版本，以及系统音频录制权限。',
        points: ['各应用独立音量', '单独静音', 'macOS 14.4+'],
      },
      toolbox: {
        name: '小工具',
        caption:
          '专注倒计时、保持屏幕常亮、屏幕清洁、键盘清洁（运行时屏蔽包括 F1-F12 的按键）、提词器、镜子与废纸篓集中在一页。横向和竖向紧凑布局均可暂停、继续、重置番茄钟并查看进度。',
        points: ['专注倒计时', '清理时屏蔽 F1-F12', '提词器与镜子'],
      },
      system: {
        name: '系统状态',
        caption:
          '监控 CPU、GPU、内存、磁盘、网络、风扇及可用的 NVMe SMART 温度；在设置查看任意日期范围的分钟级历史、导出 .xlsx 或清空记录。查看电池健康、循环次数、温度、容量、周边设备电量及公网 IPv4/IPv6。可按插电或电池供电自动切换电源模式，并选择在电量不高于 20% 时使用低电量模式；macOS 提供该选项时可立即充至 100%。缓存、日志、偏好残留和孤立 AI 工作区可先检查再移到废纸篓，也可按 7、15 或 30 天定时清理。定时清理默认关闭，可选仅可信项目或全部可操作项目（包括需要复核的项目）。',
        points: ['芯片级监控', '历史图表与 .xlsx 导出', '复核后移入废纸篓'],
      },
    },
  },
  extensions: {
    eyebrow: '灵动岛内外',
    title: '离开灵动岛，<span>仍有桌面能力。</span>',
    lede: '截图、图片与音频工具、语音、媒体、浏览器下载与 AI 管理，按各自最顺手的方式出现。',
    ariaLabel: '独立桌面能力',
    summaryMono: '灵动岛之外',
    summaryLede: '常用能力，各在最顺手的位置。',
    summaryNote: '窗口预览、截图与快捷操作各在最顺手的位置，推荐应用帮你发现更多桌面工具。',
    features: {
      floatingIsland: {
        title: '浮岛随布局调整',
        description: '可使用摄像头位置，或在屏幕边缘选择自定义位置；切换模式后保留自定义位置。横向与竖向紧凑布局会按状态图标、AI 任务、下载和媒体调整长度，并可开启更多信息。可在「设置 → 信息」拖动调整岛内功能顺序，或恢复默认顺序。',
        detail: '自定义位置 · 常驻状态图标 · 信息自适应',
      },
      dailyBriefing: {
        title: '每日简报',
        description: '从 8 种模板中选择样式，勾选使用时间、输入、系统与 zisla 活动数据，并预览版式。可手动或在设定时间导出 PNG；开启后按可用情况读取系统屏幕使用时间历史，不把缺失数据当作实测零值。导出目录可在「设置 → 保存位置」单独选择。也可选择加入真实账户剩余额度与采样时间。',
        detail: '8 种模板 · 自选内容 · 预览与定时 PNG 导出',
      },
      userCare: {
        title: '工作中的关怀提醒',
        description: '设置休息、喝水、活动和护眼提醒间隔，提示会结合一天中的时段。自然休息、锁屏与睡眠后重置计时；专注完成和便签操作也可在岛内显示简短反馈。可在设置中开关。',
        detail: '自定义间隔 · 结合时段 · 尊重空闲与睡眠',
      },
      contextNotes: {
        title: '跟随位置的便签',
        description: '为网页、应用窗口或桌面保存可编辑便签，回到对应位置时显示。可附上应用窗口截图，在中转站管理，并设置每 1 小时至每 3 天的重复提醒，也可关闭提醒。',
        detail: '位置便签 · 窗口截图 · 重复提醒',
      },
      recording: {
        title: '录屏与剪辑工作室',
        description: '录制显示器、窗口或区域，可选系统音频、麦克风和相机。在多轨时间线上编辑视频、音频、图片与文字，添加动画、缩放和字幕。可调磨皮、提亮、瘦脸、瘦身与美声效果，添加自选颜色的平滑光标轨迹，并在工作室播放剪辑结果。画幅支持原始、16:9、9:16、1:1 和 4:3；导出视频、GIF、Live Photo 或音频，部分格式需要 FFmpeg。可选 AI 剪辑先预览方案再应用。录屏目录在「设置 → 保存位置」独立设置。',
        detail: '人像与美声效果 · 自选颜色光标轨迹 · 多轨播放与导出',
      },
      permissions: {
        title: '集中管理系统权限',
        description: '在「设置 → 权限」查看授权状态、发起支持的请求，或打开对应系统设置页。首次欢迎页复用同一权限列表，并标明需要手动配置的权限。',
        detail: '授权状态 · 请求与系统设置 · 欢迎页共用',
      },
      imageTools: {
        title: '图片工具',
        description: '在设置中使用 9 类本地工具：压缩；转换 PNG、JPEG、WebP、AVIF、JPEG XL；缩放裁剪；比较最小格式；旋转镜像；水印；马赛克与模糊；文字和表格识别；抠图。可批量导出或打包 ZIP，并在「设置 → 保存位置」单独选择图片工具目录。',
        detail: '9 类本地工具 · 五种格式 · 批量与 ZIP 导出',
      },
      audioTools: {
        title: '音频工具',
        description: '在设置中使用 27 类本地操作，包括转换、压缩、裁剪、分段、拼接与混音、从视频提取音轨、LUFS 响度标准化、淡入淡出、变速变调、降噪与移除静音、均衡器、动态、声道和标签处理。需要 FFmpeg 与 ffprobe；导出时可选择文件或目录。',
        detail: '27 类本地操作 · 编辑与混音 · FFmpeg 与 ffprobe',
      },
      pdf: {
        title: 'PDF 工具',
        description: '入口位于设置，不占用灵动岛模块轮播。在本机完成 PDF 合并、拆分、旋转、裁剪、图片/Office 转换、渲染为图片、导出文字、文字/图片水印、页码、加密、解除密码和元数据编辑等 14 项操作。',
        detail: '14 种本机工具 · 按顺序合并 · 全程不出本机',
      },

      windowPreviews: {
        title: '窗口预览，点击即切换',
        description:
          '从 Dock 或 Command-Tab 切换时预览窗口，点击卡片即可激活对应窗口。新配置默认启用，可在设置中调整功能和相关权限。',
        detail: 'Dock 与 Command-Tab · 点击切换窗口 · 设置中可调整',
      },
      capture: {
        title: '截图、长截图与钉图',
        description:
          '使用可自定义的快捷键截图、钉图或拼接长截图。支持高亮、图像区域提取、圆角和保留编辑中的标注；可识别并复制文字、翻译后复制结果，或识别表格并导出 .xlsx。截图可暂存到中转站，快捷键设置会检查语音输入和快捷操作冲突。保存对话框从「设置 → 保存位置」中的独立截图目录打开。再次截图时保留已钉住的截图。长截图可使用慢速自动滚动，支持的设备可截取 HDR 画面。',
        detail: '高亮与提取 · 识别、翻译并复制 · 圆角与 .xlsx',
      },
      voice: {
        title: '语音输入与整理',
        description:
          '按键切换或按住说话，使用系统语音识别，配合领域词库和自定义热词。可选用 Ollama、LM Studio 等本地模型或远端模型，在保留原意的基础上纠错，并按需格式化明确列举的事项。',
        detail: '两种录音方式 · 词库与自定义热词 · 可选模型整理',
      },
      media: {
        title: '媒体与系统背景声',
        description:
          '在灵动岛顶部控制正在播放，也可选择 macOS 系统背景声；锁屏、屏保或显示器休眠时可自动关闭。可选择音浪或封面光晕；紧凑与浮岛布局也显示播放进度。',
        detail: '播放控制 · 歌词同步 · 自动停止背景声',
      },
      browserDownloads: {
        title: '浏览器下载进度',
        description:
          '识别 Safari、Chrome、Edge、Firefox、Brave、Vivaldi、Opera 与 Arc 的下载，在顶部显示来源和实时进度。',
        detail: '8 种浏览器 · 来源识别 · 完成提示',
      },
      copyAssistant: {
        title: '快捷操作与智能下一步',
        description:
          '启用后，复制文本、链接、文件或图片会在独立的顶部提示条中预览；可识别链接、本机已安装应用名称和 Emoji 名称，也可按实时汇率换算复制的金额，所有下一步均由你确认后执行。浏览器下载或 AirDrop 接收完成后，通过快捷操作打开文件所在文件夹。支持 Chrome 的默认与自选下载目录，可独立于下载进度显示启用。IP 地址提供独立的查询与打开链接操作；货币换算支持本地最小货币单位，表情目录更新至 Emoji 18.0。保存的文字与图片使用「设置 → 保存位置」中的独立快捷操作目录。应用无法打开时，快捷操作可先检查完整性、签名和 macOS 安全策略，通过检查后移除隔离标记并打开。',
        detail: '本机识别 · 实时汇率换算 · 默认 Command+N',
      },
      aiManagement: {
        title: 'AI CLI 与 Skills 管理',
        description:
          '在设置中检测、安装、更新和卸载常用 AI CLI，并查看和管理本机 Skills，减少在多个终端和工具之间切换。',
        detail: '检测与安装 · 更新与卸载 · 本机 Skills',
      },
      pet: {
        title: '灵动岛宠物',
        description: '从扩充后的动物和角色目录选择宠物，或将系统支持的图片、动图和视频导入并命名。可放在岛的任意一侧，也可在设置中删除自定义宠物。导入动画最长 30 秒，文件最大 100 MB。',
        detail: '扩充宠物目录 · 图片与视频导入 · 删除自定义宠物',
      },
      lockScreen: {
        title: '锁屏信息',
        description:
          '按需在 macOS 锁屏界面显示日期、状态与正在播放信息；它是独立锁屏叠层，不会出现在灵动岛的模块列表或轮播中。',
        detail: '独立锁屏叠层 · 按需开启 · 不抢焦点',
      },
      recommendedTools: {
        title: '推荐应用',
        description:
          '发现 OpenScreen（录屏与视频编辑）、DockDoor（窗口预览与应用切换）和 Quiet.md（本地笔记）等桌面工具，均为单独安装的第三方应用。',
        detail: '发现桌面工具 · 第三方应用 · 单独安装',
      },
    },
  },
  ai: {
    eyebrow: '没有黑箱的 AI',
    title: '看见 AI 状态，<span>不读取对话。</span>',
    lede: '按应用查看任务，按日期查看模型用量，并查询真实账户剩余额度。状态和数值记录留在本机，不读取对话正文。',
    summaryMono: '本机状态 / 明确边界',
    summaryLede: '不同 Harness，同一个状态入口。',
    summaryNote: 'WorkBuddy 与 WorkBuddy AI 独立识别，保留各自的会话、品牌和打开入口，不混为一个产品。',
    toolsHeading: '{tools} 个 AI 工具与 Harness',
    toolsLede: '自动检测受支持的 CLI、桌面端与 IDE 活动；Delta、Orca、WorkBuddy 和 WorkBuddy AI 均保留独立名称。',
    toolsAriaLabel: '支持的 AI 工具与 Harness',
    usageNote: '会话检测、Token 历史和账户额度各有数据来源。Delta 使用本机数值账本，Orca 复用绑定 CLI 的用量并去重，按底层供应商归属。WorkBuddy AI 可检测会话并查询 credits；上下文占用和 credits 不换算为 Token 或美元费用。额度查询能力取决于供应商与登录方式。',
    boundariesHeading: '只记录状态边界',
    privacyPoints: [
      '只解析状态元数据（含会话标题、时间、模型和会话标识）及可靠的数值用量',
      '不解析提示词或回答正文，也不上传对话',
      '第三方会话存储只读访问；协议、状态与用量记录留在本机',
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
    copy: '适用于 Apple 芯片 Mac；版本、其他架构与校验信息均在 Release 页面。安装后可按更新通道检查新版本，Sparkle 会先验证签名，再按设置手动或自动下载、安装并重启，更新会保留已授予的权限；更新设置也提供直达问题反馈的入口。若对某个版本不感兴趣，可以跳过，zisla 不会再提醒。安装更新前和重启后均可查看更新说明。',
    primaryCta: '下载',
    primaryCtaAriaLabel: '下载',
    releaseCta: '查看 Release',
    releaseCtaAriaLabel: '在 GitHub 上查看发布详情',
    brewMono: 'HOMEBREW / 一条命令',
    brewNote: 'zisla 由 Sparkle 自行更新，因此 brew upgrade 只在已装应用确实旧于 tap 中的版本时才替换它——Homebrew 5.1.6 起会读取应用自身的版本号。显式指定 cask（brew upgrade --cask zisla）依据的是 Homebrew 自己的安装记录，在 Sparkle 更新过之后可能把应用退回 tap 的版本。tap 只提供正式版。该 tap 属于第三方，应用也未经公证，首次打开需在“系统设置 → 隐私与安全性”中选择“仍要打开”。',
    copyBrewCommandAriaLabel: '复制 Homebrew 安装命令',
    notes: {
      system: { term: '系统', value: 'macOS 14 或更高版本 · 当前受支持配置为 Apple 芯片 Mac' },
      install: { term: '安装', value: '挂载 DMG 后拖入 Applications' },
      package: { term: '包体', value: 'Apple Silicon (arm64) · DMG' },
      architectures: { term: '其他架构', value: 'Release 页面' },
      mirror: { term: '镜像', value: 'Gitee Releases' },
    },
  },
  changelog: {
    releaseNotes: {
      'v0.1.22': [
        '录屏工作室新增磨皮、提亮、瘦脸、瘦身、可调美声预设与可选麦克风监听，可在录制设置和剪辑中调整效果。',
        '平滑光标轨迹可自选颜色；工作室播放包含各轨道、效果与音频的剪辑结果。',
        '「设置 → 保存位置」分别管理下载、截图、录屏、快捷操作和每日简报目录；升级保留原有位置，之后可独立更改。',
        '系统垃圾可选每 7、15 或 30 天自动移入废纸篓，范围可选可信项目或全部可操作项目（含需人工复核项），默认关闭。磁盘清理新增无保留会话关联的 AI 工作目录复核，保护保留会话与新建工作目录。',
        '剪贴板历史可自动删除超过 7、15 或 30 天的记录，保留常用项；默认不自动删除。',
        '随记支持预览手写附件，并通过系统备忘录编辑其前后文字，保留原始附件。',
        'AI 监控隐藏剩余订阅额度，保留每日用量，并改善图表滚动和月份标签。电池监控设置集中到系统状态。',
        'Quiet.md 加入桌面推荐应用，可在设置中安装和管理，用于本地笔记。',
        'Bilibili 下载按所选分 P 获取视频并支持更多链接格式；日历删除定位到所选重复事件。多次截图保留已钉住的截图，并改善工具属性标签和尺寸标识的可靠性。',
      ],
      'v0.1.21': [
        '系统监控的分钟级历史默认保留全部已有与新增记录，直到手动清空；仍可按任意时间范围查看图表并导出 .xlsx。',
        '下载、录屏与截图共用保存位置。截图保存对话框从当前下载目录打开，录屏不再提供重复的保存位置设置。',
        '仅自定义位置的胶囊布局显示「状态显示位置」及其搜索入口；刘海布局和相机位置胶囊只有菜单栏这一目的地时隐藏整行。',
        '刘海布局的快捷操作倒计时沿底部进度条显示；胶囊布局保留完整周边进度。',
      ],
      'v0.1.20': [
        '每日简报提供 8 种模板，可自选使用时间、输入、系统与 zisla 活动内容，预览并手动或定时导出本地 PNG；系统屏幕使用时间历史仅在开启且可用时纳入。',
        '上下文关怀支持自定义间隔、结合时段的提醒，以及专注和便签操作反馈；空闲、锁屏与睡眠后重置计时。位置便签可附应用窗口截图，并设置每 1 小时至每 3 天的重复提醒。',
        '浮岛支持记住自定义位置、横向与竖向紧凑布局自适应、常驻状态图标和更多信息模式；媒体新增音浪与封面光晕样式，各布局均可显示播放进度。',
        '宠物目录扩充动物和角色；支持导入并命名图片、动图和视频宠物，以及删除自定义宠物。动画最长 30 秒，源文件最大 100 MB。',
        '录屏工作室可录制显示器、窗口或区域，并选用系统音频、麦克风和相机。多轨视频、音频、图片与文字编辑支持动画、字幕、缩放、更清晰的预览和 5 种画幅，可导出视频、GIF、Live Photo 与音频；可选 AI 方案预览后由你应用。',
        '截图新增高亮、区域提取和圆角；文字识别可直接复制，或翻译后复制，表格识别可导出 .xlsx。截图与录屏可靠性得到修正，包括录制音频保留。',
        'AI 监控新增 Cursor 任务检测，以及 Cursor 与 Muse Code 数值用量和可获取的订阅额度；Cursor 长工具任务持续显示。剪贴板 IP 查询与打开链接分离，货币识别支持最小单位，表情名称更新至 Emoji 18.0。',
        '灵动岛增加应用音量与静音控制，PDF 工具移至设置，电池信息并入系统状态；权限集中至设置。新配置默认开启键盘音效、输入统计、窗口预览与关怀，语音总量显示在键盘信息页；邮件可选择文件作附件，更新安装前和重启后可查看说明。',
      ],
    },
    eyebrow: '更新日志',
    title: '每个 zisla 版本的变化：新功能、改进与修复。',
    lede: '每个 zisla 版本的变化：新功能、改进与修复。',
    ariaLabel: 'zisla 发布记录',
    releaseCountLabel: '个版本',
    latestLabel: '最新',
    shippedLabel: '已发布',
    latestBadge: '最新',
    noteLabel: '版本',
    pagerAriaLabel: '更新日志分页',
    pageLabel: '第 {page} 页',
    prevPageLabel: '上一页',
    nextPageLabel: '下一页',
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
        question: '快捷操作会自动打开或上传我复制的内容吗？',
        answer:
          '不会。启用后，内容识别和预览均在本机完成；只有你点击动作或按下快速触发后，zisla 才会执行对应下一步。',
      },
      permissions: {
        question: 'zisla 需要哪些系统权限？',
        answer: '<p>「设置 → 权限」集中显示系统权限状态、授权请求和系统设置入口。部分权限需要手动配置；由你选择发起哪些请求，首次欢迎页也提供权限入口。</p><p>屏幕录制、系统音频录制、麦克风和相机分别用于截图、录屏、混音器、镜像等对应功能；语音输入还使用语音识别。日历、提醒事项、定位、蓝牙和自动化用于相关功能，手动添加天气城市无需定位权限。</p><p>新配置默认启用键盘音效和输入统计，可分别关闭。全局键盘事件需要输入监控；统计只保存次数、键码、时间和应用名称，不保存输入正文。辅助功能用于文本插入、手势、清洁与窗口控制。</p><p>读取本地邮件索引和每日简报使用的系统屏幕使用时间历史可能需要完全磁盘访问。系统文件选择器授予的是所选文件夹的访问权限。可在 zisla 中关闭功能，或在「系统设置 → 隐私与安全性」撤销权限。</p>',
      },
      localVoice: {
        question: '如何用本地模型整理语音？',
        answer: `
      <p>支持 Ollama、LM Studio 及其他 OpenAI 兼容的本地服务。</p>
      <ol>
        <li>先在本地模型应用中下载或加载要使用的模型，并启动服务。</li>
        <li>打开“设置 → 语音 → 本地模型”，添加并启用配置，选择 Ollama 或 LM Studio，填写服务地址。其他 OpenAI 兼容服务也选择 LM Studio；未启用认证时，API Key 可留空。</li>
        <li>从自动发现的模型中选择一个，再到“语音整理模型 → 使用模型”选择该配置。</li>
      </ol>
      <p>zisla 会按芯片和整机内存给出 Gemma 4 QAT 建议；不会自动下载或加载推荐模型。</p>
    `.trim(),
      },
      network: {
        question: 'zisla 会联网吗？',
        answer:
          '天气、签名更新检查、主动下载和可选远端语音整理会按需联网；剪贴板链接检测只在本机识别，不会自行发起下载。本地模型负责转写后的文字整理；Apple 语音识别仍可能联网，取决于语言和系统支持。',
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
          '本地数据位于 ~/Library/Application Support/zisla/；键盘输入统计单独保存在 ~/Library/Application Support/zisla/typing-stats.sqlite3；随记使用系统「备忘录」。「设置 → 保存位置」分别管理下载、截图、录屏、快捷操作和每日简报的目录。升级时各项保留原共享目录，之后可独立更改。',
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
  film: {
    title: "宣传片",
    videoAriaLabel: "zisla 宣传片",
    openVideoLabel: "打开视频",
    playbackError: "无法播放视频。",
    musicLabel: "音乐",
    excerptLabel: "节选",
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
