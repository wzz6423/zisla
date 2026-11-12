import {ArrowRight, Check, FileText, LockKeyhole, ScanText, Scissors, Volume2} from 'lucide-react';
import {AlbumArt} from '../components/IslandChrome';
import {ProgressTrack, waveLevels} from '../components/Glass';
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
type Operation = readonly [string, string];

export const creativeToolState = (kind: ToolKind, frame: number) => {
  const part = Math.min(kind === 'pdf' ? 1 : 2, Math.max(0, Math.floor(frame / (kind === 'pdf' ? 270 : 180))));
  const local = Math.max(0, frame - part * (kind === 'pdf' ? 270 : 180));
  return {part, progress: clamp01((local - 28) / 68), selected: kind === 'image' ? [2, 7, 8][part] : kind === 'audio' ? [2, 0, 8][part] : [0, 4][part]};
};

const OperationList = ({items, selected}: {items: readonly Operation[]; selected: number}) => (
  <div className="flex shrink-0 flex-col gap-[3px]" style={{width: 214}}>
    {items.map(([id, label], index) => (
      <div key={id} data-operation={id} className="flex items-center" style={{height: 34, padding: '0 10px', borderRadius: 7, fontSize: 13, color: selected === index ? color.blue : white(0.8), background: selected === index ? white(0.1) : 'transparent'}}>
        {label}
      </div>
    ))}
  </div>
);

const Paper = ({index, progress = 1}: {index: number; progress?: number}) => (
  <div className="absolute" style={{left: 105 + index * (40 - progress * 28), top: 28 + index * (16 - progress * 9), width: 185, height: 234, padding: 20, borderRadius: 8, background: '#ececf0', color: '#232732', boxShadow: '0 8px 24px rgba(0,0,0,.3)', transform: `rotate(${index * (6 - progress * 4)}deg)`}}>
    <div style={{fontSize: 16, fontWeight: 700}}>Launch brief</div>
    {[.9, .72, .83, .66, .91, .74, .88, .51].map((length, line) => <div key={line} style={{width: `${length * 100}%`, height: 3, marginTop: 15, background: '#b1b7c2'}} />)}
    <div className="absolute bottom-[16px] right-[18px] font-mono" style={{fontSize: 12}}>0{index + 1}</div>
  </div>
);

const ProductArt = ({extracted = false}: {extracted?: boolean}) => (
  <div style={{width: 166, height: 166, borderRadius: 10, overflow: 'hidden', background: extracted ? 'repeating-conic-gradient(#555962 0% 25%, #32363e 0% 50%) 0 / 20px 20px' : '#cde7df'}}>
    <svg width="166" height="166" viewBox="0 0 166 166">
      {!extracted ? <><circle cx="38" cy="38" r="46" fill="#f9e8ba" /><ellipse cx="83" cy="142" rx="43" ry="8" fill="#7fafa2" opacity=".5" /></> : null}
      <path d="M62 66 Q60 56 70 52 L70 37 L96 37 L96 52 Q106 56 104 66 L104 127 Q103 138 94 139 L72 139 Q62 138 62 127 Z" fill="#e89568" />
      <rect x="70" y="29" width="26" height="13" rx="3" fill="#304a46" /><rect x="62" y="76" width="42" height="39" fill="#fff5dc" />
      <text x="83" y="94" textAnchor="middle" fill="#456158" fontSize="9" fontWeight="700">STUDIO</text><text x="83" y="105" textAnchor="middle" fill="#456158" fontSize="7">DAILY</text>
    </svg>
  </div>
);

const TablePreview = ({recognized = false}: {recognized?: boolean}) => (
  <div style={{width: 184, height: 166, padding: 14, borderRadius: 9, background: recognized ? '#f3faf6' : '#f2efe9', color: '#304238'}}>
    <div style={{fontSize: 14, fontWeight: 600, marginBottom: 13}}>{recognized ? 'Recognized table.xlsx' : 'Review schedule.png'}</div>
    <div style={{display: 'grid', gridTemplateColumns: '1.2fr 1fr', fontSize: 12, lineHeight: '27px', border: '1px solid #bccbc2'}}>{['Task', 'Due', 'Notes', '10:30', 'Review', '11:00'].map((text, index) => <div key={index} style={{padding: '0 6px', borderBottom: index < 4 ? '1px solid #bccbc2' : undefined, background: recognized && index < 2 ? '#c5e3d0' : 'transparent'}}>{text}</div>)}</div>
  </div>
);

const Preview = ({kind, part, frame, progress}: {kind: ToolKind; part: number; frame: number; progress: number}) => {
  if (kind === 'image') return (
    <div className="flex h-full flex-col items-center justify-center gap-[16px]">
      <div className="relative flex items-center gap-[20px]">
        {part === 0 ? <AlbumArt size={166} radius={12} /> : part === 1 ? <TablePreview /> : <ProductArt />}<ArrowRight size={22} color={color.secondary} />
        <div style={{opacity: progress}}>
          {part === 0 ? <AlbumArt size={115} radius={9} /> : part === 1 ? <TablePreview recognized /> : <ProductArt extracted />}
        </div>
      </div>
      <div className="font-mono" style={{fontSize: 13, color: color.secondary}}>{part === 0 ? '2400 × 2400 → 1200 × 1200' : part === 1 ? 'Recognized locally → Text / .xlsx' : 'Foreground → Transparent PNG'}</div>
    </div>
  );
  if (kind === 'audio') return (
    <div className="flex h-full flex-col justify-center" style={{padding: 22}}>
      <div className="flex items-center gap-[9px]" style={{fontSize: 17}}><Volume2 size={20} />Interview.wav</div>
      {[0, 1].map((channel) => <div key={channel} className="relative flex items-center gap-[3px]" style={{height: 78, marginTop: 15, borderRadius: 8, background: white(.035), padding: 10}}>
        {Array.from({length: 7}, (_, seed) => waveLevels(frame, 1, seed + channel)).flat().map((level, index) => <div key={index} style={{flex: 1, height: 4 + level * (part === 1 ? 42 : 54), background: part === 0 && (index < 7 || index > 40) ? white(.2) : color.cyan, borderRadius: 2}} />)}
        {part === 0 ? <div className="absolute top-0 bottom-0" style={{left: '16%', right: '15%', border: `1px solid ${color.cyan}`, borderRadius: 7, background: 'rgba(100,210,255,.07)'}} /> : null}
      </div>)}
      <div className="flex justify-between font-mono" style={{marginTop: 16, fontSize: 13, color: color.secondary}}><span>{part === 0 ? '00:05' : '48 kHz · Stereo'}</span><span>{part === 0 ? '00:28' : part === 1 ? 'Target: −16 LUFS' : 'Test tone: 440 Hz'}</span></div>
    </div>
  );
  return <div className="relative h-full">{[2, 1, 0].map((index) => <Paper key={index} index={index} progress={progress} />)}{part === 1 && progress > .7 ? <LockKeyhole className="absolute" size={34} color={color.blue} style={{right: 48, bottom: 30}} /> : null}</div>;
};

export const CreativeToolsModule = ({kind, frame}: {kind: ToolKind; frame: number}) => {
  const {part, progress, selected} = creativeToolState(kind, frame);
  const items = kind === 'image' ? imageOperations : kind === 'audio' ? audioOperations.slice(part * 9, part * 9 + 9) : pdfOperations.slice(part * 7, part * 7 + 7);
  const selectedLabel = items[selected][1];
  const output = kind === 'image' ? ['Cover.webp', 'Recognized table.xlsx', 'Subject.png'][part] : kind === 'audio' ? ['Interview-trimmed.wav', 'Interview-normalized.wav', 'Test-tone.wav'][part] : ['Launch brief.pdf', 'Launch brief-protected.pdf'][part];
  const Icon = kind === 'image' ? ScanText : kind === 'audio' ? Scissors : FileText;
  return (
    <div className="absolute inset-0 flex gap-[20px]" style={{padding: 20}}>
      <OperationList items={items} selected={selected} />
      <div className="flex min-w-0 flex-1 flex-col gap-[14px]">
        <div className="flex items-center gap-[9px]" style={{fontSize: 19, fontWeight: 600}}><Icon size={20} color={color.secondary} />{selectedLabel}</div>
        <div className="relative min-h-0 flex-1" style={{borderRadius: 12, background: white(.035), border: `1px solid ${color.strokeCard}`}}><Preview kind={kind} part={part} frame={frame} progress={progress} /></div>
        <div className="flex items-center gap-[12px]" style={{fontSize: 13, color: color.secondary}}><span>{kind === 'image' ? 'PNG · JPEG · WebP · AVIF · JPEG XL' : kind === 'audio' ? 'WAV · MP3 · M4A · FLAC · Opus' : 'Local PDF processing'}</span><div className="flex-1" /><span>Save to: {kind === 'pdf' ? 'Documents' : 'Media'}</span></div>
      </div>
      <div className="flex shrink-0 flex-col" style={{width: 248, paddingLeft: 16, borderLeft: `1px solid ${color.divider}`}}>
        <div style={{fontSize: 16, fontWeight: 600, marginBottom: 18}}>Output settings</div>
        {(kind === 'image' ? [['Quality', '80%'], ['Resize', 'Fit bounds'], ['Width', '1200 px'], ['Height', '1200 px'], ['Metadata', 'Remove'], ['Extraction', 'Foreground / background / lasso']] : kind === 'audio' ? [['Format', 'WAV / 24-bit'], ['Sample rate', '48,000 Hz'], ['Channels', 'Stereo'], ['Loudness', '−16 LUFS'], ['Noise reduction', '12 dB'], ['Tags', 'Title / Artist / Album']] : [['Files', 'Brief.pdf + Notes.pdf'], ['Pages', '1–8'], ['Order', 'As selected'], ['Watermark', 'Text / image'], ['Page numbers', 'Bottom center'], ['Password', '••••••••']]).map(([label, value]) => <div key={label} style={{marginBottom: 12}}><div style={{fontSize: 11, color: color.secondary}}>{label}</div><div style={{fontSize: 13, marginTop: 3}}>{value}</div></div>)}
        <div className="mt-auto"><ProgressTrack value={progress} tint={color.blue} width="100%" height={4} /></div>
        <div className="flex items-center gap-[7px]" style={{fontSize: 13, marginTop: 12, color: progress === 1 ? color.green : color.secondary}}>{progress === 1 ? <Check size={16} /> : null}{progress === 1 ? output : 'Processing…'}</div>
      </div>
    </div>
  );
};
