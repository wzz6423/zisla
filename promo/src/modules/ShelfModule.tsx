import type {LucideIcon} from 'lucide-react';
import type {ReactNode} from 'react';
import {
  AlignLeft,
  Archive,
  Camera,
  Check,
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
  StickyNote,
  Video,
  X,
  CircleCheck,
} from 'lucide-react';
import {TextButton} from '../components/Glass';
import type {ShelfItem, ShelfKind} from '../content';
import {shelfCategories} from '../content';
import {black, color} from '../theme';
import {shelfItemLayout} from './shelfLayout';

export const SHELF_ICONS: Record<ShelfKind, LucideIcon> = {
  note: StickyNote,
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

export const shelfCategoryCounts = (items: readonly ShelfItem[]) => [items.length, ...(['note', 'screenshot', 'folder', 'image', 'url', 'video', 'audio', 'text', 'document', 'archive', 'code'] as const).map((kind) => items.filter((item) => item.kind === kind).length), 0];

type ShelfModuleProps = {
  items: readonly ShelfItem[];
  // A fractional count animates the last file settling into the grid.
  enter: number;
  // The file targeted by the scene-level context menu.
  highlight?: number;
  // Reveal the secondary actions after the first file arrives.
  moreButtons?: number;
  // Emphasize the existing Share and Show actions.
  actionGlow?: number;
  // Highlight the shelf drop target while the file hovers over it.
  dropHover?: number;
  selectedCategory?: number;
  selection?: readonly number[];
  detail?: ReactNode;
};

export const ShelfModule = ({
  items,
  enter,
  highlight = -1,
  moreButtons = 0,
  actionGlow = 0,
  dropHover = 0,
  selectedCategory = 0,
  selection,
  detail,
}: ShelfModuleProps) => (
  <div className="absolute inset-0 flex gap-[6px]">
    <div
      className="flex w-[84px] shrink-0 flex-col items-center justify-center gap-2 p-2"
      style={{
        background: color.fillCard,
        border: `1px solid ${color.strokeCard}`,
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
        border: `1px solid ${dropHover > 0.01 ? color.blue : color.strokeCard}`,
        borderRadius: '8px 8px 22px 8px',
      }}
    >
      <div
        className="pointer-events-none absolute inset-0 rounded-[inherit]"
        style={{background: color.blue, opacity: 0.12 * dropHover}}
      />
      <div className="flex h-[30px] shrink-0 items-center gap-[5px] px-[10px]">
        <span className="text-[12px] font-semibold">Shelf</span>
        <Inbox size={12} strokeWidth={2.2} />
        <span className="tabular font-mono text-[10px] font-medium text-label-2">{items.length}</span>
        <div className="flex-1" />
        <div className="flex items-center gap-[6px]">
          <TextButton icon={SquarePen} label="Take a note" />
          <TextButton icon={ClipboardPaste} label="Paste" />
          <TextButton icon={CircleCheck} label={selection ? 'Done' : 'Select'} />
          <div className="flex items-center gap-[6px]" style={{opacity: selection ? 0 : moreButtons}}>
            <TextButton icon={FileText} label="Quick Notes" />
            <TextButton icon={Copy} label="Copy" />
            <TextButton icon={Share} label="Share" highlight={actionGlow} />
            <TextButton icon={Folder} label="Show" highlight={actionGlow} />
          </div>
        </div>
      </div>
      <div className="flex h-[31px] shrink-0 items-center gap-[6px] overflow-hidden px-[10px] py-[3px]">
        {shelfCategories.map((category, index) => {
          const Icon = CATEGORY_ICONS[index] ?? Inbox;
          const selected = index === selectedCategory;
          const count = shelfCategoryCounts(items)[index]!;
          return (
            <div
              key={category.name}
              className="flex shrink-0 items-center gap-[5px] rounded-full px-2 py-1 text-[10px] font-medium"
              style={{
                background: selected ? color.fillCard : 'transparent',
                boxShadow: selected ? '0 1px 3px rgba(0,0,0,0.25)' : undefined,
                color: selected ? color.label : color.secondary,
                opacity: count === 0 && index !== 0 ? 0.4 : 1,
              }}
            >
              <Icon size={10} strokeWidth={2.4} />
              <span>{category.name}</span>
              {index > 0 ? <span className="tabular font-mono text-[9px] text-label-3">{count}</span> : null}
            </div>
          );
        })}
      </div>
      <div className="flex h-[29px] shrink-0 items-center gap-[6px] px-[10px] py-[6px]">
        <Search size={11} strokeWidth={2.2} color={color.tertiary} />
        <span className="text-[11px] text-label-3">Search Shelf Content</span>
      </div>
      <div style={{height: 1, background: color.divider}} />
      {selection ? <div className="flex shrink-0 items-center gap-[10px] px-[10px]" data-feature="shelf.selection" style={{height: 27, fontSize: 10}}><span>{selection.length} items selected</span><div className="flex-1" /><span>Select all</span><span>Clear selection</span><span>Actions ⌄</span></div> : null}
      {detail ? <div className="relative min-h-0 flex-1">{detail}</div> : <div className="relative min-h-0 flex-1" style={{padding: '7px 8px 7px 4px'}}>
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
                ...shelfItemLayout(index),
                opacity: landed,
                // The last file settles from the same point as the drag ghost.
                transform: `translateY(${(1 - landed) * -18}px) scale(${0.86 + 0.14 * landed})`,
              }}
            >
              <div
                className="flex h-[50px] items-center justify-center"
                style={{filter: focused ? 'brightness(1.25)' : undefined}}
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
                {selection ? selection.includes(index) ? <Check size={9} strokeWidth={2.5} color="#fff" /> : <span style={{width: 8, height: 8, border: '1px solid #fff', borderRadius: 2}} /> : <X size={8} strokeWidth={3.2} color="#fff" />}
              </div>
            </div>
          );
        })}
      </div>}
    </div>
  </div>
);
