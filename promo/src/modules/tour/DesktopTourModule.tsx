import {ArrowRight, BatteryFull, Check, Fan, Folder, HardDrive, Keyboard, Laptop, Music, Power, Volume2, VolumeX, X} from 'lucide-react';
import {ProgressTrack} from '../../components/Glass';
import {BrowserGlyph, formatTime} from '../../components/IslandChrome';
import {ease, linear} from '../../motion';
import {color, white} from '../../theme';
import {SystemModule} from '../SystemModule';
import {TourAction, TourCard, TourHeading, TourPointer, TourResult, TourSelect, TourToggle} from './TourSurface';

export const desktopDemo = {
  mixer: [{name: 'Safari', volume: 0.3}, {name: 'Music', volume: 0.8}],
  typing: {characters: 12846, topApp: 'Xcode', activeMinutes: 86, peak: 12},
  battery: {level: 0.76, health: 96, cycles: 124, celsius: 31, inputWatts: 60, systemWatts: 24, chargingWatts: 36},
  cleanup: [{name: 'Application caches', sizeMB: 320, safety: 'Safe to clean'}, {name: 'Application logs', sizeMB: 24, safety: 'Safe to clean'}, {name: 'Old preferences', sizeMB: 3, safety: 'Review required'}],
} as const;

export const backgroundSounds = ['Pink noise', 'Brown noise', 'White noise', 'Balanced noise', 'Bright noise', 'Dark noise', 'Ocean', 'Rain', 'Stream', 'Night', 'Fire', 'Babble', 'Steam', 'Airplane', 'Boat', 'Bus', 'Train', 'Rain on roof', 'Quiet night'] as const;

export const MixerTourModule = ({frame}: {frame: number}) => {
  const safari = ease(frame, [25, 78], [1, desktopDemo.mixer[0].volume]);
  const muted = frame >= 112;
  return (
    <div className="absolute inset-0 flex flex-col gap-[18px]" style={{padding: 27}}>
      <TourHeading title="Application volume mixer"><span style={{fontSize: 14, color: color.secondary}}>macOS 14.4+</span></TourHeading>
      {desktopDemo.mixer.map((app, index) => {
        const volume = index === 0 ? safari : app.volume;
        return <TourCard key={app.name} style={{padding: '24px 22px'}}><div className="flex items-center gap-[18px]">
          {index === 0 ? <BrowserGlyph size={39} /> : <div className="flex items-center justify-center" style={{width: 39, height: 39, borderRadius: 10, background: '#ea4167'}}><Music size={25} /></div>}
          <div style={{width: 210, fontSize: 21, fontWeight: 500}}>{app.name}</div>
          <div className="relative flex-1"><ProgressTrack value={volume} tint={color.blue} width="100%" height={5} /><div className="absolute" style={{left: `calc(${volume * 100}% - 8px)`, top: -5, width: 15, height: 15, borderRadius: 8, background: '#fff'}} /></div>
          <div className="font-mono tabular" style={{width: 65, textAlign: 'right', fontSize: 17, color: color.secondary}}>{Math.round(volume * 100)}%</div>
          {index === 1 && muted ? <VolumeX size={23} color={color.orange} /> : <Volume2 size={23} />}
        </div></TourCard>;
      })}
      <div className="flex-1" />
      {frame >= 126 ? <TourResult>Safari at 30% · Music muted</TourResult> : <div style={{fontSize: 16, color: color.secondary}}>Adjust and mute each app independently.</div>}
      <div style={{fontSize: 14, color: color.secondary}}>System Audio Recording permission</div>
      <TourPointer frame={frame} at={56} x={629} y={137} />
      <TourPointer frame={frame} at={112} x={960} y={249} />
    </div>
  );
};

const KEYS = ['F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12', 'Q W E R T Y U I O P', 'A S D F G H J K L', 'Z X C V B N M'] as const;

export const KeyboardTourModule = ({frame}: {frame: number}) => {
  const pressed = frame >= 46 && frame < 112;
  const count = desktopDemo.typing.characters + Math.floor(linear(frame, [45, 112], [0, 14]));
  return (
    <div className="absolute inset-0 flex flex-col gap-[16px]" style={{padding: 24}}>
      <TourHeading title="Keyboard sounds and typing stats"><TourSelect value={frame < 35 ? 'Holy Panda' : frame < 132 ? 'Cherry MX Brown' : 'BCP (Suit80) · Custom sound pack'} /><TourAction label="Preview" active={pressed} /></TourHeading>
      <div className="flex gap-[12px]">{[['Today’s characters', count.toLocaleString('en-US')], ['Most used app', desktopDemo.typing.topApp], ['Peak typing', '12 chars / s'], ['Active time', '1 h 26 m']].map(([label, value]) => <TourCard key={label} style={{flex: 1, padding: '12px 15px'}}><div style={{fontSize: 14, color: color.secondary}}>{label}</div><div className="tabular" style={{fontSize: 27, fontWeight: 600, marginTop: 7}}>{value}</div></TourCard>)}</div>
      <div className="flex gap-[20px]">
        <div className="flex min-w-0 flex-[1.2] flex-col gap-[7px]">{KEYS.map((row, rowIndex) => <div key={row} className="flex justify-center gap-[5px]">{row.split(' ').map((key, index) => <div key={key} className="flex items-center justify-center" style={{width: rowIndex === 0 ? 35 : 44, height: 30, borderRadius: 5, fontSize: 12, border: `1px solid ${color.strokeCard}`, background: pressed && ['Z', 'I', 'S', 'L', 'A'].includes(key) ? color.blue : white(0.06 + ((index * 7 + rowIndex * 5) % 9) * 0.02)}}>{key}</div>)}</div>)}</div>
        <div className="flex min-w-0 flex-1 flex-col gap-[10px]">
          <TourToggle label="Keyboard sounds" on />
          <TourToggle label="Local typing stats" on />
          <div style={{fontSize: 14, color: color.secondary}}>Volume · Pitch variation · Release sounds</div>
          <div className="flex items-end gap-[5px]" style={{height: 46}}>{[12, 24, 18, 36, 44, 32, 20, 35, 15].map((height, index) => <div key={index} style={{flex: 1, height, background: color.blue, opacity: 0.4 + (index % 4) * 0.15, borderRadius: 2}} />)}</div>
        </div>
      </div>
      <div className="flex items-center gap-[20px]" style={{fontSize: 14, color: color.secondary}}><span>20 voices · Custom packs · Trend · History · App timeline</span><div className="flex-1" /><span>Voice: 142 wpm · 18 min saved</span></div>
      <TourResult>{frame >= 113 ? 'Typing stats updated · 14 characters added' : 'Key presses update the local dashboard'}</TourResult>
    </div>
  );
};

export const FocusTourModule = ({frame}: {frame: number}) => {
  const running = frame >= 38 && frame < 158;
  const finished = frame >= 158;
  const remaining = finished ? 0 : running ? 2 - Math.floor((frame - 38) / 60) : 2;
  return (
    <div className="absolute inset-0 flex gap-[26px]" style={{padding: 26}}>
      <TourCard style={{width: 342, display: 'flex', flexDirection: 'column', padding: 24}}>
        <div style={{fontSize: 23, fontWeight: 600}}>Focus countdown</div>
        <div style={{marginTop: 14}}><TourSelect value="Focus" /></div>
        <div className="font-rounded tabular" style={{fontSize: 67, fontWeight: 600, textAlign: 'center', marginTop: 30}}>{formatTime(remaining)}</div>
        <div style={{marginTop: 7, textAlign: 'center', fontSize: 16, color: color.secondary}}>{finished ? 'Session completed' : running ? 'In progress' : 'Ready to start'}</div>
        <div className="flex-1" />
        <div className="flex gap-[9px]"><TourAction label={running ? 'Pause' : 'Start'} active={!finished} /><TourAction label="Reset" /></div>
      </TourCard>
      <div className="flex min-w-0 flex-1 flex-col gap-[14px]">
        <TourHeading title="Keep work on screen" />
        <TourCard><TourToggle label="Keep display awake" on={frame >= 82} /><div style={{fontSize: 14, marginTop: 7, color: color.secondary}}>Includes lid close · Administrator authorization</div></TourCard>
        <TourCard><TourToggle label="Prevent idle sleep" on={frame >= 110} /></TourCard>
        <TourCard style={{padding: '12px 15px'}}>
          <div className="flex items-center gap-[12px]" style={{fontSize: 16}}><span className="flex-1">macOS background sounds</span><TourSelect value={frame < 129 ? 'Rain' : frame < 187 ? 'Ocean' : 'Stream'} /><TourAction label={frame >= 65 ? 'Stop' : 'Play'} active={frame >= 65} /></div>
          <div style={{marginTop: 9, fontSize: 13.5, color: color.secondary}}>Rain · Ocean · Stream · Night · Noise · Transport sounds</div>
          <div style={{marginTop: 9}}><TourToggle label="Stop on lock, screen saver or sleep" on /></div>
        </TourCard>
        <div className="flex-1" />
        {finished ? <TourResult>Focus completed · One alert and notification</TourResult> : <TourResult pending>{frame >= 110 ? 'Display awake · Idle sleep prevented' : 'Start a focus session'}</TourResult>}
      </div>
      <TourPointer frame={frame} at={38} x={96} y={372} />
      <TourPointer frame={frame} at={82} x={940} y={116} />
    </div>
  );
};

export const CleaningTourModule = ({frame}: {frame: number}) => {
  const screen = frame >= 26 && frame < 87;
  const keyboard = frame >= 94 && frame < 150;
  return (
    <div className="absolute inset-0 flex flex-col gap-[20px]" style={{padding: 27}}>
      <TourHeading title="Screen and keyboard cleaning" />
      <div className="flex gap-[13px]"><TourAction label="Clean screen" active={screen} /><TourAction label={keyboard ? 'End cleaning' : 'Clean keyboard'} active={keyboard} /><TourAction label="Trash" /></div>
      <div className="relative flex min-h-0 flex-1 items-center justify-center" style={{borderRadius: 10, background: screen ? '#000' : white(0.04), border: `1px solid ${color.strokeCard}`}}>
        {screen ? <div className="flex flex-col items-center gap-[17px]"><div style={{fontSize: 25, fontWeight: 500}}>Screen cleaning</div><TourAction label="Exit screen cleaning" active /></div> : <div className="flex flex-col items-center gap-[16px]"><Keyboard size={58} color={keyboard ? color.blue : color.secondary} /><div style={{fontSize: 24}}>{keyboard ? 'Keyboard input blocked' : 'Screen ready for work'}</div><div style={{fontSize: 16, color: color.secondary}}>Includes F1–F12</div></div>}
      </div>
      {frame >= 150 ? <TourResult>Screen restored · Keyboard input resumed</TourResult> : <div style={{fontSize: 16, color: color.secondary}}>{keyboard ? 'Click End cleaning to resume keyboard input.' : 'Click to exit the full-screen black cover.'}</div>}
      <TourPointer frame={frame} at={26} x={111} y={104} />
      <TourPointer frame={frame} at={94} x={253} y={104} />
      <TourPointer frame={frame} at={150} x={253} y={104} />
    </div>
  );
};

export const PresenterTourModule = ({frame}: {frame: number}) => {
  const playing = frame >= 38 && frame < 112;
  const closed = frame >= 136;
  return (
    <div className="absolute inset-0 flex gap-[23px]" style={{padding: 24}}>
      <div className="flex min-w-0 flex-[1.35] flex-col gap-[13px]">
        <TourHeading title="Teleprompter" />
        <div className="relative min-h-0 flex-1 overflow-hidden" style={{borderRadius: 10, background: '#070708', padding: '28px 24px'}}>
          <div className="whitespace-pre-line" style={{fontSize: 31, lineHeight: '45px', transform: `translateY(${-linear(frame, [38, 112], [0, 48])}px)`}}>Make room for the work.{'\n'}Keep the tools close.{'\n'}Let the next idea flow.</div>
        </div>
        <div className="flex items-center gap-[12px]"><TourAction label={playing ? 'Pause' : 'Play'} active={playing} /><TourAction label="Reset" /><TourSelect value="Scroll speed: 45" /></div>
        <TourResult>{frame >= 112 ? 'Script paused at your place' : 'Drag text here and start scrolling'}</TourResult>
      </div>
      <div className="flex min-w-0 flex-1 flex-col gap-[13px]">
        <TourHeading title="Camera mirror" />
        <div className="relative min-h-0 flex-1 overflow-hidden" style={{borderRadius: 10, background: '#111318'}}>
          {closed ? <div className="absolute inset-0 flex items-center justify-center" style={{fontSize: 21, color: color.secondary}}>Camera stopped</div> : <svg width="100%" height="100%" viewBox="0 0 370 270" preserveAspectRatio="xMidYMid slice" style={{transform: 'scaleX(-1)'}}>
            <defs><linearGradient id="mirror-room" x1="0" y1="0" x2="1" y2="1"><stop stopColor="#627581" /><stop offset="1" stopColor="#27323e" /></linearGradient></defs>
            <rect width="370" height="270" fill="url(#mirror-room)" /><rect x="25" y="30" width="70" height="117" fill="#a4b8c2" /><path d="M54 30v117M25 82h70" stroke="#677d8b" strokeWidth="5" />
            <path d="M83 280 Q88 183 185 181 Q282 183 287 280" fill="#425b6b" /><rect x="160" y="139" width="51" height="53" rx="17" fill="#cfaa93" />
            <ellipse cx="184" cy="104" rx="62" ry="73" fill="#d8b49a" /><path d="M122 102 Q112 21 185 17 Q254 17 251 94 L225 69 Q164 72 145 49 Z" fill="#372b2a" /><path d="M153 107h16M203 107h16" stroke="#554640" strokeWidth="4" strokeLinecap="round" /><path d="M171 143q14 10 28 0" fill="none" stroke="#966457" strokeWidth="3" strokeLinecap="round" />
          </svg>}
          {!closed ? <div className="absolute right-[8px] top-[8px] flex items-center justify-center" style={{width: 25, height: 25, borderRadius: 13, background: 'rgba(0,0,0,0.6)'}}><X size={15} /></div> : null}
        </div>
        <div style={{fontSize: 15, color: color.secondary}}>{closed ? 'Closed · Camera session released' : 'Mirrored camera preview'}</div>
      </div>
      <TourPointer frame={frame} at={38} x={61} y={360} />
      <TourPointer frame={frame} at={136} x={1003} y={91} />
    </div>
  );
};

export const SystemHistoryTourModule = ({frame, globalFrame}: {frame: number; globalFrame: number}) => (
  <div className="absolute inset-0 flex flex-col gap-[14px]" style={{padding: 16}}>
    <div className="relative" style={{height: 295}}><SystemModule frame={globalFrame} /></div>
    <div className="flex items-center gap-[13px]" style={{padding: '0 7px'}}><TourSelect value="History · Today · 09:00–18:00" /><TourAction label="Export .xlsx" active={frame >= 120} /><div className="flex-1" />{frame >= 150 ? <TourResult>Saved: System history.xlsx</TourResult> : <span style={{fontSize: 14, color: color.secondary}}>Minute-level history</span>}</div>
    <div className="flex items-center gap-[23px]" style={{padding: '0 7px', fontSize: 15, color: color.secondary}}><HardDrive size={16} />Disk: 31% · R 28 MB/s · W 12 MB/s<Fan size={16} />Fan: 2,100 rpm<span>NVMe: 34°C</span><span>Public IPv4 + IPv6</span></div>
    <TourPointer frame={frame} at={120} x={431} y={351} />
  </div>
);

export const BatteryTourModule = ({frame}: {frame: number}) => {
  const onBattery = frame >= 65;
  const lowPower = frame >= 115;
  return (
    <div className="absolute inset-0 flex gap-[25px]" style={{padding: 26}}>
      <div className="flex min-w-0 flex-1 flex-col gap-[18px]">
        <TourHeading title="Battery and power" />
        <TourCard><div className="flex items-center gap-[20px]"><BatteryFull size={40} color={color.green} /><div className="font-rounded tabular" style={{fontSize: 46, fontWeight: 600}}>76%</div><div style={{fontSize: 16, color: color.secondary}}>{onBattery ? 'On battery' : 'Charging'}</div></div><ProgressTrack value={desktopDemo.battery.level} tint={color.green} width="100%" height={5} /></TourCard>
        <div className="grid grid-cols-3 gap-[10px]">{[['Health', '96%'], ['Cycles', '124'], ['Temperature', '31°C']].map(([label, value]) => <TourCard key={label}><div style={{fontSize: 13, color: color.secondary}}>{label}</div><div className="tabular" style={{fontSize: 25, marginTop: 7, fontWeight: 600}}>{value}</div></TourCard>)}</div>
        <div style={{fontSize: 15, color: color.secondary}}>Nearby devices: Keyboard 82% · Headphones 64%</div>
      </div>
      <div className="flex min-w-0 flex-1 flex-col gap-[17px]">
        <TourHeading title={onBattery ? 'Battery → Mac' : 'Adapter → Battery + Mac'} />
        <TourCard><div className="flex items-center justify-between" style={{fontSize: 19}}>{onBattery ? <BatteryFull size={28} /> : <Power size={28} color={color.orange} />}<span>{onBattery ? '24 W' : '60 W input'}</span><ArrowRight size={26} /><Laptop size={35} /></div><div style={{marginTop: 14, fontSize: 15, color: color.secondary}}>{onBattery ? '24 W system power' : '36 W charging · 24 W system power'}</div></TourCard>
        <TourToggle label="Automatic power mode" on />
        <TourSelect value={lowPower ? 'Low power' : onBattery ? 'Automatic · Battery default' : 'High power · Adapter default'} />
        <div className="flex gap-[9px]"><TourAction label="Automatic" active={!lowPower} /><TourAction label="Low power" active={lowPower} /><TourAction label="High power" /></div>
        {lowPower ? <TourResult>Low power mode applied</TourResult> : <div style={{fontSize: 15, color: color.secondary}}>Mode follows the power source.</div>}
      </div>
      <TourPointer frame={frame} at={115} x={778} y={299} />
    </div>
  );
};

export const CleanupTourModule = ({frame}: {frame: number}) => {
  const review = frame >= 20;
  const confirmation = frame >= 49 && frame < 74;
  const done = frame >= 74;
  return (
    <div className="absolute inset-0 flex flex-col gap-[15px]" style={{padding: 26}}>
      <TourHeading title="Disk cleanup candidates"><TourAction label="Rescan" /><TourAction label="Select all" /><TourAction label="Invert selection" /></TourHeading>
      {desktopDemo.cleanup.map((item, index) => <TourCard key={item.name} style={{padding: '14px 18px'}}><div className="flex items-center gap-[13px]"><div className="flex items-center justify-center" style={{width: 19, height: 19, borderRadius: 4, background: review && index < 2 ? color.blue : 'transparent', border: `1px solid ${review && index < 2 ? color.blue : color.secondary}`}}>{review && index < 2 ? <Check size={14} /> : null}</div><Folder size={21} color={color.secondary} /><div className="flex-1" style={{fontSize: 19, fontWeight: 500}}>{item.name}</div><span style={{fontSize: 14, color: index < 2 ? color.green : color.orange}}>{item.safety}</span><span className="tabular" style={{width: 66, textAlign: 'right', fontSize: 16, color: color.secondary}}>{item.sizeMB} MB</span></div></TourCard>)}
      <div className="flex items-center gap-[18px]"><TourSelect value="Automatic cleanup: Off / 7 / 15 / 30 days" /><div className="flex-1" /><TourAction label="Move selected to Trash" active={review && !done} /></div>
      {done ? <TourResult>2 items moved to Trash · 344 MB · Review item kept</TourResult> : <div style={{fontSize: 15, color: color.secondary}}>Review candidates before moving them to Trash.</div>}
      {confirmation ? <div className="absolute" style={{left: 326, top: 151, width: 386, padding: 22, borderRadius: 13, border: `1px solid ${color.strokeCard}`, background: '#26262b', boxShadow: '0 15px 60px rgba(0,0,0,0.75)'}}><div style={{fontSize: 22, fontWeight: 600}}>Move 2 items to Trash?</div><div style={{fontSize: 16, marginTop: 11, color: color.secondary}}>Application caches and logs · 344 MB</div><div className="flex justify-end gap-[8px]" style={{marginTop: 18}}><TourAction label="Cancel" /><TourAction label="Move to Trash" active /></div></div> : null}
      <TourPointer frame={frame} at={49} x={841} y={341} />
    </div>
  );
};
