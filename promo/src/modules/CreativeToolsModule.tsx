import {Check, ChevronDown, FileText, Image as ImageIcon, Layers, Scissors, Table2} from 'lucide-react';
import type {ReactNode} from 'react';
import {AlbumArt} from '../components/IslandChrome';
import {ProgressTrack} from '../components/Glass';
import {ease} from '../motion';
import {clamp01, color, white} from '../theme';

export const imageOperations = [
  ['compress', 'Compress images'], ['convert', 'Convert formats'], ['resize', 'Resize and crop'],
  ['smallest', 'Choose smallest format'], ['transform', 'Rotate and flip'], ['watermark', 'Add watermark'],
  ['obscure', 'Mosaic and blur'], ['recognize', 'Text and tables'], ['extract', 'Local extraction'],
] as const;
export const audioOperations = [
  ['convert', 'Convert formats'], ['compress', 'Compress audio'], ['trim', 'Trim audio'],
  ['removeSegment', 'Remove a segment'], ['split', 'Split to files'], ['merge', 'Join audio'],
  ['mix', 'Mix tracks'], ['extract', 'Audio from video'], ['volume', 'Adjust volume'],
  ['normalize', 'Normalize loudness'], ['fade', 'Fade in and out'], ['speed', 'Speed, preserve pitch'],
  ['pitch', 'Pitch, preserve speed'], ['reverse', 'Reverse audio'], ['denoise', 'Reduce noise'],
  ['removeSilence', 'Remove silence'], ['equalizer', 'Equalizer'], ['dynamics', 'Compress and limit'],
  ['echo', 'Add echo'], ['channels', 'Process channels'], ['splitChannels', 'Split channels'],
  ['vocalReduction', 'Reduce centered vocals'], ['metadata', 'Edit audio tags'], ['repeatAudio', 'Repeat audio'],
  ['insertSilence', 'Insert silence'], ['generateSilence', 'Generate silence'], ['generateTone', 'Generate test tone'],
] as const;
export const pdfOperations = [
  ['merge', 'Merge PDFs'], ['split', 'Split pages'], ['rotate', 'Rotate pages'],
  ['imagesToPDF', 'Images to PDF'], ['officeToPDF', 'Office to PDF'], ['render', 'PDF to images'],
  ['extractText', 'Export text'], ['textWatermark', 'Text watermark'], ['imageWatermark', 'Image watermark'],
  ['pageNumbers', 'Page numbers'], ['crop', 'Crop pages'], ['protect', 'Encrypt PDF'],
  ['unlock', 'Remove password'], ['metadata', 'Document metadata'],
] as const;

type ToolKind = 'image' | 'audio' | 'pdf';

export const creativeToolSteps = {
  image: [
    {operation: 'smallest', from: 0, duration: 140, actionAt: 44, completeAt: 86, output: 'Cover.webp'},
    {operation: 'recognize', from: 140, duration: 140, actionAt: 27, completeAt: 65, output: 'Text and table recognized'},
    {operation: 'extract', from: 280, duration: 140, actionAt: 78, completeAt: 106, output: 'Subject.png'},
  ],
  audio: [
    {operation: 'trim', from: 0, duration: 120, actionAt: 40, completeAt: 78, output: 'Interview-trim.wav'},
    {operation: 'normalize', from: 120, duration: 120, actionAt: 32, completeAt: 72, output: 'Interview-normalize.wav'},
    {operation: 'generateTone', from: 240, duration: 120, actionAt: 39, completeAt: 77, output: 'Test-tone.wav'},
  ],
  pdf: [
    {operation: 'merge', from: 0, duration: 150, actionAt: 40, completeAt: 88, output: 'Launch brief.pdf'},
    {operation: 'protect', from: 150, duration: 150, actionAt: 54, completeAt: 98, output: 'Launch brief-protected.pdf'},
  ],
} as const;

export const creativeToolState = (kind: ToolKind, frame: number) => {
  const steps = creativeToolSteps[kind];
  const end = steps.at(-1)!;
  const position = Math.min(end.from + end.duration - 1, Math.max(0, frame));
  const step = steps.find((item) => position >= item.from && position < item.from + item.duration)!;
  const local = position - step.from;
  return {step, frame: local, progress: clamp01((local - step.actionAt) / (step.completeAt - step.actionAt)), busy: local >= step.actionAt && local < step.completeAt, completed: local >= step.completeAt};
};

const WorkspaceAction = ({label, active = false}: {label: string; active?: boolean}) => <div className="flex shrink-0 items-center justify-center" style={{padding: '6px 11px', borderRadius: 6, background: active ? color.blue : color.fillControl, fontSize: 12, fontWeight: 500}}>{label}</div>;
const Field = ({label, value, select = false}: {label: string; value: string; select?: boolean}) => <div className="flex items-center gap-[14px]" style={{fontSize: 13, lineHeight: '18px', height: 30}}><span className="shrink-0" style={{width: 150, color: color.secondary}}>{label}</span><div className="flex min-w-0 flex-1 items-center gap-[8px]" style={{padding: '5px 10px', borderRadius: 5, background: color.fillControl}}><span className="flex-1">{value}</span>{select ? <ChevronDown size={12} color={color.secondary} /> : null}</div></div>;
const Configuration = ({children}: {children: ReactNode}) => <div data-operation-configuration className="flex shrink-0 flex-col gap-[5px]">{children}</div>;

export const operationWindow = (kind: ToolKind, frame: number) => {
  if (kind === 'audio') {
    const top = frame < 240 ? ease(frame, [96, 116], [0, 2]) + ease(frame, [120, 142], [0, 6]) : 18;
    return {first: Math.floor(top), offset: -(top - Math.floor(top)) * 38, rowHeight: 38, height: 342};
  }
  if (kind === 'pdf') {
    const top = frame < 150 ? 0 : 5;
    return {first: top, offset: 0, rowHeight: 36, height: 324};
  }
  return {first: 0, offset: 0, rowHeight: 36, height: 324};
};

const OperationList = ({kind, frame, selected}: {kind: ToolKind; frame: number; selected: string}) => {
  const list = kind === 'image' ? imageOperations : kind === 'audio' ? audioOperations : pdfOperations;
  const window = operationWindow(kind, frame);
  return <div data-native-operation-list className="relative shrink-0" style={{width: kind === 'audio' ? 184 : 176, height: window.height, overflow: 'hidden'}}><div style={{translate: `0 ${window.offset}px`}}>
    {list.slice(window.first, window.first + 10).map(([id, label]) => <div key={id} data-operation={id} data-selected={selected === id} className="flex items-center gap-[8px]" style={{height: window.rowHeight, padding: '0 8px', borderRadius: 6, fontSize: 12, lineHeight: '15px', color: selected === id ? color.blue : white(.8), background: selected === id ? white(.1) : 'transparent'}}><div className="shrink-0" style={{width: 14}}>{selected === id ? <Check size={13} /> : null}</div>{label}</div>)}
  </div>{kind !== 'image' ? <div style={{position: 'absolute', right: 0, top: kind === 'audio' ? window.first / 18 * 242 : window.first / 5 * 228, height: 78, width: 3, background: white(.22), borderRadius: 2}} /> : null}</div>;
};

const WorkspaceInput = ({title, detail, children}: {title: string; detail: string; children?: ReactNode}) => <div data-native-input className="flex shrink-0 items-center gap-[14px]" style={{padding: 12, borderRadius: 10, background: white(.035), border: `1px solid ${color.strokeCard}`}}>{children}<div className="min-w-0 flex-1"><div style={{fontSize: 14, lineHeight: '18px', fontWeight: 500}}>{title}</div><div style={{fontSize: 12, lineHeight: '18px', color: color.secondary, marginTop: 4}}>{detail}</div></div><WorkspaceAction label="Choose files" /></div>;

const ProcessingFooter = ({state, action, children}: {state: ReturnType<typeof creativeToolState>; action: string; children?: ReactNode}) => <div className="mt-auto shrink-0"><div className="flex items-center gap-[12px]">{state.busy ? <div className="flex min-w-0 flex-1 items-center gap-[12px]"><div className="flex-1"><ProgressTrack value={state.progress} tint={color.blue} width="100%" /></div><span style={{fontSize: 12, color: color.secondary}}>Processing…</span></div> : state.completed ? <div data-creative-output className="flex flex-1 items-center gap-[7px]" style={{fontSize: 13, color: color.green}}><Check size={16} />{state.step.output}</div> : <div className="flex-1" />}<WorkspaceAction label={state.busy ? 'Cancel' : action} active={!state.busy} /></div>{state.completed && children ? <div className="flex gap-[8px]" style={{marginTop: 10}}>{children}</div> : null}</div>;

const ImageTour = ({state}: {state: ReturnType<typeof creativeToolState>}) => {
  const operation = state.step.operation;
  const lasso = operation === 'extract' && state.frame >= 27 && state.frame < 104;
  return <>
    <WorkspaceInput title={operation === 'smallest' ? 'Cover.png' : operation === 'recognize' ? 'Review schedule.png' : 'Product.png'} detail={operation === 'smallest' ? '2400 × 2400 · 1.8 MB' : operation === 'recognize' ? '800 × 600 · PNG' : '1200 × 1200 · PNG'}>{operation === 'smallest' ? <AlbumArt size={46} radius={6} /> : operation === 'recognize' ? <Table2 size={34} color={color.secondary} /> : <ImageIcon size={34} color={color.secondary} />}</WorkspaceInput>
    <Configuration>
      {operation === 'smallest' ? <><div className="flex gap-[14px]" style={{fontSize: 12, height: 20}}>{['PNG', 'JPEG', 'WebP', 'AVIF', 'JPEG XL'].map((format) => <span key={format} className="flex items-center gap-[5px]"><Check size={13} color={color.blue} />{format}</span>)}</div><Field label="Image quality" value="80" /><Field label="Preserve metadata" value="Off" /><Field label="Transparency fill" value="#FFFFFF" /></> : null}
      {operation === 'recognize' ? <div style={{fontSize: 13, color: color.secondary}}>Recognize text and table structure locally.</div> : null}
      {operation === 'extract' ? <><Field label="Extraction mode" value="Freehand selection" select /><div className="flex items-center gap-[10px]" style={{fontSize: 12}}><span className="flex-1">Product.png</span>{state.completed ? <Check size={14} color={color.green} /> : null}<WorkspaceAction label="Edit" active={lasso} /></div></> : null}
    </Configuration>
    {operation === 'smallest' && state.completed ? <div data-format-results className="shrink-0" style={{padding: 12, borderRadius: 8, background: white(.035)}}><div style={{fontSize: 13, marginBottom: 8}}>Cover.png · 1.8 MB</div>{[['PNG', '1.2 MB'], ['JPEG', '246 KB'], ['WebP', '118 KB'], ['AVIF', '134 KB'], ['JPEG XL', '157 KB']].map(([format, size]) => <div key={format} className="flex items-center gap-[10px]" style={{height: 23, fontSize: 12, color: format === 'WebP' ? color.green : color.secondary}}><span style={{width: 64}}>{format}</span><span>{size}</span>{format === 'WebP' ? <Check size={13} /> : null}<div className="flex-1" /><span>Compare · Export</span></div>)}</div> : null}
    {operation === 'recognize' && state.completed ? <div data-recognized-table className="shrink-0" style={{padding: 15, borderRadius: 8, background: white(.035)}}><div style={{fontSize: 13}}>Review schedule.png</div><div style={{display: 'grid', gridTemplateColumns: '1.3fr 1fr', maxWidth: 330, marginTop: 10, fontSize: 13, lineHeight: '27px'}}>{['Task', 'Due', 'Notes', '10:30', 'Review', '11:00'].map((text, index) => <div key={index} style={{padding: '0 8px', borderBottom: `1px solid ${color.divider}`}}>{text}</div>)}</div></div> : null}
    {operation === 'extract' ? <div data-image-extraction-preview className="shrink-0" style={{height: 114, padding: 12, borderRadius: 8, background: white(.035), display: 'flex', gap: 18, alignItems: 'center'}}><ProductArt extracted={state.completed} /><div style={{fontSize: 13, color: state.completed ? color.green : color.secondary}}>{state.completed ? 'Freehand selection applied · Transparent PNG' : lasso ? 'Outline the object, then apply the edit' : 'Open the image editor for a local selection'}</div></div> : null}
    <ProcessingFooter state={state} action="Start processing">{operation === 'recognize' ? <><WorkspaceAction label="Copy" /><WorkspaceAction label="Export text" /><WorkspaceAction label="Export table" /></> : <><WorkspaceAction label="Export all" />{operation === 'smallest' ? <WorkspaceAction label="Export smallest result" /> : null}<WorkspaceAction label="Export ZIP" /></>}</ProcessingFooter>
    {lasso ? <div data-image-editor className="absolute" style={{left: 0, top: 11, right: 11, bottom: 11, borderRadius: 12, background: '#272d36', border: `1px solid ${color.strokeCard}`, boxShadow: '0 14px 40px #0008', padding: 17}}><div className="flex items-center gap-[9px]" style={{height: 28, fontSize: 15, fontWeight: 600}}><ImageIcon size={17} />Image editor · Product.png<div className="flex-1" /><span style={{fontSize: 11, color: color.secondary}}>1200 × 1200</span></div><div className="flex items-center justify-center" style={{height: 188, background: '#171a20', marginTop: 12, borderRadius: 8}}><svg data-lasso-canvas width="201" height="188" viewBox="0 0 240 224"><rect width="240" height="224" fill="#cde7df" /><circle cx="34" cy="32" r="55" fill="#f9e8ba" /><path d="M88 84 Q84 65 102 61 L102 39 L140 39 L140 61 Q154 64 151 83 L151 178 Q149 194 139 196 L100 196 Q88 194 88 178Z" fill="#e89568" /><rect x="102" y="28" width="38" height="18" rx="4" fill="#304a46" /><rect x="88" y="103" width="63" height="59" fill="#fff5dc" /><path d="M81 73 Q80 51 95 47 L95 21 L146 20 L147 49 Q167 59 162 88 L162 180 Q164 207 135 208 L99 208 Q74 208 76 179 Z" fill="none" stroke={color.blue} strokeWidth="2" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - clamp01((state.frame - 35) / 35)} /></svg></div><div className="flex items-center gap-[8px]" style={{marginTop: 14, fontSize: 12}}><Layers size={16} color={color.secondary} /><span style={{color: color.blue}}>Extraction · Freehand selection</span><div className="flex-1" /><WorkspaceAction label="Copy" /><WorkspaceAction label="Apply edit" active={state.frame >= 72} /></div></div> : null}
  </>;
};

const ProductArt = ({extracted}: {extracted: boolean}) => <div style={{width: 89, height: 89, borderRadius: 6, overflow: 'hidden', background: extracted ? 'repeating-conic-gradient(#555962 0% 25%, #32363e 0% 50%) 0 / 14px 14px' : '#cde7df'}}><svg width="89" height="89" viewBox="0 0 166 166"><path d="M62 66 Q60 56 70 52 L70 37 L96 37 L96 52 Q106 56 104 66 L104 127 Q103 138 94 139 L72 139 Q62 138 62 127Z" fill="#e89568" /><rect x="70" y="29" width="26" height="13" rx="3" fill="#304a46" /><rect x="62" y="76" width="42" height="39" fill="#fff5dc" /></svg></div>;

const AudioTour = ({state}: {state: ReturnType<typeof creativeToolState>}) => {
  const operation = state.step.operation;
  const tone = operation === 'generateTone';
  return <>
    {!tone ? <WorkspaceInput title={operation === 'trim' ? 'Interview.wav' : 'Interview-trim.wav'} detail={operation === 'trim' ? '35.00 seconds · 48000 Hz · 2 channels · PCM' : '23.00 seconds · 48000 Hz · 2 channels · PCM'}><Scissors size={32} color={color.secondary} /></WorkspaceInput> : null}
    <Configuration>{operation === 'trim' ? <><Field label="Start time (seconds)" value={`${Math.round(ease(state.frame, [17, 35], [0, 5]))}`} /><Field label="End time (seconds)" value={`${Math.round(ease(state.frame, [17, 35], [35, 28]))}`} /></> : null}{operation === 'normalize' ? <Field label="Target loudness (LUFS)" value={`${Math.round(ease(state.frame, [15, 29], [-23, -16]))}`} /> : null}{tone ? <><Field label="Duration (seconds)" value="3" /><Field label="Frequency (Hz)" value={`${Math.round(ease(state.frame, [18, 34], [220, 440]))}`} /></> : null}<Field label="Output format" value="WAV" select /><Field label="Bit depth" value="24-bit" select /><Field label="Sample rate" value="48000 Hz" select /><Field label="Channels" value="Stereo" select /></Configuration>
    <ProcessingFooter state={state} action="Export audio"><WorkspaceAction label="Show in Finder" /><WorkspaceAction label="Preview" /></ProcessingFooter>
  </>;
};

const PDFTour = ({state}: {state: ReturnType<typeof creativeToolState>}) => {
  const protect = state.step.operation === 'protect';
  return <>
    <WorkspaceInput title={protect ? 'Launch brief.pdf' : 'Brief.pdf + Notes.pdf'} detail={protect ? '8 pages · PDF' : '2 documents · 8 pages · Selection order'}><FileText size={34} color={color.secondary} /></WorkspaceInput>
    {protect ? <Configuration><Field label="Open password" value={state.frame >= 24 ? '••••••••' : ''} /><Field label="Owner password" value="Optional" /></Configuration> : null}
    <ProcessingFooter state={state} action={protect ? 'Encrypt PDF' : 'Merge PDFs'} />
  </>;
};

export const CreativeToolsModule = ({kind, frame}: {kind: ToolKind; frame: number}) => {
  const state = creativeToolState(kind, frame);
  const list = kind === 'image' ? imageOperations : kind === 'audio' ? audioOperations : pdfOperations;
  const selected = list.find(([id]) => id === state.step.operation)!;
  const detail = kind === 'image' ? state.step.operation === 'smallest' ? 'Compare five formats and export the smallest image.' : state.step.operation === 'recognize' ? 'Recognize locally, then copy or export text and tables.' : 'Extract the foreground, background or a freehand selection.' : kind === 'audio' ? state.step.operation === 'trim' ? 'Keep a selected time range.' : state.step.operation === 'normalize' ? 'Set loudness in LUFS and limit peaks.' : 'Create a sine test tone with a chosen frequency and duration.' : state.step.operation === 'merge' ? 'Merge documents in the selected order.' : 'Protect this PDF with an opening password.';
  const scroll = kind === 'image' && state.step.operation === 'smallest' ? ease(state.frame, [86, 102], [0, 140]) : 0;
  return <div data-tool-workspace={kind} data-current-operation={state.step.operation} className="absolute inset-0 flex gap-[20px]" style={{padding: 20}}><OperationList kind={kind} frame={frame} selected={state.step.operation} /><div data-native-operation-main className="flex min-w-0 flex-1 flex-col gap-[12px]"><div className="shrink-0" style={{height: 48}}><div style={{fontSize: 20, lineHeight: '26px', fontWeight: 600}}>{selected[1]}</div><div style={{fontSize: 12, color: color.secondary, lineHeight: '18px', marginTop: 4}}>{detail}</div></div><div data-native-workspace-scroll className="relative min-h-0 flex-1" style={{overflow: 'hidden'}}><div className="flex h-full flex-col gap-[12px]" style={{translate: `0 ${-scroll}px`}}>{kind === 'image' ? <ImageTour state={state} /> : kind === 'audio' ? <AudioTour state={state} /> : <PDFTour state={state} />}</div></div></div></div>;
};
