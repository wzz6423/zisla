import type {ReactNode} from 'react';
import {BatteryFull, Check, Folder, GripVertical, Music, Pause, Play, Sun, Terminal} from 'lucide-react';
import {AlbumArt, BrowserGlyph, formatTime} from '../../components/IslandChrome';
import {MenuBar, Notch, Wallpaper} from '../../components/Desktop';
import {Cursor} from '../../components/Cursor';
import {QuickActionToast} from '../../components/Overlays';
import {Caption, Headline} from '../../components/Caption';
import {ProgressTrack} from '../../components/Glass';
import {track} from '../../content';
import {ease, linear} from '../../motion';
import {color, white} from '../../theme';
import {TourAction, TourCard, TourHeading, TourPointer, TourResult, TourSelect, TourToggle} from './TourSurface';

export const quickActionExamples = [
  {kind: 'Currency amount', input: 'US$20 → EUR', detail: 'Example rate: 1 USD = 0.9200 EUR', action: 'Copy result', result: '€18.40 copied', options: ['Copy result', 'Copy full expression'], from: 0, duration: 120, at: 60},
  {kind: 'App repair', input: 'Studio.app can’t be opened', detail: 'App can’t be opened', action: 'Repair and open', result: 'Studio.app opened after checks', options: ['Repair and open'], from: 120, duration: 180, at: 120},
] as const;

export const quickActionKinds = ['Link', 'IP address', 'File path', 'Email', 'Phone', 'Colour', 'Math', 'Conversion', 'Date & time', 'Address', 'Flight', 'Train', 'Tracking', 'Meeting', 'Emoji name', 'Code', 'Shell command', 'Translation', 'App', 'App repair', 'Text', 'Image', 'File'] as const;

export const permissionDemo = [
  {id: 'accessibility', name: 'Accessibility', body: 'For global shortcuts, entering text, and interacting with windows.', manual: false},
  {id: 'input_monitoring', name: 'Input Monitoring', body: 'For detecting global keyboard shortcuts and input actions.', manual: false},
  {id: 'screen_recording', name: 'Screen Recording', body: 'For taking screenshots and capturing screen content.', manual: false},
  {id: 'system_audio', name: 'System Audio', body: 'For music visualizations. Enable audio recording in System Settings; macOS may confirm again when you first use it.', manual: true},
  {id: 'microphone', name: 'Microphone', body: 'For voice input and audio recording.', manual: false},
  {id: 'camera', name: 'Camera', body: 'For the camera mirror.', manual: false},
  {id: 'speech_recognition', name: 'Speech Recognition', body: 'For converting speech to text.', manual: false},
  {id: 'calendar', name: 'Calendar', body: 'For viewing and managing calendar events.', manual: false},
  {id: 'reminders', name: 'Reminders', body: 'For viewing and managing task reminders.', manual: false},
  {id: 'location', name: 'Location', body: 'For obtaining local weather and network-related information.', manual: false},
  {id: 'notifications', name: 'Notifications', body: 'For sending timer and task reminders.', manual: false},
  {id: 'bluetooth', name: 'Bluetooth', body: 'For viewing the battery levels of connected devices.', manual: false},
  {id: 'automation', name: 'Automation', body: 'For controlling supported media apps and performing actions across apps. macOS confirms permission for each target app.', manual: true},
  {id: 'files', name: 'File Access', body: 'Select the files or folders you need, and macOS will grant the corresponding access permissions.', manual: true},
  {id: 'full_disk_access', name: 'Full Disk Access', body: 'Used to read system Screen Time, local mail indexes, or browser cookies. Enable in System Settings as needed.', manual: true},
] as const;

const WindowContent = ({app, title}: {app: 'Notes' | 'Safari' | 'Quiet.md' | 'Studio'; title: string}) => (
  <div style={{height: '100%', padding: 25, background: app === 'Safari' ? '#1c2430' : '#232327'}}>
    <div style={{fontSize: 23, fontWeight: 600}}>{title}</div>
    {app === 'Studio' ? <div style={{height: 133, marginTop: 24, borderRadius: 8, background: '#121419'}}><div style={{padding: 22, fontSize: 16, color: color.secondary}}>Media library · Timeline</div></div> :
      <div style={{marginTop: 19, fontSize: 17, lineHeight: '30px', color: white(0.82)}}>{app === 'Safari' ? 'example.com/review' : '✓ Review the launch\n✓ Check the feature tour\n✓ Share the finished film'}</div>}
  </div>
);

const DemoWindow = ({app, title, children}: {app: 'Notes' | 'Safari' | 'Quiet.md' | 'Studio' | 'Finder'; title: string; children?: ReactNode}) => (
  <div style={{borderRadius: 12, overflow: 'hidden', background: '#242428', border: `1px solid ${color.strokeCard}`, boxShadow: '0 20px 64px rgba(0,0,0,.4)'}}>
    <div className="flex items-center gap-[7px]" style={{height: 36, padding: '0 14px', background: '#303035'}}>
      {['#ff5f57', '#febc2e', '#28c840'].map((dot) => <span key={dot} style={{width: 10, height: 10, borderRadius: 5, background: dot}} />)}
      <span style={{marginLeft: 13, fontSize: 13, fontWeight: 500}}>{app} · {title}</span>
    </div>
    <div style={{height: 266}}>{children ?? (app !== 'Finder' ? <WindowContent app={app} title={title} /> : null)}</div>
  </div>
);

export const windowsTourAt = (frame: number) => {
  const commandTab = frame >= 33;
  return {commandTab, app: commandTab ? 'Notes' as const : 'Safari' as const, activated: frame >= 55};
};

const previewNames = {Safari: ['Launch review', 'Documentation'], Notes: ['Launch checklist', 'Review notes']} as const;

export const WindowsTourModule = ({frame}: {frame: number}) => {
  const state = windowsTourAt(frame);
  const app = state.activated ? 'Notes' : 'Safari';
  return (
    <div className="absolute inset-0" data-feature="windowPreviews">
      <Wallpaper dim={0.26} /><MenuBar appName={app} /><Notch />
      <Headline lines={['See the window. Switch to it.']} top={72} size={34} />
      <div className="absolute" data-window-active={app} style={{left: 296, top: 224, width: 688}}><DemoWindow app={app} title={state.activated ? 'Launch checklist' : 'Launch review'} /></div>
      {!state.activated ? <>
        <div className="absolute" data-window-preview-app={state.app} data-preview-source={state.commandTab ? 'switcher' : 'dock'} style={{left: 425, top: state.commandTab ? 358 : 368, width: 430, padding: 12, borderRadius: 12, background: '#34343ce8', boxShadow: '0 12px 40px rgba(0,0,0,.5)'}}>
          {!state.commandTab ? <div className="flex items-center gap-[8px]" style={{height: 27, fontSize: 15, fontWeight: 600}}><BrowserGlyph size={17} />{state.app}</div> : null}
          <div className="flex gap-[12px]">{previewNames[state.app].map((title) => <div key={title} data-preview-title={title} style={{width: 196, height: 114, borderRadius: 7, overflow: 'hidden', background: '#25252a'}}><div style={{padding: 14, fontSize: 15, fontWeight: 600}}>{title}</div><div style={{margin: '0 14px', height: 31, borderRadius: 4, background: white(0.12)}} /></div>)}</div>
        </div>
        {state.commandTab ? <div className="absolute flex items-center justify-center gap-[22px]" data-command-tab style={{left: 469, top: 511, width: 342, height: 82, borderRadius: 15, background: '#44444be8'}}>
          <BrowserGlyph size={43} /><div style={{padding: 9, borderRadius: 10, background: white(0.2)}}><Folder size={43} color="#f2cf57" /></div><Music size={43} color="#eb6a77" />
        </div> : null}
      </> : null}
      {!state.commandTab || state.activated ? <div className="absolute flex items-center justify-center gap-[21px]" data-dock style={{left: 495, top: 570, width: 290, height: 63, borderRadius: 15, background: white(0.16)}}><BrowserGlyph size={35} /><Folder size={35} color="#f2cf57" /><Music size={35} color="#eb6a77" /></div> : null}
      {state.activated ? <div className="absolute" style={{left: 490, top: 174}}><TourResult>Notes window activated</TourResult></div> : null}
      {!state.commandTab ? <Cursor x={544} y={596} opacity={1} /> : null}
      {state.commandTab && !state.activated ? <TourPointer frame={frame} at={55} x={532} y={416} /> : null}
      <Caption text="Dock previews · Command-Tab selects an app · Click its window" size={17} bottom={35} />
    </div>
  );
};

export const quickActionsTourAt = (frame: number) => {
  const position = Math.min(299, Math.max(0, frame));
  const example = quickActionExamples.find((item) => position >= item.from && position < item.from + item.duration)!;
  const localFrame = position - example.from;
  const repair = example.kind === 'App repair';
  const copied = localFrame >= (repair ? 28 : 18);
  const started = repair && localFrame >= 64;
  return {example, frame: localFrame, repair, copied, started, done: localFrame >= example.at, menu: !repair && localFrame >= 34 && localFrame < example.at};
};

export const QuickActionsTourModule = ({frame}: {frame: number}) => {
  const state = quickActionsTourAt(frame);
  return (
    <div className="absolute inset-0" data-feature={state.repair ? 'applicationRepair' : 'copyAssistant'}>
      <Wallpaper dim={0.27} /><MenuBar appName={state.repair && !state.done ? 'Finder' : state.repair ? 'Studio' : 'Notes'} /><Notch />
      <Headline lines={[state.repair ? 'Inspect the app. Then open it.' : 'Copy something. Choose the next step.']} top={85} size={34} />
      <div className="absolute" data-quick-action-source={state.repair ? 'Studio.app' : 'currency'} style={{left: 284, top: 213, width: 712}}>
        {state.repair ? state.done ? <DemoWindow app="Studio" title="Launch project" /> :
          <DemoWindow app="Finder" title="Applications"><div className="flex flex-col items-center gap-[16px]" style={{paddingTop: 40}}><div style={{width: 76, height: 76, borderRadius: 16, background: '#647bcc', padding: 17}}><Play size={42} fill="white" /></div><span style={{fontSize: 20, padding: '4px 12px', borderRadius: 6, background: state.copied ? color.blue : white(0.1)}}>Studio.app</span></div></DemoWindow> :
          <DemoWindow app="Notes" title="Travel budget"><div style={{padding: 34, fontSize: 23}}><div style={{fontSize: 29, fontWeight: 600}}>Travel budget</div><div style={{marginTop: 24}}>Convert to euros</div><div data-copied-currency style={{display: 'inline-block', marginTop: 19, padding: '8px 13px', borderRadius: 4, background: state.copied ? '#2969b6' : 'transparent'}}>{state.example.input}</div><div style={{marginTop: 24, fontSize: 19, color: color.secondary}}>{state.done ? '€18.40' : 'EUR —'}</div></div></DemoWindow>}
      </div>
      {state.repair && state.frame < 20 ? <div className="absolute" role="alertdialog" aria-label="macOS application opening alert" style={{left: 444, top: 265, width: 392, padding: 24, borderRadius: 12, background: '#343439', boxShadow: '0 20px 90px #0008'}}><div style={{fontSize: 20, fontWeight: 600}}>{state.example.input}</div><div style={{fontSize: 15, color: color.secondary, marginTop: 16}}>macOS could not open this application.</div><div className="flex justify-end" style={{marginTop: 22}}><TourAction label="OK" active /></div></div> : null}
      {state.copied && !state.started && !state.done ? <div data-quick-action-toast><QuickActionToast title={state.repair ? 'Studio.app' : 'US$20 → EUR'} detail={state.repair ? state.example.detail : '€18.40 · USD to EUR'} action={state.example.action} countdown={1 - state.frame / state.example.duration} actionGlow={state.menu ? 1 : 0} /></div> : null}
      {state.menu ? <div role="menu" aria-label="Currency Quick Actions" data-quick-action-menu style={{position: 'absolute', left: 713, top: 44, width: 228, padding: 6, borderRadius: 8, background: '#303035', boxShadow: '0 10px 32px #0008'}}>
        {state.example.options.map((option) => <div role="menuitem" key={option} style={{padding: '8px 11px', borderRadius: 5, fontSize: 14, background: option === 'Copy result' ? color.blue : 'transparent'}}>{option}</div>)}
      </div> : null}
      {!state.repair ? <TourPointer frame={state.frame} at={18} x={465} y={398} /> : <TourPointer frame={state.frame} at={28} x={640} y={408} />}
      {state.menu ? <TourPointer frame={state.frame} at={state.example.at} x={789} y={65} /> : state.repair && state.copied && !state.started ? <TourPointer frame={state.frame} at={64} x={801} y={17} /> : null}
      <div className="absolute" data-quick-action-outcome style={{left: 372, top: 555, width: 536, textAlign: 'center'}}>
        {state.done ? <TourResult>{state.example.result}</TourResult> : state.started ? <TourResult pending>Checking integrity, signature and macOS assessment…</TourResult> : <span style={{fontSize: 16, color: color.secondary}}>{state.repair ? 'Copy the local .app to inspect it.' : state.example.detail}</span>}
      </div>
      <Caption text={state.repair ? 'Security checks precede quarantine removal and opening' : 'Quick Actions appear at the top of the screen'} size={17} bottom={35} />
    </div>
  );
};

export const INFORMATION_TOUR_ORDER = ['Home', 'Shelf', 'Clipboard', 'Download', 'Weather & Agenda', 'Toolbox', 'Quick Notes', 'AI Info', 'Keyboard Info', 'Mail', 'CPU', 'App Volume Mixer'] as const;
export const informationOrderAt = (frame: number) => frame >= 72 ? ['AI Info', ...INFORMATION_TOUR_ORDER.filter((name) => name !== 'AI Info')] : [...INFORMATION_TOUR_ORDER];

const INFORMATION_ROW_HEIGHT = 44;
const INFORMATION_LIST_TOP = 43;
const INFORMATION_VIEWPORT_HEIGHT = 354;
const INFORMATION_CARE_TOP = INFORMATION_LIST_TOP + INFORMATION_TOUR_ORDER.length * INFORMATION_ROW_HEIGHT + 64 + 130 + 160 + 116;
export const informationTourAt = (frame: number) => {
  const care = frame >= 114;
  const scroll = care ? INFORMATION_CARE_TOP - 12 : frame < 26 ? linear(frame, [4, 20], [180, 260]) : frame < 44 ? linear(frame, [26, 42], [260, 90]) : linear(frame, [48, 72], [90, 0]);
  const dragY = linear(frame, [48, 72], [INFORMATION_LIST_TOP + 7 * INFORMATION_ROW_HEIGHT + 22 - 90, INFORMATION_LIST_TOP + 22]);
  return {care, scroll, dragging: frame >= 48 && frame < 72, dragY, order: informationOrderAt(frame)};
};

export const InformationTourModule = ({frame}: {frame: number}) => {
  const state = informationTourAt(frame);
  return (
    <div className="absolute inset-0" data-feature="island.featureOrder" style={{padding: '17px 40px'}}>
      <TourHeading title="Info" />
      <div data-information-viewport className="relative overflow-hidden" style={{height: INFORMATION_VIEWPORT_HEIGHT, marginTop: 12}}>
        <div data-information-scroll style={{transform: `translateY(${-state.scroll}px)`}}>
          <div style={{height: INFORMATION_LIST_TOP, fontSize: 19, fontWeight: 600}}>Dynamic Island Feature Order</div>
          <div style={{borderRadius: 10, background: color.fillControl}}>{state.order.map((name, index) => <div key={name} data-information-item={name} style={{display: 'flex', alignItems: 'center', gap: 14, height: INFORMATION_ROW_HEIGHT, padding: '0 16px', borderBottom: `1px solid ${color.divider}`, opacity: name === 'AI Info' && state.dragging ? 0.2 : 1, fontSize: 16}}><GripVertical size={16} color={color.secondary} /><span style={{width: 24, color: color.secondary}}>{index + 1}</span><span>{name}</span></div>)}</div>
          <div className="flex items-center justify-between" style={{height: 64, fontSize: 16}}>Restore default order<TourAction label="Restore" /></div>
          <div style={{height: 130}}><div style={{fontSize: 19, fontWeight: 600, marginBottom: 16}}>Dynamic Island mode</div><TourToggle label="Show App Logo" on /><div style={{marginTop: 16}}><TourToggle label="Show More Information" on /></div></div>
          <div style={{height: 160}}><div style={{fontSize: 19, fontWeight: 600, marginBottom: 16}}>Daily briefing</div><TourToggle label="Enable daily briefing" on /><div style={{marginTop: 16}}><TourSelect value="Template: Minimal" /></div><div style={{marginTop: 16}}><TourAction label="Preview" /></div></div>
          <div style={{height: 116}}><div style={{fontSize: 19, fontWeight: 600, marginBottom: 14}}>Workflow modules</div><TourSelect value="Playback source: Automatic" /></div>
          <div data-feature="userCare" style={{padding: 18, borderRadius: 12, background: color.fillControl}}>
            <div style={{fontSize: 19, fontWeight: 600}}>Wellbeing</div><div style={{fontSize: 16, marginTop: 14}}>Wellbeing reminder interval</div>
            <div className="flex items-center gap-[8px]" style={{marginTop: 16}}>{[['0', 'Hours'], ['45', 'Minutes'], ['0', 'Seconds']].map(([value, label]) => <div key={label} className="flex items-center gap-[7px]" style={{fontSize: 15}}><div style={{width: 48, padding: '6px 8px', borderRadius: 6, background: white(0.12), textAlign: 'right'}}>{value}</div>{label}</div>)}<TourAction label="Save" /></div>
            <div style={{fontSize: 15, lineHeight: '24px', color: color.secondary, marginTop: 16}}>A natural break resets the reminder timer.</div>
          </div>
        </div>
        {state.dragging ? <div data-information-drag style={{position: 'absolute', left: 0, top: state.dragY - 22, width: '100%', boxSizing: 'border-box', height: 44, display: 'flex', alignItems: 'center', gap: 14, padding: '0 16px', borderRadius: 7, fontSize: 16, background: '#45454b', boxShadow: '0 6px 22px #0005'}}><GripVertical size={16} />AI Info</div> : null}
        <div style={{position: 'absolute', right: 2, top: 0, width: 3, height: INFORMATION_VIEWPORT_HEIGHT, background: white(0.07)}}><div style={{height: 66, borderRadius: 3, background: white(0.4), transform: `translateY(${state.scroll / (INFORMATION_CARE_TOP + 210 - INFORMATION_VIEWPORT_HEIGHT) * (INFORMATION_VIEWPORT_HEIGHT - 66)}px)`}} /></div>
        {state.dragging ? <Cursor x={80} y={state.dragY} pressed={1} /> : null}
        {!state.care && frame >= 72 ? <div style={{position: 'absolute', left: 300, bottom: 6, padding: '6px 12px', borderRadius: 6, background: '#29292d'}}><TourResult>AI Info moved first · Toolbar updated</TourResult></div> : null}
      </div>
    </div>
  );
};

const PERMISSION_CARD_HEIGHT = 138;
const PERMISSION_CARD_GAP = 12;
export const permissionsTourAt = (frame: number) => {
  const scroll = linear(frame, [12, 32], [0, 570]);
  return {scroll, requesting: frame >= 44 && frame < 83, granted: frame >= 83};
};

export const PermissionsTourModule = ({frame}: {frame: number}) => {
  const state = permissionsTourAt(frame);
  return (
    <div className="absolute inset-0 flex flex-col" style={{padding: '17px 40px'}}>
      <TourHeading title="Permissions" />
      <div data-permission-viewport className="relative min-h-0 flex-1 overflow-hidden" style={{marginTop: 12}}>
        <div data-permission-scroll className="flex flex-col" style={{gap: PERMISSION_CARD_GAP, transform: `translateY(${-state.scroll}px)`}}>
          {permissionDemo.map((permission) => {
            const microphone = permission.id === 'microphone';
            const granted = !permission.manual && (!microphone || state.granted);
            const requesting = microphone && state.requesting;
            return <div data-permission={permission.id} key={permission.id} style={{height: PERMISSION_CARD_HEIGHT, flexShrink: 0, padding: 16, borderRadius: 12, background: color.fillControl}}>
              <div style={{fontSize: 18, fontWeight: 600}}>{permission.name}</div>
              <div style={{fontSize: 14, lineHeight: '20px', color: color.secondary, marginTop: 10}}>{permission.body}</div>
              <div className="flex items-center justify-between" style={{marginTop: 12, fontSize: 14, height: 34}}>
                {granted ? <span className="flex items-center gap-[6px]" style={{color: color.green}}><Check size={15} />Allowed</span> : <span style={{color: requesting ? color.blue : color.secondary}}>{requesting ? 'Requesting…' : permission.manual ? 'Enable in System Settings' : 'Not allowed'}</span>}
                {!granted ? <div data-permission-action={permission.id}><TourAction label={permission.manual ? 'Open System Settings' : 'Allow'} busy={requesting} active={microphone && !requesting} /></div> : null}
              </div>
            </div>;
          })}
        </div>
        <div data-permission-scrollbar style={{position: 'absolute', right: 1, top: 4, width: 3, height: 57, borderRadius: 3, background: white(0.42), transform: `translateY(${state.scroll / 2250 * 297}px)`}} />
      </div>
      {state.granted ? <div style={{height: 28, paddingTop: 5}}><TourResult>Microphone permission granted</TourResult></div> : null}
      {frame >= 32 && !state.granted ? <TourPointer frame={frame} at={44} x={936} y={218} /> : null}
    </div>
  );
};

export const LockScreenTourModule = ({frame, globalFrame}: {frame: number; globalFrame: number}) => {
  const playing = frame < 38;
  const elapsed = track.elapsed + globalFrame / 60;
  return (
    <>
      <Wallpaper dim={0.16} />
      <div className="absolute inset-x-0 flex flex-col items-center" style={{top: 108}}><div style={{fontSize: 25, fontWeight: 500}}>Wednesday, November 11</div><div className="font-rounded tabular" style={{fontSize: 113, lineHeight: '135px', fontWeight: 600}}>9:41</div><div style={{fontSize: 18, color: white(0.76)}}>Make room for the next idea.</div></div>
      <div className="absolute inset-x-0 flex items-center justify-center gap-[31px]" style={{top: 336, fontSize: 18}}><BatteryFull size={22} /><span>76% · On battery</span><Sun size={22} /><span>17° · Cloudy</span></div>
      <div className="absolute flex flex-col gap-[15px]" style={{left: 369, top: 395, width: 542, padding: '20px 24px', borderRadius: 18, background: white(0.07), border: `1px solid ${white(0.16)}`}}>
        <div className="flex items-center gap-[15px]"><AlbumArt size={66} radius={10} /><div className="min-w-0 flex-1"><div style={{fontSize: 21, fontWeight: 600}}>{track.title}</div><div style={{fontSize: 16, color: color.secondary, marginTop: 6}}>{track.artist}</div></div></div>
        <ProgressTrack value={elapsed / track.duration} tint={white(0.86)} width="100%" height={3} />
        <div className="flex items-center justify-center gap-[31px]" style={{height: 33}}><span style={{fontSize: 25}}>◀</span>{playing ? <Pause size={27} fill="white" /> : <Play size={27} fill="white" />}<span style={{fontSize: 25}}>▶</span></div>
        <div style={{textAlign: 'center', fontSize: 15, color: color.secondary}}>{playing ? `${formatTime(elapsed)} · Now playing` : 'Playback paused'}</div>
      </div>
      <div className="absolute inset-x-0 flex justify-center" style={{bottom: 31, fontSize: 17, color: color.secondary}}>Lock screen information · Separate overlay</div>
      <TourPointer frame={frame} at={38} x={640} y={561} />
    </>
  );
};

export const managementTourAt = (frame: number) => ({confirmation: frame >= 12 && frame < 31, installing: frame >= 31 && frame < 42, installed: frame >= 42, skills: frame >= 84, synchronized: frame >= 108});

export const ManagementTourModule = ({frame}: {frame: number}) => {
  const state = managementTourAt(frame);
  return (
    <div className="absolute inset-0" style={{padding: '17px 40px'}}>
      <TourHeading title="AI" />
      {state.skills ? <div data-management-section="skills" className="flex flex-col gap-[10px]">
        <TourHeading title="Skills"><TourAction label="Sync now" active={frame < 108} /></TourHeading>
        <TourCard style={{padding: '10px 15px'}}><div className="flex items-center gap-[10px]"><Folder size={19} color={color.secondary} /><span style={{fontSize: 16}}>Managed library</span><span style={{fontSize: 13, color: color.secondary}}>~/.zisla/skills</span></div></TourCard>
        <div className="flex items-center gap-[16px]" style={{fontSize: 16}}>Sync mode<div className="flex gap-[6px]"><TourAction label="Symbolic links" active /><TourAction label="File copies" /></div></div>
        <div className="flex flex-col" style={{padding: '10px 16px', borderRadius: 10, background: color.fillControl}}><div style={{fontSize: 16, fontWeight: 600, marginBottom: 12}}>Sync targets</div>{['Codex', 'Claude', 'Agents'].map((target) => <div key={target} style={{height: 35}}><TourToggle label={target} on /></div>)}</div>
        {state.synchronized ? <TourResult>Skills synced to enabled CLIs</TourResult> : <div style={{fontSize: 14, color: color.secondary}}>Code review · Research · Documentation</div>}
        {frame < 108 ? <TourPointer frame={frame} at={108} x={947} y={87} /> : null}
      </div> : <div data-management-section="cli">
        <TourHeading title="CLI"><TourAction label="Detect" /><TourAction label="Install missing" /><TourAction label="Update installed" /><TourAction label="Uninstall" /></TourHeading>
        <div className="flex flex-col" style={{gap: 8}}>{[['Claude Code', 'Installed'], ['Codex', 'Installed'], ['Gemini', state.installed ? 'Installed' : state.installing ? 'Installing…' : 'Not installed']].map(([name,status]) => <TourCard key={name} style={{padding: '11px 15px'}}><div className="flex items-center gap-[12px]" style={{fontSize: 17}}><Terminal size={19} color={color.secondary} /><span style={{width: 140}}>{name}</span><span style={{fontSize: 14, color: status === 'Installed' ? color.green : color.secondary}}>{status}</span><div className="flex-1" /><TourAction label={name === 'Gemini' && !state.installed ? 'Install' : 'Update'} busy={name === 'Gemini' && state.installing} active={name === 'Gemini' && !state.installing && !state.installed} />{status === 'Installed' ? <TourAction label="Uninstall" /> : null}</div></TourCard>)}</div>
        {state.installed ? <div style={{marginTop: 14}}><TourResult>Gemini CLI installed</TourResult></div> : null}
        {frame < 12 ? <TourPointer frame={frame} at={12} x={949} y={283} /> : null}
      </div>}
      {state.confirmation ? <div role="alertdialog" aria-label="CLI installation confirmation" style={{position: 'absolute', left: 312, top: 112, width: 416, padding: 22, borderRadius: 12, background: '#34343a', boxShadow: '0 18px 55px #0008'}}><div style={{fontSize: 21, fontWeight: 600}}>Install Gemini?</div><div style={{fontSize: 16, color: color.secondary, marginTop: 12}}>Download and install Gemini CLI.</div><div className="flex justify-end gap-[8px]" style={{marginTop: 20}}><TourAction label="Cancel" /><TourAction label="Continue" active /></div><TourPointer frame={frame} at={31} x={354} y={126} /></div> : null}
    </div>
  );
};

export const recommendedDemo = [{name: 'OpenScreen', purpose: 'Screen recording and video editing'}, {name: 'DockDoor', purpose: 'Dock previews and app switching'}, {name: 'Quiet.md', purpose: 'Local notes'}] as const;
export const recommendedTourAt = (frame: number) => ({opened: frame >= 24, features: frame >= 68, preview: frame >= 78 && frame < 106, restored: frame >= 106});

export const RecommendedTourModule = ({frame}: {frame: number}) => {
  const state = recommendedTourAt(frame);
  const tilt = state.preview ? ease(frame, [79, 100], [0, 48]) : 0;
  return <div className="absolute inset-0">
    {state.opened && !state.features ? <div style={{padding: '37px 132px'}} data-recommended-app="Quiet.md"><DemoWindow app="Quiet.md" title="Launch checklist" /><div style={{marginTop: 18}}><TourResult>Quiet.md opened as a separate app</TourResult></div></div> : <div style={{padding: '17px 40px'}}>
      <TourHeading title={state.features ? 'Features' : 'Recommended tools'} />
      {state.features ? <div data-recommended-section="features" className="flex flex-col gap-[16px]">
        <div style={{fontSize: 19, fontWeight: 600}}>Tools and monitoring</div>
        <TourToggle label="Lid-close animation" on /><div style={{fontSize: 15, color: color.secondary}}>Depth transition on a compatible MacBook</div>
        <div className="flex items-center justify-between" style={{height: 42, fontSize: 16}}>Preview animation<TourAction label="Preview" active={state.preview} /></div>
        <div className="relative" style={{height: 140, overflow: 'hidden', borderRadius: 10, background: '#10141b', perspective: 500}}><div data-lid-preview style={{position: 'absolute', left: 230, top: 10, width: 460, height: 116, borderRadius: 7, background: 'linear-gradient(135deg,#38547a,#263045)', transform: `rotateX(${tilt}deg)`, transformOrigin: '50% 100%', opacity: state.preview ? 1 - ease(frame, [84, 102], [0, 0.7]) : 1}}><div style={{padding: 20, fontSize: 22}}>zisla</div></div></div>
        {state.restored ? <TourResult>Preview ended · Desktop restored</TourResult> : null}
        {frame < 106 ? <TourPointer frame={frame} at={78} x={945} y={196} /> : null}
      </div> : <div data-recommended-section="tools">
        <TourHeading title="Desktop applications"><TourAction label="Detect" /><TourAction label="Install missing" /><TourAction label="Update installed" /></TourHeading>
        {recommendedDemo.map((app) => <div key={app.name} style={{display: 'flex', alignItems: 'center', gap: 16, padding: '17px 16px', background: color.fillControl, borderBottom: `1px solid ${color.divider}`}}><div className="flex-1"><div style={{fontSize: 19, fontWeight: 600}}>{app.name}</div><div style={{fontSize: 14, color: color.secondary, marginTop: 7}}>{app.purpose}</div></div><Check size={17} color={color.green} /><span style={{fontSize: 14}}>Installed</span><TourAction label="Update" /></div>)}
        <div style={{marginTop: 20, fontSize: 15, color: color.secondary}}>Third-party apps · Installed separately</div>
        <div className="flex items-center gap-[12px]" data-recommended-dock style={{position: 'absolute', left: 420, bottom: 20, padding: '10px 18px', borderRadius: 12, background: white(0.16)}}><BrowserGlyph size={31} /><div data-open-quiet-md style={{width: 36, height: 36, borderRadius: 8, background: '#ece8d7', color: '#403c31', fontSize: 22, textAlign: 'center'}}>Q</div><Music size={31} /></div>
        <TourPointer frame={frame} at={24} x={514} y={398} />
      </div>}
    </div>}
  </div>;
};
