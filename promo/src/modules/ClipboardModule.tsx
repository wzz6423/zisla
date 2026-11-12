import {
  Clipboard as ClipboardIcon,
  Code,
  FileText,
  Image as ImageIcon,
  LayoutGrid,
  Link,
  Search,
  Star,
  StarOff,
  StickyNote,
  Trash2,
} from 'lucide-react';
import type {LucideIcon} from 'lucide-react';
import {clipboard} from '../content';
import {clamp01, color, lerp, white} from '../theme';

type ClipKind = (typeof clipboard.items)[number]['kind'];

const TYPES: readonly {name: string; icon: LucideIcon; kind?: ClipKind}[] = [
  {name: 'All', icon: LayoutGrid},
  {name: 'Image', icon: ImageIcon, kind: 'image'},
  {name: 'URL', icon: Link, kind: 'link'},
  {name: 'Text', icon: FileText, kind: 'text'},
  {name: 'Code', icon: Code, kind: 'code'},
];

const SCOPES: readonly {name: string; icon: LucideIcon}[] = [
  {name: 'All', icon: LayoutGrid},
  {name: 'Favorites', icon: Star},
  {name: 'Non-favorites', icon: StarOff},
];

const countOf = (kind?: ClipKind): number => (kind ? clipboard.items.filter((item) => item.kind === kind).length : clipboard.items.length);

// 真实界面的副行是 “<类型> · Copied at HH:mm:ss”；时间由序号推出，保持确定性
const copiedAt = (index: number): string => {
  const seconds = 9 * 3600 + 40 * 60 + 52 - index * 137;
  const pad = (value: number) => String(value).padStart(2, '0');
  return `${pad(Math.floor(seconds / 3600))}:${pad(Math.floor((seconds % 3600) / 60))}:${pad(seconds % 60)}`;
};

type ClipboardModuleProps = {
  // 选中的类型胶囊序号，可小数：0 = All，4 = Code
  filter?: number;
  // 搜索框里已输入的文字
  query?: string;
};

export const ClipboardModule = ({filter = 0, query = ''}: ClipboardModuleProps) => {
  const active = TYPES[Math.round(filter)] ?? TYPES[0];
  const needle = query.toLowerCase();
  const rows = clipboard.items
    .map((item, index) => ({item, index}))
    .filter(({item}) => (!active?.kind || item.kind === active.kind) && item.preview.toLowerCase().includes(needle));
  // 胶囊切换的一瞬列表淡一下，交代内容是被过滤出来的
  const settle = 1 - Math.abs(filter - Math.round(filter)) * 2;

  return (
    <div
      className="absolute inset-0 flex flex-col overflow-hidden"
      style={{background: color.fillCard, border: `1px solid ${color.strokeCard}`, borderRadius: '8px 8px 22px 22px'}}
    >
      <div className="flex h-[30px] shrink-0 items-center gap-[6px] px-[10px]">
        <ClipboardIcon size={12} strokeWidth={2.2} color={color.label} />
        <div className="text-[12px] font-semibold">Clipboard</div>
        <div className="flex-1" />
        <div className="tabular font-mono text-[10px] text-label-2">{clipboard.items.length}</div>
        <Trash2 size={11} strokeWidth={2.1} color={color.secondary} />
      </div>
      <div className="mx-[10px] flex h-[24px] shrink-0 rounded-[6px] p-[2px]" style={{background: white(0.06)}}>
        {SCOPES.map(({name, icon: Icon}, index) => (
          <div
            key={name}
            className="flex flex-1 items-center justify-center gap-[4px] rounded-[5px] text-[10px] font-semibold"
            style={{background: index === 0 ? white(0.12) : 'transparent', color: index === 0 ? color.label : color.secondary}}
          >
            <Icon size={11} strokeWidth={2.2} />
            {name}
          </div>
        ))}
      </div>
      <div className="flex h-[28px] shrink-0 items-center gap-[6px] px-[10px]" style={{marginTop: 4}}>
        {TYPES.map(({name, icon: Icon, kind}, index) => {
          const selected = clamp01(1 - Math.abs(filter - index));
          return (
            <div
              key={name}
              className="flex items-center gap-[4px] rounded-full px-[8px] py-[4px]"
              style={{background: white(0.12 * selected), color: white(lerp(0.6, 1, selected))}}
            >
              <Icon size={10} strokeWidth={2.2} />
              <span className="text-[10px] leading-[12px] font-medium">{name}</span>
              <span className="tabular font-mono text-[9px] leading-[12px]" style={{opacity: 0.7}}>
                {countOf(kind)}
              </span>
            </div>
          );
        })}
      </div>
      <div className="flex shrink-0 items-center gap-[6px]" style={{padding: '8px 20px 6px'}}>
        <Search size={11} strokeWidth={2.3} color={color.secondary} />
        <span className="text-[11px] leading-[14px]" style={{color: query ? color.label : color.tertiary}}>
          {query || 'Search'}
        </span>
        {query ? <div style={{width: 1, height: 12, marginLeft: -4, background: color.blue}} /> : null}
      </div>
      <div className="flex min-h-0 flex-1 flex-col gap-[6px] overflow-hidden" style={{padding: 8, opacity: 0.35 + 0.65 * settle}}>
        {rows.map(({item, index}) => (
          <div
            key={item.preview}
            className="flex shrink-0 items-center gap-[8px]"
            style={{padding: '6px 8px', background: white(0.1), borderRadius: 6}}
          >
            {item.kind === 'image' ? (
              <div
                className="shrink-0"
                style={{width: 42, height: 28, borderRadius: 5, background: 'linear-gradient(135deg, #2b3a67, #7fb2ff 60%, #ffcf7a)'}}
              />
            ) : null}
            <div className="min-w-0 flex-1">
              <div className={`truncate text-[11px] leading-[14px] font-medium ${item.kind === 'code' ? 'font-mono' : ''}`}>{item.preview}</div>
              <div className="tabular text-[9px] leading-[12px] font-medium text-label-2">
                {item.kind === 'image' ? 'Image' : 'Text'} · Copied at {copiedAt(index)}
              </div>
            </div>
            <div className="flex shrink-0 items-center gap-[8px] text-[10px] font-medium text-label-2">
              <StickyNote size={10} strokeWidth={2.2} />
              <Star size={10} strokeWidth={2.2} />
              <Trash2 size={10} strokeWidth={2.2} />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};
