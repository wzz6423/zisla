import {Check, FileImage, Mic, StickyNote, Video, X} from 'lucide-react';
import {AgendaModule} from '../AgendaModule';
import {ClipboardModule} from '../ClipboardModule';
import {NotesModule} from '../NotesModule';
import {ShelfModule} from '../ShelfModule';
import {AlbumArt} from '../../components/IslandChrome';
import {Caption, Headline} from '../../components/Caption';
import {MenuBar, Notch, Wallpaper} from '../../components/Desktop';
import {GlassPanel, waveLevels} from '../../components/Glass';
import {Island} from '../../components/Island';
import {clamp01, color} from '../../theme';
import {FilmMotion, ZislaMotion, ease, easeOutAt, linear, springAt} from '../../motion';
import {NativeModuleSurface, TourAction, TourField, TourHeading, TourPointer, TourPointerTrack, TourSelect, TourToggle} from './TourSurface';

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

export const NotesTourModule = ({frame}: {frame: number}) => {
  const checked = frame >= 54 ? 2 + ease(frame, [54, 64], [0, 1]) : 2;
  return (
    <div className="absolute inset-0" data-feature="quickNotes">
      <NotesModule checked={checked} />
      <div className="absolute" style={{left: 178, bottom: 14, fontSize: 11, color: frame >= 78 ? color.green : color.secondary}}>{frame >= 78 ? 'Saved to Apple Notes' : 'Saving to Notes…'}</div>
      <TourPointer frame={frame} at={48} x={196.5} y={234} />
    </div>
  );
};

export const ClipboardTourModule = ({frame}: {frame: number}) => {
  const filter = frame >= 38 ? ease(frame, [38, 46], [0, 4]) : 0;
  const query = frame >= 74 ? 'brew'.slice(0, Math.min(4, Math.floor((frame - 74) / 3) + 1)) : '';
  return (
    <div className="absolute inset-0" data-feature="clipboard">
      <ClipboardModule filter={filter} query={query} groupByApp />
      {frame >= 100 ? <div className="absolute bottom-[14px] left-[18px]" style={{fontSize: 11, color: color.green, opacity: easeOutAt(frame, [100, 108], [0, 1])}}>Copied to clipboard</div> : null}
      <TourPointerTrack frame={frame} actions={[{at: 32, x: 337, y: 72}, {at: 68, x: 102, y: 102}, {at: 94, x: 210, y: 142}]} />
    </div>
  );
};

export const AgendaTourModule = ({frame}: {frame: number}) => (
  <div className="absolute inset-0" data-feature="agenda">
    <AgendaModule done={ease(frame, [50, 64], [0, 1])} />
    <TourPointer frame={frame} at={44} x={729.5} y={137} />
    {frame >= 68 ? <div className="absolute bottom-[4px] right-[20px]" style={{fontSize: 10, color: color.green, opacity: easeOutAt(frame, [68, 76], [0, 1])}}>Reminder completed</div> : null}
  </div>
);

export const meetingTourAt = (frame: number) => ({
  compact: frame < 56,
  joined: frame >= 54,
  noteOpen: frame >= 98 && frame < 148,
  noteSaved: frame >= 148,
  noteLinked: frame >= 216,
  menu: frame >= 70 && frame < 98 || frame >= 190 && frame < 216,
  remaining: Math.max(0, 2 - Math.floor(frame / 45)),
});

const NoteDetail = ({text, location, saved, reminder = false, scroll = 0}: {text: string; location: string; saved: boolean; reminder?: boolean; scroll?: number}) => (
  <div className="absolute inset-0 flex flex-col gap-[6px]" data-feature="contextNote.detail" style={{padding: 8, fontSize: 10, lineHeight: '15px'}}>
    <div className="flex shrink-0 items-center gap-[10px]" style={{height: 20}}><StickyNote size={13} /><strong>Location note</strong><div className="flex-1" /><span>Copy</span><span>Go to location</span><span data-note-save style={{color: color.green}}>Save</span><X size={12} /></div>
    <div className="relative min-h-0 flex-1 overflow-hidden" data-note-scroll>
      <div className="flex flex-col gap-[6px]" style={{transform: `translateY(${-scroll}px)`}}>
        <div className="shrink-0" style={{color: color.secondary}}>Recorded location</div>
        <div className="shrink-0">{location}</div>
        <div className="flex shrink-0 gap-[12px]"><span style={{color: color.secondary}}>Recorded at</span><span>Nov 11, 2026 · 9:41</span></div>
        <div className="shrink-0" style={{color: color.secondary}}>Note content</div>
        {reminder ? <div className="flex shrink-0 items-center gap-[10px]" style={{height: 22}}><span>Recurring reminder</span><div className="flex-1" /><span>Every 3 hours ⌄</span></div> : null}
        <div className="shrink-0 whitespace-pre-line" style={{height: 90, padding: 8, borderRadius: 8, background: color.fillCard, fontSize: 12, lineHeight: '19px'}}>{text}{!saved ? <span style={{color: color.blue}}>│</span> : null}</div>
        {reminder ? <div className="flex shrink-0 flex-col gap-[6px]"><div className="flex items-center gap-[8px]" style={{color: color.secondary}}><FileImage size={12} /><span>Window screenshot</span><div className="flex-1" /><span>Copy screenshot</span></div><div className="relative self-center overflow-hidden" data-feature="contextNote.screenshot" aria-label="View screenshot" style={{width: 230, height: 86, borderRadius: 6, background: '#222832'}}><div style={{height: 18, padding: '2px 8px', fontSize: 8, background: '#151a22'}}>Safari · Launch review</div><div className="flex items-center gap-[12px]" style={{padding: 9}}><AlbumArt size={40} radius={5} /><div style={{fontSize: 13}}>Launch review</div></div></div></div> : null}
      </div>
    </div>
  </div>
);

export const MeetingTourModule = ({frame, title = 'Ten minutes before every call.', caption = 'Top-edge countdown · One-click join · Linked meeting notes'}: {frame: number; title?: string; caption?: string}) => {
  const state = meetingTourAt(frame);
  const note = '1. Review the island layout.\n2. Confirm the launch date.';
  const pointer = <TourPointerTrack frame={frame} actions={[{at: 48, x: 786, y: 17}, {at: 64, x: 993.5, y: 210}, {at: 92, x: 845, y: 235}, {at: 142, x: 969, y: 253}, {at: 184, x: 993.5, y: 210}, {at: 210, x: 835, y: 259}]} />;
  if (state.compact) {
    const enter = easeOutAt(frame, [0, 12], [0, 1]);
    return <>
      <Wallpaper dim={.22} /><MenuBar />
      <Island reveal={0} height={34} wing={112} left={<Video size={13} />} right={<span data-feature="meetingCountdown" className="font-rounded tabular" style={{fontSize: 12}}>00:{String(state.remaining).padStart(2, '0')}</span>} />
      <Notch />
      <Headline lines={[title]} top={260} size={34} opacity={enter} />
      <div className="absolute inset-x-0 text-center" style={{top: 319, fontSize: 16, color: color.secondary, opacity: enter}}>Design review · {state.joined ? 'Meeting link opened' : 'Starts in 00:02'}</div>
      <Caption text={caption} size={17} bottom={35} opacity={enter} />
      {pointer}
    </>;
  }
  const reveal = clamp01(springAt(frame, 60, 56, ZislaMotion.islandReveal, 18));
  const morphFrame = state.noteOpen ? frame - 98 : frame >= 148 ? frame - 148 : undefined;
  const menuStart = frame < 148 ? 70 : 190;
  const menuOpacity = state.menu ? easeOutAt(frame, [menuStart, menuStart + 7], [0, 1]) : 0;
  return <>
    <NativeModuleSurface
      title={title}
      caption={caption}
      module={state.noteOpen ? 'shelf' : 'agenda'}
      height={state.noteOpen ? 355 : 160}
      fromModule={state.noteOpen ? 'agenda' : frame >= 148 ? 'shelf' : undefined}
      fromHeight={state.noteOpen ? 160 : frame >= 148 ? 355 : undefined}
      frame={morphFrame}
      reveal={reveal}
    >
      <div className="absolute inset-0" data-feature="meetingWorkflow">
        {state.noteOpen ? <div data-feature="meetingNotes"><ShelfModule items={state.noteSaved ? [{name: 'Design review note', kind: 'note', tint: color.yellow}] : []} enter={1} selectedCategory={1} detail={!state.noteSaved ? <NoteDetail text={note.slice(0, Math.floor(ease(frame, [98, 134], [0, note.length])))} location="Calendar · Design review · example.com/meet/review" saved={false} /> : undefined} /></div> : <AgendaModule done={1} meeting />}
        {state.menu ? (
          <div
            role="menu"
            aria-label="Meeting note actions"
            className="absolute"
            style={{
              right: 22,
              top: 76,
              padding: 6,
              width: 242,
              borderRadius: 7,
              background: '#29292e',
              fontSize: 11,
              lineHeight: '24px',
              boxShadow: '0 14px 35px #0008',
              opacity: menuOpacity,
              transform: `scale(${0.96 + 0.04 * menuOpacity})`,
              transformOrigin: 'top right',
            }}
          >
            {frame < 98 ? <><div role="menuitem" data-meeting-note-option="new" style={{background: color.blue, padding: '0 6px', borderRadius: 4}}>New meeting note</div><div role="menuitem" style={{padding: '0 6px'}}>Link existing note ›</div></> : <><div role="menuitem" style={{padding: '0 6px'}}>Design review note</div><div role="menuitem" data-meeting-note-option="link" style={{background: color.blue, padding: '0 6px', borderRadius: 4}}>Link existing note · Review checklist</div><div role="menuitem" style={{padding: '0 6px'}}>Unlink note ›</div></>}
          </div>
        ) : null}
        {state.joined && frame < 98 ? <div className="absolute" data-feature="meetingJoin.result" style={{left: 222, bottom: 5, fontSize: 10, color: color.green, padding: '1px 7px', borderRadius: 5, background: 'rgba(18,18,22,0.88)'}}>Meeting link opened</div> : null}
        {state.noteSaved && !state.menu ? <div className="absolute" data-feature="meetingNote.result" style={{left: 222, bottom: 5, fontSize: 10, color: color.green, padding: '1px 7px', borderRadius: 5, background: 'rgba(18,18,22,0.88)'}}>{state.noteLinked ? 'Existing note linked · Open from Calendar' : 'Meeting note saved · Linked to Design review'}</div> : null}
      </div>
    </NativeModuleSurface>
    {pointer}
  </>;
};

export const ContextNotesTourModule = ({frame}: {frame: number}) => {
  const text = everydayDemo.context.text.slice(0, Math.floor(ease(frame, [10, 60], [0, everydayDemo.context.text.length])));
  return <div className="absolute inset-0" data-feature="contextNotes">
    <ShelfModule items={[{name: 'Launch review note', kind: 'note', tint: color.yellow}]} enter={1} selectedCategory={1} detail={<NoteDetail text={text} location={everydayDemo.context.location} saved={frame >= 76} reminder scroll={ease(frame, [80, 108], [0, 132])} />} />
    {frame >= 76 ? <div className="absolute" data-feature="contextNote.saved" style={{left: 24, bottom: 6, color: color.green, fontSize: 10, opacity: easeOutAt(frame, [76, 84], [0, 1])}}>Saved · Shown when you return</div> : null}
    <TourPointer frame={frame} at={70} x={705} y={112} />
  </div>;
};

export const briefingTourAt = (frame: number) => ({selected: frame < 30 ? 0 : 4, preview: frame >= 58, exporting: frame >= 86 && frame < 99, saved: frame >= 99});

const BriefingPreview = ({template}: {template: typeof briefingTemplates[number]}) => (
  <div className="h-full" style={{background: template.background, color: '#25343a', padding: '28px 25px'}}>
    <div style={{fontSize: 13, lineHeight: '17px', letterSpacing: '0.09em', color: template.accent}}>DAILY BRIEFING</div>
    <div style={{fontSize: 27, lineHeight: '32px', fontWeight: 700, marginTop: 10}}>Nov 11</div>
    <div style={{fontSize: 32, lineHeight: '36px', fontWeight: 600, marginTop: 14}}>{everydayDemo.briefing.active}</div>
    <div style={{fontSize: 14, lineHeight: '18px', opacity: 0.6}}>Active on this Mac</div>
    <div className="flex items-end gap-[5px]" style={{height: 65, marginTop: 18}}>{[14, 28, 37, 15, 33, 46, 41, 21].map((height, index) => <div key={index} style={{flex: 1, height, borderRadius: 2, background: template.accent, opacity: .35 + index * .06}} />)}</div>
    <div style={{fontSize: 15, lineHeight: '20px', marginTop: 22}}>{everydayDemo.briefing.characters} characters</div>
    <div style={{fontSize: 15, lineHeight: '20px', marginTop: 12}}>3 focus sessions completed</div>
    <div style={{fontSize: 15, lineHeight: '20px', marginTop: 12}}>32–100% battery</div>
  </div>
);

export const BriefingTourModule = ({frame}: {frame: number}) => {
  const state = briefingTourAt(frame);
  const template = briefingTemplates[state.selected]!;
  const panelIn = clamp01(springAt(frame, 60, 0, FilmMotion.pop, 18));
  const previewIn = state.preview ? clamp01(springAt(frame, 60, 58, FilmMotion.pop, 16)) : 0;
  return <>
    <Wallpaper dim={.3} /><MenuBar /><Notch />
    <Headline lines={['Daily Briefing.']} top={100} size={34} opacity={easeOutAt(frame, [0, 12], [0, 1])} />
    <GlassPanel opacity={panelIn} style={{left: 125, top: 175, width: 720, height: 445, transform: `translateY(${(1 - panelIn) * 8}px)`}}>
      <div className="absolute inset-0 flex flex-col gap-[13px]" data-feature="briefing.settings" style={{padding: 22}}>
        <TourHeading title="Settings → Daily briefing" />
        <TourToggle label="Daily briefing" on />
        <div className="flex items-center gap-[10px]" style={{fontSize: 14}}><span>Export time</span><div className="flex-1" /><TourSelect value={everydayDemo.briefing.time} /></div>
        <TourToggle label="Read system Screen Time" on />
        <div className="flex items-center gap-[8px]" style={{fontSize: 14}}><span>› Briefing content</span><div className="flex-1" /><span style={{color: color.secondary}}>Usage · Typing · System · Quotas</span></div>
        <div className="grid grid-cols-4 gap-[8px]">
          {briefingTemplates.map((item, index) => <div key={item.id} data-template={item.id} style={{padding: 5, borderRadius: 8, border: `1px solid ${state.selected === index ? color.blue : color.strokeCard}`}}><div className="flex flex-col gap-[4px]" style={{height: 34, padding: '5px 9px', borderRadius: 4, background: item.background}}><div style={{height: 4, width: '65%', background: item.accent}} /><div style={{height: 3, width: '86%', background: item.accent, opacity: .35}} /><div style={{height: 3, width: '73%', background: item.accent, opacity: .35}} /></div><div className="flex items-center justify-between" style={{fontSize: 12, lineHeight: '18px', marginTop: 3}}>{item.title}{state.selected === index ? <Check size={13} color={color.blue} /> : null}</div></div>)}
        </div>
        <div className="flex items-center gap-[10px]"><div className="shrink-0" data-briefing-action="preview"><TourAction label="Preview" active={state.preview} /></div><div className="flex-1" /><div className="shrink-0" data-briefing-action="export"><TourAction label="Export today’s PNG" active={state.exporting} busy={state.exporting} spinFrame={frame} /></div></div>
        <div data-feature="briefing.result" style={{fontSize: 14, color: state.saved ? color.green : color.secondary}}>{state.saved ? `Saved: ${everydayDemo.briefing.file}` : state.exporting ? 'Exporting PNG…' : '8 templates · Choose the content you want'}</div>
      </div>
    </GlassPanel>
    {state.preview ? (
      <GlassPanel
        opacity={previewIn}
        style={{left: 849, top: 175, width: 305, height: 445, transform: `translateX(${(1 - previewIn) * 14}px) scale(${0.96 + 0.04 * previewIn})`}}
      >
        <div className="flex items-center gap-[6px]" style={{height: 28, padding: '0 10px', background: '#242429', fontSize: 10}}>{['#ff5f57', '#febc2e', '#28c840'].map((tint) => <span key={tint} style={{width: 8, height: 8, borderRadius: 4, background: tint}} />)}<span style={{marginLeft: 9}}>Daily briefing · {template.title}</span></div>
        <BriefingPreview template={template} />
      </GlassPanel>
    ) : null}
    <Caption text="8 templates · Screen Time, typing & AI quotas · Scheduled PNG" size={17} bottom={35} opacity={easeOutAt(frame, [0, 12], [0, 1])} />
    <TourPointerTrack frame={frame} actions={[{at: 24, x: 235, y: 509}, {at: 52, x: 186, y: 573}, {at: 80, x: 746, y: 573}]} />
  </>;
};

export const voiceTourAt = (frame: number) => ({
  settings: frame < 36,
  recording: frame >= 36 && frame < 84,
  cleaning: frame >= 84 && frame < 106,
  done: frame >= 106,
  transcript: everydayDemo.voice.raw.slice(0, Math.floor(linear(frame, [40, 82], [0, everydayDemo.voice.raw.length]))),
});

export const VoiceTourModule = ({frame, globalFrame}: {frame: number; globalFrame: number}) => {
  const state = voiceTourAt(frame);
  const settingsIn = clamp01(springAt(frame, 60, 0, FilmMotion.pop, 16));
  const editorIn = !state.settings ? clamp01(springAt(frame, 60, 36, FilmMotion.pop, 16)) : 0;
  const barIn = (state.recording || state.cleaning)
    ? clamp01(springAt(frame, 60, 36, ZislaMotion.quickAction, 16)) * linear(frame, [100, 106], [1, 0])
    : 0;
  return <>
    <Wallpaper dim={.26} /><MenuBar /><Notch />
    <Headline lines={['Voice dictation, cleaned on the fly.']} top={83} size={34} opacity={easeOutAt(frame, [0, 12], [0, 1])} />
    {state.settings ? <GlassPanel opacity={settingsIn} style={{left: 280, top: 144, width: 720, height: 485, transform: `translateY(${(1 - settingsIn) * 8}px)`}}>
      <div className="absolute inset-0 flex flex-col gap-[13px]" data-feature="voice.settings" style={{padding: 24}}>
        <TourHeading title="Settings → Voice input" />
        <div className="flex items-center gap-[12px]" style={{fontSize: 14}}><span>Input mode</span><div className="flex-1" /><TourSelect value="Hold to talk" /><TourSelect value="⌥ Space" /></div>
        <div className="flex items-center gap-[12px]" style={{fontSize: 14}}><span>Cleanup model</span><div className="flex-1" /><TourSelect value="Ollama · Local cleanup" /></div>
        <TourToggle label="Structured formatting" on />
        <TourToggle label="Keep original recordings" on />
        <div className="flex items-center gap-[12px]" style={{fontSize: 13, color: color.secondary}}><span>LM Studio · Ollama · Remote models</span><div className="flex-1" /><span>Voice history · Auto-cleanup</span></div>
        <div className="relative flex-1 overflow-hidden"><div className="flex flex-col gap-[8px]" style={{transform: `translateY(${-ease(frame, [10, 32], [0, 190])}px)`}}><div style={{fontSize: 14, fontWeight: 600}}>Recognition vocabulary</div>{voiceVocabularies.map((name) => <TourToggle key={name} label={name} on />)}<TourField label="Hot words" value={everydayDemo.voice.hotword} /></div></div>
      </div>
    </GlassPanel> : <>
      {state.recording || state.cleaning ? (
        <GlassPanel
          radius={14}
          opacity={barIn}
          style={{left: 370, top: 0, width: 540, height: 54, borderRadius: '0 0 14px 14px', background: '#151518', transform: `translateY(${(1 - barIn) * -36}px)`}}
        >
          <div data-feature="voice.recording" className="absolute inset-x-0 top-0 flex items-center justify-between" style={{height: 34, padding: '0 12px'}}><Mic size={13} color={state.recording ? color.red : color.secondary} /><div className="flex items-center gap-[3px]" style={{height: 20}}>{waveLevels(globalFrame, state.recording ? .9 : .14, 0).map((level, index) => <div key={index} style={{width: 3, height: 3 + level * 14, borderRadius: 2, background: color.cyan}} />)}</div></div>
          <div data-feature="voice.transcript" className="absolute inset-x-0 truncate" style={{top: 34, height: 20, fontSize: 10.5, lineHeight: '20px', padding: '0 12px', color: color.secondary}}>{state.recording ? state.transcript || 'Listening…' : 'Cleaning the transcript…'}</div>
        </GlassPanel>
      ) : null}
      <Notch />
      <GlassPanel opacity={editorIn} style={{left: 298, top: 174, width: 684, height: 348, transform: `scale(${0.97 + 0.03 * editorIn})`}}><div className="flex items-center gap-[7px]" style={{height: 31, padding: '0 12px', background: '#25252a', fontSize: 12}}>{['#ff5f57', '#febc2e', '#28c840'].map((tint) => <span key={tint} style={{width: 9, height: 9, borderRadius: 5, background: tint}} />)}<span style={{marginLeft: 18}}>Notes · Review tasks</span></div><div className="whitespace-pre-line" data-feature="voice.insertion" style={{padding: 25, fontSize: 21, lineHeight: '32px'}}>{state.done ? everydayDemo.voice.cleaned : 'Review tasks\n\n'}{!state.done ? <span style={{color: color.blue}}>│</span> : null}</div></GlassPanel>
      <div className="absolute inset-x-0 text-center" style={{top: 551, fontSize: 15, color: state.done ? color.green : state.recording ? color.red : color.secondary}}>{state.done ? 'Cleaned transcript inserted' : state.cleaning ? 'Cleaning the transcript…' : 'Recording · Release to finish'}</div>
    </>}
    <Caption text="Hold to talk · Custom hotwords · Local Ollama or remote polish" size={17} bottom={35} opacity={easeOutAt(frame, [0, 12], [0, 1])} />
  </>;
};
