import {Check, Circle, Copy, Crop, Pin, ScanText, Video} from 'lucide-react';
import {useCurrentFrame} from 'remotion';
import {Headline} from '../components/Caption';
import {Cursor} from '../components/Cursor';
import {MenuBar, Notch, Wallpaper} from '../components/Desktop';
import {GlassPanel, ProgressTrack} from '../components/Glass';
import {ScreenRecordingModule, ScreenshotsModule} from '../modules/ToolsModule';
import {CreativeToolsModule} from '../modules/CreativeToolsModule';
import {ease, fadeWindow} from '../motion';
import {clamp01, color, white} from '../theme';

export const creativeGroups = [
  {id: 'capture', from: 0, duration: 480, title: 'Capture. Pin. Extract.', features: ['capture']},
  {id: 'recording', from: 480, duration: 600, title: 'Record your screen. Shape the story.', features: ['recording']},
  {id: 'image', from: 1080, duration: 540, title: 'Everything your images need.', features: ['imageTools']},
  {id: 'audio', from: 1620, duration: 540, title: 'The right sound, with local tools.', features: ['audioTools']},
  {id: 'pdf', from: 2160, duration: 540, title: 'Documents, finished on your Mac.', features: ['pdf']},
] as const;

export const creativeTourAt = (frame: number, duration = 2700) => {
  const position = Math.min(2699, Math.max(0, frame * 2700 / duration));
  const group = [...creativeGroups].reverse().find((item) => position >= item.from)!;
  return {group, frame: position - group.from};
};

const ScreenshotTour = ({frame}: {frame: number}) => {
  const part = Math.min(2, Math.floor(Math.max(0, frame) / 160));
  const progress = ease(frame % 160, [22, 105], [0, 1]);
  return <>
    <GlassPanel style={{left: 96, top: 190, width: 626, height: 426}}>
      <ScreenshotsModule annotation={progress} />
    </GlassPanel>
    <GlassPanel style={{left: 740, top: 190, width: 444, height: 426, padding: 24}}>
      <div className="flex items-center gap-[9px]" style={{fontSize: 20, fontWeight: 600}}>{part === 0 ? <Crop size={21} /> : part === 1 ? <Pin size={21} /> : <ScanText size={21} />}{['Capture and annotate', 'Long capture and pin', 'Text, translation and tables'][part]}</div>
      <div className="flex flex-wrap gap-[7px]" style={{marginTop: 15}}>{['Rectangle', 'Ellipse', 'Brush', 'Highlighter', 'Arrow', 'Number', 'Text', 'Blur', 'Extraction'].map((item, index) => <span key={item} style={{padding: '5px 8px', borderRadius: 6, background: white(.05), fontSize: 12, color: index === part + 3 ? color.blue : color.secondary}}>{item}</span>)}</div>
      <div className="relative" style={{height: 165, marginTop: 18, padding: 16, background: white(.04), borderRadius: 10, overflow: 'hidden'}}>
        {part === 0 ? <><div style={{fontSize: 17, fontWeight: 500}}>Ship the next idea.</div><div style={{marginTop: 15, padding: 8, borderRadius: 8, background: `rgba(10,132,255,${progress * .18})`, border: `1px solid ${color.blue}`}}>Ready for review.</div><div style={{marginTop: 14, fontSize: 13, color: color.secondary}}>Copy · Save · Send to Shelf</div></> : part === 1 ? <div className="relative" style={{height: 210, transform: `translateY(${-progress * 56}px)`}}>{[0,1,2,3,4].map((row) => <div key={row} style={{height: 34, marginBottom: 5, padding: 8, borderRadius: 6, background: white(.07), fontSize: 13}}>Release checklist {row + 1}</div>)}<div className="absolute right-0 top-0" style={{color: color.blue}}><Pin size={20} /></div></div> : <><div className="flex items-center gap-[7px]" style={{fontSize: 14}}><ScanText size={16} />{progress > .6 ? 'Ready for review.' : 'Recognizing…'}</div><div className="flex items-center gap-[9px]" style={{marginTop: 20, fontSize: 13}}><Copy size={16} />{progress > .6 ? '准备好评审。' : 'Translate and copy'}</div><div className="flex" style={{marginTop: 20, gap: 12, fontSize: 13, color: color.blue}}>Export table.xlsx <Check size={16} /></div></>}
      </div>
      <div style={{marginTop: 18}}><ProgressTrack value={progress} tint={color.blue} width="100%" height={4} /></div>
      <div style={{marginTop: 14, fontSize: 13, color: progress === 1 ? color.green : color.secondary}}>{progress === 1 ? ['Annotation saved', 'Long capture pinned · Existing pins retained', 'Text copied · Table exported'][part] : 'Capture on this Mac'}</div>
      <div style={{marginTop: 12, fontSize: 11, color: color.secondary}}>Resize · Round corners · Image extraction · Custom shortcuts</div>
    </GlassPanel>
  </>;
};

const RecordingTour = ({frame}: {frame: number}) => {
  const part = Math.min(2, Math.floor(Math.max(0, frame) / 200));
  const progress = ease(frame % 200, [22, 120], [0, 1]);
  const properties = part === 0 ? [['Source', 'Display / Window / Region'], ['System audio', 'Enabled'], ['Microphone', 'Enabled'], ['Camera', 'Picture in picture'], ['Capture', progress === 1 ? 'Saved to project' : 'Recording 00:12']] : part === 1 ? [['Tracks', 'Video / Audio / Image / Text'], ['Effects', 'Animation / Zoom / Skin smoothing'], ['Portrait', 'Brighten / Slim face / Slim body'], ['Voice', 'Voice effects'], ['Cursor', 'Smooth trail · Custom color']] : [['Captions', 'Transcribe / Edit / Style'], ['AI edit', 'Preview proposal → Apply'], ['Aspect ratio', 'Original / 16:9 / 9:16 / 1:1 / 4:3'], ['Export', 'Video / GIF / Live Photo / Audio'], ['Project', 'Save / Open / Undo / Redo']];
  return <>
    <GlassPanel style={{left: 96, top: 190, width: 626, height: 426}}><ScreenRecordingModule frame={frame * 12} />
      {part === 0 ? <div className="absolute" style={{right: 31, top: 144, padding: '7px 12px', borderRadius: 8, background: color.red, fontSize: 14}}>REC · Display + Camera</div> : part === 1 ? <div className="absolute" style={{right: 31, top: 144, padding: '7px 12px', borderRadius: 8, background: white(.14), fontSize: 14}}>Zoom · {Math.round(100 + progress * 20)}%</div> : <div className="absolute" style={{left: 130, right: 60, top: 206, textAlign: 'center', fontSize: 17, padding: '7px 12px', borderRadius: 6, background: 'rgba(0,0,0,.8)', opacity: progress}}>Appears when you need it.</div>}
    </GlassPanel>
    <GlassPanel style={{left: 740, top: 190, width: 444, height: 426, padding: 24}}>
      <div className="flex items-center gap-[9px]" style={{fontSize: 20, fontWeight: 600}}><Video size={22} />{['Capture sources', 'Multitrack editing', 'Preview and export'][part]}</div>
      {properties.map(([label, value]) => <div key={label} style={{marginTop: 17}}><div style={{fontSize: 11, color: color.secondary}}>{label}</div><div style={{fontSize: 14, marginTop: 4}}>{value}</div></div>)}
      <div style={{marginTop: 20}}><ProgressTrack value={progress} tint={color.blue} width="100%" height={4} /></div>
      <div className="flex items-center gap-[7px]" style={{marginTop: 12, fontSize: 13, color: progress === 1 ? color.green : color.secondary}}>{progress === 1 ? <Check size={16} /> : <Circle size={16} />}{progress === 1 ? ['Recording saved', 'Timeline edits applied', 'Product walkthrough.mp4 exported'][part] : 'Preparing the next step'}</div>
    </GlassPanel>
  </>;
};

export const SceneCreativeTools = ({duration = 2700}: {duration?: number}) => {
  const state = creativeTourAt(useCurrentFrame(), duration);
  const {group, frame: local} = state;
  return <>
    <Wallpaper dim={.36} /><MenuBar /><Notch />
    <Headline lines={[group.title]} top={104} size={38} align="left" opacity={clamp01(local / 14)} />
    <div data-feature={group.features.join(' ')} style={{opacity: clamp01(local / 12)}}>
      {group.id === 'capture' ? <ScreenshotTour frame={local} /> : group.id === 'recording' ? <RecordingTour frame={local} /> : <GlassPanel style={{left: 96, top: 190, width: 1088, height: 426}}><CreativeToolsModule kind={group.id} frame={local} /></GlassPanel>}
    </div>
    <Cursor x={group.id === 'capture' ? 940 : 1125} y={group.id === 'capture' ? 404 : 592} opacity={fadeWindow(local, 20, 115, 12)} />
  </>;
};
