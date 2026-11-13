import type {ReactNode} from 'react';
import {BatteryFull, Camera, Check, ChartLine, ChevronDown, ClipboardPaste, Folder, HardDrive, Keyboard, Laptop, Music, Pause, Play, Plug, Power, RotateCcw, Settings, Sun, Trash2, Volume2, VolumeX, X} from 'lucide-react';
import {IconButton, ProgressTrack} from '../../components/Glass';
import {BrowserGlyph, formatTime} from '../../components/IslandChrome';
import {ease, linear} from '../../motion';
import {alpha, color, white} from '../../theme';
import {SystemModule} from '../SystemModule';
import {TourAction, TourCard, TourHeading, TourPointer, TourPointerTrack, TourResult, TourSelect, TourToggle} from './TourSurface';

export const desktopDemo = {
  mixer: [{name: 'Safari', volume: 0.3}, {name: 'Music', volume: 0.8}],
  typing: {characters: 12846, topApp: 'Xcode', activeMinutes: 86, peak: 12},
  battery: {level: 0.76, health: 96, cycles: 124, celsius: 31, inputWatts: 60, systemWatts: 24, chargingWatts: 36},
  cleanup: [{name: 'Application caches', sizeMB: 320, safety: 'Safe to clean', source: 'App caches', detail: '~/Library/Caches', reason: 'Regenerated when apps need them'}, {name: 'Package manager caches', sizeMB: 24, safety: 'Safe to clean', source: 'Package manager caches', detail: '~/Library/Caches/Homebrew', reason: 'Downloaded packages can be fetched again'}, {name: 'Old preferences', sizeMB: 3, safety: 'Review required', source: 'Application residuals', detail: '~/Library/Preferences', reason: 'May contain settings you want to keep'}],
} as const;

export const backgroundSounds = ['Pink noise', 'Brown noise', 'White noise', 'Balanced noise', 'Bright noise', 'Dark noise', 'Ocean', 'Rain', 'Stream', 'Night', 'Fire', 'Babble', 'Steam', 'Airplane', 'Boat', 'Bus', 'Train', 'Rain on roof', 'Quiet night'] as const;

export const MixerTourModule = ({frame}: {frame: number}) => {
  const safari = ease(frame, [25, 78], [1, desktopDemo.mixer[0].volume]);
  const muted = frame >= 112;
  return (
    <div className="absolute inset-0 flex flex-col gap-[8px]" data-feature="volumeMixer" style={{padding: 12}}>
      {desktopDemo.mixer.map((app, index) => {
        const volume = index === 0 ? safari : app.volume;
        return <div key={app.name} data-mixer-app={app.name} data-muted={index === 1 && muted} className="flex shrink-0 items-center gap-[12px]" style={{padding: 12, borderRadius: 12, background: color.fillCard, border: `1px solid ${color.strokeCard}`}}>
          {index === 0 ? <BrowserGlyph size={32} /> : <div className="flex shrink-0 items-center justify-center" style={{width: 32, height: 32, borderRadius: 8, background: '#ea4167'}}><Music size={21} /></div>}
          <div data-mixer-name style={{width: 220, flexShrink: 0, fontSize: 12, fontWeight: 500}}>{app.name}</div>
          <div className="relative flex-1"><ProgressTrack value={volume} tint={color.blue} width="100%" height={3} /><div className="absolute" style={{left: `calc(${volume * 100}% - 6px)`, top: -4, width: 12, height: 12, borderRadius: 6, background: '#fff'}} /></div>
          <div data-mixer-percent className="font-mono tabular" style={{width: 48, flexShrink: 0, textAlign: 'right', fontSize: 11, color: color.secondary}}>{Math.round(volume * 100)}%</div>
          <div className="flex shrink-0 items-center justify-center" style={{width: 32, height: 32}}>{index === 1 && muted ? <VolumeX size={13} color={color.orange} /> : <Volume2 size={13} />}</div>
        </div>;
      })}
      <div className="flex-1" />
      <TourPointerTrack frame={frame} actions={[{at: 78, x: 417, y: 42}, {at: 112, x: 712, y: 106}]} />
    </div>
  );
};

const KEYS = ['Esc F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12', '1 2 3 4 5 6 7 8 9 0 − =', 'Q W E R T Y U I O P [ ]', 'A S D F G H J K L ;', 'Z X C V B N M , . /', 'Ctrl Option Command Space Command Option ← ↓ ↑ →'] as const;

export const keyboardVoices = ['Holy Panda', 'Cherry MX Brown', 'Cherry MX Clear', 'Logitech G915 TKL Brown', 'Studio Tactile', 'Cherry MX Blue', 'Kailh BOX Navy', 'Kailh BOX White', 'Kailh Low-profile Blue', 'SKCM Blue Alps', 'Studio Clicky', 'NovelKeys Cream', 'Alpaca', 'Gateron Black Ink', 'Gateron Red Ink', 'Cherry MX Black', 'Turquoise Tealios', 'Keychron Red Linear', 'Topre', 'IBM Buckling Spring'] as const;

const NativeAction = ({label, active = false, icon}: {label: string; active?: boolean; icon?: ReactNode}) => <div className="flex shrink-0 items-center justify-center gap-[5px]" style={{height: 24, padding: '0 8px', borderRadius: 5, background: active ? color.blue : color.fillControl, fontSize: 11}}>{icon}{label}</div>;

export const DesktopSettingsPage = ({title, children}: {title: string; children: ReactNode}) => <div className="absolute inset-0 flex" data-desktop-settings style={{background: '#252529'}}>
  <div className="flex shrink-0 flex-col" style={{width: 250, padding: '16px 12px', background: white(0.035), borderRight: `1px solid ${color.divider}`}}>
    <div style={{height: 28, padding: '6px 10px', borderRadius: 7, background: white(0.06), fontSize: 11, color: color.secondary}}>Search settings</div>
    {[
      ['Basics', ['General', 'Features', 'Information']],
      ['Sound', ['Keyboard sounds']],
      ['Others', ['System status and cleanup']],
    ].map(([group, rows]) => <div key={String(group)} style={{marginTop: 18}}><div style={{fontSize: 11, color: color.secondary, padding: '0 10px 7px'}}>{group}</div>{(rows as string[]).map((name) => <div key={name} className="flex items-center gap-[10px]" style={{height: 38, padding: '0 10px', marginBottom: 5, borderRadius: 6, fontSize: 13, color: name === title ? color.blue : color.label, background: name === title ? white(0.12) : 'transparent'}}><div className="flex items-center justify-center" style={{width: 24, height: 24, borderRadius: 6, background: name === 'System status and cleanup' ? '#c34d53' : '#717176'}}>{name === 'Keyboard sounds' ? <Keyboard size={13} color="white" /> : name === 'System status and cleanup' ? <ChartLine size={13} color="white" /> : <Settings size={13} color="white" />}</div>{name}</div>)}</div>)}
  </div>
  <div className="relative min-w-0 flex-1" style={{padding: '24px 28px'}}><div style={{fontSize: 23, fontWeight: 600, marginBottom: 23}}>{title}</div>{children}</div>
</div>;

export const keyboardTourAt = (frame: number) => {
  const position = Math.min(179, Math.max(0, frame));
  return {
    phase: position < 78 ? 'settings' : 'dashboard',
    profileMenu: position >= 10 && position < 35,
    profile: position < 29 ? 'Holy Panda' : position < 51 ? 'Cherry MX Brown' : 'BCP (Suit80)',
    preview: position >= 35 && position < 49 || position >= 60 && position < 72,
    characters: desktopDemo.typing.characters + Math.floor(linear(position, [92, 126], [0, 14])),
    pressed: position >= 92 && position < 126,
    scroll: ease(position, [128, 157], [0, 282]),
  } as const;
};

const TypingChart = ({history = false}: {history?: boolean}) => <svg width="100%" height="110" viewBox="0 0 340 110" preserveAspectRatio="xMidYMid meet">
  {[12, 42, 72].map((y) => <path key={y} d={`M27 ${y}H324`} stroke={color.divider} />)}
  {[15, 35, 23, 54, 41, 63, 35, 48, 66, 52, 80, 60].map((height, index) => <rect key={index} x={29 + index * 24} y={85 - height} width={15} height={height} rx={2} fill={white(0.10)} />)}
  <polyline points="29,70 53,50 77,62 101,31 125,44 149,22 173,50 197,37 221,19 245,33 269,5 293,25" stroke={color.blue} fill="none" strokeWidth={2} />
  {[history ? '11/06' : '09:00', history ? '11/09' : '13:30', history ? '11/12' : '18:00'].map((label, index) => <text key={label} x={27 + index * 149} y={104} fill={color.secondary} fontSize={8} textAnchor={index === 0 ? 'start' : index === 2 ? 'end' : 'middle'}>{label}</text>)}
</svg>;

export const KeyboardTourModule = ({frame}: {frame: number}) => {
  const state = keyboardTourAt(frame);
  if (state.phase === 'settings') return <DesktopSettingsPage title="Keyboard sounds"><div data-keyboard-settings className="flex flex-col gap-[20px]">
    <div style={{fontSize: 12, fontWeight: 600, color: color.secondary}}>Global sounds</div>
    <TourCard style={{padding: '0 12px'}}>
      <div className="flex items-center gap-[10px]" style={{height: 52, borderBottom: `1px solid ${color.divider}`}}><Keyboard size={15} color={color.secondary} /><div className="flex-1" style={{fontSize: 13}}>Keyboard voice</div><TourSelect value={state.profile} /><div aria-label="Preview"><IconButton icon={Play} compact active={state.preview} /></div></div>
      <div className="flex items-center gap-[10px]" style={{height: 46, borderBottom: `1px solid ${color.divider}`}}><Volume2 size={15} color={color.secondary} /><div className="flex-1" style={{fontSize: 13}}>Keyboard volume</div><div className="relative" style={{width: 150}}><ProgressTrack value={0.55} tint={color.blue} width={150} height={3} /><div className="absolute" style={{left: 77, top: -4, width: 12, height: 12, borderRadius: 6, background: 'white'}} /></div></div>
      <div style={{padding: '12px 0', borderBottom: `1px solid ${color.divider}`}}><TourToggle label="Release sounds" on /></div>
      <div style={{padding: '12px 0'}}><TourToggle label="Pitch variation" on /></div>
    </TourCard>
    <div style={{fontSize: 12, fontWeight: 600, color: color.secondary}}>Typing statistics</div>
    <TourCard style={{padding: 12}}><TourToggle label="Record local typing stats" on /><div style={{fontSize: 10, lineHeight: '16px', marginTop: 6, color: color.secondary}}>Character counts, key presses, apps and time aggregates.</div></TourCard>
    <div style={{fontSize: 11, color: color.secondary}}>20 voices · Installed custom pack: BCP (Suit80)</div>
    {state.profileMenu ? <div data-keyboard-profile-menu className="absolute" style={{right: 63, top: 95, width: 259, padding: '6px 0', borderRadius: 7, border: `1px solid ${color.strokeCard}`, background: '#343438', boxShadow: '0 12px 35px #0008'}}>{[...keyboardVoices, 'BCP (Suit80)'].map((name) => <div key={name} className="flex items-center gap-[7px]" style={{height: 22, padding: '0 10px', fontSize: 11, color: name === state.profile ? color.blue : color.label}}><span style={{width: 12}}>{name === state.profile ? '✓' : ''}</span>{name}</div>)}</div> : null}
    <TourPointerTrack frame={frame} actions={[{at: 29, x: 530, y: 135}, {at: 60, x: 656, y: 147}]} />
  </div></DesktopSettingsPage>;
  return <div className="absolute inset-0" data-keyboard-dashboard style={{padding: 12}}>
    <div data-keyboard-scroll className="relative" style={{height: 396, overflow: 'hidden'}}>
      <div data-keyboard-scroll-content className="flex flex-col gap-[16px]" style={{transform: `translateY(${-state.scroll}px)`}}>
        <div className="flex gap-[8px]">{[['Characters Today', state.characters.toLocaleString('en-US'), 'Estimated key input'], ['Top app', desktopDemo.typing.topApp, '8,640 characters'], ['Peak Today', '12 chars / s', 'Last input · Just now'], ['Active time', '1 h 26 m', '86 minutes']].map(([label, value, detail]) => <div data-typing-metric={label} key={label} style={{flex: 1, height: 76, padding: 9, borderRadius: 10, background: color.fillCard, border: `1px solid ${color.strokeCard}`}}><div style={{fontSize: 9, lineHeight: '11px', color: color.secondary}}>{label}</div><div className="font-rounded tabular" style={{fontSize: 17, lineHeight: '20px', fontWeight: 700, marginTop: 5}}>{value}</div><div style={{fontSize: 8, lineHeight: '10px', marginTop: 5, color: color.secondary}}>{detail}</div></div>)}</div>
        <div className="flex gap-[10px]" style={{height: 152}}>{['Typing trend', 'History'].map((title, index) => <TourCard key={title} style={{flex: 1, padding: '8px 10px'}}><div style={{fontSize: 11, fontWeight: 600, marginBottom: 4}}>{title}</div><TypingChart history={index === 1} /></TourCard>)}</div>
        <TourCard style={{height: 328, padding: '10px 12px'}}><div style={{fontSize: 11, fontWeight: 600, marginBottom: 8}}>Keyboard</div><div className="flex gap-[18px]" style={{fontSize: 9, color: color.secondary}}>Today’s presses {state.characters.toLocaleString('en-US')}<span>Total presses 218,404</span></div><div className="flex flex-col justify-center gap-[6px]" data-keyboard-heatmap style={{height: 270}}>{KEYS.map((row, rowIndex) => <div key={row} className="flex justify-center gap-[4px]">{row.split(' ').map((key, index) => <div key={key + index} className="flex items-center justify-center" style={{width: key === 'Space' ? 192 : key.length > 2 && rowIndex === 5 ? 48 : rowIndex === 0 ? 39 : 42, height: rowIndex === 0 ? 25 : 30, borderRadius: 5, fontSize: 9, border: `1px solid ${color.strokeCard}`, background: state.pressed && ['Z', 'I', 'S', 'L', 'A'].includes(key) ? color.blue : white(0.04 + ((index * 7 + rowIndex * 5) % 9) * 0.016)}}>{key}</div>)}</div>)}</div></TourCard>
        <div data-keyboard-timeline data-content-y={604} style={{height: 74}}><TourCard style={{height: 74, padding: '8px 10px'}}><div style={{fontSize: 11, fontWeight: 600, marginBottom: 8}}>App timeline</div><div className="flex items-center gap-[8px]"><div style={{width: 110, fontSize: 10}}>Xcode</div><div className="flex flex-1 items-end gap-[1px]" style={{height: 24}}>{Array.from({length: 30}, (_, index) => <div key={index} style={{flex: 1, height: 4 + (index * 7 % 20), background: color.blue, opacity: 0.72, borderRadius: 1}} />)}</div><div className="tabular" style={{width: 52, textAlign: 'right', fontSize: 9}}>8,640</div></div></TourCard></div>
      </div>
      <div className="absolute right-0" style={{top: state.scroll / 282 * 286, width: 4, height: 110, borderRadius: 2, background: white(0.22)}} />
    </div>
  </div>;
};

export const focusTourAt = (frame: number) => {
  const position = Math.min(239, Math.max(0, frame));
  const finished = position >= 190;
  const running = position >= 38 && position < 80 || position >= 112 && position < 190;
  const paused = position >= 80 && position < 112;
  const activeFrames = position < 38 ? 0 : Math.min(position - 38, 42) + Math.max(0, position - 112);
  return {phase: running ? 'running' : paused ? 'paused' : 'idle', mode: finished ? 'rest' : 'focus', running, paused, finished, completed: position >= 190 && position < 224, compact: position >= 68 && position < 190, remaining: finished ? 300 : Math.max(0, 2 - activeFrames / 60)} as const;
};

export const CompactFocusControls = ({frame}: {frame: number}) => {
  const state = focusTourAt(frame);
  return <div data-compact-focus-controls className="flex items-center gap-[6px]" style={{height: 24}}>
    <div data-control="pomodoro.toggleStartPause" aria-label={state.running ? 'Pause' : 'Continue'} style={{width: 24, height: 24}}><IconButton icon={state.running ? Pause : Play} compact /></div>
    <div data-control="pomodoro.reset" aria-label="Reset" style={{width: 24, height: 24}}><IconButton icon={RotateCcw} compact /></div>
  </div>;
};

export const FocusTourModule = ({frame}: {frame: number}) => {
  const {running, paused, finished, remaining} = focusTourAt(frame);
  return (
    <div className="absolute inset-0 flex gap-[10px]" data-feature="toolbox" data-toolbox-layout="236+10+flex">
      <div className="flex shrink-0 flex-col" style={{width: 236, height: 136, padding: 10, borderRadius: '8px 8px 8px 22px', background: color.fillCard, border: `1px solid ${color.strokeCard}`}}>
        <div style={{fontSize: 12, fontWeight: 600, color: color.secondary}}>{finished ? 'Rest' : 'Focus'}</div>
        <div className="flex flex-1 items-center justify-center font-rounded tabular" style={{fontSize: 26, fontWeight: 700}}>{formatTime(Math.ceil(remaining))}{!running && !paused ? <span style={{fontSize: 9, marginLeft: 3}}>⌄</span> : null}</div>
        <div className="flex gap-[8px]" style={{height: 40}}>{[running ? 'Pause' : paused ? 'Continue' : 'Start', 'Reset'].map((label, index) => <div key={index} className="flex flex-1 items-center justify-center" style={{fontSize: 11, fontWeight: 600, background: index === 0 ? color.fillCard : color.fillControl, borderRadius: index === 0 ? '8px 8px 8px 12px' : 8}}>{label}</div>)}</div>
      </div>
      <div className="flex min-w-0 flex-1 flex-col gap-[8px]" data-toolbox-actions="2/2/3">
        {[
          [[Sun, 'Keep display awake', frame >= 50], [Laptop, 'Prevent idle sleep', frame >= 62]],
          [[Sun, 'Clean screen', false], [Keyboard, 'Clean keyboard', false]],
          [[HardDrive, 'Teleprompter', false], [Camera, 'Mirror', false], [Trash2, 'Trash', false]],
        ].map((row, index) => <div key={index} className="flex gap-[8px]" style={{height: 40}}>{row.map(([Icon, label, active]) => {
          const Glyph = Icon as typeof Sun;
          return <div key={String(label)} className="flex min-w-0 flex-1 items-center justify-center gap-[5px]" style={{borderRadius: 8, background: color.fillCard, color: active ? color.blue : color.label, fontSize: 11, fontWeight: 600}}><Glyph size={13} />{String(label)}</div>;
        })}</div>)}
      </div>
      <TourPointerTrack frame={frame} actions={[{at: 38, x: 64, y: 105}, {at: 50, x: 370, y: 20}, {at: 62, x: 627, y: 20}]} />
    </div>
  );
};

export const BackgroundSoundsTourModule = ({frame}: {frame: number}) => (
  <div className="absolute inset-0 flex flex-col gap-[22px]" data-feature="backgroundSounds" style={{padding: 28}}>
    <TourHeading title="Settings → Music" />
    <TourToggle label="macOS background sounds" on={frame >= 36} />
    <div className="flex items-center gap-[14px]" style={{fontSize: 15}}><span>Sound</span><div className="flex-1" /><TourSelect value={frame >= 72 ? 'Ocean' : 'Rain'} /><TourAction label={frame >= 36 ? 'Stop' : 'Play'} active={frame >= 36} /></div>
    <TourToggle label="Stop on lock, screen saver or sleep" on />
    <div style={{fontSize: 14, lineHeight: '24px', color: color.secondary}}>Rain · Ocean · Stream · Night · Noise · Transport</div>
    {frame >= 93 ? <TourResult>Ocean playing · Stops when unused</TourResult> : <div style={{fontSize: 15, color: color.secondary}}>Choose a background sound.</div>}
    <TourPointerTrack frame={frame} actions={[{at: 36, x: 995, y: 102}, {at: 72, x: 900, y: 151}]} />
  </div>
);

export const CleaningTourModule = ({frame}: {frame: number}) => {
  const screen = frame >= 26 && frame < 87;
  const keyboard = frame >= 94 && frame < 150;
  return (
    <div className="absolute inset-0 flex flex-col gap-[20px]" style={{padding: 27}}>
      <TourHeading title="Screen and keyboard cleaning" />
      <div className="flex gap-[13px]"><TourAction label="Clean screen" active={screen} /><TourAction label={keyboard ? 'End cleaning' : 'Clean keyboard'} active={keyboard} /><TourAction label="Trash" /></div>
      <div className="flex min-h-0 flex-1 items-center justify-center"><Keyboard size={58} color={keyboard ? color.blue : color.secondary} /></div>
      {frame >= 150 ? <TourResult>Screen restored · Keyboard input resumed</TourResult> : <div style={{fontSize: 16, color: color.secondary}}>{keyboard ? 'Click End cleaning to resume keyboard input.' : 'Click to exit the full-screen black cover.'}</div>}
      <TourPointer frame={frame} at={26} x={111} y={104} />
      <TourPointer frame={frame} at={94} x={253} y={104} />
      <TourPointer frame={frame} at={150} x={253} y={104} />
    </div>
  );
};

export const ScreenCleaningCover = ({frame}: {frame: number}) => <div data-screen-cleaning-cover className="absolute inset-0 flex items-center justify-center" style={{background: '#000'}}><div data-screen-cleaning-exit className="flex items-center justify-center" style={{width: 184, height: 52, borderRadius: 12, background: '#474747', fontSize: 16, fontWeight: 600}}>Exit screen cleaning</div><TourPointer frame={frame} at={64} x={640} y={360} /></div>;

export const PresenterTourModule = ({frame}: {frame: number}) => {
  const playing = frame >= 38 && frame < 112;
  const closed = frame >= 142;
  const scriptHover = frame < 64 || frame >= 101 && frame < 126;
  return (
    <div className="absolute inset-0 flex gap-[23px]" style={{padding: 24}}>
      <div className="flex min-w-0 flex-[1.35] flex-col gap-[13px]">
        <TourHeading title="Teleprompter" />
        <div data-teleprompter-stage className="relative min-h-0 flex-1 overflow-hidden" style={{borderRadius: 10, background: '#070708', padding: '28px 24px'}}>
          <div className="whitespace-pre-line" style={{fontSize: 31, lineHeight: '45px', transform: `translateY(${-linear(frame, [38, 112], [0, 48])}px)`}}>Make room for the work.{'\n'}Keep the tools close.{'\n'}Let the next idea flow.</div>
          {scriptHover ? <div data-teleprompter-controls className="flex items-center gap-[12px]" style={{position: 'absolute', bottom: 8, left: 14, right: 14, padding: '6px 10px', borderRadius: 22, background: 'rgba(32,32,36,0.92)'}}><div aria-label={playing ? 'Pause' : 'Play'}><IconButton icon={playing ? Pause : Play} /></div><div aria-label="Reset"><IconButton icon={RotateCcw} /></div><div className="relative" style={{width: 132, flexShrink: 0}}><ProgressTrack width={132} value={0.22} height={3} tint={color.blue} /><div className="absolute" style={{left: 25, top: -4, width: 11, height: 11, borderRadius: 6, background: 'white'}} /></div><span style={{fontSize: 11, flexShrink: 0}}>45 pt/s</span><div className="flex-1" /><div aria-label="Paste"><IconButton icon={ClipboardPaste} /></div><div aria-label="Close"><IconButton icon={X} /></div></div> : null}
        </div>
        <TourResult>{frame >= 112 ? 'Script paused at your place' : 'Drag text here and start scrolling'}</TourResult>
      </div>
      <div className="flex min-w-0 flex-1 flex-col gap-[13px]">
        <TourHeading title="Camera mirror" />
        <div className="relative min-h-0 flex-1 overflow-hidden" style={{borderRadius: 10, background: '#111318'}}>
          {closed ? <div className="absolute inset-0 flex flex-col items-center justify-center gap-[16px]" style={{fontSize: 15, color: color.secondary}}><Camera size={33} /><span>Camera stopped</span><NativeAction label="Mirror" icon={<Camera size={13} />} /></div> : <svg data-camera-preview width="100%" height="100%" viewBox="0 0 370 270" preserveAspectRatio="xMidYMid slice" style={{transform: 'scaleX(-1)'}}>
            <defs><linearGradient id="mirror-room" x1="0" y1="0" x2="1" y2="1"><stop stopColor="#627581" /><stop offset="1" stopColor="#27323e" /></linearGradient></defs>
            <rect width="370" height="270" fill="url(#mirror-room)" /><rect x="25" y="30" width="70" height="117" fill="#a4b8c2" /><path d="M54 30v117M25 82h70" stroke="#677d8b" strokeWidth="5" />
            <path d="M83 280 Q88 183 185 181 Q282 183 287 280" fill="#425b6b" /><rect x="160" y="139" width="51" height="53" rx="17" fill="#cfaa93" />
            <ellipse cx="184" cy="104" rx="62" ry="73" fill="#d8b49a" /><path d="M122 102 Q112 21 185 17 Q254 17 251 94 L225 69 Q164 72 145 49 Z" fill="#372b2a" /><path d="M153 107h16M203 107h16" stroke="#554640" strokeWidth="4" strokeLinecap="round" /><path d="M171 143q14 10 28 0" fill="none" stroke="#966457" strokeWidth="3" strokeLinecap="round" />
          </svg>}
          {frame >= 122 && !closed ? <div data-camera-close aria-label="Close mirror" className="absolute right-[8px] top-[8px] flex items-center justify-center" style={{width: 24, height: 24, borderRadius: 13, background: 'rgba(0,0,0,0.6)'}}><X size={11} /></div> : null}
        </div>
        <div style={{fontSize: 15, color: color.secondary}}>{closed ? 'Closed · Camera session released' : 'Mirrored camera preview'}</div>
      </div>
      <TourPointerTrack frame={frame} actions={[{at: 38, x: 62, y: 362}, {at: 112, x: 62, y: 362}, {at: 136, x: 996, y: 99}]} />
    </div>
  );
};

const historyCategories = [
  {name: 'CPU', title: 'CPU utilisation', unit: '%', values: ['Usage', 'User', 'System']},
  {name: 'GPU', title: 'GPU utilisation', unit: '%', values: ['Usage', 'Renderer', 'Tiler']},
  {name: 'Memory', title: 'Memory utilisation', unit: '%', values: ['Memory']},
  {name: 'Disk', title: 'Disk read and write', unit: 'MB/s', values: ['Read', 'Write']},
  {name: 'Fan', title: 'Fan speed', unit: 'rpm', values: ['Fan 1']},
  {name: 'Network', title: 'Network rate', unit: 'MB/s', values: ['Download', 'Upload']},
] as const;

export const systemHistoryTourAt = (frame: number) => {
  const position = Math.min(269, Math.max(0, frame));
  const scroll = position < 120 ? ease(position, [84, 105], [0, 380]) : ease(position, [133, 154], [380, 724]);
  return {phase: position < 18 ? 'live' : position < 42 ? 'settings' : 'history', range: position >= 68 ? '24 hours' : '7 days', scroll, save: position >= 194 && position < 212, exported: position >= 212} as const;
};

const HistoryChart = ({category, index, range}: {category: typeof historyCategories[number]; index: number; range: string}) => <div data-history-category={category.name} className="shrink-0" style={{height: 178, padding: 12, borderRadius: 10, background: color.fillCard, border: `1px solid ${color.strokeCard}`}}>
  <div className="flex items-center gap-[12px]" style={{height: 16, lineHeight: '14px', marginBottom: 4, fontSize: 12, fontWeight: 600}}>{category.title}<div className="flex-1" />{category.values.map((label, series) => <span key={label} style={{fontSize: 9, color: [color.blue, color.red, color.cyan][series], fontWeight: 400}}>{label}</span>)}</div>
  <svg width="100%" height="132" viewBox="0 0 660 132" preserveAspectRatio="xMidYMid meet">
    {[17, 53, 89].map((y) => <path key={y} d={`M42 ${y}H646`} stroke={color.divider} />)}
    {[category.unit === 'rpm' ? '3,000' : category.unit === '%' ? '100' : '60', category.unit === 'rpm' ? '1,500' : category.unit === '%' ? '50' : '30', '0'].map((label, row) => <text key={row} x={35} y={20 + row * 36} fontSize={8} textAnchor="end" fill={color.secondary}>{label}</text>)}
    {category.values.map((label, series) => <polyline key={label} data-history-series={label} points={Array.from({length: 52}, (_, point) => `${42 + point * 11.8},${66 - Math.sin((point * 0.28) + index + series) * (17 + series * 3) - Math.cos(point * 0.64 + series) * 7 + series * 10}`).join(' ')} stroke={[color.blue, color.red, color.cyan][series]} strokeWidth={1.7} fill="none" />)}
    {(range === '24 hours' ? ['00:00', '06:00', '12:00', '18:00', 'Now'] : ['11/05', '11/07', '11/09', '11/11', 'Now']).map((label, point) => <text key={label} x={42 + point * 151} y={125} fontSize={8} fill={color.secondary} textAnchor={point === 0 ? 'start' : point === 4 ? 'end' : 'middle'}>{label}</text>)}
  </svg>
</div>;

export const SystemHistoryTourModule = ({frame, globalFrame}: {frame: number; globalFrame: number}) => {
  const state = systemHistoryTourAt(frame);
  if (state.phase === 'live') return <SystemModule frame={globalFrame} />;
  if (state.phase === 'settings') return <DesktopSettingsPage title="System status and cleanup"><div data-system-history-settings><div style={{fontSize: 12, fontWeight: 600, color: color.secondary, marginBottom: 14}}>System monitor</div><TourCard><TourToggle label="Record history" on /><div style={{fontSize: 10, lineHeight: '16px', color: color.secondary, marginTop: 7}}>Minute readings for CPU, GPU, memory, disk, fans and network.</div><div className="flex items-center gap-[12px]" style={{marginTop: 17}}><NativeAction label="View history" active /><div style={{fontSize: 10, color: color.secondary}}>1,440 readings · 24 hours</div></div></TourCard><TourPointer frame={frame} at={36} x={70} y={203} /></div></DesktopSettingsPage>;
  return <div data-system-history-window className="relative" style={{width: 720, height: 560, padding: 18, background: '#27272b', borderRadius: 12, border: `1px solid ${color.strokeCard}`, boxShadow: '0 22px 60px #0009'}}>
    <div data-system-history-header className="flex flex-col gap-[10px]" style={{height: 76}}>
      <div className="flex items-center gap-[8px]" style={{height: 34}}><div><div style={{fontSize: 16, fontWeight: 600}}>System history</div><div style={{fontSize: 10, color: color.secondary, marginTop: 3}}>10,080 readings · Nov 5–12</div></div><div className="flex-1" /><NativeAction label="Clear" /><NativeAction label="Export" active /></div>
      <div className="flex items-center gap-[10px]" style={{height: 26}}><span style={{fontSize: 11, color: color.secondary}}>Time range</span><div className="flex" style={{width: 280, height: 24, borderRadius: 6, padding: 2, background: color.fillControl}}>{['24 hours', '7 days', '30 days', 'All'].map((range) => <div key={range} className="flex flex-1 items-center justify-center" style={{fontSize: 10, background: range === state.range ? white(0.15) : 'transparent', borderRadius: 4}}>{range}</div>)}</div><div className="flex-1" /><div aria-label="Refresh"><IconButton compact icon={RotateCcw} /></div></div>
    </div>
    <div data-system-history-scroll className="relative" style={{height: 404, marginTop: 14, overflow: 'hidden'}}>
      <div data-system-history-scroll-content className="flex flex-col gap-[12px]" style={{transform: `translateY(${-state.scroll}px)`}}>{historyCategories.map((category, index) => <HistoryChart key={category.name} category={category} index={index} range={state.range} />)}</div>
      <div className="absolute right-0" style={{top: state.scroll / 724 * 261, height: 143, width: 4, borderRadius: 2, background: white(0.22)}} />
    </div>
    <div data-system-history-footer className="flex items-center gap-[6px]" style={{height: 16, marginTop: 14, fontSize: 10, color: state.exported ? color.green : color.secondary}}>{state.exported ? <Check size={12} /> : null}{state.exported ? 'Saved: System history.xlsx' : state.save ? 'Exporting all recorded readings…' : 'Minute-level readings · All history included in export'}</div>
    {state.save ? <div data-system-history-save className="absolute flex flex-col gap-[14px]" style={{left: 145, top: 133, width: 430, padding: 20, borderRadius: 12, background: '#353539', border: `1px solid ${color.strokeCard}`, boxShadow: '0 16px 50px #000b'}}><div style={{fontSize: 14, fontWeight: 600}}>Export system history</div><div className="flex items-center gap-[12px]" style={{fontSize: 12}}><span>Save As:</span><div className="flex-1" style={{padding: '7px 9px', background: color.fillControl, borderRadius: 5}}>System history.xlsx</div></div><div className="flex items-center gap-[13px]" style={{fontSize: 12}}><span>Where:</span><span>Documents</span></div><div className="flex justify-end gap-[8px]"><NativeAction label="Cancel" /><NativeAction label="Save" active /></div><TourPointer frame={frame} at={206} x={391} y={145} /></div> : null}
    {!state.save ? <TourPointerTrack frame={frame} actions={[{at: 68, x: 132, y: 76}, {at: 188, x: 669, y: 36}]} /> : null}
  </div>;
};

export const batteryTourAt = (frame: number) => {
  const position = Math.min(209, Math.max(0, frame));
  const onBattery = position >= 170;
  const fullyCharged = position >= 110 && !onBattery;
  const charging = position >= 44 && position < 110;
  return {...desktopDemo.battery, onBattery, fullyCharged, charging, chargingRequested: position >= 38, lowPower: position >= 151, level: position >= 110 ? 1 : desktopDemo.battery.level, chargingWatts: charging ? desktopDemo.battery.chargingWatts : 0, inputWatts: onBattery ? 0 : fullyCharged ? 12.7 : charging ? desktopDemo.battery.inputWatts : desktopDemo.battery.systemWatts, systemWatts: fullyCharged ? 12.7 : desktopDemo.battery.systemWatts};
};

const BatteryTrend = ({title, value, tint}: {title: string; value: string; tint: string}) => <TourCard style={{padding: 10, height: 77}}><div className="flex items-center" style={{fontSize: 12, fontWeight: 600}}>{title}<div className="flex-1" /><span className="tabular" style={{fontSize: 11, color: tint}}>{value}</span></div><svg width="100%" height="40" viewBox="0 0 425 40" preserveAspectRatio="xMidYMid meet" style={{marginTop: 7}}><polyline points="0,31 20,30 40,31 60,28 80,29 100,27 120,26 140,27 160,25 180,24 200,23 220,22 240,23 260,20 280,20 300,21 320,18 340,18 360,17 380,15 400,16 425,15" stroke={tint} strokeWidth={1.5} fill="none" /></svg></TourCard>;

const PowerEndpoint = ({icon, value, caption}: {icon: ReactNode; value?: string; caption: string}) => <div className="flex h-full w-full flex-col items-center justify-center gap-[5px]" style={{padding: '0 6px', borderRadius: 8, background: color.fillCard, border: `0.5px solid ${color.strokeCard}`}}>{icon}{value ? <span className="font-rounded tabular" style={{fontSize: 12, fontWeight: 600}}>{value}</span> : null}<span style={{fontSize: 9, fontWeight: 500, color: color.secondary}}>{caption}</span></div>;

export const BatteryTourModule = ({frame}: {frame: number}) => {
  const state = batteryTourAt(frame);
  const percent = `${Math.round(state.level * 100)}%`;
  const split = state.charging;
  return <div data-battery-detail className="absolute inset-0 flex flex-col gap-[12px]" style={{padding: 12}}>
    <div data-battery-section="header" className="flex shrink-0 items-center gap-[8px]" style={{height: 30}}><Laptop size={13} /><span style={{fontSize: 12, fontWeight: 600}}>Local battery</span><div className="flex gap-[4px]">{['Automatic', 'Low power', 'High power'].map((mode) => <div key={mode} style={{padding: '2px 8px', borderRadius: 5, fontSize: 10, background: mode === (state.lowPower ? 'Low power' : state.onBattery || state.fullyCharged ? 'Automatic' : 'High power') ? color.blue : color.fillControl}}>{mode}</div>)}</div><div className="flex-1" />{!state.onBattery && !state.fullyCharged && !state.charging ? <div data-feature="chargeToFull"><NativeAction label="Charge to 100%" icon={<Power size={11} />} /></div> : null}<span style={{fontSize: 9, color: color.secondary}}>{state.onBattery ? 'On battery' : state.fullyCharged ? 'Fully charged' : state.charging ? 'Charging' : 'Optimised charging'}</span><BatteryFull size={13} color={state.lowPower ? color.yellow : color.green} /><span className="font-rounded tabular" style={{fontSize: 10, fontWeight: 600}}>{percent}</span></div>
    <div data-battery-section="flow" className="flex shrink-0 gap-[8px]" style={{height: split ? 176 : 96}}>
      <div className="shrink-0" style={{width: 84}}><PowerEndpoint icon={state.onBattery ? <BatteryFull size={22} color={color.green} /> : <Plug size={22} color={color.orange} />} value={state.onBattery ? percent : `${state.inputWatts} W`} caption={state.onBattery ? 'Battery supply' : 'Adapter input'} /></div>
      {split ? <>
        <div className="relative min-w-0 flex-1">
          <svg width="100%" height="176" viewBox="0 0 540 176" preserveAspectRatio="none">
            <defs><linearGradient id="battery-charge-route" x1="0" y1="0" x2="1" y2="0"><stop stopColor={color.orange} stopOpacity={0.30} /><stop offset="1" stopColor={color.green} stopOpacity={0.16} /></linearGradient><linearGradient id="battery-system-route" x1="0" y1="0" x2="1" y2="0"><stop stopColor={color.orange} stopOpacity={0.30} /><stop offset="1" stopColor={color.cyan} stopOpacity={0.16} /></linearGradient></defs>
            <path data-power-route="battery" d="M0 0H532Q540 0 540 8V83.6Q540 91.6 532 91.6C334.8 91.6 194.4 105.6 97.2 105.6H0Z" fill="url(#battery-charge-route)" stroke={color.strokeCard} strokeWidth={0.5} />
            <path data-power-route="system" d="M0 105.6H97.2C194.4 105.6 334.8 119.6 532 119.6Q540 119.6 540 127.6V168Q540 176 532 176H0Z" fill="url(#battery-system-route)" stroke={color.strokeCard} strokeWidth={0.5} />
          </svg>
          {[['Charging', state.chargingWatts, 52.8], ['System use', state.systemWatts, 140.8]].map(([title, watts, y]) => <div key={title} className="absolute inset-x-0 flex flex-col items-center gap-[2px]" style={{top: Number(y), transform: 'translateY(-50%)'}}><span className="font-rounded tabular" style={{fontSize: 15, fontWeight: 700}}>{watts} W</span><span style={{fontSize: 9, fontWeight: 500, color: color.secondary}}>{title}</span></div>)}
        </div>
        <div className="flex shrink-0 flex-col gap-[8px]" style={{width: 88}}><div style={{height: 100.8}}><PowerEndpoint icon={<BatteryFull size={22} color={color.green} />} value={percent} caption="Charging" /></div><div className="flex-1"><PowerEndpoint icon={<Laptop size={22} color={color.cyan} />} caption="This Mac" /></div></div>
      </> : <>
        <div data-power-route="system" className="flex min-w-0 flex-1 flex-col items-center justify-center gap-[2px]" style={{borderRadius: 8, border: `0.5px solid ${color.strokeCard}`, background: `linear-gradient(90deg, ${alpha(color.orange, 0.28)}, ${alpha(color.cyan, 0.14)})`}}><span className="font-rounded tabular" style={{fontSize: 15, fontWeight: 700}}>{state.systemWatts.toFixed(1)} W</span><span style={{fontSize: 9, fontWeight: 500, color: color.secondary}}>{state.onBattery ? 'Battery supply' : 'System use'}</span></div>
        <div className="shrink-0" style={{width: 84}}><PowerEndpoint icon={<Laptop size={22} color={color.cyan} />} caption="This Mac" /></div>
      </>}
    </div>
    <div data-battery-section="readings" className="flex gap-[12px]" style={{height: 164}}><div className="flex min-w-0 flex-1 flex-col gap-[10px]"><BatteryTrend title="Battery level" value={percent} tint={state.lowPower ? color.yellow : color.green} /><BatteryTrend title="System power" value={`${state.systemWatts.toFixed(1)} W`} tint={color.orange} /></div><div data-battery-metrics className="flex shrink-0 flex-col gap-[4px]" style={{width: 250, padding: 8, borderRadius: 6, background: white(0.06), border: `1px solid ${color.strokeCard}`}}>{[['Health', '96%'], ['Cycles', '124'], ['Temperature', '31°C'], ['Max capacity', '4,800 mAh'], ['Design capacity', '5,000 mAh'], ['Current charge', `${Math.round(4800 * state.level).toLocaleString('en-US')} mAh`], ['Current', state.onBattery ? '−1.60 A' : state.charging ? '+2.40 A' : '0.00 A'], ['Voltage', '15.00 V'], ['Adapter rated', '96 W']].map(([label, value]) => <div key={label} className="flex items-center" style={{height: 12, fontSize: 9}}><span style={{color: color.secondary}}>{label}</span><div className="flex-1" /><span className="tabular">{value}</span></div>)}</div></div>
    <div data-battery-section="devices" className="flex items-center gap-[14px]" style={{height: 30, fontSize: 11}}><span style={{fontSize: 12, fontWeight: 600}}>Nearby devices</span><Keyboard size={16} color={color.secondary} /><span>Keyboard 82%</span><Music size={16} color={color.secondary} /><span>Headphones 64%</span></div>
    <TourPointerTrack frame={frame} actions={[{at: 38, x: 570, y: 27}, {at: 145, x: 245, y: 27}]} />
  </div>;
};

export const CleanupTourModule = ({frame}: {frame: number}) => {
  const review = frame >= 20;
  const confirmation = frame >= 55 && frame < 80;
  const done = frame >= 80;
  return (
    <div data-cleanup-window className="relative" style={{width: 560, height: 430, padding: 18, borderRadius: 12, background: '#27272b', border: `1px solid ${color.strokeCard}`, boxShadow: '0 22px 60px #0009'}}>
      <div className="flex items-center gap-[7px]" style={{height: 47}}><div className="min-w-0 flex-1"><div style={{fontSize: 16, fontWeight: 600}}>Cleanup candidates</div><div style={{fontSize: 10, color: color.secondary, marginTop: 4}}>Grouped by source · Move selected items to Trash</div></div><NativeAction label="Select all" /><NativeAction label="Invert" /><div aria-label="Rescan"><IconButton compact icon={RotateCcw} /></div></div>
      <div data-cleanup-list style={{height: 276, marginTop: 14, padding: '6px 10px', borderRadius: 6, background: white(0.035), overflow: 'hidden'}}>{desktopDemo.cleanup.map((item, index) => !done || index === 2 ? <div key={item.name} style={{marginBottom: 8}}><div className="flex items-center gap-[6px]" style={{height: 18, fontSize: 10, color: color.secondary}}><ChevronDown size={9} /><span>{item.source}</span><span style={{fontSize: 9}}>· {review && index < 2 ? 1 : 0}/1</span><div className="flex-1" /><span className="tabular" style={{fontSize: 9}}>{item.sizeMB} MB</span></div><div data-cleanup-candidate={item.name} className="flex items-start gap-[10px]" style={{padding: '8px 5px', height: 65}}><div className="flex shrink-0 items-center justify-center" style={{width: 13, height: 13, marginTop: 3, borderRadius: 3, background: review && index < 2 ? color.blue : 'transparent', border: `1px solid ${review && index < 2 ? color.blue : color.secondary}`}}>{review && index < 2 ? <Check size={10} /> : null}</div><Folder size={17} color={color.secondary} style={{marginTop: 2, flexShrink: 0}} /><div className="min-w-0 flex-1"><div className="flex items-center gap-[7px]" style={{fontSize: 11}}><span>{item.name}</span><span style={{fontSize: 9, color: index < 2 ? color.green : color.orange}}>{item.safety}</span></div><div style={{fontSize: 9, color: color.secondary, marginTop: 3}}>{item.detail}</div><div style={{fontSize: 9, color: color.secondary, marginTop: 3}}>{item.reason}</div></div><span className="tabular" style={{fontSize: 10, color: color.secondary}}>{item.sizeMB} MB</span></div></div> : null)}</div>
      {done ? <div data-cleanup-result className="flex items-center gap-[5px]" style={{fontSize: 10, color: color.green, marginTop: 10}}><Check size={12} />2 items moved to Trash · 344 MB · Review item kept</div> : null}
      <div data-cleanup-footer className="absolute flex items-center gap-[8px]" style={{left: 18, right: 18, top: 383, height: 29, fontSize: 10}}><span style={{color: color.secondary}}>{done ? 'Selected 0 / 1 · 0 MB' : `Selected ${review ? 2 : 0} / 3 · ${review ? 344 : 0} MB`}</span><div className="flex-1" /><NativeAction label={done ? 'Done' : 'Cancel'} /><NativeAction label="Move to Trash" active={review && !done} /></div>
      {confirmation ? <div data-cleanup-confirmation className="absolute" style={{left: 95, top: 127, width: 370, padding: 18, borderRadius: 13, border: `1px solid ${color.strokeCard}`, background: '#343438', boxShadow: '0 15px 60px rgba(0,0,0,0.75)'}}><div style={{fontSize: 15, fontWeight: 600}}>Move 2 items to Trash?</div><div style={{fontSize: 11, lineHeight: '17px', marginTop: 10, color: color.secondary}}>Application and package manager caches · 344 MB</div><div className="flex justify-end gap-[8px]" style={{marginTop: 18}}><NativeAction label="Cancel" /><NativeAction label="Move to Trash" active /></div><TourPointer frame={frame} at={74} x={294} y={100} /></div> : null}
      {!confirmation ? <TourPointer frame={frame} at={49} x={480} y={397} /> : null}
    </div>
  );
};
