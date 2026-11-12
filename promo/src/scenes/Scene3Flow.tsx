import {useCurrentFrame, useVideoConfig} from 'remotion';
import {Caption} from '../components/Caption';
import {ClickRipple, Cursor} from '../components/Cursor';
import {MenuBar, Notch, Wallpaper} from '../components/Desktop';
import {GlassPanel, Waveform, waveLevels} from '../components/Glass';
import {Island, modulePhase} from '../components/Island';
import {
  AlbumArt,
  BrowserGlyph,
  CompactCheck,
  CompactPercent,
  IslandBody,
  NowPlayingHeader,
  StatusHeader,
  TABS,
  formatTime,
  lyricAt,
} from '../components/IslandChrome';
import {DragGhost, DropShoulders, QuickActionToast} from '../components/Overlays';
import {BrowserWindow, DownloadPopover, FinderWindow} from '../components/Windows';
import type {FinderItem} from '../components/Windows';
import {copy, download, focus, shelfItems, track as song} from '../content';
import type {ShelfItem} from '../content';
import {HomeModule} from '../modules/HomeModule';
import {ShelfModule} from '../modules/ShelfModule';
import {FilmMotion, ZislaMotion, ease, easeOutAt, fadeWindow, linear, springAt} from '../motion';
import {filmFrame} from '../timeline';
import {MODULE_HEIGHT, STAGE, clamp01, color, islandHeightFor, lerp, white} from '../theme';

const CENTER = STAGE.width / 2;

// 三拍：媒体 → Handoff → 下载。幕首接着上一幕的展开态，不再重新展开
const MEDIA = {open: 0, close: 226};
const HANDOFF = {start: 250, grab: 292, drop: 384, open: 388, close: 500};
const DOWNLOAD = {start: 516, done: 640, toast: 650, click: 716, finder: 722};

const LYRIC_PERIOD = 132;

const dropped = shelfItems[0] as ShelfItem;
// 托盘里已有的条目在前，刚拖进来的那一个排在最后吸附进去
const SHELF = [...shelfItems.slice(1), dropped];

const DESIGN_FILES: readonly FinderItem[] = [
  {name: dropped.name, tint: dropped.tint, kind: 'image'},
  {name: 'Motion Study.mp4', tint: '#ff9d6c', kind: 'video'},
  {name: 'Release Notes.md', tint: '#8fe3c0', kind: 'text'},
  {name: 'Exports', tint: '#9ad0ff', kind: 'folder'},
];

const DOWNLOADS: readonly FinderItem[] = [
  {name: download.name, tint: '#ffcf7a', kind: 'archive'},
  {name: 'Glass Sample.heic', tint: '#ffa8c4', kind: 'image'},
  {name: 'Spec Draft.pages', tint: '#9fb4ff', kind: 'text'},
  {name: 'Archive', tint: '#9ad0ff', kind: 'folder'},
];

const DESIGN_WINDOW = {x: 150, y: 352, width: 500, height: 262};
const GRAB = {x: DESIGN_WINDOW.x + 18 + 58, y: DESIGN_WINDOW.y + 65 + 18 + 34};
// DropShoulders 右侧 Shelf 肩的中心
const SHOULDER = {x: CENTER + 376 - 54, y: 88};
const BROWSER = {x: 260, y: 150, width: 760, height: 470};
// QuickActionToast 里 “Open Folder” 按钮的中心
const TOAST_ACTION = {x: 808, y: 18};

export const Scene3Flow = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  // 歌和番茄钟从片头一直在走，读数按全片时间算，前后几幕才接得上
  const played = filmFrame('flow', frame);
  const elapsed = song.elapsed + played / fps;
  const levels = waveLevels(frame, 1, 0);
  const spectrum = [0, 1, 2, 3, 4, 5, 6].flatMap((seed) => [...waveLevels(frame, 1, seed)]);

  const mediaReveal = Math.max(0, 1 - springAt(frame, fps, MEDIA.close, ZislaMotion.islandRecycle, 34));
  const shelfReveal = Math.max(
    0,
    springAt(frame, fps, HANDOFF.open, ZislaMotion.islandReveal, 42) - springAt(frame, fps, HANDOFF.close, ZislaMotion.islandRecycle, 34),
  );
  const inMedia = frame < HANDOFF.start;
  const inDownload = frame >= DOWNLOAD.start;
  const reveal = inMedia ? mediaReveal : shelfReveal;

  // 媒体特写：岛外的放大唱片只是影片层的强调，岛内封面保持静止
  const spotlight = Math.min(springAt(frame, fps, MEDIA.open + 22, FilmMotion.gentle, 38), linear(frame, [MEDIA.close - 22, MEDIA.close], [1, 0]));
  const lyricIndex = Math.floor(played / LYRIC_PERIOD) % song.lyrics.length;
  const lyric = lyricAt(played, LYRIC_PERIOD);

  // Handoff：抓起 → 拖到 Shelf 肩 → 松手吸附
  const windowIn = Math.min(springAt(frame, fps, HANDOFF.start, FilmMotion.gentle, 34), linear(frame, [HANDOFF.close - 6, HANDOFF.close + 14], [1, 0]));
  const travel = ease(frame, [HANDOFF.grab + 10, HANDOFF.drop - 12], [0, 1]);
  const hold = springAt(frame, fps, HANDOFF.grab, FilmMotion.pop, 24);
  const ghostX = lerp(GRAB.x, SHOULDER.x, travel);
  const ghostY = lerp(GRAB.y, SHOULDER.y, travel) - Math.sin(travel * Math.PI) * 40;
  const ghostOpacity = frame >= HANDOFF.grab ? linear(frame, [HANDOFF.drop, HANDOFF.drop + 10], [1, 0]) : 0;
  const shoulders = Math.min(linear(frame, [HANDOFF.grab + 22, HANDOFF.grab + 38], [0, 1]), linear(frame, [HANDOFF.drop, HANDOFF.drop + 12], [1, 0]));
  const overShelf = travel > 0.82 ? 1 : 0;
  const landed = springAt(frame, fps, HANDOFF.open + 16, ZislaMotion.surfaceResize, 36);
  const menu = Math.min(linear(frame, [448, 458], [0, 1]), linear(frame, [HANDOFF.close - 16, HANDOFF.close - 6], [1, 0]));

  // 下载：浏览器里跑进度，收起态两翼同步，完成后顶部落下快捷操作
  const downloadProgress = ease(frame, [DOWNLOAD.start + 34, DOWNLOAD.done], [0.38, 1]);
  const done = frame >= DOWNLOAD.done;
  const browserIn = Math.min(springAt(frame, fps, DOWNLOAD.start, FilmMotion.gentle, 34), linear(frame, [DOWNLOAD.finder, DOWNLOAD.finder + 18], [1, 0.0]));
  const popover = Math.min(linear(frame, [DOWNLOAD.start + 24, DOWNLOAD.start + 38], [0, 1]), linear(frame, [DOWNLOAD.toast + 10, DOWNLOAD.toast + 24], [1, 0]));
  const downloadWing = lerp(0, 44, clamp01(springAt(frame, fps, DOWNLOAD.start + 30, ZislaMotion.notice, 30)));
  const toast = springAt(frame, fps, DOWNLOAD.toast, ZislaMotion.quickAction, 30);
  const finderIn = springAt(frame, fps, DOWNLOAD.finder, FilmMotion.gentle, 36);

  let cursorX = 0;
  let cursorY = 0;
  let cursorOpacity = 0;
  let pressed = 0;
  if (!inMedia && !inDownload) {
    const approach = easeOutAt(frame, [HANDOFF.start + 6, HANDOFF.grab], [0, 1]);
    const toMenu = ease(frame, [HANDOFF.drop + 30, 452], [0, 1]);
    cursorX = frame < HANDOFF.grab ? lerp(330, GRAB.x, approach) : lerp(ghostX, 876, toMenu);
    cursorY = frame < HANDOFF.grab ? lerp(560, GRAB.y, approach) : lerp(ghostY, 304, toMenu);
    cursorOpacity = Math.min(linear(frame, [HANDOFF.start + 4, HANDOFF.start + 18], [0, 1]), linear(frame, [HANDOFF.close - 4, HANDOFF.close + 10], [1, 0]));
    pressed = frame >= HANDOFF.grab && frame < HANDOFF.drop ? 1 : 0;
  } else if (inDownload) {
    const toAction = ease(frame, [DOWNLOAD.toast + 10, DOWNLOAD.click - 6], [0, 1]);
    cursorX = lerp(700, TOAST_ACTION.x, toAction);
    cursorY = lerp(330, TOAST_ACTION.y, toAction);
    cursorOpacity = linear(frame, [DOWNLOAD.start + 8, DOWNLOAD.start + 22], [0, 1]);
    pressed = frame >= DOWNLOAD.click && frame < DOWNLOAD.click + 8 ? 1 : 0;
  }

  const mediaWing = lerp(74, 0, clamp01((frame - HANDOFF.grab - 16) / 20));

  return (
    <>
      <Wallpaper dim={0.14} />
      <MenuBar appName={inDownload ? 'Browser' : 'Finder'} menus={['File', 'Edit', 'View', 'Go', 'Window', 'Help']} />

      {!inMedia && !inDownload ? (
        <FinderWindow
          {...DESIGN_WINDOW}
          items={DESIGN_FILES}
          path="Design"
          selected={0}
          selectGlow={frame >= HANDOFF.grab - 4 ? 1 : 0}
          opacity={windowIn}
          scale={0.96 + 0.04 * clamp01(windowIn)}
        />
      ) : null}

      {inDownload && browserIn > 0.01 ? (
        <BrowserWindow {...BROWSER} progress={downloadProgress} opacity={browserIn} scale={0.96 + 0.04 * clamp01(browserIn)} />
      ) : null}
      {inDownload ? (
        <DownloadPopover x={BROWSER.x + BROWSER.width - 356} y={BROWSER.y + 76} progress={downloadProgress} opacity={popover} done={done} />
      ) : null}
      {inDownload && frame >= DOWNLOAD.finder ? (
        <FinderWindow
          x={316}
          y={196}
          items={DOWNLOADS}
          path={download.folder}
          selected={0}
          selectGlow={linear(frame, [DOWNLOAD.finder + 16, DOWNLOAD.finder + 30], [0, 1])}
          opacity={finderIn}
          scale={0.94 + 0.06 * clamp01(finderIn)}
        />
      ) : null}

      {inMedia && spotlight > 0.01 ? (
        <GlassPanel
          radius={26}
          opacity={clamp01(spotlight)}
          className="absolute flex items-center gap-[34px]"
          style={{left: CENTER - 340, top: 286 + (1 - spotlight) * 18, width: 680, height: 236, padding: '0 34px'}}
        >
          <div
            className="relative shrink-0 overflow-hidden rounded-full"
            style={{width: 172, height: 172, transform: `rotate(${frame * 0.55}deg)`, boxShadow: '0 18px 44px rgba(0,0,0,0.55)'}}
          >
            <AlbumArt size={172} radius={86} />
            <div
              className="absolute rounded-full"
              style={{left: 72, top: 72, width: 28, height: 28, background: '#0c0c10', border: `1px solid ${white(0.3)}`}}
            />
          </div>
          <div className="flex min-w-0 flex-1 flex-col">
            <div className="text-[24px] leading-[28px] font-semibold">{song.title}</div>
            <div className="text-[14px] leading-[20px] text-label-2">
              {song.artist} · {song.album}
            </div>
            <div style={{marginTop: 14}}>
              <div className="flex items-center gap-[3px]" style={{height: 46}}>
                {spectrum.map((level, index) => (
                  <div
                    key={index}
                    className="rounded-full"
                    style={{width: 5, height: 4 + 42 * level, background: color.coverTint, opacity: 0.55 + 0.45 * level}}
                  />
                ))}
              </div>
            </div>
            <div className="tabular flex justify-between font-mono text-[11px] text-label-3" style={{marginTop: 6}}>
              <span>{formatTime(elapsed)}</span>
              <span>{formatTime(song.duration)}</span>
            </div>
            <div className="relative overflow-hidden" style={{marginTop: 10, height: 48}}>
              <div
                className="absolute inset-x-0 truncate text-[17px] leading-[24px] font-medium"
                style={{top: (1 - lyric.opacity) * 24, opacity: lyric.opacity}}
              >
                {lyric.text}
              </div>
              <div
                className="absolute inset-x-0 truncate text-[13px] leading-[24px] text-label-3"
                style={{top: 24 + (1 - lyric.opacity) * 24, opacity: 0.4 + 0.6 * lyric.opacity}}
              >
                {song.lyrics[(lyricIndex + 1) % song.lyrics.length]}
              </div>
            </div>
          </div>
        </GlassPanel>
      ) : null}

      <DropShoulders highlight={overShelf} opacity={shoulders} frame={frame} />

      <Island
        reveal={reveal}
        height={islandHeightFor(inMedia ? MODULE_HEIGHT.home : MODULE_HEIGHT.shelf)}
        wing={inDownload ? downloadWing : mediaWing}
        left={inDownload ? <BrowserGlyph size={20} /> : <AlbumArt size={26} radius={5} />}
        right={
          inDownload ? (
            done ? (
              <CompactCheck />
            ) : (
              <CompactPercent value={downloadProgress} />
            )
          ) : (
            <Waveform width={34} height={18} levels={levels} />
          )
        }
        progress={
          inDownload
            ? frame >= DOWNLOAD.start + 30
              ? {value: downloadProgress, tint: done ? color.green : color.blue}
              : undefined
            : frame < HANDOFF.grab + 16
              ? {value: clamp01(elapsed / song.duration), tint: color.coverTint}
              : undefined
        }
      >
        {inMedia ? (
          <IslandBody header={<NowPlayingHeader elapsed={elapsed} levels={levels} lyric={lyric} />} active={TABS.home}>
            <div style={modulePhase(clamp01((frame - MEDIA.open - 8) / 24), 1, true)}>
              <HomeModule cards={['media', 'focus']} focusRemaining={focus.remaining - played / fps} />
            </div>
          </IslandBody>
        ) : (
          <IslandBody header={<StatusHeader />} active={TABS.shelf}>
            <div className="absolute inset-0" style={modulePhase(clamp01((frame - HANDOFF.open - 8) / 24), 1, true)}>
              <ShelfModule
                items={SHELF}
                enter={SHELF.length - 1 + clamp01(landed)}
                highlight={SHELF.length - 1}
                moreButtons={linear(frame, [HANDOFF.open + 40, HANDOFF.open + 54], [0, 1])}
                actionGlow={fadeWindow(frame, HANDOFF.open + 52, 452, 10)}
                menu={menu}
                menuHighlight={linear(frame, [462, 474], [0, 1])}
              />
            </div>
          </IslandBody>
        )}
      </Island>
      <Notch />

      {inDownload && frame >= DOWNLOAD.toast ? (
        <QuickActionToast
          title={download.name}
          detail={`Saved to ${download.path}`}
          action="Open Folder"
          opacity={toast}
          countdown={linear(frame, [DOWNLOAD.toast, DOWNLOAD.toast + 360], [1, 0])}
          actionGlow={linear(frame, [DOWNLOAD.click - 12, DOWNLOAD.click], [0, 1])}
        />
      ) : null}

      <DragGhost x={ghostX} y={ghostY} name={dropped.name} tint={dropped.tint} hold={clamp01(hold)} opacity={ghostOpacity} />
      {inDownload ? <ClickRipple x={TOAST_ACTION.x} y={TOAST_ACTION.y} progress={linear(frame, [DOWNLOAD.click, DOWNLOAD.click + 22], [0, 1])} /> : null}
      <Cursor x={cursorX} y={cursorY} pressed={pressed} opacity={cursorOpacity} />

      <Caption text={copy.flow.media} opacity={fadeWindow(frame, MEDIA.open + 40, MEDIA.close + 4)} bottom={86} />
      <Caption text={copy.flow.handoff} opacity={fadeWindow(frame, HANDOFF.grab + 20, HANDOFF.close + 2)} bottom={40} />
      <Caption text={copy.flow.download} opacity={fadeWindow(frame, DOWNLOAD.start + 40, 772)} bottom={40} />
    </>
  );
};
