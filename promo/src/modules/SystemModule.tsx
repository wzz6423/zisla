import type {LucideIcon} from 'lucide-react';
import {ArrowDown, ArrowUp, Cpu, Globe, MemoryStick, Microchip} from 'lucide-react';
import {ProgressTrack} from '../components/Glass';
import {monitors} from '../content';
import {clamp01, color, white} from '../theme';

const DEMO = {memoryTotalGB: 32, memoryUsedGB: 14.7, downloadMB: 2.4, uploadKB: 350} as const;

// Simulated readings use film time so a cut cannot restart the history.
export const systemReadingsAt = (frame: number) => ({
  cpu: clamp01(monitors[0].value + Math.sin(frame * 0.014) * 0.025),
  gpu: clamp01(monitors[1].value + Math.sin(frame * 0.011 + 1) * 0.035),
  memoryUsedGB: DEMO.memoryUsedGB,
  memoryTotalGB: DEMO.memoryTotalGB,
  downloadMB: DEMO.downloadMB + Math.sin(frame * 0.009) * 0.15,
  uploadKB: Math.round(DEMO.uploadKB + Math.sin(frame * 0.007) * 24),
});

const ComputeCard = ({icon: Icon, title, usage, frame, seed}: {icon: LucideIcon; title: string; usage: number; frame: number; seed: number}) => {
  const history = Array.from({length: 66}, (_, index) => {
    const historicalFrame = frame - (65 - index) * 16;
    const value = clamp01(usage + 0.06 * Math.sin(historicalFrame * 0.022 + seed) + 0.035 * Math.sin(historicalFrame * 0.071 + seed * 2));
    return `${index * 7.8},${63 - value * 98}`;
  }).join(' ');
  return (
    <div className="flex min-h-0 flex-1 items-center gap-[20px]" style={{padding: '15px 18px', borderRadius: 10, background: color.fillCard, border: `1px solid ${color.strokeCard}`}}>
      <div className="shrink-0" style={{width: 105}}>
        <div className="flex items-center gap-[7px]" style={{fontSize: 17, fontWeight: 600}}><Icon size={17} color={color.secondary} />{title}</div>
        <div className="font-rounded tabular" style={{marginTop: 7, fontSize: 31, lineHeight: '34px', fontWeight: 600}}>{Math.round(usage * 100)}<span style={{fontSize: 19, color: color.secondary}}>%</span></div>
      </div>
      <div className="relative min-w-0 flex-1" style={{height: 64}}>
        <svg width="100%" height="100%" viewBox="0 0 507 64" preserveAspectRatio="none">
          {[21, 42, 63].map((y) => <path key={y} d={`M0 ${y} H507`} stroke={white(0.1)} strokeWidth={0.8} />)}
          <polygon points={`0,64 ${history} 507,64`} fill="rgba(10,132,255,0.09)" />
          <polyline points={history} fill="none" stroke={color.blue} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
        </svg>
      </div>
    </div>
  );
};

export const SystemModule = ({frame}: {frame: number}) => {
  const reading = systemReadingsAt(frame);
  return (
    <div className="absolute inset-0 flex flex-col" style={{padding: 20}}>
      <div className="flex shrink-0 items-center gap-[9px]" style={{marginBottom: 16}}>
        <Cpu size={22} color={color.secondary} />
        <div style={{fontSize: 23, fontWeight: 600, letterSpacing: '-0.02em'}}>System monitor</div>
        <div className="flex-1" />
        <div style={{fontSize: 14, color: color.secondary}}>Real-time performance</div>
      </div>
      <div className="flex min-h-0 flex-1 gap-[14px]">
        <div className="flex min-w-0 flex-[1.4] flex-col gap-[12px]">
          <ComputeCard icon={Cpu} title="CPU" usage={reading.cpu} frame={frame} seed={0} />
          <ComputeCard icon={Microchip} title="GPU" usage={reading.gpu} frame={frame} seed={2} />
        </div>
        <div className="flex min-w-0 flex-1 flex-col gap-[12px]">
          <div className="flex min-h-0 flex-1 flex-col justify-center" style={{padding: '15px 18px', borderRadius: 10, background: color.fillCard, border: `1px solid ${color.strokeCard}`}}>
            <div className="flex items-center gap-[7px]" style={{fontSize: 17, fontWeight: 600}}><MemoryStick size={17} color={color.secondary} />Memory</div>
            <div className="font-rounded tabular" style={{marginTop: 8, marginBottom: 12, fontSize: 27, lineHeight: '30px', fontWeight: 600}}>{reading.memoryUsedGB} <span style={{fontSize: 18, color: color.secondary}}>/ {reading.memoryTotalGB} GB</span></div>
            <ProgressTrack value={reading.memoryUsedGB / reading.memoryTotalGB} tint={color.blue} width="100%" height={5} />
          </div>
          <div className="flex min-h-0 flex-1 flex-col justify-center" style={{padding: '15px 18px', borderRadius: 10, background: color.fillCard, border: `1px solid ${color.strokeCard}`}}>
            <div className="flex items-center gap-[7px]" style={{fontSize: 17, fontWeight: 600}}><Globe size={17} color={color.secondary} />Network</div>
            <div className="flex items-center gap-[22px]" style={{marginTop: 12}}>
              <div className="flex items-center gap-[6px] font-rounded tabular"><ArrowDown size={19} color={color.blue} /><span style={{fontSize: 26, fontWeight: 600}}>{reading.downloadMB.toFixed(1)}</span><span style={{fontSize: 13, color: color.secondary}}>MB/s</span></div>
              <div className="flex items-center gap-[6px] font-rounded tabular"><ArrowUp size={19} color={color.orange} /><span style={{fontSize: 22, fontWeight: 600}}>{reading.uploadKB}</span><span style={{fontSize: 13, color: color.secondary}}>KB/s</span></div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
