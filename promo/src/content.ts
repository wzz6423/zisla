// Demo tasks, files, songs, lyrics, cities, events and notes are fictional.
// They contain no local user data or lyrics from existing works.
import {color} from './theme';

export const clock = {date: 'Wed Nov 11', time: '9:41 AM', uptime: 'Uptime: 6 d 4 h 12 min'};

export const brands = {
  claude: {name: 'CLAUDE', color: color.claude},
  codex: {name: 'CODEX', color: 'rgb(92,230,168)'},
  gemini: {name: 'GEMINI', color: 'rgb(128,174,255)'},
} as const;

export type Provider = keyof typeof brands;

export type AiTask = {
  id: string;
  provider: Provider;
  title: string;
  detail: string;
  effort: string;
  start: string;
  pid: number;
};

export const aiTasks: readonly AiTask[] = [
  {
    id: 'build-01',
    provider: 'claude',
    title: 'Refactoring core',
    detail: 'worktree',
    effort: 'high effort',
    start: '2026-11-11 09:12:04',
    pid: 48213,
  },
  {
    id: 'test-07',
    provider: 'codex',
    title: 'Verifying island layout',
    detail: 'main',
    effort: 'medium effort',
    start: '2026-11-11 09:09:52',
    pid: 48190,
  },
  {
    id: 'docs-02',
    provider: 'gemini',
    title: 'Summarizing release notes',
    detail: 'docs',
    effort: 'low effort',
    start: '2026-11-11 09:15:31',
    pid: 48240,
  },
];

export const tokenTrend = {
  points: [
    {label: '11/05', tokens: 412_000},
    {label: '11/06', tokens: 588_000},
    {label: '11/07', tokens: 331_000},
    {label: '11/08', tokens: 764_000},
    {label: '11/09', tokens: 642_000},
    {label: '11/10', tokens: 918_000},
    {label: '11/11', tokens: 553_000},
  ],
} as const;

export const tokenAbbreviation = (tokens: number): string =>
  tokens >= 1_000_000 ? `${(tokens / 1_000_000).toFixed(1)}M` : `${Math.round(tokens / 1000)}k`;

// A fixed seed keeps the 24-week heatmap identical across renders.
const heatSeed = (week: number, day: number): number => {
  let value = (week * 7 + day) * 2654435761 + 1013904223;
  value = (value ^ (value >>> 13)) * 1274126177;
  return ((value ^ (value >>> 16)) >>> 0) / 4294967296;
};

export const heatmap = {
  weeks: 24,
  monthLabels: [
    {week: 0, label: 'M6'},
    {week: 4, label: 'M7'},
    {week: 8, label: 'M8'},
    {week: 13, label: 'M9'},
    {week: 17, label: 'M10'},
    {week: 21, label: 'M11'},
  ],
  // Zero means no usage; one through four select green intensity.
  level: (week: number, day: number): number => {
    const value = heatSeed(week, day);
    const weekend = day >= 5 ? 0.55 : 1;
    const scaled = value * weekend;
    if (scaled < 0.22) return 0;
    if (scaled < 0.45) return 1;
    if (scaled < 0.68) return 2;
    if (scaled < 0.86) return 3;
    return 4;
  },
  total: 86_400_000,
  // The cursor selects the third day in the final column.
  selected: {week: 23, day: 2, label: 'Nov 11'},
};

export const track = {
  title: 'Paper Lanterns',
  artist: 'Mira Solen',
  album: 'Night Cartography',
  duration: 282,
  // Later scenes advance from this offset using global film time.
  elapsed: 74,
  art: ['#ff9d6c', '#b8446a', '#1d2350'] as const,
  // Original demo lyrics, independent of the soundtrack.
  lyrics: [
    'City lights are folding into paper',
    'We drift above the rooftops, weightless',
    'Every window turns to gold',
    'Hold the thread and let the night unfold',
    'Paper lanterns, carry what we said',
    'Over rivers made of quiet streets',
    'Maps we drew in breath on winter glass',
    'Count the bridges till the dark gives way',
    'Small bright islands in a sea of slate',
    'Let them rise and let them go',
    'Morning finds the embers in the air',
    'And the sky keeps every name we wrote',
  ],
};

export const shelfCategories = [
  {name: 'All'},
  {name: 'Notes'},
  {name: 'Screenshots'},
  {name: 'Folder'},
  {name: 'Image'},
  {name: 'URL'},
  {name: 'Video'},
  {name: 'Audio'},
  {name: 'Text'},
  {name: 'Document'},
  {name: 'Archive'},
  {name: 'Code'},
  {name: 'Other'},
] as const;

export type ShelfKind =
  | 'note'
  | 'image'
  | 'folder'
  | 'url'
  | 'text'
  | 'video'
  | 'audio'
  | 'document'
  | 'archive'
  | 'code'
  | 'screenshot';

export type ShelfItem = {name: string; kind: ShelfKind; tint: string};

export const shelfItems: readonly ShelfItem[] = [
  {name: 'Island Mockup.png', kind: 'image', tint: '#7fb2ff'},
  {name: 'Release Notes.md', kind: 'text', tint: '#8fe3c0'},
  {name: 'launch-assets.zip', kind: 'archive', tint: '#ffcf7a'},
  {name: 'Motion Study.mp4', kind: 'video', tint: '#ff9d6c'},
  {name: 'Tray Icons.svg', kind: 'code', tint: '#c9a6ff'},
  {name: 'Handoff Folder', kind: 'folder', tint: '#9ad0ff'},
  {name: 'Spec Draft.pages', kind: 'document', tint: '#9fb4ff'},
  {name: 'Glass Sample.heic', kind: 'screenshot', tint: '#ffa8c4'},
];

export const download = {
  name: 'launch-assets.zip',
  folder: 'Downloads',
  path: '~/Downloads',
  size: '48.2 MB',
};

export const notes = {
  sidebar: [
    {title: 'Launch checklist', date: 'Nov 11'},
    {title: 'Island metrics', date: 'Nov 09'},
    {title: 'Release notes draft', date: 'Nov 07'},
    {title: 'Reading list', date: 'Nov 04'},
  ],
  title: 'Launch checklist',
  body: [
    {kind: 'h1', text: 'Launch checklist'},
    {kind: 'p', text: 'Everything that has to be true before the launch film ships.'},
    {kind: 'h2', text: 'Must ship'},
    {kind: 'check', text: 'Island reveal measured at 60 fps on macOS 14'},
    {kind: 'check', text: 'Zero frame loop while the island is hidden'},
    {kind: 'check', text: 'Privacy copy reviewed by the docs pass'},
    {kind: 'check', text: 'Homebrew cask updated to the new build'},
    {kind: 'h2', text: 'Notes'},
    {kind: 'p', text: 'The tray keeps a security-scoped bookmark instead of copying files.'},
    {kind: 'code', text: 'zislactl update --id build-01 --progress 68'},
  ],
} as const;

// Six code entries fill the filtered clipboard viewport.
export const clipboard = {
  items: [
    {kind: 'code', preview: 'let island = IslandLayout(module: .ai)'},
    {kind: 'text', preview: 'Privacy copy: structured metadata only.'},
    {kind: 'link', preview: 'github.com/wzz6423/zisla'},
    {kind: 'text', preview: 'Ship the film at 60 fps, 1080p and 4K.'},
    {kind: 'code', preview: 'brew install --cask wzz6423/tap/zisla'},
    {kind: 'image', preview: 'Screenshot 09-41-12.png'},
    {kind: 'code', preview: '.spring(response: 0.22, dampingFraction: 0.8)'},
    {kind: 'link', preview: 'developer.apple.com/design/human-interface-guidelines'},
    {kind: 'text', preview: 'Bento grid: notes, clipboard, weather, metrics.'},
    {kind: 'code', preview: 'zislactl finish --id build-01'},
    {kind: 'code', preview: 'panel.styleMask.insert(.nonactivatingPanel)'},
    {kind: 'code', preview: 'swift build -c release'},
  ],
} as const;

export const weather = {
  cities: [
    {name: 'Kyoto', temp: 17, condition: 'Cloudy', high: 19, low: 11, icon: 'cloud' as const},
    {name: 'Lisbon', temp: 21, condition: 'Clear', high: 23, low: 14, icon: 'sun' as const},
    {name: 'Tromsø', temp: 2, condition: 'Snow', high: 3, low: -2, icon: 'snow' as const},
  ],
};

export const agenda = {
  days: [
    {weekday: 'Mon', day: 9},
    {weekday: 'Tue', day: 10},
    {weekday: 'Wed', day: 11},
    {weekday: 'Thu', day: 12},
    {weekday: 'Fri', day: 13},
    {weekday: 'Sat', day: 14},
    {weekday: 'Sun', day: 15},
    {weekday: 'Mon', day: 16},
    {weekday: 'Tue', day: 17},
    {weekday: 'Wed', day: 18},
    {weekday: 'Thu', day: 19},
    {weekday: 'Fri', day: 20},
    {weekday: 'Sat', day: 21},
    {weekday: 'Sun', day: 22},
  ],
  today: 2,
  items: [
    {kind: 'event' as const, time: '10:30', title: 'Design review'},
    {kind: 'event' as const, time: '13:00', title: 'Docs pass'},
    {kind: 'reminder' as const, time: '', title: 'Ship the launch film'},
    {kind: 'reminder' as const, time: '', title: 'Update the cask'},
  ],
};

// Remaining seconds decrease with global film time, like playback progress.
export const focus = {phase: 'Focus', remaining: 18 * 60 + 44};

export const monitors = [
  {label: 'CPU', value: 0.14},
  {label: 'GPU', value: 0.22},
  {label: 'RAM', value: 0.46},
  {label: 'Disk', value: 0.31},
];

export const metrics = [
  {value: '0', label: 'Frame loop while hidden'},
  {value: 'Swift 6', label: 'Native, no Electron'},
  {value: 'macOS 14–26', label: 'Vibrancy to Liquid Glass'},
];

export const copy = {
  slogan: 'Appears when you need it.',
  sloganSecond: 'Gets out of the way.',
  trigger: '6 pt hover zone',
  privacy: {
    title: 'Structured metadata only.',
    subtitle: 'Never reads your prompts.',
    detail: 'zisla reads task state, progress and token counts. Prompts and answer bodies are never read.',
  },
  flow: {
    media: 'MediaRemote + Core Audio know which app is really playing',
    handoff: 'Drop it on the shelf. No copies, just a security-scoped bookmark.',
    download: 'Finished downloads come back with one tap',
  },
  bento: 'Native modules, laid out like a bento box',
  outro: 'brew install --cask wzz6423/tap/zisla',
};
