import {
  Bold,
  IndentDecrease,
  IndentIncrease,
  Image as ImageIcon,
  Italic,
  Link,
  List,
  Palette,
  Plus,
  RefreshCw,
  StickyNote,
  Strikethrough,
  Table,
  Type,
  Underline,
} from 'lucide-react';
import {Hairline} from '../components/Glass';
import {notes} from '../content';
import {color, white} from '../theme';

const TOOLS = [Type, Bold, Italic, Underline, Strikethrough, Palette, List, IndentDecrease, IndentIncrease, Link, ImageIcon, Table];
// 文字样式、BIUS、调色板、列表缩进、插入四组之间各有一条分隔
const TOOL_GROUP_ENDS = [0, 4, 5, 8];

const characters = notes.body.reduce((total, block) => total + block.text.length, 0);

// 随记：左侧列表 + 右侧所见即所得编辑器。checked 为已勾选的清单条数，可小数（最后一条正在勾上）。
export const NotesModule = ({checked = 3}: {checked?: number}) => {
  let checkIndex = -1;
  return (
    <div className="absolute inset-0 flex" style={{padding: 12}}>
      <div className="flex shrink-0 flex-col" style={{width: 152, paddingRight: 8}}>
        <div className="flex h-[28px] shrink-0 items-center gap-[5px]">
          <div className="text-[12px] font-semibold">Quick Notes</div>
          <div className="tabular text-[9px] font-medium text-label-2">{notes.sidebar.length}</div>
          <div className="flex-1" />
          <RefreshCw size={11} strokeWidth={2.2} color={color.secondary} />
          <div className="flex items-center justify-center rounded-full" style={{width: 24, height: 24, background: color.fillControl}}>
            <Plus size={12} strokeWidth={2.4} color={color.label} />
          </div>
        </div>
        <div className="flex flex-col gap-[2px]" style={{marginTop: 4}}>
          <div style={{padding: '6px 8px'}}>
            <div className="text-[10.5px] leading-[13px] font-semibold">Hello, friend. Start here.</div>
            <div className="text-[9px] leading-[12px] font-medium text-label-3">Built-in Guide</div>
          </div>
          <Hairline style={{margin: '2px 0'}} />
          {notes.sidebar.map((note, index) => (
            <div
              key={note.title}
              className="flex items-center gap-[6px]"
              style={{padding: '6px 8px', borderRadius: 7, background: index === 0 ? white(0.1) : 'transparent'}}
            >
              <div className="min-w-0 flex-1">
                <div className="truncate text-[10.5px] leading-[13px] font-semibold">{note.title}</div>
                <div className="text-[9px] leading-[12px] font-medium text-label-3">{index === 0 ? 'Just now' : note.date}</div>
              </div>
              <div className="font-mono text-[10px] text-label-3">⌘{index + 1}</div>
            </div>
          ))}
        </div>
      </div>
      <Hairline vertical />
      <div className="flex min-w-0 flex-1 flex-col" style={{paddingLeft: 10}}>
        <div className="flex h-[34px] shrink-0 items-center gap-[9px]">
          <StickyNote size={11} strokeWidth={2.2} color={color.blue} />
          <div className="text-[11px] font-semibold">{notes.title}</div>
          <div className="flex-1" />
          {TOOLS.map((Tool, index) => (
            <div key={index} className="flex items-center gap-[9px]">
              <Tool size={12} strokeWidth={2.1} color={color.secondary} />
              {TOOL_GROUP_ENDS.includes(index) ? <div style={{width: 1, height: 12, background: white(0.14)}} /> : null}
            </div>
          ))}
        </div>
        <div className="flex h-[20px] shrink-0 items-center gap-[5px]">
          {['#launch', '#film'].map((tag) => (
            <div
              key={tag}
              className="rounded-[5px] px-[5px] text-[9px] leading-[14px] font-semibold"
              style={{color: color.cyan, background: 'rgba(100,210,255,0.1)'}}
            >
              {tag}
            </div>
          ))}
          <div className="flex-1" />
          <div className="tabular text-[9px] text-label-3">{characters} characters</div>
        </div>
        <div
          className="relative min-h-0 flex-1 overflow-hidden"
          style={{
            marginTop: 4,
            borderRadius: '8px 8px 22px 8px',
            background: white(0.05),
            border: `1px solid ${white(0.12)}`,
            padding: '4px 14px 20px',
            fontSize: 13,
            lineHeight: 1.55,
            color: white(0.92),
          }}
        >
          {notes.body.map((block) => {
            if (block.kind === 'h1') {
              return (
                <div key={block.text} className="font-bold" style={{fontSize: 23, lineHeight: 1.3, margin: '8px 0 4px'}}>
                  {block.text}
                </div>
              );
            }
            if (block.kind === 'h2') {
              return (
                <div key={block.text} className="font-semibold" style={{fontSize: 19, lineHeight: 1.3, margin: '11px 0 6px'}}>
                  {block.text}
                </div>
              );
            }
            if (block.kind === 'check') {
              checkIndex += 1;
              const fill = Math.max(0, Math.min(1, checked - checkIndex));
              return (
                <div key={block.text} className="flex items-center" style={{margin: '2px 0'}}>
                  <div
                    className="flex shrink-0 items-center justify-center"
                    style={{
                      width: 13,
                      height: 13,
                      marginRight: 7,
                      borderRadius: 3.5,
                      border: `1px solid ${fill > 0.5 ? color.blue : white(0.4)}`,
                      background: fill > 0.5 ? color.blue : 'transparent',
                    }}
                  >
                    <svg width={9} height={9} viewBox="0 0 9 9">
                      <path
                        d="M1.6 4.7 L3.7 6.7 L7.4 2.4"
                        fill="none"
                        stroke="#fff"
                        strokeWidth={1.6}
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeDasharray={9}
                        strokeDashoffset={9 * (1 - fill)}
                      />
                    </svg>
                  </div>
                  <span className="truncate">{block.text}</span>
                </div>
              );
            }
            if (block.kind === 'code') {
              return (
                <div
                  key={block.text}
                  className="truncate font-mono"
                  style={{fontSize: 11.5, background: white(0.08), borderRadius: 6, padding: '8px 10px', marginTop: 6}}
                >
                  {block.text}
                </div>
              );
            }
            return (
              <div key={block.text} style={{margin: '5px 0'}}>
                {block.text}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};
