// 数值取自 mac/Sources/Zisla/DesignSystem.swift 与 IslandDashboardLayout，单位是 macOS 的 pt。
// 整个桌面按 1280×720 pt 绘制，再由 Stage 等比放大到合成尺寸。

export const STAGE = {width: 1280, height: 720} as const;

export const BAR_HEIGHT = 34;
export const NOTCH_WIDTH = 190;

export const ISLAND = {
  width: 776,
  collapsedBottomRadius: 14,
  expandedBottomRadius: 34,
  headerHeight: 72,
  toolbarHeight: 30,
  moduleInset: 12,
  moduleInnerRadius: 8,
  moduleOuterBottomRadius: 22,
  moduleWidth: 752,
  // 16 顶部留白 + 72 标题行 + 4 + 30 工具栏 + 7
  chromeHeight: 129,
  compactWing: 40,
  compactDetailWing: 160,
} as const;

export const MODULE_HEIGHT = {
  home: 78,
  agenda: 160,
  ai: 350,
  shelf: 355,
  clipboard: 355,
  notes: 401,
} as const;

export const islandHeightFor = (moduleHeight: number): number =>
  ISLAND.chromeHeight + moduleHeight + ISLAND.moduleInset * 2;

export const color = {
  label: 'rgba(255,255,255,1)',
  secondary: 'rgba(235,235,245,0.6)',
  tertiary: 'rgba(235,235,245,0.3)',
  fillCard: 'rgba(255,255,255,0.12)',
  fillControl: 'rgba(255,255,255,0.10)',
  strokeCard: 'rgba(255,255,255,0.14)',
  divider: 'rgba(255,255,255,0.08)',
  blue: '#0A84FF',
  green: '#30D158',
  orange: '#FF9F0A',
  red: '#FF453A',
  cyan: '#64D2FF',
  purple: '#BF5AF2',
  yellow: '#FFD60A',
  // ProviderBrand.color(for: .claude) = RGB(0.95, 0.48, 0.34)
  claude: 'rgb(242,122,87)',
  // 封面里最鲜艳的颜色，波形与收起态进度线用它着色
  coverTint: 'rgb(255,138,92)',
} as const;

export const font = {
  sans: '-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", system-ui, sans-serif',
  rounded: 'ui-rounded, "SF Pro Rounded", -apple-system, system-ui, sans-serif',
  mono: 'ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace',
} as const;

export const white = (alpha: number): string => `rgba(255,255,255,${alpha})`;
export const black = (alpha: number): string => `rgba(0,0,0,${alpha})`;

// 品牌色和系统色的写法不统一（hex / rgb），用 color-mix 统一套透明度
export const alpha = (value: string, opacity: number): string =>
  `color-mix(in srgb, ${value} ${Math.round(opacity * 1000) / 10}%, transparent)`;

export const clamp01 = (value: number): number => Math.min(1, Math.max(0, value));
export const lerp = (from: number, to: number, t: number): number => from + (to - from) * t;
