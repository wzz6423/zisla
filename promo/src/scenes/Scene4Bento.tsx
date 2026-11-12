import type {ReactNode} from 'react';
import {useCurrentFrame, useVideoConfig} from 'remotion';
import {Gauge, Layers, Feather} from 'lucide-react';
import {Headline} from '../components/Caption';
import {Wallpaper} from '../components/Desktop';
import {GlassPanel} from '../components/Glass';
import {AgendaModule} from '../modules/AgendaModule';
import {ClipboardModule} from '../modules/ClipboardModule';
import {NotesModule} from '../modules/NotesModule';
import {copy, metrics} from '../content';
import {FilmMotion, ease, springAt} from '../motion';
import {STAGE, clamp01, color, white} from '../theme';

const METRIC_ICONS = [Gauge, Feather, Layers];

// 两列便当格：沟槽统一为 GAP，上排两格等高，下排右列再三等分
const GAP = 18;
const GRID = {left: 96, right: 1184, top: 190};
const COLUMN = (GRID.right - GRID.left - GAP) / 2;
const ROW_TOP = 281;
const ROW_BOTTOM = 115;
const RIGHT = GRID.left + COLUMN + GAP;
const BOTTOM = GRID.top + ROW_TOP + GAP;
const METRIC_WIDTH = (COLUMN - GAP * 2) / 3;
const TITLE_TOP = GRID.top - 86;
// 推近以标题到网格底的中点为中心，上下留白才不会越推越偏
const FOCUS_Y = (TITLE_TOP + BOTTOM + ROW_BOTTOM) / 2;

// GlassPanel 的描边占 1px，可用内容区比外框每边小这么多
const BORDER = 1;
// 剪贴板模块排到这个高度时列表正好容下六行，再高会露出半截第七行
const CLIPBOARD_HEIGHT = 390;
// 日程模块自身不带边距，贴边会被玻璃的圆角裁掉
const AGENDA_INSET = '6px 14px';

type CellProps = {
  x: number;
  y: number;
  width: number;
  height: number;
  scale: number;
  enter: number;
  radius?: number;
  children: ReactNode;
};

// 便当格：外层玻璃按网格尺寸摆放，模块在内层按原始密度排版，再整体缩放进描边以内
const Cell = ({x, y, width, height, scale, enter, radius = 22, children}: CellProps) => (
  <GlassPanel
    radius={radius}
    opacity={clamp01(enter)}
    className="absolute"
    style={{
      left: x,
      top: y,
      width,
      height,
      transform: `translateY(${(1 - clamp01(enter)) * 22}px) scale(${0.96 + 0.04 * clamp01(enter)})`,
      boxShadow: '0 26px 60px rgba(0,0,0,0.5)',
    }}
  >
    <div
      className="absolute left-0 top-0"
      style={{
        width: (width - BORDER * 2) / scale,
        height: (height - BORDER * 2) / scale,
        transform: `scale(${scale})`,
        transformOrigin: '0 0',
      }}
    >
      {children}
    </div>
  </GlassPanel>
);

export const Scene4Bento = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();

  // 便当格依次弹入，末尾整组缓慢推近
  const cellIn = (index: number) => springAt(frame, fps, 40 + index * 20, FilmMotion.pop, 34);
  const push = ease(frame, [300, 600], [1, 1.06]);

  return (
    <>
      <Wallpaper dim={0.42} />

      <div className="absolute left-0 top-0" style={{width: STAGE.width, height: STAGE.height, transform: `scale(${push})`, transformOrigin: `50% ${FOCUS_Y}px`}}>
        <Headline lines={[copy.bento]} top={TITLE_TOP} size={38} align="left" opacity={clamp01(springAt(frame, fps, 16, FilmMotion.title, 40))} />

        <Cell x={GRID.left} y={GRID.top} width={COLUMN} height={ROW_TOP} scale={0.7} enter={cellIn(0)}>
          <NotesModule checked={1.6 + 2 * clamp01((frame - 120) / 90)} />
        </Cell>

        <Cell x={RIGHT} y={GRID.top} width={COLUMN} height={ROW_TOP} scale={(ROW_TOP - BORDER * 2) / CLIPBOARD_HEIGHT} enter={cellIn(1)}>
          <ClipboardModule filter={clamp01((frame - 150) / 70) * 4} />
        </Cell>

        <Cell x={GRID.left} y={BOTTOM} width={COLUMN} height={ROW_BOTTOM} scale={0.68} enter={cellIn(2)} radius={18}>
          <div className="absolute" style={{inset: AGENDA_INSET}}>
            <AgendaModule done={clamp01((frame - 210) / 60)} />
          </div>
        </Cell>

        {metrics.map((metric, index) => {
          const Icon = METRIC_ICONS[index];
          const enter = clamp01(cellIn(3 + index));
          // 长数值（macOS 14–26）换行会把标签挤出格子，按长度降字号保证单行
          const long = metric.value.length > 8;
          const valueSize = long ? 19 : metric.value.length > 3 ? 26 : 34;
          return (
            <GlassPanel
              key={metric.label}
              radius={18}
              opacity={enter}
              className="absolute flex flex-col"
              style={{
                left: RIGHT + index * (METRIC_WIDTH + GAP),
                top: BOTTOM,
                width: METRIC_WIDTH,
                height: ROW_BOTTOM,
                padding: '14px 16px',
                transform: `translateY(${(1 - enter) * 22}px) scale(${0.96 + 0.04 * enter})`,
                boxShadow: '0 26px 60px rgba(0,0,0,0.5)',
              }}
            >
              <Icon size={15} strokeWidth={2.2} color={color.secondary} />
              <div
                className="font-rounded tabular"
                style={{
                  marginTop: 8,
                  fontSize: valueSize,
                  lineHeight: '36px',
                  fontWeight: 700,
                  letterSpacing: '-0.02em',
                  color: index === 0 ? color.green : white(0.96),
                }}
              >
                {metric.value}
              </div>
              <div className="leading-[15px] font-medium" style={{marginTop: 2, color: color.secondary, fontSize: long ? 10 : 11}}>
                {metric.label}
              </div>
            </GlassPanel>
          );
        })}
      </div>
    </>
  );
};
