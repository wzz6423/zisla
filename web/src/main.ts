import {
  ArrowDownToLine,
  ArrowUpRight,
  Bot,
  Check,
  Code2,
  Copy,
  Download,
  ExternalLink,
  Image,
  Lock,
  Menu,
  Mic,
  Plus,
  Shield,
  Sparkles,
  Sun,
  Waves,
  X,
  createIcons,
} from 'lucide';
import {
  crossModuleFeatures,
  developmentSetup,
  documentationLinks,
  downloadLinks,
  faqItems,
  flowSteps,
  heroHints,
  heroTitle,
  latestRelease,
  license,
  navItems,
  performanceFeatures,
  privacyPoints,
  productDescription,
  productTagline,
  proofItems,
  repositoryLinks,
  showcaseGroups,
  showcaseModules,
  supportedAITools,
  systemRequirements,
} from './content';
import './styles.css';

const app = document.querySelector<HTMLDivElement>('#app');

if (!app) {
  throw new Error('找不到官网挂载节点');
}

const icon = (name: string, size = 16) =>
  `<i data-lucide="${name}" width="${size}" height="${size}" aria-hidden="true"></i>`;

const siteIcons = {
  ArrowDownToLine,
  ArrowUpRight,
  Bot,
  Check,
  Code2,
  Copy,
  Download,
  ExternalLink,
  Image,
  Lock,
  Menu,
  Mic,
  Plus,
  Shield,
  Sparkles,
  Sun,
  Waves,
  X,
};

const workflowMarkup = showcaseGroups
  .map((group, groupIndex) => {
    const modules = showcaseModules.filter((module) => module.group === group);
    return `
      <section class="workflow-group reveal-sequence">
        <header class="workflow-group-head reveal-step" style="--reveal-index: 0">
          <span class="workflow-group-order">${String(groupIndex + 1).padStart(2, '0')}</span>
          <h3>${group}</h3>
          <span class="workflow-group-count">${modules.length} 个模块</span>
        </header>
        <div class="workflow-module-list">
          ${modules
            .map(
              (module, moduleIndex) => `
                <article class="workflow-module reveal-step" style="--reveal-index: ${moduleIndex + 1}">
                  <span class="workflow-module-order">${String(moduleIndex + 1).padStart(2, '0')}</span>
                  <div class="workflow-module-copy">
                    <h4>${module.name}</h4>
                    <p>${module.caption}</p>
                    <ul class="workflow-points" aria-label="${module.name} 的功能要点">
                      ${module.points.map((point) => `<li>${point}</li>`).join('')}
                    </ul>
                  </div>
                </article>`,
            )
            .join('')}
        </div>
      </section>`;
  })
  .join('');

const toolMarkup = supportedAITools
  .map((tool) => `<span class="tool-chip"><span class="tool-chip-dot"></span>${tool.name}</span>`)
  .join('');

const crossModuleMarkup = crossModuleFeatures
  .map(
    (feature, index) => `
    <article class="extension-item reveal-step" style="--reveal-index: ${index}">
      <header class="extension-item-head">
        <span class="extension-item-order">${String(index + 1).padStart(2, '0')}</span>
        <span class="extension-item-icon">${icon(feature.icon, 18)}</span>
        <h3>${feature.title}</h3>
      </header>
      <p>${feature.description}</p>
      <span class="extension-item-detail">${feature.detail}</span>
    </article>`,
  )
  .join('');

const docsMarkup = documentationLinks
  .slice(0, 4)
  .map(
    (doc, index) => `
    <a class="doc-link reveal-step" style="--reveal-index: ${index}" href="${doc.url}" target="_blank" rel="noreferrer">
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
          <a class="header-cta" href="#download" aria-label="跳转到下载区域">下载${icon('arrow-down-to-line', 14)}</a>
        </nav>
      </header>

      <div class="section-wrap hero-inner">
        <div class="hero-copy">
          <p class="eyebrow">NATIVE MACOS WORKSPACE</p>
          <h1 class="hero-title">${heroTitle}</h1>
          <p class="hero-lede">${productDescription}</p>
          <div class="hero-actions">
            <a class="button button-primary" href="${latestRelease.dmg}" download aria-label="下载">${icon('download', 16)}下载</a>
            <a class="button button-ghost" href="${repositoryLinks.github}" target="_blank" rel="noreferrer" aria-label="在 GitHub 上查看 zisla 源代码">${icon('code-2', 15)}查看源码</a>
          </div>
          <ul class="hero-hints">
            ${heroHints.map((hint) => `<li>${icon('check', 13)}<span>${hint}</span></li>`).join('')}
          </ul>
        </div>

        <div class="hero-identity" aria-hidden="true">
          <span class="hero-identity-rule"></span>
          <img class="hero-identity-mark" src="./assets/zisla-icon.png" alt="" />
          <span class="hero-identity-caption">TOP OF SCREEN</span>
        </div>
      </div>
    </section>

    <section class="proof-band" aria-label="产品概览">
      <div class="section-wrap proof-grid reveal-sequence">
        ${proofItems
          .map(
            (item, index) =>
              `<div class="proof-item reveal-step" style="--reveal-index: ${index}"><strong>${item.title}</strong><span>${item.desc}</span></div>`,
          )
          .join('')}
      </div>
    </section>

    <section class="section" id="showcase">
      <div class="section-wrap">
        <div class="section-heading reveal">
          <div>
            <p class="eyebrow">ONE PLACE / EVERYDAY FLOW</p>
            <h2 class="section-title">常用工作流，<span>留在屏幕顶部。</span></h2>
          </div>
          <p class="section-lede">从 AI 任务到剪贴板、日程与系统状态，zisla 把分散的桌面工作流收进同一个入口。</p>
        </div>
        <div class="workflow-overview" aria-label="zisla 功能目录">
          <aside class="workflow-summary reveal">
            <span class="mono-label">${showcaseModules.length} MODULES / ${showcaseGroups.length} WORKFLOWS</span>
            <p>从顶部工作流到本地工具，实际能完成的任务都在这里逐项写清。</p>
            <span>${showcaseModules.length} 个顶部模块 + ${crossModuleFeatures.length} 项独立能力，覆盖截图、语音、媒体、下载、复制助手、AI 管理、宠物与锁屏。</span>
          </aside>
          <div class="workflow-groups">${workflowMarkup}</div>
        </div>
      </div>
    </section>

    <section class="section extensions-section" id="capabilities">
      <div class="section-wrap">
        <div class="section-heading reveal">
          <div>
            <p class="eyebrow">ISLAND AND BEYOND</p>
            <h2 class="section-title">离开灵动岛，<span>仍有桌面能力。</span></h2>
          </div>
          <p class="section-lede">截图、语音、媒体、浏览器下载与 AI 管理按各自最顺手的方式出现。</p>
        </div>
        <div class="extension-overview" aria-label="独立桌面能力">
          <aside class="extension-summary reveal">
            <span class="mono-label">BEYOND THE ISLAND</span>
            <p>常用能力，各在最顺手的位置。</p>
            <span>截图、录音、媒体、浏览器下载、复制助手、AI 管理、宠物与锁屏各自独立呈现。</span>
          </aside>
          <div class="extension-list reveal-sequence">${crossModuleMarkup}</div>
        </div>
      </div>
    </section>

    <section class="section ai-section" id="ai">
      <div class="section-wrap">
        <div class="section-heading reveal">
          <div>
            <p class="eyebrow">AI WITHOUT THE BLACK BOX</p>
            <h2 class="section-title">看见 AI 状态，<span>不读取对话。</span></h2>
          </div>
          <p class="section-lede">任务、状态和 Token 趋势留在本机；页面只说明能力，不虚构运行中的任务画面。</p>
        </div>
        <div class="ai-overview">
          <aside class="ai-summary reveal">
            <span class="mono-label">LOCAL STATUS / EXPLICIT BOUNDARIES</span>
            <p>接入常用 AI 工具，保留当前工作需要的上下文边界。</p>
            <span>页面只说明检测范围、数据边界和接入方式，不模拟正在运行的会话。</span>
          </aside>
          <div class="ai-detail-list reveal-sequence">
            <article class="ai-detail reveal-step" style="--reveal-index: 0">
              <span class="ai-detail-order">01</span>
              <div>
                <h3>支持的 AI 工具</h3>
                <p>自动识别受支持的 CLI、桌面端与 IDE 活动，并聚合任务状态。</p>
                <div class="tool-list" aria-label="支持的 AI 工具">${toolMarkup}</div>
              </div>
            </article>
            <article class="ai-detail reveal-step" style="--reveal-index: 1">
              <span class="ai-detail-order">02</span>
              <div>
                <h3>只记录状态边界</h3>
                <ul class="privacy-list">
                  ${privacyPoints
                    .map((point) => `<li>${icon('shield', 15)}<span>${point}</span></li>`)
                    .join('')}
                </ul>
              </div>
            </article>
            <article class="ai-detail reveal-step" style="--reveal-index: 2">
              <span class="ai-detail-order">03</span>
              <div>
                <h3>接入你自己的任务</h3>
                <p>通过 zislactl 将外部任务的结构化状态送入顶部状态条。</p>
                <div class="command-box"><code>${developmentSetup.zislactlCommand}</code><button id="copyZislactl" type="button" aria-label="复制 zislactl 命令" title="复制命令">${icon('copy', 15)}</button></div>
              </div>
            </article>
          </div>
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
        <div class="flow-overview" aria-label="顶部交互节奏">
          <aside class="flow-summary reveal">
            <span class="mono-label">TOP BAR / 3 STEPS</span>
            <p>需要时展开，阅读完成后收回。</p>
            <span>由鼠标位置触发；无操作时不占用视觉空间，也不抢走当前应用焦点。</span>
          </aside>
          <ol class="flow-list reveal-sequence">
            ${flowSteps
              .map(
                (step, index) => `
            <li class="flow-step reveal-step" style="--reveal-index: ${index}">
              <span class="flow-step-number">${step.step}</span>
              <div>
                <h3>${step.title}</h3>
                <p>${step.desc}</p>
              </div>
            </li>`,
              )
              .join('')}
          </ol>
        </div>
      </div>
    </section>

    <section class="download-section" id="download">
      <div class="section-wrap download-layout reveal-sequence">
        <div class="download-copy-block reveal-step" style="--reveal-index: 0">
          <p class="eyebrow">READY WHEN YOU ARE</p>
          <h2 class="download-title">下载 zisla</h2>
          <p class="download-copy">适用于 Apple 芯片 Mac；版本、其他架构与校验信息均在 Release 页面。安装后可按更新通道检查新版本，Sparkle 会先验证签名，再按设置手动或自动下载、安装并重启。</p>
          <div class="download-actions">
            <a class="button button-light" href="${latestRelease.dmg}" download aria-label="下载">${icon('download', 16)}下载</a>
            <a class="button button-ghost" href="${latestRelease.releasePage}" target="_blank" rel="noreferrer" aria-label="在 GitHub 上查看发布详情">${icon('external-link', 16)}查看 Release</a>
          </div>
        </div>
        <dl class="download-notes reveal-step" style="--reveal-index: 1">
          <div class="download-note"><dt>系统</dt><dd>${systemRequirements.os} · ${systemRequirements.platform}</dd></div>
          <div class="download-note"><dt>安装</dt><dd>挂载 DMG 后拖入 Applications</dd></div>
          <div class="download-note"><dt>包体</dt><dd>Apple Silicon (arm64) · DMG</dd></div>
          <div class="download-note"><dt>其他架构</dt><dd><a href="${latestRelease.releasePage}" target="_blank" rel="noreferrer">Release 页面</a></dd></div>
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
        <div class="docs-grid reveal-sequence">${docsMarkup}</div>
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
    <div class="section-wrap reveal-sequence">
      <div class="footer-top reveal-step" style="--reveal-index: 0">
        <a class="brand" href="#top" aria-label="回到 zisla 首页"><img class="brand-mark" src="./assets/zisla-icon.png" alt="" /><span>zisla</span></a>
        <div class="footer-links">
          <a href="${repositoryLinks.github}" target="_blank" rel="noreferrer">GitHub</a>
          <a href="${repositoryLinks.gitee}" target="_blank" rel="noreferrer">Gitee</a>
          <a href="${latestRelease.previewPage}" target="_blank" rel="noreferrer">Preview channel</a>
          <a href="${documentationLinks[4]?.url ?? repositoryLinks.github}" target="_blank" rel="noreferrer">贡献指南</a>
        </div>
      </div>
      <div class="footer-bottom reveal-step" style="--reveal-index: 1"><span>开源、原生、把控制权留在你手里。</span><span class="footer-meta">${license} · ${latestRelease.version} · macOS</span></div>
    </div>
  </footer>

  <div class="toast" id="toast" role="status" aria-live="polite"></div>
`;

createIcons({ icons: siteIcons });

const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

const siteHeader = document.querySelector<HTMLElement>('.site-header');
const menuToggle = document.querySelector<HTMLButtonElement>('.menu-toggle');
const nav = document.querySelector<HTMLElement>('.nav');

const setMenuOpen = (isOpen: boolean) => {
  nav?.classList.toggle('is-open', isOpen);
  document.body.classList.toggle('is-locked', isOpen);
  menuToggle?.setAttribute('aria-expanded', String(isOpen));
  if (!menuToggle) return;

  menuToggle.setAttribute('aria-label', isOpen ? '关闭导航' : '打开导航菜单');
  menuToggle.innerHTML = icon(isOpen ? 'x' : 'menu', 18);
  createIcons({ icons: siteIcons });
};

menuToggle?.addEventListener('click', () => {
  setMenuOpen(!(nav?.classList.contains('is-open') ?? false));
});

nav?.querySelectorAll('a').forEach((link) => {
  link.addEventListener('click', () => setMenuOpen(false));
});

window.matchMedia('(min-width: 901px)').addEventListener('change', ({ matches }) => {
  if (matches) setMenuOpen(false);
});

const toast = document.querySelector<HTMLElement>('#toast');
let toastTimer: number | undefined;
const copyFeedbackTimers = new WeakMap<HTMLButtonElement, number>();

const showToast = (message: string) => {
  if (!toast) return;
  toast.textContent = message;
  toast.classList.add('is-visible');
  if (toastTimer) window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => toast.classList.remove('is-visible'), 3600);
};

const showCopyFeedback = (button?: HTMLButtonElement | null) => {
  if (!button) return;

  const previousTimer = copyFeedbackTimers.get(button);
  if (previousTimer) window.clearTimeout(previousTimer);

  button.dataset.copyLabel ??= button.getAttribute('aria-label') ?? '复制命令';
  button.classList.add('is-copied');
  button.setAttribute('aria-label', '已复制');
  button.innerHTML = icon('check', 15);
  createIcons({ icons: siteIcons });

  const timer = window.setTimeout(() => {
    button.classList.remove('is-copied');
    button.setAttribute('aria-label', button.dataset.copyLabel ?? '复制命令');
    button.innerHTML = icon('copy', 15);
    createIcons({ icons: siteIcons });
    copyFeedbackTimers.delete(button);
  }, 1600);
  copyFeedbackTimers.set(button, timer);
};

const copyText = async (text: string, message: string, button?: HTMLButtonElement | null) => {
  let copied = false;

  try {
    await navigator.clipboard.writeText(text);
    copied = true;
  } catch {
    const input = document.createElement('textarea');
    input.value = text;
    input.setAttribute('readonly', 'true');
    input.style.position = 'fixed';
    input.style.opacity = '0';
    document.body.append(input);

    try {
      input.select();
      copied = document.execCommand('copy');
    } catch {
      copied = false;
    } finally {
      input.remove();
    }
  }

  if (!copied) return;
  showToast(message);
  showCopyFeedback(button);
};

const copyCommandButton = document.querySelector<HTMLButtonElement>('#copyCommand');
const copyZislactlButton = document.querySelector<HTMLButtonElement>('#copyZislactl');

copyCommandButton?.addEventListener('click', () =>
  copyText(developmentSetup.runCommand, '源码运行命令已复制', copyCommandButton),
);
copyZislactlButton?.addEventListener('click', () =>
  copyText(developmentSetup.zislactlCommand, 'zislactl 命令已复制', copyZislactlButton),
);

const progressBar = document.createElement('div');
progressBar.className = 'scroll-progress';
document.body.append(progressBar);

const revealItems = document.querySelectorAll<HTMLElement>('.reveal, .reveal-sequence');
if (!prefersReducedMotion) {
  document.documentElement.classList.add('reveal-ready');

  const revealObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting || entry.boundingClientRect.top < 0) {
          entry.target.classList.add('visible');
          revealObserver.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.08, rootMargin: '0px 0px -60px 0px' },
  );

  window.requestAnimationFrame(() => {
    revealItems.forEach((el) => {
      if (el.getBoundingClientRect().top < window.innerHeight) {
        el.classList.add('visible');
        return;
      }
      revealObserver.observe(el);
    });
  });
}

document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
  anchor.addEventListener('click', (event) => {
    const href = anchor.getAttribute('href');
    if (!href || href === '#') return;
    const target = document.getElementById(href.substring(1));
    if (!target) return;
    event.preventDefault();
    const headerOffset = siteHeader?.getBoundingClientRect().height ?? 82;
    const y = target.getBoundingClientRect().top + window.pageYOffset - headerOffset - 16;
    window.scrollTo({ top: y, behavior: prefersReducedMotion ? 'auto' : 'smooth' });
  });
});
