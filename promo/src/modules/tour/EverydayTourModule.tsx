import {Check, FileImage, Mic, StickyNote} from 'lucide-react';
import {AgendaModule} from '../AgendaModule';
import {ClipboardModule} from '../ClipboardModule';
import {NotesModule} from '../NotesModule';
import {AlbumArt} from '../../components/IslandChrome';
import {waveLevels} from '../../components/Glass';
import {clamp01, color} from '../../theme';
import {ease, linear} from '../../motion';
import {TourAction, TourCard, TourField, TourHeading, TourPointer, TourResult, TourSelect, TourToggle} from './TourSurface';

export const briefingTemplates = [
  {id: 'minimal', title: 'Minimal', background: '#ffffff', accent: '#e35729'},
  {id: 'paper', title: 'Paper', background: '#f7f2e6', accent: '#85422e'},
  {id: 'forest', title: 'Forest', background: '#ebf2e6', accent: '#33664a'},
  {id: 'sunrise', title: 'Sunrise', background: '#fff2e0', accent: '#cc4d24'},
  {id: 'coastal', title: 'Coastal', background: '#ebf7fc', accent: '#3073a1'},
  {id: 'blossom', title: 'Blossom', background: '#ffeff5', accent: '#ad5775'},
  {id: 'midnight', title: 'Midnight', background: '#131729', accent: '#abb3ff'},
  {id: 'terminal', title: 'Terminal', background: '#0e1f24', accent: '#69e6ba'},
] as const;

export const voiceVocabularies = ['Computer terms', 'Classical poetry', 'Internet slang', 'People & places', 'Brands & products', 'Medicine & health', 'Law & government', 'Finance & business', 'Education & research', 'Film & music', 'Games & anime', 'Travel & transport', 'Daily life'] as const;

export const everydayDemo = {
  context: {location: 'Safari · Launch review · example.com/review', text: 'Check the spacing before the review.', reminder: 'Every 3 hours'},
  briefing: {file: 'Daily briefing — Nov 11.png', time: '22:00', active: '6 h 45 m', characters: '12,846'},
  voice: {raw: 'first update the notes second send the review', cleaned: '1. Update the notes.\n2. Send the review.', hotword: 'zisla'},
} as const;

export const NotesTourModule = ({frame}: {frame: number}) => (
  <div className="absolute inset-0 flex" style={{padding: 22}}>
    <div className="relative min-w-0 flex-1" style={{height: 400}}><NotesModule checked={1.4 + 2.6 * clamp01((frame - 54) / 70)} /></div>
    <div className="flex shrink-0 flex-col gap-[18px]" style={{width: 250, padding: '8px 10px 8px 22px'}}>
      <TourHeading title="Quick Notes" />
      <div style={{fontSize: 16, color: color.secondary}}>Apple Notes</div>
      <TourSelect value="Launch checklist" />
      <div style={{fontSize: 15}}>⌘1–9 · Jump to a note</div>
      <div style={{fontSize: 15}}>Markdown · Live preview</div>
      <div className="flex-1" />
      {frame < 150 ? <TourResult pending>Saving to Notes…</TourResult> : <TourResult>Saved to Apple Notes</TourResult>}
      <div className="flex gap-[8px]"><TourAction label="New" /><TourAction label="Delete" /></div>
    </div>
    <TourPointer frame={frame} at={86} x={506} y={180} />
  </div>
);

export const ClipboardTourModule = ({frame}: {frame: number}) => {
  const filter = ease(frame, [36, 76], [0, 4]);
  return (
    <div className="absolute inset-0 flex gap-[22px]" style={{padding: 22}}>
      <div className="relative min-w-0 flex-1" style={{height: 400}}><ClipboardModule filter={filter} query={frame >= 108 ? 'brew' : ''} /></div>
      <div className="flex shrink-0 flex-col gap-[12px]" style={{width: 268, paddingTop: 8}}>
        <TourHeading title="Clipboard" />
        <div style={{fontSize: 15, color: color.secondary}}>History · Type filters · Search</div>
        <TourCard><div className="font-mono" style={{fontSize: 15, lineHeight: '24px'}}>brew install --cask<br />wzz6423/tap/zisla</div></TourCard>
        <div className="flex gap-[8px]"><TourAction label="Copy" active={frame >= 145} /><TourAction label="Favorite" /></div>
        <div className="flex gap-[8px]"><TourAction label="Quick Notes" /><TourAction label="Delete" /></div>
        {frame >= 165 ? <TourResult>Copied to clipboard</TourResult> : <div style={{fontSize: 15, color: color.secondary}}>Copied Nov 11 · 09:41</div>}
        <div className="flex-1" />
        <TourSelect value="Auto-delete: Off / 7 / 15 / 30 days" />
      </div>
      <TourPointer frame={frame} at={145} x={760} y={226} />
    </div>
  );
};

export const AgendaTourModule = ({frame}: {frame: number}) => (
  <div className="absolute inset-0 flex flex-col" style={{padding: 22}}>
    <TourHeading title="Weather, calendar and reminders"><TourAction label="Refresh weather" /></TourHeading>
    <div className="relative" style={{height: 217, marginTop: 6, marginBottom: 7}}>
      <div className="absolute inset-0" style={{width: 752, height: 164, transform: 'scale(1.31)', transformOrigin: '0 0'}}><AgendaModule done={ease(frame, [68, 92], [0, 1])} /></div>
    </div>
    <div className="flex items-center gap-[12px]" style={{marginBottom: 7}}>
      <TourAction label="Add event" active={frame >= 28 && frame < 60} />
      <TourAction label="Add reminder" />
      <TourAction label="Delete" />
      <div className="flex-1" />
      {frame >= 112 ? <TourResult>Reminder completed</TourResult> : <TourResult pending>Ship the launch film</TourResult>}
    </div>
    <TourCard style={{padding: '12px 15px'}}>
      <div className="flex items-center gap-[16px]" style={{fontSize: 15}}>
        <span style={{fontWeight: 600}}>Care reminders</span><span>Break · Water · Move · Rest eyes</span><div className="flex-1" /><TourSelect value="Every 45 min" />
      </div>
      {frame >= 160 ? <div style={{marginTop: 8, color: color.green, fontSize: 15}}>A natural break resets the reminder timer.</div> : <div style={{marginTop: 8, color: color.secondary, fontSize: 15}}>Time for water and a short break.</div>}
    </TourCard>
    <TourPointer frame={frame} at={78} x={993} y={201} />
  </div>
);

export const ContextNotesTourModule = ({frame}: {frame: number}) => {
  const saved = frame >= 133;
  const text = everydayDemo.context.text.slice(0, Math.floor(ease(frame, [16, 100], [0, everydayDemo.context.text.length])));
  return (
    <div className="absolute inset-0 flex gap-[24px]" style={{padding: 24}}>
      <div className="flex min-w-0 flex-1 flex-col gap-[15px]">
        <TourHeading title="Location notes"><StickyNote size={23} color={color.secondary} /></TourHeading>
        <div style={{fontSize: 15, color: color.secondary}}>{everydayDemo.context.location}</div>
        <TourCard style={{height: 119, padding: 17}}><div style={{fontSize: 21, lineHeight: '30px'}}>{text}{!saved ? <span style={{color: color.blue}}>│</span> : null}</div></TourCard>
        <div className="flex items-center gap-[14px]"><span style={{fontSize: 15}}>Recurring reminder</span><TourSelect value={everydayDemo.context.reminder} /></div>
        <div className="flex gap-[8px]"><TourAction label="Copy" /><TourAction label="Go to location" /><TourAction label="Save" active={!saved} /></div>
        {saved ? <TourResult>Saved · Shown when you return</TourResult> : <TourResult pending>Attach this app-window screenshot</TourResult>}
      </div>
      <div className="flex shrink-0 flex-col" style={{width: 326, paddingTop: 56}}>
        <div className="flex items-center gap-[8px]" style={{fontSize: 16, marginBottom: 12}}><FileImage size={17} />Window screenshot</div>
        <div style={{height: 236, borderRadius: 9, overflow: 'hidden', background: '#242832', border: `1px solid ${color.strokeCard}`}}>
          <div style={{height: 27, padding: '5px 12px', fontSize: 12, color: color.secondary, background: '#181b22'}}>Safari · Launch review</div>
          <div className="flex items-center gap-[14px]" style={{padding: 24}}><AlbumArt size={90} radius={8} /><div style={{fontSize: 20, fontWeight: 600}}>Launch<br />review</div></div>
          <div style={{margin: '0 24px', fontSize: 16, color: color.secondary}}>Check the next idea.</div>
        </div>
        <div className="flex gap-[8px]" style={{marginTop: 14}}><TourAction label="View screenshot" /><TourAction label="Copy" /></div>
      </div>
      <TourPointer frame={frame} at={128} x={390} y={321} />
    </div>
  );
};

export const BriefingTourModule = ({frame}: {frame: number}) => {
  const selected = frame < 50 ? 0 : 4;
  const exporting = frame >= 178 && frame < 220;
  const template = briefingTemplates[selected];
  return (
    <div className="absolute inset-0 flex gap-[24px]" style={{padding: 24}}>
      <div className="flex min-w-0 flex-1 flex-col gap-[8px]">
        <TourHeading title="Daily briefing"><TourSelect value={`Daily at ${everydayDemo.briefing.time}`} /></TourHeading>
        <div className="grid grid-cols-4 gap-[10px]">
          {briefingTemplates.map((item, index) => <div key={item.id} style={{padding: 5, borderRadius: 8, border: `1px solid ${selected === index ? color.blue : color.strokeCard}`}}>
            <div className="flex flex-col gap-[4px]" style={{height: 34, padding: '5px 9px', borderRadius: 4, background: item.background}}><div style={{height: 4, width: '65%', background: item.accent}} /><div style={{height: 3, width: '86%', background: item.accent, opacity: 0.35}} /><div style={{height: 3, width: '73%', background: item.accent, opacity: 0.35}} /></div>
            <div className="flex items-center justify-between" style={{fontSize: 14, lineHeight: '18px', marginTop: 3}}>{item.title}{selected === index ? <Check size={13} color={color.blue} /> : null}</div>
          </div>)}
        </div>
        <div className="flex items-center gap-[10px]" style={{fontSize: 15}}><Check size={14} color={color.blue} />Usage<Check size={14} color={color.blue} />Typing<Check size={14} color={color.blue} />System<Check size={14} color={color.blue} />zisla activity</div>
        <div className="flex gap-[10px]"><TourAction label="Preview" /><TourAction label="Export today’s PNG" active={frame >= 170} busy={exporting} /></div>
        {frame >= 220 ? <TourResult>Saved: {everydayDemo.briefing.file}</TourResult> : <div style={{fontSize: 15, color: color.secondary}}>{exporting ? 'Exporting PNG…' : '8 templates · Choose the content you want'}</div>}
      </div>
      <div className="shrink-0" style={{width: 253, background: template.background, color: '#25343a', borderRadius: 7, padding: '26px 22px'}}>
        <div style={{fontSize: 13, lineHeight: '17px', letterSpacing: '0.09em', color: template.accent}}>DAILY BRIEFING</div>
        <div style={{fontSize: 27, lineHeight: '32px', fontWeight: 700, marginTop: 10}}>Nov 11</div>
        <div style={{fontSize: 32, lineHeight: '36px', fontWeight: 600, marginTop: 14}}>{everydayDemo.briefing.active}</div>
        <div style={{fontSize: 14, lineHeight: '18px', opacity: 0.6}}>Active on this Mac</div>
        <div className="flex items-end gap-[5px]" style={{height: 50, marginTop: 12}}>{[14, 28, 37, 15, 33, 46, 41, 21].map((height, index) => <div key={index} style={{flex: 1, height, borderRadius: 2, background: template.accent, opacity: 0.35 + index * 0.06}} />)}</div>
        <div style={{fontSize: 15, lineHeight: '20px', marginTop: 16}}>{everydayDemo.briefing.characters} characters</div>
        <div style={{fontSize: 15, lineHeight: '20px', marginTop: 7}}>3 focus sessions completed</div>
        <div style={{fontSize: 15, lineHeight: '20px', marginTop: 7}}>32–100% battery</div>
      </div>
      <TourPointer frame={frame} at={50} x={110} y={192} />
      <TourPointer frame={frame} at={178} x={295} y={322} />
    </div>
  );
};

export const VoiceTourModule = ({frame, globalFrame}: {frame: number; globalFrame: number}) => {
  const recording = frame >= 35 && frame < 124;
  const cleaning = frame >= 124 && frame < 183;
  const done = frame >= 183;
  const transcript = everydayDemo.voice.raw.slice(0, Math.floor(linear(frame, [44, 121], [0, everydayDemo.voice.raw.length])));
  return (
    <div className="absolute inset-0 flex gap-[24px]" style={{padding: 24}}>
      <div className="flex min-w-0 flex-[1.2] flex-col gap-[9px]">
        <TourHeading title="Voice input"><Mic size={22} color={recording ? color.red : color.secondary} /></TourHeading>
        <div className="flex gap-[8px]"><TourAction label="Toggle" active={frame < 20} /><TourAction label="Hold to talk" active={frame >= 20} /><TourSelect value="⌥ Space" /></div>
        <div className="flex items-center gap-[3px]" style={{height: 24}}>{Array.from({length: 4}, (_, seed) => waveLevels(globalFrame, recording ? 0.9 : 0.14, seed)).flat().map((level, index) => <div key={index} style={{flex: 1, height: 3 + level * 21, borderRadius: 2, background: recording ? color.red : color.cyan}} />)}</div>
        <TourCard style={{height: 96}}><div className="whitespace-pre-line" style={{fontSize: 22, lineHeight: '30px'}}>{done ? everydayDemo.voice.cleaned : transcript || 'Hold the shortcut and speak.'}</div></TourCard>
        <div className="flex gap-[9px]"><TourSelect value={frame < 84 ? 'LM Studio' : 'Ollama · Local cleanup'} /><TourAction label="Format numbered items" active /></div>
        {done ? <TourResult>Cleaned transcript inserted</TourResult> : cleaning ? <TourResult pending>Cleaning the transcript…</TourResult> : <div style={{fontSize: 16, color: recording ? color.red : color.secondary}}>{recording ? 'Recording · Release to finish' : 'System speech recognition'}</div>}
      </div>
      <div className="flex min-w-0 flex-1 flex-col gap-[12px]">
        <TourHeading title="Recognition vocabulary" />
        <div className="grid grid-cols-2 gap-x-[16px] gap-y-[10px]">{voiceVocabularies.map((name) => <div key={name} className="flex items-center gap-[5px]" style={{fontSize: 13.5, lineHeight: '19px'}}><Check size={12} color={color.blue} />{name}</div>)}</div>
        <TourField label="Hot words" value={everydayDemo.voice.hotword} />
        <TourToggle label="Structured formatting" on />
        <div style={{fontSize: 13, lineHeight: '18px', color: color.secondary}}>Ollama · LM Studio · Remote models<br />Voice history · Recording retention · Auto-cleanup</div>
      </div>
      <TourPointer frame={frame} at={22} x={176} y={100} />
    </div>
  );
};
