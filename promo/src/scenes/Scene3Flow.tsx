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
import {DragGhost, QuickActionToast, ShelfContextMenu} from '../components/Overlays';
import {BrowserWindow, DownloadPopover, FinderWindow} from '../components/Windows';
import type {FinderItem} from '../components/Windows';
import {copy, download, focus, shelfItems, track as song} from '../content';
import type {ShelfItem} from '../content';
import {HomeModule} from '../modules/HomeModule';
import {ShelfModule} from '../modules/ShelfModule';
import {shelfItemPoint, shelfMenuPlacement} from '../modules/shelfLayout';
import {FilmMotion, ZislaMotion, ease, easeOutAt, fadeWindow, linear, springAt} from '../motion';
import {filmFrame} from '../timeline';
import {ISLAND, MODULE_HEIGHT, STAGE, clamp01, color, islandHeightFor, lerp, white} from '../theme';

const CENTER = STAGE.width / 2;

// Continue the previous scene's expanded state before handoff and downloads.
const MEDIA = {open: 0, close: 226};
const HANDOFF = {start: 250, grab: 292, open: 326, drop: 384, close: 500};
const DOWNLOAD = {start: 516, done: 640, toast: 650, click: 716, finder: 722};

const LYRIC_PERIOD = 132;

const dropped = shelfItems[0] as ShelfItem;
// The incoming file settles after the items already in the shelf.
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

const DESIGN_WINDOW = {x: 100, y: 438, width: 500, height: 220};
const GRAB = {x: DESIGN_WINDOW.x + 18 + 58, y: DESIGN_WINDOW.y + 65 + 18 + 34};
const SHELF_ORIGIN = {x: CENTER - ISLAND.width / 2 + ISLAND.moduleInset, y: ISLAND.chromeHeight + ISLAND.moduleInset};
const LAST_FILE = shelfItemPoint(SHELF.length - 1);
const DROP = {x: SHELF_ORIGIN.x + LAST_FILE.x, y: SHELF_ORIGIN.y + LAST_FILE.y};
const MENU_ANCHOR = {x: DROP.x + 8, y: DROP.y + 31};
const MENU = shelfMenuPlacement(MENU_ANCHOR, STAGE);
const FINDER_ACTION = {x: MENU.x + 70, y: MENU.y + 42};
const BROWSER = {x: 260, y: 150, width: 760, height: 470};
// Center of the existing Open Folder quick action.
const TOAST_ACTION = {x: 808, y: 18};

export const Scene3Flow = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  // Shared media and focus counters stay continuous across scenes.
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

  // The film spotlight rotates; the application's artwork stays still.
  const spotlight = Math.min(springAt(frame, fps, MEDIA.open + 22, FilmMotion.gentle, 38), linear(frame, [MEDIA.close - 22, MEDIA.close], [1, 0]));
  const lyricIndex = Math.floor(played / LYRIC_PERIOD) % song.lyrics.length;
  const lyric = lyricAt(played, LYRIC_PERIOD);

  // Enter the top trigger, expand the shelf, then settle the file in its grid slot.
  const windowIn = Math.min(springAt(frame, fps, HANDOFF.start, FilmMotion.gentle, 34), linear(frame, [HANDOFF.close - 6, HANDOFF.close + 14], [1, 0]));
  const hold = springAt(frame, fps, HANDOFF.grab, FilmMotion.pop, 24);
  const toTrigger = ease(frame, [HANDOFF.grab + 10, HANDOFF.open], [0, 1]);
  const toGrid = ease(frame, [HANDOFF.open + 8, HANDOFF.drop], [0, 1]);
  const ghostX = frame < HANDOFF.open ? lerp(GRAB.x, CENTER, toTrigger) : lerp(CENTER, DROP.x, toGrid);
  const ghostY = frame < HANDOFF.open ? lerp(GRAB.y, 4, toTrigger) : lerp(4, DROP.y, toGrid);
  const ghostOpacity = frame >= HANDOFF.grab ? linear(frame, [HANDOFF.drop, HANDOFF.drop + 10], [1, 0]) : 0;
  const dropHover = frame >= HANDOFF.open + 8 && frame < HANDOFF.drop ? 1 : 0;
  const landed = springAt(frame, fps, HANDOFF.drop, ZislaMotion.surfaceResize, 24);
  const menu = Math.min(linear(frame, [448, 458], [0, 1]), linear(frame, [HANDOFF.close - 16, HANDOFF.close - 6], [1, 0]));

  // Download progress hands off to the top-edge quick action.
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
    const toFile = ease(frame, [HANDOFF.drop + 16, 448], [0, 1]);
    const toAction = ease(frame, [458, 474], [0, 1]);
    cursorX = frame < HANDOFF.grab ? lerp(330, GRAB.x, approach) : frame < 458 ? lerp(ghostX, MENU_ANCHOR.x, toFile) : lerp(MENU_ANCHOR.x, FINDER_ACTION.x, toAction);
    cursorY = frame < HANDOFF.grab ? lerp(560, GRAB.y, approach) : frame < 458 ? lerp(ghostY, MENU_ANCHOR.y, toFile) : lerp(MENU_ANCHOR.y, FINDER_ACTION.y, toAction);
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
                dropHover={dropHover}
              />
            </div>
          </IslandBody>
        )}
      </Island>
      <Notch />
      {menu > 0 ? <ShelfContextMenu anchor={MENU_ANCHOR} opacity={menu} highlight={linear(frame, [462, 474], [0, 1])} /> : null}

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
