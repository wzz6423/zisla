import {
  Archive,
  ArrowDown,
  ArrowDownToLine,
  ArrowUpRight,
  CalendarDays,
  ChartLine,
  Check,
  ChevronDown,
  CircleCheck,
  Clipboard,
  ClipboardPaste,
  Code2,
  Copy,
  Cpu,
  Download,
  ExternalLink,
  Film,
  Folder,
  Gauge,
  Inbox,
  LayoutDashboard,
  Link,
  Menu,
  Pin,
  Plus,
  ScanText,
  Settings,
  ShieldCheck,
  Sparkles,
  StickyNote,
  Volume2,
  Wrench,
  X,
  createIcons,
} from 'lucide';
import {
  aiWorkflowFeatures,
  coreFeatures,
  dailyInfoFeatures,
  developmentSetup,
  documentationLinks,
  downloadLinks,
  faqItems,
  latestRelease,
  license,
  navItems,
  performanceFeatures,
  productDescription,
  productTagline,
  repositoryLinks,
  supportedAITools,
  systemRequirements,
  topWorkflowFeatures,
  utilityFeatures,
} from './content';
import './styles.css';

const app = document.querySelector<HTMLDivElement>('#app');

if (!app) {
  throw new Error('找不到官网挂载节点');
}

const icon = (name: string, size = 16) =>
  `<i data-lucide="${name}" width="${size}" height="${size}" aria-hidden="true"></i>`;

const siteIcons = {
  Archive,
  ArrowDown,
  ArrowDownToLine,
  ArrowUpRight,
  CalendarDays,
  ChartLine,
  Check,
  ChevronDown,
  CircleCheck,
  Clipboard,
  ClipboardPaste,
  Code2,
  Copy,
  Cpu,
  Download,
  ExternalLink,
  Film,
  Folder,
  Gauge,
  Inbox,
  LayoutDashboard,
  Link,
  Menu,
  Pin,
  Plus,
  ScanText,
  Settings,
  ShieldCheck,
  Sparkles,
  StickyNote,
  Volume2,
  Wrench,
  X,
};

const capabilityRows = [
  {
    index: '工作流',
    title: coreFeatures[1]?.title ?? '工作流集中在桌面顶部',
    description: coreFeatures[1]?.description ?? '',
    tags: topWorkflowFeatures.slice(0, 4).map((feature) => feature.title),
  },
  {
    index: 'AI 状态',
    title: coreFeatures[2]?.title ?? '看见 AI 的实际工作状态',
    description: coreFeatures[2]?.description ?? '',
    tags: aiWorkflowFeatures.slice(0, 3).map((feature) => feature.title),
  },
  {
    index: '日常信息',
    title: '把时间、天气和随记留在同一处',
    description: dailyInfoFeatures[0]?.description ?? '',
    tags: dailyInfoFeatures.slice(0, 4).map((feature) => feature.title),
  },
  {
    index: '实用工具',
    title: '需要时，工具就在手边',
    description: utilityFeatures[0]?.description ?? '',
    tags: utilityFeatures.map((feature) => feature.title),
  },
];

const workflowRail = [...topWorkflowFeatures.slice(0, 3), ...utilityFeatures.slice(1, 3)];

const capabilityMarkup = capabilityRows
  .map(
    (row, index) => `
      <article class="capability-row reveal">
        <div class="capability-index">0${index + 1} / ${row.index}</div>
        <h3 class="capability-name">${row.title}</h3>
        <div>
          <p class="capability-copy">${row.description}</p>
          <div class="capability-tags">
            ${row.tags.map((tag) => `<span class="capability-tag">${tag}</span>`).join('')}
          </div>
        </div>
      </article>
    `,
  )
  .join('');

const workflowMarkup = workflowRail
  .map(
    (feature) => `
      <article class="feature-rail-item reveal">
        <span class="mono-label">${feature.title}</span>
        <p>${feature.description}</p>
      </article>
    `,
  )
  .join('');

const toolMarkup = supportedAITools
  .map(
    (tool) => `
      <span class="tool-chip"><span class="tool-chip-dot"></span>${tool.name}</span>
    `,
  )
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
      </a>
    `,
  )
  .join('');

const faqMarkup = faqItems
  .map(
    (item) => `
      <details class="faq-item reveal">
        <summary>${item.question}${icon('plus', 18)}</summary>
        <div class="faq-answer">${item.answer}</div>
      </details>
    `,
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
        <button class="menu-toggle" type="button" aria-label="打开导航" aria-expanded="false" title="打开导航">${icon('menu', 18)}</button>
        <nav class="nav" aria-label="主导航">
          ${navItems
            .map((item) => `<a class="nav-link" href="${item.href}">${item.label}</a>`)
            .join('')}
          <a class="header-cta" href="#download">下载 ${latestRelease.version}${icon('arrow-down-to-line', 14)}</a>
        </nav>
      </header>

      <div class="section-wrap hero-inner">
        <div class="hero-copy">
          <p class="eyebrow">NATIVE MACOS WORKSPACE / ${latestRelease.version}</p>
          <h1 class="hero-title">把正在发生的事，放到你<em>看得见</em>的地方。</h1>
          <p class="hero-lede">${productDescription}</p>
          <div class="hero-actions">
            <a class="button button-primary" href="${latestRelease.dmg}" download>${icon('download', 16)}下载 macOS DMG</a>
          </div>
        </div>

        <div class="workspace-window" role="img" aria-label="zisla 顶部工作台的下载模块界面">
          <div class="window-stage">
            <div class="desktop-strip"><span>zisla</span><span id="demoClock">--:--</span></div>
            <div class="product-island">
              <div class="product-crown">
                <div class="product-status">
                  <span class="product-status-icon">${icon('calendar-days', 16)}</span>
                  <span class="product-status-copy"><strong id="heroDate">--</strong></span>
                  <strong class="product-clock" id="islandClock">--:--</strong>
                </div>
                <div class="product-tools" aria-label="产品模块工具栏">
                  <span class="product-tool" title="首页">${icon('layout-dashboard', 13)}</span>
                  <span class="product-tool" title="中转">${icon('inbox', 13)}</span>
                  <span class="product-tool" title="AI 监控">${icon('chart-line', 13)}</span>
                  <span class="product-tool" title="AI Agent">${icon('sparkles', 13)}</span>
                  <span class="product-tool is-active" title="下载">${icon('download', 13)}</span>
                  <span class="product-tool" title="日程">${icon('calendar-days', 13)}</span>
                  <span class="product-tool" title="随记">${icon('sticky-note', 13)}</span>
                  <span class="product-tool" title="PDF">${icon('scan-text', 13)}</span>
                  <span class="product-tool" title="小工具">${icon('wrench', 13)}</span>
                  <span class="product-tool" title="系统">${icon('gauge', 13)}</span>
                  <span class="product-tool-spacer"></span>
                  <span class="product-tool product-tool-action" title="固定">${icon('pin', 13)}</span>
                  <span class="product-tool product-tool-action" title="设置">${icon('settings', 13)}</span>
                </div>
              </div>
              <div class="product-module product-download-module">
                <div class="download-url-field">
                  ${icon('link', 14)}
                  <span>视频或音频链接</span>
                  <i class="module-icon-button" title="粘贴">${icon('clipboard-paste', 13)}</i>
                </div>
                <div class="download-module-controls">
                  <div class="download-mode-picker" aria-label="下载类型">
                    <span class="is-selected">${icon('film', 12)}视频</span>
                    <span>${icon('volume-2', 12)}音频</span>
                  </div>
                  <div class="download-folder">${icon('folder', 13)}<span>下载</span>${icon('chevron-down', 10)}</div>
                  <span class="download-module-button is-disabled">${icon('arrow-down', 12)}下载</span>
                </div>
                <div class="download-ready">${icon('circle-check', 13)}<span>准备就绪</span></div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>

    <section class="proof-band" aria-label="产品概览">
      <div class="section-wrap proof-grid">
        <div class="proof-item"><strong>一条顶部入口</strong><span>把常用上下文放在当前工作旁边</span></div>
        <div class="proof-item"><strong>macOS 14+</strong><span>支持 Apple 芯片 Mac</span></div>
        <div class="proof-item"><strong>多显示器</strong><span>刘海屏与外接屏都能使用</span></div>
        <div class="proof-item"><strong>本地优先</strong><span>AI 状态不读取对话正文</span></div>
      </div>
    </section>

    <section class="section" id="features">
      <div class="section-wrap">
        <div class="section-heading reveal">
          <div>
            <p class="eyebrow">A QUIET SURFACE FOR BUSY DAYS</p>
            <h2 class="section-title">常用功能，<span>都在屏幕顶部。</span></h2>
          </div>
          <p class="section-lede">媒体、文件、AI、日程和系统工具，按需开启。</p>
        </div>
        <div class="capability-list">${capabilityMarkup}</div>
        <div class="feature-rail">${workflowMarkup}</div>
      </div>
    </section>

    <section class="section dark-section" id="ai">
      <div class="section-wrap signal-layout">
        <div class="signal-panel reveal" aria-label="zisla AI 监控模块空状态界面">
          <div class="ai-monitor-preview">
            <div class="running-pane">
              <div class="pane-title"><span>${icon('cpu', 13)}运行任务</span><b>0</b></div>
              <div class="empty-state">${icon('circle-check', 25)}<span>暂无活动任务</span></div>
            </div>
            <div class="usage-pane">
              <div class="pane-title"><span>${icon('chart-line', 13)}Token 消耗趋势</span></div>
              <div class="usage-empty-state">${icon('chart-line', 25)}<span>暂无 Token 用量</span></div>
              <div class="empty-usage-heatmap" aria-hidden="true">
                ${Array.from({ length: 168 }, () => '<i></i>').join('')}
              </div>
            </div>
          </div>
        </div>
        <div class="signal-copy">
          <p class="eyebrow">AI WITHOUT THE BLACK BOX</p>
          <h2 class="section-title">看见 AI 状态，<span>不读取对话。</span></h2>
          <p>查看任务、进度和 Token 趋势，数据留在本机。</p>
          <div class="tool-list" aria-label="支持的 AI 工具">${toolMarkup}</div>
          <div class="privacy-line">${icon('shield-check', 18)}<span>只读取任务状态，不读取提示词或回答正文。</span></div>
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
          <article class="flow-step reveal"><span class="flow-step-number">01 / 触发</span><h3>移到屏幕顶部中央</h3><p>刘海屏和外接屏使用同样的触发方式。</p></article>
          <article class="flow-step reveal"><span class="flow-step-number">02 / 查看</span><h3>看一眼当前状态</h3><p>媒体、文件、AI 和日程集中显示。</p></article>
          <article class="flow-step reveal"><span class="flow-step-number">03 / 收起</span><h3>继续手上的工作</h3><p>移开鼠标后自动收起，模块可独立开关。</p></article>
        </div>
      </div>
    </section>

    <section class="download-section" id="download">
      <div class="section-wrap download-layout">
        <div>
          <p class="eyebrow">READY WHEN YOU ARE</p>
          <h2 class="download-title">下载 zisla。</h2>
          <p class="download-copy">${latestRelease.version} · macOS Universal · DMG / ZIP</p>
          <div class="download-actions">
            <a class="button button-light" href="${latestRelease.dmg}" download>${icon('download', 16)}下载 DMG</a>
            <a class="button button-ghost" href="${latestRelease.zip}" download>${icon('archive', 16)}下载 ZIP</a>
            <a class="button button-ghost" href="${latestRelease.releasePage}" target="_blank" rel="noreferrer">${icon('external-link', 16)}查看 Release</a>
          </div>
        </div>
        <dl class="download-notes">
          <div class="download-note"><dt>系统</dt><dd>${systemRequirements.os} · ${systemRequirements.platform}</dd></div>
          <div class="download-note"><dt>安装</dt><dd>挂载 DMG 后拖入 Applications</dd></div>
          <div class="download-note"><dt>包体</dt><dd>Universal · DMG / ZIP · 约 15 MB</dd></div>
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
            <h3>把自己的任务接入顶部状态条。</h3>
            <p>使用 <code>zislactl</code> 上报任务状态、进度和用量，状态文件留在本机。</p>
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

const clockFormatter = new Intl.DateTimeFormat('zh-CN', {
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});

const dateFormatter = new Intl.DateTimeFormat('zh-CN', {
  weekday: 'long',
  month: 'long',
  day: 'numeric',
});

const updateDemoClocks = () => {
  const now = new Date();
  const time = clockFormatter.format(now);
  const date = dateFormatter.format(now);
  document.querySelectorAll<HTMLElement>('#demoClock, #islandClock').forEach((clock) => {
    clock.textContent = time;
  });
  const heroDate = document.querySelector<HTMLElement>('#heroDate');
  if (heroDate) {
    heroDate.textContent = date;
  }
};

updateDemoClocks();
window.setInterval(updateDemoClocks, 30_000);

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

const toast = document.querySelector<HTMLElement>('#toast');
let toastTimer: number | undefined;

const showToast = (message: string) => {
  if (!toast) return;
  toast.textContent = message;
  toast.classList.add('is-visible');
  if (toastTimer) window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => toast.classList.remove('is-visible'), 2400);
};

document.querySelector<HTMLButtonElement>('#copyCommand')?.addEventListener('click', async () => {
  const command = developmentSetup.runCommand;
  try {
    await navigator.clipboard.writeText(command);
    showToast('源码运行命令已复制');
  } catch {
    const temporaryInput = document.createElement('textarea');
    temporaryInput.value = command;
    temporaryInput.setAttribute('readonly', 'true');
    temporaryInput.style.position = 'fixed';
    temporaryInput.style.opacity = '0';
    document.body.append(temporaryInput);
    temporaryInput.select();
    document.execCommand('copy');
    temporaryInput.remove();
    showToast('源码运行命令已复制');
  }
});
