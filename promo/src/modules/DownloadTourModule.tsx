import {Check, Clipboard, Download, Folder, Link, LoaderCircle, LockKeyhole, Music, Video} from 'lucide-react';
import {ProgressTrack} from '../components/Glass';
import {clamp01, color, white} from '../theme';

export const downloadPlatforms = [
  ['youtube', 'YouTube'], ['bilibili', 'Bilibili'], ['douyin', 'Douyin'],
  ['xiaohongshu', 'Xiaohongshu'], ['weibo', 'Weibo'], ['tiktok', 'TikTok'], ['instagram', 'Instagram'],
] as const;

export const nativeDownloadAt = (frame: number) => ({
  url: 'https://example.com/interview'.slice(0, Math.floor(clamp01(frame / 26) * 29)),
  mode: frame < 66 ? 'video' : 'audio',
  format: frame < 38 ? 'Reading formats…' : frame < 66 ? '1080p · 60 fps · MP4' : '128 kbps · Opus → M4A',
  phase: frame < 92 ? 'ready' : frame < 152 ? 'downloading' : 'completed',
  progress: clamp01((frame - 92) / 60),
});

export const DownloadTourModule = ({frame}: {frame: number}) => {
  const state = nativeDownloadAt(frame);
  const done = state.phase === 'completed';
  return (
    <div className="absolute inset-0 flex flex-col gap-[22px]" style={{padding: 28}} data-feature="download">
      <div className="flex items-center gap-[12px]" style={{fontSize: 23, fontWeight: 600}}><Download size={24} />Video and audio downloads</div>
      <div className="flex items-center gap-[12px]" style={{height: 52, padding: '0 18px', borderRadius: 9, background: color.fillCard, border: `1px solid ${color.strokeCard}`, fontSize: 18}}><Link size={20} color={color.secondary} /><span>{state.url}</span><div className="flex-1" /><Clipboard size={19} color={color.secondary} /></div>
      <div className="flex items-center gap-[16px]">
        <div className="flex gap-[5px]" style={{padding: 4, borderRadius: 8, background: white(.05)}}>{[['video', 'Video', Video], ['audio', 'Audio', Music]].map(([id, label, Icon]) => {
          const Symbol = Icon as typeof Video;
          return <div key={String(id)} data-download-mode={String(id)} className="flex items-center gap-[8px]" style={{padding: '10px 16px', borderRadius: 6, fontSize: 16, background: state.mode === id ? color.fillControl : 'transparent'}}><Symbol size={17} />{String(label)}</div>;
        })}</div>
        <div style={{padding: '12px 16px', borderRadius: 8, fontSize: 16, background: color.fillControl}}>{state.format}</div>
        <div className="flex-1" />
        <div className="flex items-center gap-[8px]" style={{fontSize: 15}}><LockKeyhole size={17} color={color.secondary} />Chrome · Default cookies</div>
      </div>
      <div className="flex items-center gap-[12px]" style={{fontSize: 17}}><Folder size={20} color={color.cyan} />Downloads<div className="flex-1" /><div data-download-action style={{padding: '10px 20px', borderRadius: 8, background: color.blue}}>{state.phase === 'downloading' ? 'Cancel download' : 'Download'}</div></div>
      <div className="flex min-h-0 flex-1 flex-col justify-center gap-[16px]" style={{padding: 20, borderRadius: 10, background: white(.04)}}>
        <div className="flex items-center gap-[10px]" style={{fontSize: 20, color: done ? color.green : color.label}}>{done ? <Check size={23} /> : state.phase === 'downloading' ? <LoaderCircle size={22} /> : <Download size={22} />}{done ? 'Interview.m4a saved' : state.phase === 'downloading' ? 'Interview · Downloading audio' : 'Choose source formats, then download'}</div>
        <ProgressTrack value={state.progress} tint={done ? color.green : color.blue} width="100%" height={5} />
        <div className="flex justify-between" style={{fontSize: 15, color: color.secondary}}><span>{done ? 'Open in Finder' : `${Math.round(state.progress * 100)}%`}</span><span>{done ? 'Downloads / Interview.m4a' : 'Video or audio · Selected source quality'}</span></div>
      </div>
      <div className="flex justify-between gap-[12px]" style={{fontSize: 13, color: color.secondary}}>{downloadPlatforms.map(([id, label]) => <span key={id} data-platform={id}>{label}</span>)}</div>
    </div>
  );
};
