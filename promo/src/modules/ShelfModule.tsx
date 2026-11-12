import type {LucideIcon} from 'lucide-react';
import {
  AlignLeft,
  Archive,
  Camera,
  ClipboardPaste,
  CodeXml,
  Copy,
  FileArchive,
  FileQuestion,
  FileText,
  Folder,
  Image,
  Inbox,
  Link,
  Music,
  Search,
  Share,
  SquarePen,
  Video,
  X,
} from 'lucide-react';
import {TextButton} from '../components/Glass';
import type {ShelfItem, ShelfKind} from '../content';
import {shelfCategories} from '../content';
import {black, color, white} from '../theme';

export const SHELF_ICONS: Record<ShelfKind, LucideIcon> = {
  image: Image,
  folder: Folder,
  url: Link,
  text: AlignLeft,
  video: Video,
  audio: Music,
  document: FileText,
  archive: FileArchive,
  code: CodeXml,
  screenshot: Camera,
};

export const CATEGORY_ICONS: readonly LucideIcon[] = [
  Inbox,
  SquarePen,
  Camera,
  Folder,
  Image,
  Link,
  Video,
  Music,
  AlignLeft,
  FileText,
  Archive,
  CodeXml,
  FileQuestion,
];

type ShelfModuleProps = {
  items: readonly ShelfItem[];
  // 已落位的条目数，可以是小数，最后一个正在吸附进去
  enter: number;
  // 高亮的条目序号（右键菜单指向的那一个）
  highlight?: number;
  menu?: number;
  menuHighlight?: number;
  // 0–1，右侧那组次要按钮（Quick Notes / Copy / Share / Show）出现
  moreButtons?: number;
  // 0–1，Share 与 Show 两个按钮被点亮
  actionGlow?: number;
  // 拖拽悬停在托盘上
  dropHover?: number;
  selectedCategory?: number;
};

const ITEM = {width: 66, height: 84, pitchX: 74, pitchY: 92};

export const ShelfModule = ({
  items,
  enter,
  highlight = -1,
  menu = 0,
  menuHighlight = 0,
  moreButtons = 0,
  actionGlow = 0,
  dropHover = 0,
  selectedCategory = 0,
}: ShelfModuleProps) => (
  <div className="absolute inset-0 flex gap-[6px]">
    <div
      className="flex w-[84px] shrink-0 flex-col items-center justify-center gap-2 p-2"
      style={{
        background: color.fillCard,
        border: `1px solid ${dropHover > 0.01 ? white(0.4) : color.strokeCard}`,
        borderRadius: '8px 8px 8px 22px',
      }}
    >
      <Share size={20} strokeWidth={1.9} color={color.secondary} />
      <div className="text-[11px] leading-[13px] font-semibold text-label-2">Share</div>
      <div
        className="flex w-full items-center justify-center rounded-[6px] py-1 text-[10px] font-medium text-label-2"
        style={{background: color.fillCard}}
      >
        Paste
      </div>
    </div>
    <div
      className="relative flex min-w-0 flex-1 flex-col"
      style={{
        background: color.fillCard,
        border: `1px solid ${dropHover > 0.01 ? white(0.4) : color.strokeCard}`,
        borderRadius: '8px 8px 22px 8px',
      }}
    >
      <div
        className="pointer-events-none absolute inset-0 rounded-[inherit]"
        style={{background: color.green, opacity: 0.12 * dropHover}}
      />
      <div className="flex h-[30px] shrink-0 items-center gap-[5px] px-[10px]">
        <span className="text-[12px] font-semibold">Shelf</span>
        <Inbox size={12} strokeWidth={2.2} />
        <span className="tabular font-mono text-[10px] font-medium text-label-2">{items.length}</span>
        <div className="flex-1" />
        <div className="flex items-center gap-[6px]">
          <TextButton icon={SquarePen} label="Take a note" />
          <TextButton icon={ClipboardPaste} label="Paste" />
          <div className="flex items-center gap-[6px]" style={{opacity: moreButtons}}>
            <TextButton icon={FileText} label="Quick Notes" />
            <TextButton icon={Copy} label="Copy" />
            <TextButton icon={Share} label="Share" highlight={actionGlow} />
            <TextButton icon={Folder} label="Show" highlight={actionGlow} />
          </div>
        </div>
      </div>
      <div className="flex shrink-0 items-center gap-[6px] px-[10px] py-[6px]">
        <Search size={11} strokeWidth={2.2} color={color.tertiary} />
        <span className="text-[11px] text-label-3">Search Shelf Content</span>
      </div>
      <div style={{height: 1, background: color.divider}} />
      <div className="flex shrink-0 flex-wrap items-center gap-[6px] px-[10px] py-[6px]">
        {shelfCategories.map((category, index) => {
          const Icon = CATEGORY_ICONS[index] ?? Inbox;
          const selected = index === selectedCategory;
          return (
            <div
              key={category.name}
              className="flex items-center gap-[5px] rounded-full px-2 py-1 text-[10px] font-medium"
              style={{
                background: selected ? color.fillCard : 'transparent',
                boxShadow: selected ? '0 1px 3px rgba(0,0,0,0.25)' : undefined,
                color: selected ? color.label : color.secondary,
                opacity: category.count === 0 ? 0.4 : 1,
              }}
            >
              <Icon size={10} strokeWidth={2.4} />
              <span>{category.name}</span>
              <span className="tabular font-mono text-[9px] text-label-3">{category.count}</span>
            </div>
          );
        })}
      </div>
      <div className="relative min-h-0 flex-1" style={{padding: '7px 8px 7px 4px'}}>
        {items.length === 0 ? (
          <div
            className="flex h-full flex-col items-center justify-center gap-[7px]"
            style={{color: dropHover > 0.01 ? 'rgb(122,230,158)' : color.secondary}}
          >
            <Inbox size={25} strokeWidth={1.9} />
            <div className="text-[10px] font-medium">Shelf is empty</div>
          </div>
        ) : null}
        {items.map((item, index) => {
          const Icon = SHELF_ICONS[item.kind];
          const landed = Math.min(1, Math.max(0, enter - index));
          if (landed <= 0) {
            return null;
          }
          const focused = index === highlight;
          return (
            <div
              key={item.name}
              className="absolute"
              style={{
                left: 4 + (index % 8) * ITEM.pitchX,
                top: 7 + Math.floor(index / 8) * ITEM.pitchY,
                width: ITEM.width,
                height: ITEM.height,
                opacity: landed,
                // 落位时从上方吸附进来
                transform: `translateY(${(1 - landed) * -18}px) scale(${0.86 + 0.14 * landed})`,
              }}
            >
              <div
                className="flex h-[50px] items-center justify-center"
                style={{filter: focused && menu > 0.5 ? 'brightness(1.25)' : undefined}}
              >
                <Icon size={42} strokeWidth={1.2} color={item.tint} />
              </div>
              <div className="flex h-[24px] w-[64px] items-center justify-center px-[2px] text-center text-[9px] leading-[10px] font-medium">
                {item.name}
              </div>
              <div
                className="absolute flex items-center justify-center rounded-full"
                style={{right: 0, top: 0, width: 14, height: 14, background: black(0.72)}}
              >
                <X size={8} strokeWidth={3.2} color="#fff" />
              </div>
            </div>
          );
        })}
        {menu > 0.01 ? (
          <div
            className="absolute z-10 w-[178px] py-[5px] text-[12px]"
            style={{
              left: 4 + ((highlight < 0 ? 0 : highlight) % 8) * ITEM.pitchX + 40,
              top: 7 + Math.floor((highlight < 0 ? 0 : highlight) / 8) * ITEM.pitchY + 56,
              background: 'rgba(28,28,32,0.86)',
              backdropFilter: 'blur(24px) saturate(180%)',
              border: `1px solid ${white(0.12)}`,
              borderRadius: 8,
              boxShadow: '0 12px 34px rgba(0,0,0,0.5)',
              opacity: menu,
              transform: `scale(${0.96 + 0.04 * menu})`,
              transformOrigin: 'top left',
            }}
          >
            {[
              {label: 'Open', highlight: false},
              {label: 'Show in Finder', highlight: true},
              {label: 'Copy', highlight: false},
              {label: 'Send to Quick Notes', highlight: false},
            ].map((row) => (
              <div
                key={row.label}
                className="px-[10px] py-[3px]"
                style={{background: row.highlight && menuHighlight > 0.5 ? color.blue : 'transparent'}}
              >
                {row.label}
              </div>
            ))}
            <div style={{height: 1, background: color.divider, margin: '4px 0'}} />
            <div className="px-[10px] py-[3px]">Remove</div>
          </div>
        ) : null}
      </div>
    </div>
  </div>
);
