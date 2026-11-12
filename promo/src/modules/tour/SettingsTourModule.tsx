import {BatteryFull, Check, Copy, Music, Pause, Play, Sun, Terminal} from 'lucide-react';
import {AlbumArt, BrowserGlyph, formatTime} from '../../components/IslandChrome';
import {Wallpaper} from '../../components/Desktop';
import {ProgressTrack} from '../../components/Glass';
import {track} from '../../content';
import {ease} from '../../motion';
import {color, white} from '../../theme';
import {NotesModule} from '../NotesModule';
import {TourAction, TourCard, TourHeading, TourPointer, TourResult, TourSelect, TourToggle} from './TourSurface';

export const quickActionExamples = [
  {kind: 'Currency amount', input: 'US$20 → EUR', detail: 'Example rate: 1 USD = 0.9200 EUR', action: 'Copy result', result: '€18.40 copied', options: ['Copy result', 'Copy full expression']},
  {kind: 'IP address', input: '192.0.2.10', detail: 'IP lookup and open-link actions', action: 'Open link', result: 'Opened http://192.0.2.10', options: ['IP lookup', 'Open link']},
  {kind: 'Emoji name', input: ':smile:', detail: 'Emoji 18.0 catalogue', action: 'Copy emoji', result: '😄 copied', options: ['Copy emoji', 'Search']},
  {kind: 'Link', input: 'https://example.com/review', detail: 'Website link recognised on this Mac', action: 'Open link', result: 'Opened in Safari', options: ['Open link', 'Download', 'Share']},
] as const;

export const quickActionKinds = ['Link', 'IP address', 'File path', 'Email', 'Phone', 'Colour', 'Math', 'Conversion', 'Date & time', 'Address', 'Flight', 'Train', 'Tracking', 'Meeting', 'Emoji name', 'Code', 'Shell command', 'Translation', 'App', 'App repair', 'Text', 'Image', 'File'] as const;

export const permissionDemo = [
  {id: 'accessibility', name: 'Accessibility', manual: false}, {id: 'input_monitoring', name: 'Input Monitoring', manual: false},
  {id: 'screen_recording', name: 'Screen Recording', manual: false}, {id: 'system_audio', name: 'System Audio Recording', manual: true},
  {id: 'microphone', name: 'Microphone', manual: false}, {id: 'camera', name: 'Camera', manual: false},
  {id: 'speech_recognition', name: 'Speech Recognition', manual: false}, {id: 'calendar', name: 'Calendar', manual: false},
  {id: 'reminders', name: 'Reminders', manual: false}, {id: 'location', name: 'Location', manual: false},
  {id: 'notifications', name: 'Notifications', manual: false}, {id: 'bluetooth', name: 'Bluetooth', manual: false},
  {id: 'automation', name: 'Automation', manual: true}, {id: 'files', name: 'Files and Folders', manual: true},
  {id: 'full_disk_access', name: 'Full Disk Access', manual: true},
] as const;

const PreviewCard = ({name, selected, notesPreview = false}: {name: string; selected: boolean; notesPreview?: boolean}) => (
  <div style={{width: 244, padding: 7, borderRadius: 9, background: white(0.06), border: `1px solid ${selected ? color.blue : color.strokeCard}`}}>
    <div className="relative overflow-hidden" style={{height: 124, borderRadius: 5, background: '#22262e'}}>
      {notesPreview ? <div className="absolute left-0 top-0" style={{width: 752, height: 390, transform: 'scale(0.305)', transformOrigin: '0 0'}}><NotesModule checked={3} /></div> : <div style={{padding: '23px 19px'}}><div style={{fontSize: 18, fontWeight: 600}}>Launch review</div><div style={{fontSize: 12, color: color.secondary, marginTop: 10}}>example.com/review</div><div style={{marginTop: 12, width: 143, height: 5, background: white(0.15)}} /></div>}
    </div>
    <div style={{fontSize: 14, padding: '8px 4px 3px'}}>{name}</div>
  </div>
);

export const WindowsTourModule = ({frame}: {frame: number}) => {
  const switched = frame >= 65;
  const commandTab = frame >= 112;
  return (
    <div className="absolute inset-0 flex flex-col" style={{padding: 24}}>
      <TourHeading title="Window previews"><TourSelect value={commandTab ? 'Command-Tab' : 'Dock hover'} /></TourHeading>
      <div className="flex min-h-0 flex-1 gap-[24px]">
        <div className="flex min-w-0 flex-1 flex-col gap-[12px]">
          <div className="flex gap-[14px]"><PreviewCard name="Safari · Launch review" selected={!switched} /><PreviewCard name="Notes · Launch checklist" selected={switched} notesPreview /></div>
          <div className="flex items-center justify-center gap-[24px]" style={{height: 56, borderRadius: 12, background: white(0.08)}}><BrowserGlyph size={34} /><div className="flex items-center justify-center" style={{width: 34, height: 34, borderRadius: 8, background: '#f1c84a'}}><span style={{color: '#3f3423', fontSize: 21}}>☰</span></div><div className="flex items-center justify-center" style={{width: 34, height: 34, borderRadius: 8, background: '#dc4261'}}><Music size={23} /></div></div>
          <TourResult>{switched ? 'Notes window activated' : 'Hover an app to preview its windows'}</TourResult>
        </div>
        <div className="relative shrink-0 overflow-hidden" style={{width: 405, borderRadius: 10, background: '#20242c', border: `1px solid ${color.strokeCard}`}}>
          <div style={{height: 28, padding: '5px 12px', background: '#171a21', fontSize: 13}}>{switched ? 'Notes · Launch checklist' : 'Safari · Launch review'}</div>
          {switched ? <div className="absolute left-0" style={{top: 28, width: 752, height: 390, transform: 'scale(0.535)', transformOrigin: '0 0'}}><NotesModule checked={3} /></div> : <div style={{padding: 27}}><div style={{fontSize: 26, fontWeight: 600}}>Launch review</div><div style={{fontSize: 16, color: color.secondary, marginTop: 15}}>Click a preview to bring that window forward.</div></div>}
        </div>
      </div>
      <TourPointer frame={frame} at={60} x={392} y={176} />
    </div>
  );
};

export const quickActionsTourAt = (frame: number) => {
  const index = Math.min(3, Math.max(0, Math.floor(frame / 60)));
  return {example: quickActionExamples[index], frame: frame - index * 60};
};

export const QuickActionsTourModule = ({frame}: {frame: number}) => {
  const state = quickActionsTourAt(frame);
  const done = state.frame >= 35;
  return (
    <div className="absolute inset-0 flex gap-[23px]" style={{padding: 24}}>
      <div className="flex min-w-0 flex-[1.15] flex-col gap-[14px]">
        <TourHeading title="Quick Actions"><TourSelect value="⌘ N" /></TourHeading>
        <div className="flex items-center gap-[9px]" style={{fontSize: 14, color: color.secondary}}><Copy size={16} />Copied from the active app</div>
        <TourCard style={{height: 126}}><div style={{fontSize: 15, color: color.secondary}}>{state.example.kind}</div><div style={{fontSize: 25, fontWeight: 600, marginTop: 11}}>{state.example.input}</div><div style={{fontSize: 14, color: color.secondary, marginTop: 10}}>{state.example.detail}</div></TourCard>
        <div className="flex gap-[9px]">{state.example.options.map((option) => <TourAction key={option} label={option} active={option === state.example.action && state.frame >= 20} />)}</div>
        {done ? <TourResult>{state.example.result}</TourResult> : <div style={{fontSize: 16, color: color.secondary}}>Choose a next step.</div>}
        <div style={{fontSize: 14, color: color.secondary}}>Download / AirDrop → Open folder · Text / Image → Save</div>
      </div>
      <div className="flex min-w-0 flex-1 flex-col gap-[11px]">
        <TourHeading title="Recognised content" />
        <div className="grid grid-cols-3 gap-x-[14px] gap-y-[8px]">{quickActionKinds.map((kind) => <div key={kind} style={{fontSize: 13.5, lineHeight: '19px', color: kind === state.example.kind || kind === 'Conversion' && state.example.kind === 'Currency amount' ? color.label : color.secondary}}>{kind}</div>)}</div>
        <div className="grid grid-cols-2 gap-[9px]" style={{marginTop: 9}}>{quickActionExamples.map((example) => <div key={example.kind} style={{padding: '8px 10px', borderRadius: 6, background: white(0.06), fontSize: 13.5}}>{example.input}</div>)}</div>
      </div>
      <TourPointer frame={state.frame} at={25} x={116} y={270} />
    </div>
  );
};

export const PermissionsTourModule = ({frame}: {frame: number}) => (
  <div className="absolute inset-0 flex flex-col gap-[13px]" style={{padding: 24}}>
    <TourHeading title="Settings → Permissions"><TourToggle label="Feature enabled" on /></TourHeading>
    <div className="grid grid-cols-2 gap-x-[20px] gap-y-[7px]">{permissionDemo.map((permission) => {
      const microphone = permission.id === 'microphone';
      const granted = !permission.manual && (!microphone || frame >= 91);
      const requesting = microphone && frame >= 51 && frame < 91;
      return <div key={permission.id} className="flex items-center gap-[10px]" style={{padding: '7px 10px', borderRadius: 7, background: color.fillControl, minHeight: 32}}>
        <div className="min-w-0 flex-1" style={{fontSize: 14.5}}>{permission.name}</div>
        {granted ? <span className="flex items-center gap-[4px]" style={{fontSize: 13.5, color: color.green}}><Check size={13} />Granted</span> : <span style={{fontSize: 13.5, color: requesting ? color.blue : color.secondary}}>{requesting ? 'Requesting…' : permission.manual ? 'Open Settings' : 'Grant'}</span>}
      </div>;
    })}</div>
    <div className="flex-1" />
    <div className="flex items-center gap-[19px]">{frame >= 91 ? <TourResult>Microphone permission granted</TourResult> : <TourResult pending>Review status and request access when needed</TourResult>}<div className="flex-1" /><span style={{fontSize: 14, color: color.secondary}}>Manual permissions open System Settings</span></div>
    <TourPointer frame={frame} at={51} x={460} y={165} />
  </div>
);

export const LockScreenTourModule = ({frame, globalFrame}: {frame: number; globalFrame: number}) => {
  const playing = frame < 90;
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
      <TourPointer frame={frame} at={90} x={640} y={561} />
    </>
  );
};

export const ManagementTourModule = ({frame}: {frame: number}) => {
  const installed = frame >= 90;
  const synchronized = frame >= 126;
  return (
    <div className="absolute inset-0 flex gap-[24px]" style={{padding: 24}}>
      <div className="flex min-w-0 flex-1 flex-col gap-[9px]">
        <TourHeading title="AI CLI management"><TourAction label="Detect" active={frame < 32} /></TourHeading>
        {[['Claude Code', 'Installed'], ['Codex', 'Installed'], ['Gemini', installed ? 'Installed' : frame >= 43 ? 'Installing…' : 'Not installed'], ['Pi', 'Installed']].map(([name, status]) => <TourCard key={name} style={{padding: '10px 15px'}}><div className="flex items-center gap-[10px]"><Terminal size={18} color={color.secondary} /><span className="flex-1" style={{fontSize: 18}}>{name}</span><span style={{fontSize: 14, color: status === 'Installed' ? color.green : color.secondary}}>{status}</span><TourAction label={status === 'Installed' ? 'Update' : 'Install'} active={name === 'Gemini' && !installed} /></div></TourCard>)}
        <div className="flex items-center gap-[10px]"><TourAction label="Install" /><TourAction label="Update" /><TourAction label="Remove" /></div>
        {installed ? <TourResult>Gemini CLI installed</TourResult> : <div style={{fontSize: 15, color: color.secondary}}>Detect installed tools, then choose an action.</div>}
      </div>
      <div className="flex min-w-0 flex-1 flex-col gap-[17px]">
        <TourHeading title="Skills"><TourAction label="Sync now" active={frame >= 100} /></TourHeading>
        <TourCard><div style={{fontSize: 17, fontWeight: 500}}>Managed library</div><div style={{fontSize: 14, color: color.secondary, marginTop: 8}}>Shared with enabled CLIs</div></TourCard>
        <TourSelect value="Sync mode: Links" />
        <TourCard><TourToggle label="Code review" on /><div style={{marginTop: 13}}><TourToggle label="Research" on /></div><div style={{marginTop: 13}}><TourToggle label="Documentation" on={frame >= 112} /></div></TourCard>
        <div style={{fontSize: 15, color: color.secondary}}>Enable · Disable · Open folder · Uninstall</div>
        {synchronized ? <TourResult>Skills synced to enabled CLIs</TourResult> : <div style={{fontSize: 15, color: color.secondary}}>Claude Code · Codex · Gemini · Pi</div>}
      </div>
      <TourPointer frame={frame} at={43} x={450} y={251} />
      <TourPointer frame={frame} at={106} x={935} y={41} />
    </div>
  );
};

export const recommendedDemo = [{name: 'OpenScreen', purpose: 'Screen recording and video editing'}, {name: 'DockDoor', purpose: 'Dock previews and app switching'}, {name: 'Quiet.md', purpose: 'Local notes'}] as const;

export const RecommendedTourModule = ({frame}: {frame: number}) => {
  const opened = frame >= 42;
  const preview = frame >= 125 && frame < 191;
  const restored = frame >= 191;
  const tilt = preview ? ease(frame, [126, 170], [0, 48]) : 0;
  return (
    <div className="absolute inset-0 flex gap-[25px]" style={{padding: 24}}>
      <div className="flex min-w-0 flex-[1.15] flex-col gap-[10px]">
        <TourHeading title="Recommended apps"><TourAction label="Refresh" /></TourHeading>
        {recommendedDemo.map((app) => <TourCard key={app.name} style={{padding: '17px 15px'}}><div className="flex items-center gap-[10px]"><div className="flex-1"><div style={{fontSize: 20, fontWeight: 500}}>{app.name}</div><div style={{fontSize: 14, color: color.secondary, marginTop: 6}}>{app.purpose}</div></div><TourAction label="Open" active={app.name === 'Quiet.md' && !opened} /></div></TourCard>)}
        {opened ? <TourResult>Quiet.md opened as a separate app</TourResult> : <div style={{fontSize: 16, color: color.secondary}}>Third-party apps · Installed separately</div>}
        <div style={{fontSize: 14, color: color.secondary}}>Detect · Install missing · Update installed</div>
      </div>
      <div className="flex min-w-0 flex-1 flex-col gap-[17px]">
        <TourHeading title="Lid-close animation" />
        <TourToggle label="Lid-close animation" on />
        <div className="relative min-h-0 flex-1 overflow-hidden" style={{borderRadius: 10, background: '#0a0d13', perspective: 500}}>
          <div className="absolute" style={{left: 21, right: 21, top: 31, height: 167, borderRadius: 7, background: 'linear-gradient(135deg, #38547a, #263045)', transform: `rotateX(${tilt}deg)`, transformOrigin: '50% 100%', filter: `blur(${preview ? ease(frame, [130, 170], [0, 5]) : 0}px)`, opacity: preview ? 1 - ease(frame, [132, 179], [0, 0.7]) : 1}}>
            <div style={{padding: '23px 20px', fontSize: 21, fontWeight: 600}}>zisla</div><div style={{margin: '0 20px', fontSize: 16, color: color.secondary}}>The desktop recedes with the lid.</div>
          </div>
        </div>
        <TourAction label="Preview animation" active={preview} />
        {restored ? <TourResult>Preview ended · Desktop restored</TourResult> : <div style={{fontSize: 14, color: color.secondary}}>Compatible MacBook · Depth transition</div>}
      </div>
      <TourPointer frame={frame} at={37} x={491} y={314} />
      <TourPointer frame={frame} at={125} x={821} y={356} />
    </div>
  );
};
