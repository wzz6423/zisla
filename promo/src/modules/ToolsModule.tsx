import type {LucideIcon} from 'lucide-react';
import {
  ArrowRight,
  ArrowUpRight,
  AudioLines,
  Check,
  Circle,
  Crop,
  FileText,
  Image as ImageIcon,
  MousePointer2,
  Pencil,
  Play,
  ScanText,
  Scissors,
  Square,
  Type,
  Video,
} from 'lucide-react';
import {AlbumArt, formatTime} from '../components/IslandChrome';
import {ProgressTrack, waveLevels} from '../components/Glass';
import {clamp01, color, white} from '../theme';
import {FPS} from '../timeline';

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

const CAPTURE_TOOLS = [Square, Circle, Pencil, ArrowUpRight, Type, Crop, ScanText] as const;

export const ScreenshotsModule = ({annotation = 1}: {annotation?: number}) => {
  const progress = clamp01(annotation);
  return (
    <div className="absolute inset-0 flex flex-col" style={{padding: 20}}>
      <ToolHeader icon={Crop} title="Screenshots" detail="Capture · Annotate · Blur · Extract text" />
      <div className="relative min-h-0 flex-1 overflow-hidden" style={{borderRadius: 12, background: white(0.045), border: `1px solid ${color.strokeCard}`}}>
        <div className="absolute inset-[18px]" style={{borderRadius: 8, padding: '18px 22px', background: '#20242b'}}>
          <div style={{fontSize: 13, color: color.secondary}}>{toolDemo.screenshot.title}</div>
          <div style={{marginTop: 18, fontSize: 25, lineHeight: '31px', fontWeight: 600}}>Ship the next idea.</div>
          <div className="flex items-center gap-[9px]" style={{marginTop: 18, fontSize: 17}}>
            <div className="flex items-center justify-center" style={{width: 20, height: 20, borderRadius: 5, background: color.blue}}><Check size={14} /></div>
            {toolDemo.screenshot.text}
          </div>
          <div style={{marginTop: 18, width: 172, color: color.secondary, fontSize: 15, filter: `blur(${progress * 4}px)`}}>launch@studio.test</div>
        </div>
        <svg className="absolute inset-0" width="100%" height="100%" viewBox="0 0 493 244" preserveAspectRatio="none">
          <rect x={39} y={104} width={238} height={41} rx={7} fill="none" stroke={color.blue} strokeWidth={2} opacity={progress} />
          <path d="M382 179 L306 137 M306 137 L312 156 M306 137 L326 132" fill="none" stroke={color.orange} strokeWidth={4} strokeLinecap="round" strokeLinejoin="round" strokeDasharray={122} strokeDashoffset={122 * (1 - progress)} />
        </svg>
      </div>
      <div className="flex shrink-0 items-center justify-between" style={{marginTop: 14}}>
        <div className="flex gap-[6px]">
          {CAPTURE_TOOLS.map((Icon, index) => (
            <div key={index} className="flex items-center justify-center" style={{width: 30, height: 30, borderRadius: 7, background: index === 3 ? white(0.16) : 'transparent'}}>
              <Icon size={17} strokeWidth={2} color={index === 3 ? color.blue : color.secondary} />
            </div>
          ))}
        </div>
        <div style={{fontSize: 14, fontWeight: 500, color: color.secondary}}>Copy · Save</div>
      </div>
    </div>
  );
};

export const ScreenRecordingModule = ({frame}: {frame: number}) => {
  const position = (frame / FPS * 0.2) % toolDemo.recording.duration;
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
        <MousePointer2 size={22} fill="white" stroke="black" strokeWidth={1.2} className="absolute" style={{left: 320 + Math.sin(frame * 0.012) * 8, top: 123}} />
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
