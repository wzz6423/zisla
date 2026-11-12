import {useCurrentFrame, useVideoConfig} from 'remotion';
import {Blackout} from '../components/Caption';
import {Cursor} from '../components/Cursor';
import {MenuBar, Notch, Wallpaper} from '../components/Desktop';
import {GLASS_BLUR, Waveform, waveLevels} from '../components/Glass';
import {Island, modulePhase} from '../components/Island';
import {AlbumArt, IslandBody, NowPlayingHeader, TABS, lyricAt} from '../components/IslandChrome';
import {HomeModule} from '../modules/HomeModule';
import {copy, track} from '../content';
import {FilmMotion, ZislaMotion, ease, easeOutAt, linear, springAt} from '../motion';
import {BAR_HEIGHT, MODULE_HEIGHT, STAGE, alpha, black, clamp01, color, islandHeightFor, lerp, white} from '../theme';

const CENTER = STAGE.width / 2;

// 光标进入触发区 → 岛体展开 → 光标离开 → 收回。全片只有这一段是完整的一次进出。
const REVEAL_START = 168;
const COLLAPSE_START = 396;

export const Scene1Awakening = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();

  const enter = springAt(frame, fps, REVEAL_START, ZislaMotion.islandReveal, 42);
  const exit = springAt(frame, fps, COLLAPSE_START, ZislaMotion.islandRecycle, 34);
  const reveal = Math.max(0, enter - exit);

  // 媒体先起播，收起态两侧的封面与波形才跟着出现
  const playing = frame >= 404;
  const wing = lerp(0, 74, clamp01((frame - 410) / 26));
  const levels = waveLevels(frame, 1, 0);

  const approach = easeOutAt(frame, [34, 150], [0, 1]);
  const leave = ease(frame, [384, 452], [0, 1]);
  const cursorX = lerp(lerp(548, CENTER, approach), 792, leave);
  const cursorY = lerp(lerp(486, 44, approach), 298, leave);
  const cursorOpacity = Math.min(linear(frame, [20, 44], [0, 1]), linear(frame, [448, 472], [1, 0]));

  const hint = clamp01(Math.min(linear(frame, [58, 80], [0, 1]), linear(frame, [172, 196], [1, 0]))) * (0.82 + 0.18 * Math.sin(frame * 0.14));
  const hintLabel = Math.min(linear(frame, [96, 116], [0, 1]), linear(frame, [160, 180], [1, 0]));

  const wordmark = springAt(frame, fps, 206, FilmMotion.gentle, 38);
  const slogan = springAt(frame, fps, 236, FilmMotion.gentle, 34);
  const sloganSecond = springAt(frame, fps, 416, FilmMotion.gentle, 32);

  const moduleIn = clamp01((frame - 176) / 24);
  const downloadProgress = linear(frame, [206, 330], [0.42, 0.72]);

  return (
    <>
      <Wallpaper dim={0.1} />
      <MenuBar />

      {/* 顶部中央 6 pt 触发区：光标进入前先亮起，岛体展开后由岛体盖住 */}
      <div className="absolute" style={{left: CENTER - 110, top: BAR_HEIGHT, width: 220, height: 6, opacity: hint}}>
        <div className="absolute inset-0" style={{background: `linear-gradient(to bottom, ${white(0.6)}, ${white(0)})`}} />
        <div
          className="absolute inset-x-0 top-0"
          style={{height: 1.5, background: white(0.88), boxShadow: `0 0 18px ${alpha(color.cyan, 0.9)}`}}
        />
      </div>
      <div className="absolute inset-x-0 flex justify-center" style={{top: 58, opacity: hintLabel}}>
        <div
          className="rounded-full px-[11px] py-[5px] text-[12px] font-medium"
          style={{background: black(0.5), border: `1px solid ${white(0.12)}`, color: white(0.9), backdropFilter: GLASS_BLUR, WebkitBackdropFilter: GLASS_BLUR}}
        >
          {copy.trigger}
        </div>
      </div>

      <Island
        reveal={reveal}
        height={islandHeightFor(MODULE_HEIGHT.home)}
        wing={wing}
        left={<AlbumArt size={26} radius={5} />}
        right={<Waveform width={34} height={18} levels={levels} />}
        progress={playing ? {value: clamp01((track.elapsed + frame / fps) / track.duration), tint: color.coverTint} : undefined}
      >
        <IslandBody
          header={<NowPlayingHeader elapsed={track.elapsed + frame / fps} levels={levels} lyric={lyricAt(frame)} />}
          active={TABS.home}
        >
          <div style={modulePhase(moduleIn, 1, true)}>
            <HomeModule cards={['media', 'download']} downloadProgress={downloadProgress} />
          </div>
        </IslandBody>
      </Island>

      <Notch />

      <div className="absolute inset-x-0 flex flex-col items-center" style={{top: 402}}>
        <div
          className="font-rounded"
          style={{
            fontSize: 46,
            lineHeight: '50px',
            fontWeight: 700,
            letterSpacing: '-0.03em',
            opacity: clamp01(wordmark),
            transform: `translateY(${(1 - wordmark) * 14}px)`,
            textShadow: '0 4px 34px rgba(0,0,0,0.65)',
          }}
        >
          zisla
        </div>
        <div
          className="text-center"
          style={{
            marginTop: 14,
            fontSize: 21,
            lineHeight: '27px',
            fontWeight: 500,
            color: white(0.74),
            opacity: clamp01(slogan),
            transform: `translateY(${(1 - slogan) * 12}px)`,
          }}
        >
          {copy.slogan}
        </div>
        <div
          className="text-center"
          style={{
            marginTop: 7,
            fontSize: 21,
            lineHeight: '27px',
            fontWeight: 500,
            color: white(0.74),
            opacity: clamp01(sloganSecond),
            transform: `translateY(${(1 - sloganSecond) * 12}px)`,
          }}
        >
          {copy.sloganSecond}
        </div>
      </div>

      <Cursor x={cursorX} y={cursorY} opacity={cursorOpacity} />
      <Blackout opacity={linear(frame, [0, 44], [1, 0])} />
    </>
  );
};
