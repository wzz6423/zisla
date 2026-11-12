import {Img, useCurrentFrame, useVideoConfig} from 'remotion';
import {Blackout} from '../components/Caption';
import {Cursor} from '../components/Cursor';
import {MenuBar, Notch, Wallpaper} from '../components/Desktop';
import {GLASS_BLUR, waveLevels} from '../components/Glass';
import {Island} from '../components/Island';
import {IslandBody, NowPlayingHeader, TABS, lyricAt} from '../components/IslandChrome';
import {Caret, typedChars} from '../components/Terminal';
import {githubMark, zislaIcon} from '../assets';
import {copy, focus, track} from '../content';
import {HomeModule} from '../modules/HomeModule';
import {FilmMotion, ZislaMotion, ease, linear, springAt} from '../motion';
import {soundtrack} from '../soundtrack';
import {FPS, SCENES, TOTAL_FRAMES, filmFrame} from '../timeline';
import {MODULE_HEIGHT, clamp01, color, islandHeightFor, lerp, white} from '../theme';

// Hold the expanded island through the crossfade before the cursor leaves.
const LEAVE = [14, 50] as const;
const COLLAPSE_AT = 34;
const BRAND_AT = 70;
const PILL_AT = 124;
const REPO_AT = 136;
const TYPE_AT = 150;
const OUT_AT = [TYPE_AT + 86, TYPE_AT + 104, TYPE_AT + 126];

const OUTPUT = [
  {text: '==> Installing Cask zisla', tint: color.secondary},
  {text: "==> Moving App 'zisla.app' to '/Applications/zisla.app'", tint: white(0.72)},
  {text: '🍺  zisla was successfully installed!', tint: white(0.95)},
];
const OUTPUT_TOP = 10;
const OUTPUT_GAP = 5;
const OUTPUT_LINE = 18;

export const Scene5Outro = ({duration = SCENES.outro.duration}: {duration?: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  // Continue media and focus readouts from film time across scene boundaries.
  const played = filmFrame('outro', frame);

  // Collapse the island before drawing attention to the centered brand.
  const reveal = Math.max(0, 1 - springAt(frame, fps, COLLAPSE_AT, ZislaMotion.islandRecycle, 30));
  const dim = linear(frame, [COLLAPSE_AT, COLLAPSE_AT + 60], [0.3, 0.54]);
  const brand = clamp01(springAt(frame, fps, BRAND_AT, FilmMotion.title, 44));
  const pill = clamp01(springAt(frame, fps, PILL_AT, FilmMotion.gentle, 32));
  const typed = typedChars(frame, TYPE_AT, copy.outro.length, 28, fps);
  const repo = clamp01(springAt(frame, fps, REPO_AT, FilmMotion.gentle, 34));
  // Grow the terminal with arriving output instead of reserving an empty box.
  const outputHeight = OUT_AT.reduce(
    (height, at, index) =>
      height + ((index === 0 ? OUTPUT_TOP : OUTPUT_GAP) + OUTPUT_LINE) * clamp01(springAt(frame, fps, at - 6, ZislaMotion.surfaceResize, 22)),
    0,
  );

  // Leaving the lower edge triggers the same collapse as the native island.
  const leave = ease(frame, LEAVE, [0, 1]);
  const cursorX = lerp(678, 900, leave);
  const cursorY = lerp(107, 340, leave);

  return (
    <>
      <Wallpaper dim={dim} />
      <MenuBar appName="Finder" />

      {frame < COLLAPSE_AT + 40 ? (
        <Island reveal={reveal} height={islandHeightFor(MODULE_HEIGHT.home)}>
          <IslandBody
            header={<NowPlayingHeader elapsed={track.elapsed + played / fps} levels={waveLevels(frame, 1, 0)} lyric={lyricAt(played)} />}
            active={TABS.home}
          >
            <HomeModule cards={['media', 'focus']} focusRemaining={focus.remaining - played / fps} />
          </IslandBody>
        </Island>
      ) : null}
      <Cursor x={cursorX} y={cursorY} opacity={frame < LEAVE[0] ? 1 : linear(frame, [LEAVE[1] - 4, LEAVE[1] + 14], [1, 0])} />
      <Notch />

      <div className="absolute inset-x-0 flex flex-col items-center" style={{top: 224}}>
        <Img src={zislaIcon} style={{width: 76, height: 76, borderRadius: 19, opacity: brand, transform: `scale(${0.9 + 0.1 * brand})`, boxShadow: '0 18px 48px rgba(0,0,0,0.6)'}} />
        <div
          className="font-rounded"
          style={{
            marginTop: 12,
            fontSize: 40,
            lineHeight: '44px',
            fontWeight: 700,
            letterSpacing: '-0.03em',
            opacity: brand,
            transform: `translateY(${(1 - brand) * 12}px)`,
            textShadow: '0 4px 30px rgba(0,0,0,0.6)',
          }}
        >
          zisla
        </div>
        <div className="text-[17px] leading-[22px] font-medium text-label-2" style={{marginTop: 4, opacity: brand}}>
          {copy.slogan} {copy.sloganSecond}
        </div>
      </div>

      <div className="absolute inset-x-0 flex justify-center" style={{top: 404}}>
        <div
          style={{
            width: 640,
            opacity: pill,
            transform: `translateY(${(1 - pill) * 16}px)`,
            borderRadius: 14,
            background: 'rgba(9,9,12,0.74)',
            backdropFilter: GLASS_BLUR,
            WebkitBackdropFilter: GLASS_BLUR,
            border: `1px solid ${white(0.14)}`,
            boxShadow: '0 22px 60px rgba(0,0,0,0.55)',
            padding: '16px 20px',
          }}
        >
          <div className="whitespace-nowrap font-mono text-[14px] leading-[20px]">
            <span style={{color: color.green}}>➜</span>
            <span style={{color: color.cyan}}> ~ </span>
            <span>{copy.outro.slice(0, Math.floor(typed))}</span>
            <Caret frame={frame} frameRate={fps} opacity={frame < OUT_AT[0] ? 1 : 0} />
          </div>
          <div className="overflow-hidden" style={{height: outputHeight}}>
            <div className="flex flex-col" style={{paddingTop: OUTPUT_TOP, gap: OUTPUT_GAP}}>
              {OUTPUT.map((line, index) => (
                <div
                  key={line.text}
                  className="truncate font-mono text-[12.5px]"
                  style={{
                    lineHeight: `${OUTPUT_LINE}px`,
                    color: line.tint,
                    opacity: frame >= OUT_AT[index] ? ease(frame, [OUT_AT[index], OUT_AT[index] + 10], [0, 1]) : 0,
                  }}
                >
                  {line.text}
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      <div
        className="absolute inset-x-0 flex items-center justify-center gap-[9px]"
        style={{bottom: 60, opacity: repo, transform: `translateY(${(1 - repo) * 10}px)`}}
      >
        <Img src={githubMark} style={{width: 18, height: 18, opacity: 0.85, filter: 'invert(1)'}} />
        <div className="font-mono text-[14px] leading-[18px]" style={{color: white(0.78)}}>
          github.com/wzz6423/zisla
        </div>
      </div>

      <div className="absolute inset-x-0 text-center text-[9px] leading-[12px]" style={{bottom: 32, color: white(0.5), opacity: repo}}>
        Music: {soundtrack.title} by {soundtrack.artist} · {soundtrack.license} · scottbuckley.com.au · {TOTAL_FRAMES / FPS}s edit
      </div>

      {/* The last frame is duration - 1, so the fade must reach black on that frame. */}
      <Blackout opacity={ease(frame, [duration - 28, duration - 1], [0, 1])} />
    </>
  );
};
