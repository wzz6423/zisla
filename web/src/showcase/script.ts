/**
 * Copy for the showcase animation.
 *
 * `en` is the complete base and every other locale is a deep partial override,
 * so an untranslated line falls back to English instead of leaving a gap. This
 * mirrors the marketing catalogs in `../i18n`, which merge `en` the same way,
 * but is typed for this page's own shape.
 */
import type { SiteLocale } from '../locales';

export type ChapterId = 'opening' | 'context' | 'features' | 'highlights' | 'outro';

export interface ChapterCopy {
  /** Small uppercase label above the title. */
  kicker: string;
  title: string;
  /** One supporting line under the title. */
  caption: string;
}

export interface ShowcaseCopy {
  /** Document title and the on-canvas end card. */
  documentTitle: string;
  endCard: {
    product: string;
    tagline: string;
    cta: string;
  };
  chapters: Record<ChapterId, ChapterCopy>;
  /** Chips used by the "features" chapter, one per module card. */
  featureChips: readonly string[];
  /** Rows used by the "highlights" chapter. */
  highlightRows: readonly string[];
  /** Labels for the fictional source apps in the "context" chapter. */
  contextSources: readonly string[];
  transport: {
    play: string;
    pause: string;
    replay: string;
    /** Announced for the fullscreen toggle button. */
    enterFullscreen: string;
    exitFullscreen: string;
    /** `current / total` template, `{current}` and `{total}` are replaced. */
    timeTemplate: string;
    progress: string;
    chapters: string;
    skipToChapter: string;
    reducedMotionNotice: string;
  };
}

const en: ShowcaseCopy = {
  documentTitle: 'zisla · Animated introduction',
  endCard: {
    product: 'zisla',
    tagline: 'A native macOS workspace that appears when you need it.',
    cta: 'github.com/wzz6423/zisla',
  },
  chapters: {
    opening: {
      kicker: 'zisla',
      title: 'Puts what is happening where you can see it',
      caption: 'One native workspace along the top edge of the screen.',
    },
    context: {
      kicker: 'The problem',
      title: 'Live status is scattered across apps',
      caption: 'Media, downloads, mail and AI sessions each live in their own window.',
    },
    features: {
      kicker: 'What it does',
      title: 'Everything waits in one tray',
      caption: 'Expand on demand, act in place, and the windows behind stay untouched.',
    },
    highlights: {
      kicker: 'How it works',
      title: 'Expanding never takes the focus',
      caption: 'One system material, local recognition, and permissions asked for only when used.',
    },
    outro: {
      kicker: 'Get started',
      title: 'Move the pointer to the top center',
      caption: 'Or pick Show Island from the menu bar icon.',
    },
  },
  featureChips: [
    'Now Playing',
    'AI activity',
    'Downloads',
    'Clipboard',
    'Mail & calendar',
    'System & battery',
  ],
  highlightRows: [
    'No focus activation on hover',
    'Single system material',
    'On-device recognition',
    'Independent feature switches',
  ],
  contextSources: ['Music', 'Downloads', 'Mail', 'AI session', 'Clipboard', 'Calendar'],
  transport: {
    play: 'Play',
    pause: 'Pause',
    replay: 'Replay',
    enterFullscreen: 'Enter fullscreen',
    exitFullscreen: 'Exit fullscreen',
    timeTemplate: '{current} / {total}',
    progress: 'Playback progress',
    chapters: 'Chapters',
    skipToChapter: 'Skip to chapter',
    reducedMotionNotice: 'Reduced motion is on, so the camera holds still. Use the chapter buttons to step through.',
  },
};

export type DeepPartial<T> = T extends readonly (infer Item)[]
  ? readonly DeepPartial<Item>[]
  : T extends object
    ? { [Key in keyof T]?: DeepPartial<T[Key]> }
    : T;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

/** Deep-merges `overrides` onto `base`; arrays and scalars are replaced whole. */
const merge = <T>(base: T, overrides: unknown): T => {
  if (overrides === undefined) return base;
  if (isRecord(base) && isRecord(overrides)) {
    const merged: Record<string, unknown> = { ...base };
    Object.entries(overrides).forEach(([key, value]) => {
      merged[key] = merge(merged[key], value);
    });
    return merged as T;
  }
  return overrides as T;
};

const catalog = (overrides: DeepPartial<ShowcaseCopy>): ShowcaseCopy => merge(en, overrides);

const zhHans: ShowcaseCopy = catalog({
  documentTitle: 'zisla · 动画介绍',
  endCard: {
    product: 'zisla',
    tagline: '按需出现的原生 macOS 工作空间。',
    cta: 'github.com/wzz6423/zisla',
  },
  chapters: {
    opening: {
      kicker: 'zisla',
      title: '把正在发生的事放到你看得见的地方',
      caption: '一个沿屏幕顶部展开的原生工作空间。',
    },
    context: {
      kicker: '问题',
      title: '实时状态散落在各个应用里',
      caption: '媒体、下载、邮件和 AI 会话，各自待在自己的窗口中。',
    },
    features: {
      kicker: '能做什么',
      title: '所有待办集中在一个托盘',
      caption: '按需展开、就地处理，身后的窗口不受打扰。',
    },
    highlights: {
      kicker: '怎么做到',
      title: '展开时从不抢走焦点',
      caption: '单层系统材质、本地识别，权限只在首次使用时申请。',
    },
    outro: {
      kicker: '开始使用',
      title: '把指针移到屏幕顶部中央',
      caption: '或者从菜单栏图标选择「显示灵动岛」。',
    },
  },
  featureChips: ['正在播放', 'AI 活动', '下载', '剪贴板', '邮件与日历', '系统与电池'],
  highlightRows: ['悬停展开不激活应用', '单层系统材质', '识别完全在本地', '功能开关彼此独立'],
  contextSources: ['音乐', '下载', '邮件', 'AI 会话', '剪贴板', '日历'],
  transport: {
    play: '播放',
    pause: '暂停',
    replay: '重播',
    enterFullscreen: '进入全屏',
    exitFullscreen: '退出全屏',
    timeTemplate: '{current} / {total}',
    progress: '播放进度',
    chapters: '章节',
    skipToChapter: '跳到章节',
    reducedMotionNotice: '系统开启了「减弱动态效果」，相机保持静止，可使用章节按钮逐步浏览。',
  },
});

const zhHant: ShowcaseCopy = catalog({
  documentTitle: 'zisla · 動畫介紹',
  endCard: {
    product: 'zisla',
    tagline: '按需出現的原生 macOS 工作空間。',
    cta: 'github.com/wzz6423/zisla',
  },
  chapters: {
    opening: {
      kicker: 'zisla',
      title: '把正在發生的事放到你看得到的地方',
      caption: '一個沿螢幕頂部展開的原生工作空間。',
    },
    context: {
      kicker: '問題',
      title: '即時狀態散落在各個 App 裡',
      caption: '媒體、下載、郵件與 AI 工作階段，各自待在自己的視窗中。',
    },
    features: {
      kicker: '能做什麼',
      title: '所有待辦集中在一個托盤',
      caption: '按需展開、就地處理，身後的視窗不受打擾。',
    },
    highlights: {
      kicker: '怎麼做到',
      title: '展開時從不搶走焦點',
      caption: '單層系統材質、本地辨識，權限只在首次使用時申請。',
    },
    outro: {
      kicker: '開始使用',
      title: '把游標移到螢幕頂部中央',
      caption: '或者從選單列圖示選擇「顯示靈動島」。',
    },
  },
  featureChips: ['正在播放', 'AI 活動', '下載', '剪貼簿', '郵件與行事曆', '系統與電池'],
  highlightRows: ['懸停展開不啟用 App', '單層系統材質', '辨識完全在本地', '功能開關彼此獨立'],
  contextSources: ['音樂', '下載', '郵件', 'AI 工作階段', '剪貼簿', '行事曆'],
  transport: {
    play: '播放',
    pause: '暫停',
    replay: '重播',
    enterFullscreen: '進入全螢幕',
    exitFullscreen: '離開全螢幕',
    timeTemplate: '{current} / {total}',
    progress: '播放進度',
    chapters: '章節',
    skipToChapter: '跳到章節',
    reducedMotionNotice: '系統開啟了「減少動態效果」，相機保持靜止，可使用章節按鈕逐步瀏覽。',
  },
});

const catalogs: Partial<Record<SiteLocale, ShowcaseCopy>> = {
  'zh-Hans': zhHans,
  'zh-Hant': zhHant,
};

export const showcaseCopy = (locale: SiteLocale): ShowcaseCopy => catalogs[locale] ?? en;

export const formatTimecode = (seconds: number): string => {
  const safe = Math.max(0, Math.floor(seconds));
  const minutes = Math.floor(safe / 60);
  return `${minutes}:${String(safe % 60).padStart(2, '0')}`;
};