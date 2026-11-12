import type {ReactNode} from 'react';
import {useCurrentFrame, useVideoConfig} from 'remotion';
import {Gauge, Layers, Feather} from 'lucide-react';
import {Headline} from '../components/Caption';
import {Wallpaper} from '../components/Desktop';
import {GlassPanel} from '../components/Glass';
import {AgendaModule} from '../modules/AgendaModule';
import {ClipboardModule} from '../modules/ClipboardModule';
import {NotesModule} from '../modules/NotesModule';
import {AudioModule, ImagesModule, PDFModule, ScreenRecordingModule, ScreenshotsModule} from '../modules/ToolsModule';
import {SystemModule} from '../modules/SystemModule';
import {copy, metrics} from '../content';
import {FilmMotion, ease, fadeWindow, springAt} from '../motion';
import {STAGE, clamp01, color, white} from '../theme';
import {filmFrame} from '../timeline';

const METRIC_ICONS = [Gauge, Feather, Layers];

// Existing module geometry stays intact for the opening group.
const GAP = 18;
const GRID = {left: 96, right: 1184, top: 190};
const COLUMN = (GRID.right - GRID.left - GAP) / 2;
const ROW_TOP = 281;
const ROW_BOTTOM = 115;
const RIGHT = GRID.left + COLUMN + GAP;
const BOTTOM = GRID.top + ROW_TOP + GAP;
const TITLE_TOP = GRID.top - 86;
// Center the push between the headline and the lower cards.
const FOCUS_Y = (TITLE_TOP + BOTTOM + ROW_BOTTOM) / 2;

// Fit the module inside GlassPanel's one-point border.
const BORDER = 1;
// This height fits six complete clipboard rows.
const CLIPBOARD_HEIGHT = 390;
// AgendaModule has no padding of its own.
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

// Scale each module within the existing glass boundary.
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

const MetricsRow = ({x, y, width, enter, expanded = false}: {x: number; y: number; width: number; enter: number; expanded?: boolean}) => {
  const metricWidth = (width - GAP * 2) / 3;
  return metrics.map((metric, index) => {
    const Icon = METRIC_ICONS[index];
    const long = metric.value.length > 8;
    const valueSize = expanded ? (long ? 29 : 34) : long ? 19 : metric.value.length > 3 ? 26 : 34;
    return (
      <GlassPanel
        key={metric.label}
        radius={18}
        opacity={enter}
        className="absolute flex flex-col"
        style={{
          left: x + index * (metricWidth + GAP),
          top: y,
          width: metricWidth,
          height: ROW_BOTTOM,
          padding: '14px 16px',
          transform: `translateY(${(1 - enter) * 22}px) scale(${0.96 + 0.04 * enter})`,
          boxShadow: '0 26px 60px rgba(0,0,0,0.5)',
        }}
      >
        <Icon size={15} strokeWidth={2.2} color={color.secondary} />
        <div className="font-rounded tabular" style={{marginTop: 8, fontSize: valueSize, lineHeight: '36px', fontWeight: 700, letterSpacing: '-0.02em', color: index === 0 ? color.green : white(0.96)}}>{metric.value}</div>
        <div className="font-medium" style={{marginTop: 2, lineHeight: '17px', color: color.secondary, fontSize: expanded ? 15 : long ? 10 : 11}}>{metric.label}</div>
      </GlassPanel>
    );
  });
};

export const Scene4Bento = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const global = filmFrame('bento', frame);

  const everyday = ease(frame, [140, 150], [1, 0]);
  const capture = fadeWindow(frame, 140, 330, 10);
  const processing = fadeWindow(frame, 320, 500, 10);
  const system = ease(frame, [490, 500], [0, 1]);
  const cellIn = (index: number) => everyday * clamp01(springAt(frame, fps, 22 + index * 8, FilmMotion.pop, 26));
  const captureIn = capture * clamp01(springAt(frame, fps, 140, FilmMotion.pop, 26));
  const toolsIn = (index: number) => processing * clamp01(springAt(frame, fps, 320 + index * 7, FilmMotion.pop, 26));
  const systemIn = system * clamp01(springAt(frame, fps, 490, FilmMotion.pop, 26));
  const push = ease(frame, [300, 600], [1, 1.06]);
  const toolsWidth = (GRID.right - GRID.left - GAP * 2) / 3;

  return (
    <>
      <Wallpaper dim={0.42} />

      <div className="absolute left-0 top-0" style={{width: STAGE.width, height: STAGE.height, transform: `scale(${push})`, transformOrigin: `50% ${FOCUS_Y}px`}}>
        <Headline lines={['Beautifully native. Built for every day.']} top={TITLE_TOP} size={38} align="left" opacity={everyday * clamp01(springAt(frame, fps, 10, FilmMotion.title, 34))}>
          <div style={{marginTop: 9, fontSize: 17, lineHeight: '23px', color: color.secondary}}>{copy.bento}</div>
        </Headline>
        <Headline lines={['Capture it. Make it clear.']} top={TITLE_TOP} size={38} align="left" opacity={capture * clamp01(springAt(frame, fps, 140, FilmMotion.title, 32))} />
        <Headline lines={['Create with images, audio and PDFs.']} top={TITLE_TOP} size={38} align="left" opacity={processing * clamp01(springAt(frame, fps, 320, FilmMotion.title, 32))} />
        <Headline lines={['Your Mac, at a glance.']} top={TITLE_TOP} size={38} align="left" opacity={system * clamp01(springAt(frame, fps, 490, FilmMotion.title, 32))} />

        <Cell x={GRID.left} y={GRID.top} width={COLUMN} height={ROW_TOP} scale={0.7} enter={cellIn(0)}>
          <NotesModule checked={1.6 + 2 * clamp01((frame - 50) / 70)} />
        </Cell>

        <Cell x={RIGHT} y={GRID.top} width={COLUMN} height={ROW_TOP} scale={(ROW_TOP - BORDER * 2) / CLIPBOARD_HEIGHT} enter={cellIn(1)}>
          <ClipboardModule filter={clamp01((frame - 75) / 50) * 4} />
        </Cell>

        <Cell x={GRID.left} y={BOTTOM} width={COLUMN} height={ROW_BOTTOM} scale={0.68} enter={cellIn(2)} radius={18}>
          <div className="absolute" style={{inset: AGENDA_INSET}}>
            <AgendaModule done={clamp01((frame - 85) / 40)} />
          </div>
        </Cell>

        <MetricsRow x={RIGHT} y={BOTTOM} width={COLUMN} enter={cellIn(3)} />

        <Cell x={GRID.left} y={GRID.top} width={COLUMN} height={418} scale={1} enter={captureIn}>
          <ScreenshotsModule annotation={ease(frame, [168, 225], [0, 1])} />
        </Cell>
        <Cell x={RIGHT} y={GRID.top} width={COLUMN} height={418} scale={1} enter={captureIn}>
          <ScreenRecordingModule frame={global} />
        </Cell>

        <Cell x={GRID.left} y={GRID.top} width={toolsWidth} height={418} scale={1} enter={toolsIn(0)}>
          <ImagesModule progress={ease(frame, [346, 395], [0.15, 1])} />
        </Cell>
        <Cell x={GRID.left + toolsWidth + GAP} y={GRID.top} width={toolsWidth} height={418} scale={1} enter={toolsIn(1)}>
          <AudioModule frame={global} progress={ease(frame, [353, 402], [0.15, 1])} />
        </Cell>
        <Cell x={GRID.left + (toolsWidth + GAP) * 2} y={GRID.top} width={toolsWidth} height={418} scale={1} enter={toolsIn(2)}>
          <PDFModule progress={ease(frame, [360, 409], [0.15, 1])} />
        </Cell>

        <Cell x={GRID.left} y={GRID.top} width={GRID.right - GRID.left} height={300} scale={1} enter={systemIn}>
          <SystemModule frame={global} />
        </Cell>
        <MetricsRow x={GRID.left} y={GRID.top + 300 + GAP} width={GRID.right - GRID.left} enter={systemIn} expanded />
      </div>
    </>
  );
};
