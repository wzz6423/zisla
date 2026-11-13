import type {LucideIcon} from 'lucide-react';
import {
  ArrowRight,
  ArrowUpRight,
  AudioLines,
  Check,
  Circle,
  Captions,
  ChevronDown,
  Copy,
  Crop,
  Download,
  FileText,
  Folder,
  GripVertical,
  Highlighter,
  Layers,
  Mic,
  Monitor,
  PersonStanding,
  Image as ImageIcon,
  MousePointer2,
  Pause,
  Pencil,
  Pin,
  Play,
  Redo2,
  RectangleHorizontal,
  ScanText,
  Scissors,
  Sparkles,
  Square,
  SquareDashed,
  Table2,
  Trash2,
  Type,
  Undo2,
  Video,
  Volume2,
  X,
  ZoomIn,
} from 'lucide-react';
import {AlbumArt, formatTime} from '../components/IslandChrome';
import {ProgressTrack, waveLevels} from '../components/Glass';
import {clamp01, color, white} from '../theme';
import {FPS} from '../timeline';
import {ease, linear} from '../motion';

// Fictional files keep the film independent of the user's captures and media library.
export const toolDemo = {
  screenshot: {title: 'Launch checklist', text: 'Ready for review.'},
  recording: {title: 'Product walkthrough', duration: 24, format: 'MP4'},
  image: {input: 'Cover.png', output: 'Cover.webp', sourceSize: '2400 × 2400', outputSize: '1200 × 1200'},
  audio: {input: 'Interview.wav', start: 5, end: 28, sampleRate: '48 kHz'},
  pdf: {inputs: ['Brief.pdf', 'Notes.pdf'], output: 'Launch brief.pdf', pages: 8},
} as const;

const ToolHeader = ({icon: Icon, title, detail}: {icon: LucideIcon; title: string; detail: string}) => (
  <div className="shrink-0" style={{marginBottom: 16}}>
    <div className="flex items-center gap-[9px]">
      <Icon size={20} strokeWidth={2} color={color.secondary} />
      <div style={{fontSize: 22, lineHeight: '27px', fontWeight: 600, letterSpacing: '-0.02em'}}>{title}</div>
    </div>
    <div style={{marginTop: 6, fontSize: 15, lineHeight: '21px', color: color.secondary}}>{detail}</div>
  </div>
);

const CAPTURE_TOOLS = [
  ['rectangle', Square, 'Rectangle'], ['ellipse', Circle, 'Ellipse'], ['brush', Pencil, 'Brush'],
  ['highlighter', Highlighter, 'Highlighter'], ['arrow', ArrowUpRight, 'Arrow'], ['number', Circle, 'Number'],
  ['text', Type, 'Text'], ['mosaic', Layers, 'Blur'], ['extraction', SquareDashed, 'Extraction'],
] as const;

export const screenshotGeometry = {
  review: {x: 64, y: 142, width: 352, height: 42},
  checkbox: {x: 77, y: 153, width: 20, height: 20},
  text: {x: 110, y: 169},
  arrow: {from: {x: 510, y: 235}, to: {x: 416, y: 163}},
} as const;

export const screenshotTourState = (frame: number) => {
  const position = Math.min(359, Math.max(0, frame));
  return {
    frame: position, hdr: position >= 18,
    rectangle: clamp01((position - 38) / 22), arrow: clamp01((position - 66) / 30), obscure: clamp01((position - 106) / 18),
    scroll: clamp01((position - 154) / 72), longCapture: position >= 146 && position < 230,
    pinned: position >= 312, recognitionMenu: position >= 230 && position < 240,
    tableSave: position >= 240 && position < 260,
    recognizing: position >= 260 && position < 288, recognized: position >= 288,
    selected: position < 18 ? 'capture' : position < 38 ? 'hdr' : position < 66 ? 'rectangle' : position < 106 ? 'arrow' : position < 146 ? 'mosaic' : position < 230 ? 'long' : position < 312 ? 'recognize' : 'pin',
  };
};

export const ScreenshotCanvas = ({rectangle, arrow, obscure, hdr, scroll}: {rectangle: number; arrow: number; obscure: number; hdr: boolean; scroll: number}) => {
  const {review, checkbox, text, arrow: pointer} = screenshotGeometry;
  return (
    <svg data-screenshot-canvas width="100%" height="100%" viewBox="0 0 800 320" preserveAspectRatio="xMidYMid meet" style={{display: 'block'}}>
      <defs><filter id="capture-privacy"><feGaussianBlur stdDeviation={obscure * 4} /></filter><linearGradient id="capture-highlight"><stop stopColor={hdr ? '#fff1cf' : '#bbc4ce'} /><stop offset="1" stopColor={hdr ? '#f4a663' : '#a2adba'} /></linearGradient><clipPath id="capture-table"><rect x="556" y="118" width="178" height="158" rx="6" /></clipPath></defs>
      <rect x="26" y="14" width="748" height="292" rx="12" fill="#20242b" />
      <text x="64" y="51" fill={color.secondary} fontSize="15">{toolDemo.screenshot.title}</text>
      <text x="64" y="100" fill="white" fontSize="29" fontWeight="600">Ship the next idea.</text>
      <rect data-review-checkbox x={checkbox.x} y={checkbox.y} width={checkbox.width} height={checkbox.height} rx="5" fill={color.blue} />
      <path d="M81 163 L86 168 L94 159" fill="none" stroke="white" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
      <text data-review-text x={text.x} y={text.y} fill="white" fontSize="20">{toolDemo.screenshot.text}</text>
      <text x="77" y="219" fill={color.secondary} fontSize="17" filter="url(#capture-privacy)">launch@studio.test</text>
      <text x="64" y="275" fill={color.secondary} fontSize="14">Draft → Review → Publish</text>
      <rect data-review-box x={review.x} y={review.y} width={review.width} height={review.height} rx="7" fill="none" stroke={color.blue} strokeWidth="2" opacity={rectangle} />
      <path data-review-arrow d={`M${pointer.from.x} ${pointer.from.y} L${pointer.to.x} ${pointer.to.y} M${pointer.to.x} ${pointer.to.y} L${pointer.to.x + 6} ${pointer.to.y + 18} M${pointer.to.x} ${pointer.to.y} L${pointer.to.x + 21} ${pointer.to.y + 1}`} fill="none" stroke={color.orange} strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - arrow} />
      <rect x="556" y="48" width="178" height="49" rx="7" fill="url(#capture-highlight)" />
      <text x="573" y="79" fill="#30313a" fontSize="16" fontWeight="600">Review schedule</text>
      <g clipPath="url(#capture-table)"><g transform={`translate(0 ${-scroll * 66})`}>
        {['Task        Due', 'Notes       10:30', 'Review      11:00', 'Assets      11:30', 'Publish     12:00', 'Archive     12:30'].map((row, index) => <g key={row}><rect x="556" y={118 + index * 37} width="178" height="34" rx="5" fill={white(.06)} /><text x="568" y={140 + index * 37} fill={index === 0 ? '#fff' : color.secondary} fontSize="14" fontFamily="ui-monospace, monospace">{row}</text></g>)}
      </g></g>
    </svg>
  );
};

const CaptureTool = ({icon: Icon, title, selected}: {icon: LucideIcon; title: string; selected: boolean}) => <div data-capture-tool={title} data-selected={selected} className="flex flex-1 items-center justify-center" style={{minWidth: 16, maxWidth: 29, height: 29, borderRadius: 6, background: selected ? white(.15) : 'transparent', color: selected ? color.blue : color.secondary}}><Icon size={16} /></div>;

export const ScreenshotsModule = ({annotation = 1, frame}: {annotation?: number; frame?: number}) => {
  const state = frame === undefined ? {...screenshotTourState(100), rectangle: clamp01(annotation), arrow: clamp01(annotation), obscure: clamp01(annotation)} : screenshotTourState(frame);
  const status = state.pinned ? 'Pinned · Existing pins retained' : state.recognized ? 'Review schedule.xlsx exported' : state.recognizing ? 'Recognizing table…' : state.tableSave ? 'Choose where to save the table' : state.frame >= 230 ? 'Long capture complete' : state.longCapture ? 'Auto-scroll · Waiting for the next stitch' : state.frame >= 124 ? 'Annotation saved · Contact blurred' : state.hdr ? 'HDR on · Original highlights retained' : 'Capture a region';
  return (
    <div data-capture-frame={state.frame} className="absolute inset-0 flex flex-col" style={{padding: 16, gap: 10}}>
      <div className="flex shrink-0 items-center gap-[10px]" style={{height: 27, fontSize: 15, fontWeight: 600}}><Crop size={18} color={color.blue} /><span className="shrink-0">{state.pinned ? 'Pinned screenshot' : 'Screenshot editor'}</span><div className="flex-1" /><span className="min-w-0" style={{fontSize: 12, color: state.recognized ? color.green : color.secondary, fontWeight: 400}}>{frame === undefined ? '1600 × 640 · r: 12' : status}</span><X className="shrink-0" size={15} color={color.secondary} /></div>
      <div className="relative min-h-0 flex-1" style={{background: '#171a20', borderRadius: 10}}><ScreenshotCanvas rectangle={state.rectangle} arrow={state.arrow} obscure={state.obscure} hdr={state.hdr} scroll={state.scroll} />
        {state.longCapture ? <div data-long-capture-preview className="absolute" style={{right: 13, bottom: 12, width: 141, padding: 10, borderRadius: 7, border: `1px solid ${color.blue}`, background: '#252b34'}}><div style={{fontSize: 11, color: color.secondary}}>Long capture preview</div><div className="font-mono" style={{fontSize: 14, marginTop: 7}}>1600 × {640 + Math.floor(state.scroll * 520)}</div></div> : null}
        {state.recognitionMenu ? <div data-capture-recognition-menu className="absolute" style={{right: 159, bottom: 10, width: 200, padding: 6, borderRadius: 8, border: `1px solid ${color.strokeCard}`, background: '#303640', boxShadow: '0 9px 25px #0006'}}>{['Text / OCR', 'Translate and copy', 'Recognize table'].map((label) => <div key={label} style={{height: 29, padding: '5px 9px', fontSize: 12, borderRadius: 4, color: label === 'Recognize table' ? color.blue : color.label, background: label === 'Recognize table' ? white(.1) : 'transparent'}}>{label}</div>)}</div> : null}
        {state.tableSave ? <div data-capture-table-export className="absolute" style={{left: '50%', top: '50%', translate: '-50% -50%', width: 400, padding: 18, borderRadius: 12, border: `1px solid ${color.strokeCard}`, background: '#2c333d', boxShadow: '0 12px 40px #0008'}}><div className="flex items-center gap-[8px]" style={{fontSize: 15, fontWeight: 600}}><Table2 size={18} />Export recognized table</div><div style={{fontSize: 12, marginTop: 15, color: color.secondary}}>Save as</div><div style={{marginTop: 7, padding: '8px 10px', fontSize: 14, borderRadius: 5, background: color.fillControl}}>Review schedule.xlsx</div><div style={{fontSize: 12, marginTop: 12, color: color.secondary}}>Documents</div><div className="flex justify-end gap-[9px]" style={{marginTop: 17, fontSize: 12}}><StudioAction label="Cancel" /><StudioAction label="Save" active /></div></div> : null}
      </div>
      {state.pinned ? <div data-pinned-capture className="flex shrink-0 items-center justify-center gap-[16px]" style={{height: 38, borderRadius: 9, fontSize: 12, background: white(.045)}}><GripVertical size={15} color={color.secondary} /><span>−</span><span>100%</span><span>+</span><span style={{color: color.secondary}}>Opacity</span><div style={{width: 80}}><ProgressTrack value={1} tint={color.blue} width="100%" height={3} /></div><X size={15} color={color.secondary} /></div> : <div className="flex shrink-0 items-center justify-center gap-[4px]" style={{height: 38, borderRadius: 9, background: white(.045)}}><GripVertical size={16} color={color.secondary} />
        {CAPTURE_TOOLS.map(([id, Icon, title]) => <CaptureTool key={id} icon={Icon} title={title} selected={state.selected === id} />)}
        <CaptureTool icon={RectangleHorizontal} title="Round corners" selected={false} />
        <div style={{width: 1, height: 19, margin: '0 3px', background: color.divider}} />
        <div data-capture-tool="HDR" data-selected={state.hdr} className="flex shrink-0 items-center justify-center" style={{height: 29, padding: '0 6px', fontSize: 11, fontWeight: 600, borderRadius: 6, color: state.hdr ? color.blue : color.secondary, background: state.hdr ? white(.13) : 'transparent'}}>HDR</div>
        <CaptureTool icon={Undo2} title="Undo" selected={false} />
        <CaptureTool icon={ScanText} title="Recognize" selected={state.selected === 'recognize'} />
        <CaptureTool icon={state.longCapture ? Pause : Layers} title={state.longCapture ? 'Pause auto-scroll' : 'Long capture'} selected={state.selected === 'long'} />
        <CaptureTool icon={Pin} title="Pin" selected={state.selected === 'pin'} />
        <CaptureTool icon={Folder} title="Send to Shelf" selected={false} />
        <CaptureTool icon={Copy} title="Copy" selected={false} />
        <CaptureTool icon={Download} title="Save" selected={false} />
        <CaptureTool icon={X} title="Close" selected={false} />
      </div>}
    </div>
  );
};

export const ScreenRecordingModule = ({frame}: {frame: number}) => {
  const position = Math.min(toolDemo.recording.duration, Math.max(0, frame / FPS * 0.2));
  const playhead = position / toolDemo.recording.duration;
  return (
    <div className="absolute inset-0 flex flex-col" style={{padding: 20}}>
      <ToolHeader icon={Video} title="Screen recording studio" detail="Record · Edit · Export" />
      <div className="relative min-h-0 flex-1 overflow-hidden" style={{borderRadius: 12, background: 'linear-gradient(135deg, #1e365e, #382641)', border: `1px solid ${color.strokeCard}`}}>
        <div className="absolute flex items-center gap-[13px]" style={{left: 49, right: 49, top: 29, height: 90, padding: '14px 18px', borderRadius: '0 0 25px 25px', background: 'rgba(0,0,0,0.82)', boxShadow: '0 18px 30px rgba(0,0,0,0.28)'}}>
          <AlbumArt size={48} radius={7} />
          <div>
            <div style={{fontSize: 20, fontWeight: 600}}>zisla</div>
            <div style={{marginTop: 4, fontSize: 14, color: color.secondary}}>Appears when you need it.</div>
          </div>
        </div>
        <MousePointer2 size={22} fill="white" stroke="black" strokeWidth={1.2} className="absolute" style={{left: 290 + playhead * 30, top: 123}} />
        <div className="absolute bottom-[13px] left-[16px]" style={{fontSize: 14, color: white(0.75)}}>{toolDemo.recording.title}</div>
      </div>
      <div className="flex shrink-0 items-center gap-[8px]" style={{marginTop: 12, marginBottom: 8, fontSize: 13}}>
        <Play size={15} fill={color.label} />
        <span className="font-mono tabular">{formatTime(position)} / {formatTime(toolDemo.recording.duration)}</span>
        <div className="flex-1" />
        <Scissors size={14} color={color.secondary} />
        <span style={{color: color.secondary}}>Timeline</span>
        <span style={{marginLeft: 10, color: color.blue, fontWeight: 600}}>{toolDemo.recording.format}</span>
      </div>
      <div className="relative shrink-0" style={{paddingLeft: 57}}>
        <div className="absolute left-0 top-[5px]" style={{fontSize: 12, color: color.secondary}}>Screen</div>
        <div className="flex gap-[3px]" style={{height: 28}}>
          {[0.36, 0.27, 0.37].map((length, index) => <div key={index} style={{flex: length, borderRadius: 5, background: 'rgba(10,132,255,0.45)', border: `1px solid ${color.blue}`}} />)}
        </div>
        <div className="absolute left-0 top-[38px]" style={{fontSize: 12, color: color.secondary}}>Voice</div>
        <div className="flex items-center gap-[3px] overflow-hidden" style={{height: 22, marginTop: 5, padding: '0 6px', borderRadius: 5, background: 'rgba(48,209,88,0.22)'}}>
          {Array.from({length: 5}, (_, seed) => waveLevels(frame, 0.75, seed)).flat().map((level, index) => <div key={index} style={{flex: 1, height: 3 + level * 15, borderRadius: 1, background: color.green}} />)}
        </div>
        <div className="absolute top-0 bottom-0" style={{left: `calc(57px + (100% - 57px) * ${playhead})`, width: 1.5, background: white(0.92)}} />
      </div>
    </div>
  );
};

export const recordingTourState = (frame: number) => {
  const position = Math.min(719, Math.max(0, frame));
  return {
    frame: position,
    phase: position < 184 ? 'capture' : position < 264 ? 'clip' : position < 350 ? 'effects' : position < 442 ? 'captions' : position < 558 ? 'ai' : 'export',
    recording: position >= 86 && position < 132, paused: position >= 132 && position < 150,
    captured: position >= 150, camera: position >= 22,
    portraitMenu: position >= 25 && position < 82, portrait: ease(position, [37, 57], [0, 1]),
    captureTime: linear(position, [86, 132], [0, 24]),
    trim: ease(position, [202, 228], [0, 1]), animation: ease(position, [236, 256], [0, 1]),
    zoom: ease(position, [282, 312], [1, 1.2]),
    captions: position >= 402, captionEdited: position >= 422,
    proposal: position >= 500, applied: position >= 536,
    playbackTime: linear(position, [184, 620], [0, 12]),
    playbackDuration: position < 228 ? 24 : position < 536 ? 16 : 12,
    exporting: position >= 600 && position < 654, exported: position >= 654,
  };
};

const StudioField = ({label, value}: {label: string; value: string}) => <div className="flex items-center gap-[10px]" style={{fontSize: 12, minHeight: 31}}><span className="flex-1" style={{color: color.secondary}}>{label}</span><span className="font-mono" style={{minWidth: 91, padding: '5px 8px', borderRadius: 5, background: color.fillControl, textAlign: 'right'}}>{value}</span></div>;

const StudioAction = ({label, active = false}: {label: string; active?: boolean}) => <div className="flex shrink-0 items-center justify-center" style={{padding: '6px 10px', borderRadius: 5, fontSize: 12, fontWeight: 500, background: active ? color.blue : color.fillControl}}>{label}</div>;

const RecordingPortrait = ({effect}: {effect: number}) => <svg data-recording-portrait width="100%" height="100%" viewBox="0 0 147 181" preserveAspectRatio="xMidYMid slice" style={{filter: `brightness(${1 + effect * .16})`}}><rect width="147" height="181" fill="#9eafbc" /><circle cx="74" cy="65" r="31" fill="#debda5" /><g opacity={1 - effect * .8}>{[[61, 69], [84, 69], [86, 72], [60, 73]].map(([x, y]) => <circle key={`${x}-${y}`} cx={x} cy={y} r="1.2" fill="#ae7d65" />)}</g><path d="M41 55 Q41 13 75 24 Q112 22 105 60 L92 48 L51 50Z" fill="#383d46" /><path d="M17 181 Q18 111 74 109 Q130 111 132 181Z" fill="#465887" /></svg>;

export const RecordingStudioTour = ({frame}: {frame: number}) => {
  const state = recordingTourState(frame);
  const inspector = state.phase === 'export' ? 'ai' : state.phase;
  const caption = state.captionEdited ? 'Your work, always within reach.' : 'Appears when you need it.';
  if (state.phase === 'capture') return <div data-recording-phase="capture" className="absolute inset-0" style={{padding: 20}}>
    <div className="relative" style={{height: '100%', borderRadius: 12, overflow: 'hidden', background: 'linear-gradient(135deg, #1c3357, #31273f)'}}>
      <div className="absolute" style={{left: 124, top: 62, width: 510, height: 240, padding: 30, borderRadius: 12, background: '#20242b'}}><div style={{fontSize: 18, color: color.secondary}}>Product walkthrough</div><div style={{fontSize: 32, fontWeight: 600, marginTop: 28}}>Bring your tools closer.</div><div style={{fontSize: 18, color: color.secondary, marginTop: 20}}>Capture once. Continue in the studio.</div></div>
      {state.camera ? <div className="absolute" style={{right: 64, top: 79, width: 147, height: 147, borderRadius: 14, overflow: 'hidden', border: `2px solid ${color.strokeCard}`, background: '#a2b8c7'}}><RecordingPortrait effect={state.portrait} /></div> : null}
      {state.portraitMenu ? <div data-capture-portrait-menu className="absolute" style={{right: 235, bottom: 87, width: 252, padding: 14, borderRadius: 10, background: '#303640', border: `1px solid ${color.strokeCard}`, boxShadow: '0 12px 35px #0007'}}><div style={{fontSize: 15, fontWeight: 600, marginBottom: 7}}>Portrait and voice effects</div>{[['Skin smoothing', 35], ['Brighten', 16], ['Slim face', 8], ['Slim body', 5]].map(([label, maximum]) => <div key={label} className="flex items-center gap-[10px]" style={{height: 28, fontSize: 11}}><span style={{width: 90, color: color.secondary}}>{label}</span><div className="flex-1"><ProgressTrack value={state.portrait * Number(maximum) / 100} tint={color.blue} width="100%" height={3} /></div><span className="font-mono" style={{width: 25}}>{Math.round(state.portrait * Number(maximum))}%</span></div>)}<StudioField label="Voice" value={state.portrait === 1 ? 'Natural' : 'Original'} /><StudioField label="Amount" value="50%" /><div style={{fontSize: 11, color: color.green, marginTop: 8}}>{state.portrait === 1 ? 'Effects ready for this capture' : 'Adjust the capture preview'}</div></div> : null}
      <div className="absolute flex items-center justify-center gap-[11px]" style={{left: 143, right: 143, bottom: 30, height: 45, padding: '0 12px', borderRadius: 10, background: '#292c33', border: `1px solid ${color.strokeCard}`, boxShadow: '0 10px 25px #0006', fontSize: 12}}><GripVertical size={17} color={color.secondary} /><X size={15} color={color.secondary} />
        {state.recording || state.paused ? <><div className="flex items-center gap-[8px]" style={{color: color.red}}><Circle size={13} fill={color.red} /><span className="font-mono">{formatTime(state.captureTime)}</span></div><span style={{color: color.secondary}}>{state.paused ? 'Paused' : 'Recording'}</span><div className="flex-1" /><Pause size={17} /><Square size={16} fill="white" /></> : state.captured ? <><Check size={17} color={color.green} />Recording saved · Product walkthrough<div className="flex-1" /><StudioAction label="Open studio" active /></> : <><Monitor size={17} color={color.blue} /><span style={{color: color.blue}}>Display</span><Video size={16} /><span>Window</span><SquareDashed size={16} /><span>Region</span><span style={{width: 1, height: 21, background: color.divider}} /><Volume2 size={16} color={color.blue} /><Mic size={16} color={color.blue} /><Video size={16} color={state.camera ? color.blue : color.secondary} /><PersonStanding size={16} color={state.portraitMenu ? color.blue : color.secondary} /><div className="flex-1" /><Circle size={20} fill={color.red} color={color.red} /></>}
      </div>
      <div className="absolute" style={{left: 30, top: 22, fontSize: 16, color: color.secondary}}>Screen capture</div>
    </div>
  </div>;
  return <div data-recording-phase={state.phase} data-playback-time={state.playbackTime} className="absolute inset-0 flex flex-col">
    <div className="flex shrink-0 items-center gap-[14px]" style={{height: 48, padding: '0 16px', borderBottom: `1px solid ${color.divider}`}}><Video size={19} color={color.secondary} /><div style={{fontSize: 16, fontWeight: 600}}>Screen recording studio<span style={{fontSize: 11, color: color.secondary, marginLeft: 12, fontWeight: 400}}>Product walkthrough</span></div><StudioAction label="Project" /><div className="flex-1" /><Undo2 size={15} color={color.secondary} /><Redo2 size={15} color={color.secondary} /><StudioAction label="Export recording" active={state.phase === 'export'} /></div>
    <div className="flex min-h-0 flex-1">
      <div data-studio-library className="flex shrink-0 flex-col" style={{width: 176, padding: 13, gap: 11, borderRight: `1px solid ${color.divider}`}}><div style={{fontSize: 13, fontWeight: 600}}>Media library</div><StudioAction label="Import media" />{([['Screen + Camera', '24 seconds', Video], ['Interview.wav', '24 seconds', AudioLines], ['Cover.png', '1200 × 1200', ImageIcon]] as const).map(([name, detail, Icon]) => <div key={name} style={{padding: 10, borderRadius: 7, background: white(.05)}}><div className="flex items-center gap-[7px]" style={{fontSize: 11}}><Icon size={16} color={color.secondary} />{name}</div><div style={{fontSize: 10, color: color.secondary, marginTop: 6}}>{detail}</div></div>)}<div className="mt-auto flex items-center gap-[7px]" style={{fontSize: 11, color: color.secondary}}><Trash2 size={13} />Removed media</div></div>
      <div className="flex min-w-0 flex-1 flex-col" style={{padding: 12, gap: 8}}>
        <div data-studio-preview className="relative min-h-0 flex-1 overflow-hidden" style={{borderRadius: 9, background: '#080a10'}}><div className="absolute inset-[12px]" style={{borderRadius: 8, overflow: 'hidden', background: 'linear-gradient(135deg, #1d365b, #382640)', transform: `scale(${state.zoom})`, opacity: state.phase === 'clip' && state.frame >= 236 ? state.animation : 1}}><div className="absolute flex items-center gap-[13px]" style={{left: '14%', right: '14%', top: '24%', height: 69, padding: 15, background: 'rgba(0,0,0,.84)', borderRadius: '0 0 21px 21px'}}><AlbumArt size={38} radius={6} /><div><div style={{fontSize: 22, fontWeight: 600}}>zisla</div><div style={{fontSize: 12, color: color.secondary, marginTop: 3}}>Always within reach.</div></div></div><div data-preview-cursor-trail style={{position: 'absolute', left: '36%', top: 'calc(63% + 5px)', width: `${2 + state.playbackTime * 1.5}%`, height: 3, borderRadius: 2, background: color.cyan, opacity: state.frame >= 294 ? .65 : 0}} /><MousePointer2 size={18} fill="white" stroke="#000" strokeWidth={1.1} style={{position: 'absolute', left: `${38 + state.playbackTime * 1.5}%`, top: '63%'}} />{state.camera ? <div data-preview-camera style={{position: 'absolute', right: 12, top: 12, width: 57, height: 57, borderRadius: 8, overflow: 'hidden', border: `1px solid ${color.strokeCard}`}}><RecordingPortrait effect={state.portrait} /></div> : null}{state.captions ? <div data-studio-caption style={{position: 'absolute', left: 22, right: 22, bottom: 12, textAlign: 'center', fontSize: 14, padding: 6, borderRadius: 4, background: '#000b'}}>{caption}</div> : null}</div></div>
        <div className="flex shrink-0 items-center gap-[9px]" style={{height: 26, fontSize: 11}}>{state.exported ? <Play size={16} fill="white" /> : <Pause size={16} />}<div className="min-w-0 flex-1"><ProgressTrack value={state.playbackTime / state.playbackDuration} width="100%" height={3} tint={color.blue} /></div><span className="shrink-0 font-mono">{formatTime(state.playbackTime)} / {formatTime(state.playbackDuration)}</span><span className="shrink-0">16:9</span><ChevronDown size={11} /></div>
        <div data-studio-timeline className="relative shrink-0" style={{height: 138, borderTop: `1px solid ${color.divider}`, paddingTop: 5}}><div className="flex items-center gap-[8px]" style={{height: 23, fontSize: 11, color: color.secondary}}>Timeline<Layers size={12} /><Scissors size={12} /><div className="flex-1" />Snap to playhead</div>
          {[['Screen', color.blue, state.trim], ['Audio', color.green, 1], ['Image', color.purple, 1], ['Text', color.orange, state.captions ? 1 : 0]].map(([name, tint, progress], index) => <div key={String(name)} className="flex items-center gap-[8px]" style={{height: 25}}><span style={{width: 42, fontSize: 10, color: color.secondary}}>{String(name)}</span><div className="relative flex-1" style={{height: 19, borderRadius: 4, background: white(.035)}}><div style={{position: 'absolute', left: index === 2 ? '40%' : index === 3 ? '23%' : '0%', width: index === 2 ? '20%' : index === 3 ? '56%' : `${100 - Number(progress) * 4}%`, height: 19, borderRadius: 4, background: `color-mix(in srgb, ${String(tint)} 36%, transparent)`, border: `1px solid ${String(tint)}`, opacity: index === 3 && !state.captions ? 0 : 1}} /></div></div>)}
          <div data-studio-playhead style={{position: 'absolute', left: `calc(50px + (100% - 50px) * ${state.playbackTime / state.playbackDuration})`, top: 26, bottom: 0, width: 1.5, background: '#fff'}} />
        </div>
      </div>
      <div data-studio-inspector className="flex shrink-0 flex-col" style={{width: 285, padding: 13, gap: 12, borderLeft: `1px solid ${color.divider}`, background: white(.035)}}><div className="flex shrink-0 items-center justify-around" style={{height: 29, borderRadius: 5, background: white(.045)}}>{([['clip', Scissors], ['effects', ZoomIn], ['captions', Captions], ['ai', Sparkles]] as const).map(([id, Icon]) => <div key={id} style={{padding: '4px 12px', borderRadius: 4, color: inspector === id ? color.blue : color.secondary, background: inspector === id ? white(.12) : 'transparent'}}><Icon size={16} /></div>)}</div>
        {state.phase === 'clip' ? <><div style={{fontSize: 16, fontWeight: 600}}>Clip · Screen + Camera</div><StudioField label="Source start" value={`${Math.round(state.trim * 5)} seconds`} /><StudioField label="Source end" value={`${24 - Math.round(state.trim * 3)} seconds`} /><StudioField label="Playback speed" value="1×" /><StudioField label="Entrance animation" value={state.frame >= 234 ? 'Fade · 0.5s' : 'None'} /><div className="flex gap-[7px]"><StudioAction label="Split" /><StudioAction label="Copy" /><StudioAction label="Paste" /></div><div style={{fontSize: 12, color: state.trim === 1 ? color.green : color.secondary}}>{state.animation === 1 ? 'Trim and entrance animation applied' : state.trim === 1 ? 'Trimmed · 16-second timeline' : 'Adjust the selected clip'}</div></> : null}
        {state.phase === 'effects' ? <><div style={{fontSize: 16, fontWeight: 600}}>Canvas and manual zoom</div><StudioField label="Canvas ratio" value="16:9" /><StudioField label="Zoom starts" value="0:03" /><StudioField label="Duration" value="2 seconds" /><StudioField label="Scale" value={`${Math.round(state.zoom * 100)}%`} /><div className="flex items-center gap-[7px]" style={{fontSize: 12}}><Check size={14} color={color.blue} />Cursor trail · Custom color</div><div style={{fontSize: 12, color: state.zoom === 1.2 ? color.green : color.secondary}}>{state.zoom === 1.2 ? 'Zoom applied in the preview' : 'Focus on the selected detail'}</div></> : null}
        {state.phase === 'captions' ? <><div style={{fontSize: 16, fontWeight: 600}}>Generate captions</div><StudioField label="Language" value="English" /><div className="flex gap-[7px]"><StudioAction label={state.captions ? 'Generate captions' : state.frame >= 366 ? 'Transcribing…' : 'Generate captions'} active={!state.captions} /><StudioAction label="Export SRT" /></div><div style={{fontSize: 12, color: color.secondary}}>0:03 — 0:12</div><div data-caption-editor style={{padding: 11, minHeight: 74, background: color.fillControl, borderRadius: 6, fontSize: 14, lineHeight: '20px'}}>{state.captions ? caption : 'Waiting for transcription'}</div><div style={{fontSize: 12, color: state.captionEdited ? color.green : color.secondary}}>{state.captionEdited ? 'Caption edited · Preview updated' : state.captions ? 'Caption added to the Text track' : 'Generate captions from the recording'}</div></> : null}
        {inspector === 'ai' ? <><div style={{fontSize: 16, fontWeight: 600}}>AI edit</div><StudioField label="Model" value="Demo model" /><div style={{padding: 10, borderRadius: 6, minHeight: 63, lineHeight: '19px', fontSize: 13, background: color.fillControl}}>Keep the opening and the product reveal. Make it 12 seconds.</div><StudioAction label={state.frame >= 464 && !state.proposal ? 'Generating…' : 'Generate proposal'} active={!state.proposal} />{state.proposal ? <div data-recording-proposal style={{padding: 11, height: 114, borderRadius: 7, background: white(.055)}}><div style={{fontSize: 13, fontWeight: 600}}>Proposal preview</div><div style={{fontSize: 12, marginTop: 8}}>Output 0:12 · 2 clips · 1 zoom · 1 caption</div><div className="flex gap-[7px]" style={{marginTop: 11}}><StudioAction label="Apply proposal" active={!state.applied} /><StudioAction label="Discard" /></div></div> : null}{state.applied ? <div style={{fontSize: 12, color: color.green}}>Proposal applied · Timeline is 12 seconds</div> : null}</> : null}

      </div>
    </div>
    {state.phase === 'export' && !state.exported ? <div data-recording-export-panel className="absolute" style={{left: '50%', top: 61, translate: '-50% 0', width: 438, padding: 18, borderRadius: 12, background: '#2d333c', border: `1px solid ${color.strokeCard}`, boxShadow: '0 18px 55px #000b'}}><div style={{fontSize: 16, fontWeight: 600, marginBottom: 14}}>Export recording</div><StudioField label="Save as" value="Product walkthrough.mp4" /><div className="flex gap-[6px]" style={{fontSize: 11, marginTop: 9, marginBottom: 10}}><StudioAction label="Video" active /><div style={{opacity: .35}}><StudioAction label="Live Photo" /></div><StudioAction label="Audio only" /></div><div style={{fontSize: 11, color: color.secondary, marginBottom: 8}}>Live Photo supports timelines up to 3 seconds.</div><StudioField label="Format" value="MP4" /><StudioField label="Resolution" value="1080p" /><StudioField label="Frame rate" value="60 FPS" /><div style={{fontSize: 11, color: color.secondary, margin: '8px 0 12px'}}>Video / GIF · M4A / MP3 / WAV / FLAC</div>{state.exporting ? <><ProgressTrack value={(state.frame - 600) / 54} tint={color.blue} width="100%" /><div style={{fontSize: 12, color: color.secondary, marginTop: 8}}>Exporting recording…</div></> : <div className="flex justify-end gap-[8px]"><StudioAction label="Cancel" /><StudioAction label="Export recording" active /></div>}</div> : null}
    {state.exported ? <div data-recording-output className="absolute flex items-center gap-[9px]" style={{left: 340, top: 64, padding: '12px 16px', borderRadius: 9, background: '#28332f', border: `1px solid ${color.strokeCard}`, boxShadow: '0 10px 28px #0008', color: color.green, fontSize: 14}}><Check size={18} /><span>Product walkthrough.mp4<br /><span style={{fontSize: 12}}>Exported · 12 seconds</span></span></div> : null}
  </div>;
};

export const ImagesModule = ({progress = 1}: {progress?: number}) => {
  const completed = clamp01(progress);
  return (
    <div className="absolute inset-0 flex flex-col" style={{padding: 20}}>
      <ToolHeader icon={ImageIcon} title="Image tools" detail="Compress · Resize · Convert" />
      <div className="flex min-h-0 flex-1 items-center justify-center gap-[16px]" style={{marginBottom: 18, borderRadius: 12, background: white(0.045)}}>
        <div className="flex flex-col items-center gap-[12px]">
          <AlbumArt size={124} radius={8} />
          <div className="tabular" style={{fontSize: 13, color: color.secondary}}>{toolDemo.image.sourceSize}</div>
        </div>
        <ArrowRight size={20} color={color.secondary} />
        <div className="flex flex-col items-center gap-[12px]" style={{opacity: 0.3 + completed * 0.7}}>
          <AlbumArt size={82} radius={6} />
          <div className="tabular" style={{fontSize: 13, color: color.secondary}}>{toolDemo.image.outputSize}</div>
        </div>
      </div>
      <div style={{fontSize: 15, fontWeight: 500}}>{toolDemo.image.input} <span style={{color: color.secondary}}>→</span> {toolDemo.image.output}</div>
      <div style={{marginTop: 14}}><ProgressTrack value={completed} tint={color.blue} width="100%" height={4} /></div>
      <div className="flex items-center gap-[7px]" style={{marginTop: 14, fontSize: 16, color: completed === 1 ? color.green : color.secondary}}>
        {completed === 1 ? <Check size={17} /> : <Crop size={17} />}
        {completed === 1 ? 'Resized and converted' : 'Processing image'}
      </div>
    </div>
  );
};

export const AudioModule = ({frame, progress = 1}: {frame: number; progress?: number}) => {
  const completed = clamp01(progress);
  const levels = Array.from({length: 6}, (_, seed) => waveLevels(frame, 0.85, seed)).flat();
  return (
    <div className="absolute inset-0 flex flex-col" style={{padding: 20}}>
      <ToolHeader icon={AudioLines} title="Audio tools" detail="Trim · Denoise · Normalize" />
      <div className="relative flex min-h-0 flex-1 flex-col justify-center" style={{marginBottom: 18, padding: '18px 14px', borderRadius: 12, background: white(0.045)}}>
        <div style={{fontSize: 16, fontWeight: 500}}>{toolDemo.audio.input}</div>
        <div className="relative flex items-center gap-[3px]" style={{height: 94, marginTop: 14}}>
          {levels.map((level, index) => <div key={index} style={{flex: 1, height: 5 + level * 67, borderRadius: 2, background: index < 7 || index > 35 ? white(0.2) : color.cyan}} />)}
          <div className="absolute top-0 bottom-0" style={{left: '17%', right: '15%', border: `1px solid ${color.cyan}`, borderRadius: 5, background: 'rgba(100,210,255,0.07)'}}>
            <div className="absolute left-[-2px] top-0 bottom-0" style={{width: 4, borderRadius: 2, background: color.cyan}} />
            <div className="absolute right-[-2px] top-0 bottom-0" style={{width: 4, borderRadius: 2, background: color.cyan}} />
          </div>
        </div>
        <div className="flex justify-between font-mono tabular" style={{marginTop: 12, fontSize: 14, color: color.secondary}}><span>{formatTime(toolDemo.audio.start)}</span><span>{formatTime(toolDemo.audio.end)}</span></div>
      </div>
      <div style={{fontSize: 15, color: color.secondary}}>WAV · {toolDemo.audio.sampleRate}</div>
      <div style={{marginTop: 14}}><ProgressTrack value={completed} tint={color.cyan} width="100%" height={4} /></div>
      <div className="flex items-center gap-[7px]" style={{marginTop: 14, fontSize: 16, color: completed === 1 ? color.green : color.secondary}}>
        {completed === 1 ? <Check size={17} /> : <AudioLines size={17} />}
        {completed === 1 ? 'Audio processed' : 'Processing audio'}
      </div>
    </div>
  );
};

export const PDFModule = ({progress = 1}: {progress?: number}) => {
  const completed = clamp01(progress);
  return (
    <div className="absolute inset-0 flex flex-col" style={{padding: 20}}>
      <ToolHeader icon={FileText} title="PDF tools" detail="Merge · Split · Export text" />
      <div className="relative min-h-0 flex-1" style={{marginBottom: 18, borderRadius: 12, background: white(0.045)}}>
        {[2, 1, 0].map((index) => (
          <div key={index} className="absolute" style={{left: 57 + index * (20 - completed * 12), top: 22 + index * (13 - completed * 8), width: 174, height: 166, padding: '18px 16px', borderRadius: 7, background: '#ececf0', boxShadow: '0 5px 15px rgba(0,0,0,0.28)', color: '#242630', transform: `rotate(${index * (5 - completed * 3)}deg)`}}>
            <div style={{fontSize: 14, fontWeight: 700}}>Launch brief</div>
            <div style={{height: 2, background: '#a0a5b1', marginTop: 11}} />
            {[0.9, 0.74, 0.86, 0.63, 0.9].map((width, line) => <div key={line} style={{width: `${width * 100}%`, height: 3, marginTop: 9, borderRadius: 1, background: '#c0c3cc'}} />)}
            <div className="absolute bottom-[13px] right-[16px] font-mono" style={{fontSize: 10, color: '#757b88'}}>0{index + 1}</div>
          </div>
        ))}
      </div>
      <div style={{fontSize: 15, fontWeight: 500}}>{completed === 1 ? toolDemo.pdf.output : toolDemo.pdf.inputs.join(' + ')}</div>
      <div style={{marginTop: 14}}><ProgressTrack value={completed} tint={color.purple} width="100%" height={4} /></div>
      <div className="flex items-center gap-[7px]" style={{marginTop: 14, fontSize: 16, color: completed === 1 ? color.green : color.secondary}}>
        {completed === 1 ? <Check size={17} /> : <FileText size={17} />}
        {completed === 1 ? `Merged · ${toolDemo.pdf.pages} pages` : 'Merging documents'}
      </div>
    </div>
  );
};
