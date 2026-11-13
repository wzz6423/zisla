import {Img, useCurrentFrame} from 'remotion';
import {Blackout} from '../components/Caption';
import {githubMark, zislaIcon} from '../assets';
import {copy} from '../content';
import {ease} from '../motion';
import {soundtracks} from '../soundtrack';
import type {SoundtrackVariant} from '../soundtrack';
import {SCENES} from '../timeline';
import {color, white} from '../theme';

export const Scene5Outro = ({duration = SCENES.outro.duration, music = 'funk'}: {duration?: number; music?: SoundtrackVariant}) => {
  const frame = useCurrentFrame();
  const soundtrack = soundtracks[music];
  const brand = ease(frame, [0, 18], [0, 1]);
  const details = ease(frame, [8, 26], [0, 1]);

  return (
    <div data-outro className="absolute inset-0" style={{background: '#000'}}>
      <div data-outro-brand className="absolute inset-x-0 flex flex-col items-center" style={{top: 224, opacity: brand}}>
        <Img src={zislaIcon} alt="zisla" style={{width: 76, height: 76, borderRadius: 19, boxShadow: '0 18px 48px rgba(0,0,0,0.6)'}} />
        <div className="font-rounded" style={{marginTop: 12, fontSize: 40, lineHeight: '44px', fontWeight: 700, letterSpacing: '-0.03em'}}>zisla</div>
        <div className="text-[17px] leading-[22px] font-medium text-label-2" style={{marginTop: 4}}>{copy.slogan} {copy.sloganSecond}</div>
      </div>

      <div className="absolute inset-x-0 flex justify-center" style={{top: 404, opacity: details}}>
        <div data-outro-install-command className="whitespace-nowrap font-mono text-[14px] leading-[20px]" style={{padding: '16px 20px', borderRadius: 14, background: white(0.045), border: `1px solid ${white(0.14)}`}}>
          <span style={{color: color.green}}>➜</span><span style={{color: color.cyan}}> ~ </span><span>{copy.outro}</span>
        </div>
      </div>

      <div data-outro-repository className="absolute inset-x-0 flex items-center justify-center gap-[9px]" style={{bottom: 60, opacity: details}}>
        <Img src={githubMark} alt="GitHub" style={{width: 18, height: 18, opacity: 0.85, filter: 'invert(1)'}} />
        <div className="font-mono text-[14px] leading-[18px]" style={{color: white(0.78)}}>github.com/wzz6423/zisla</div>
      </div>

      <div data-outro-music-credit className="absolute inset-x-0 text-center text-[9px] leading-[12px]" style={{bottom: 32, color: white(0.5), opacity: details}}>
        Music: {soundtrack.title} by {soundtrack.artist} · {soundtrack.license} · {soundtrack.creditSite}
      </div>

      <Blackout opacity={ease(frame, [duration - 30, duration - 7], [0, 1])} />
    </div>
  );
};
