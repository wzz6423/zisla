import type {FC} from 'react';
import {Audio, Sequence, staticFile, useCurrentFrame} from 'remotion';
import {Stage} from './components/Stage';
import {Scene1Awakening} from './scenes/Scene1Awakening';
import {Scene2AICenter} from './scenes/Scene2AICenter';
import {Scene3Flow} from './scenes/Scene3Flow';
import {Scene4Bento} from './scenes/Scene4Bento';
import {Scene5Outro} from './scenes/Scene5Outro';
import {CROSSFADE, SCENES} from './timeline';
import {clamp01} from './theme';

type Entry = {
  id: string;
  Scene: FC<{duration?: number}>;
  from: number;
  duration: number;
};

// 后一幕提前 CROSSFADE 帧入场，在仍不透明的前一幕之上淡入，到名义起点时刚好完全显现。
// 因此除第一幕外，幕内帧号从叠化起点算起，比名义起点早 CROSSFADE 帧。
const ENTRIES: readonly Entry[] = [
  {id: 'awakening', Scene: Scene1Awakening, ...SCENES.awakening},
  {id: 'aiCenter', Scene: Scene2AICenter, ...SCENES.aiCenter},
  {id: 'flow', Scene: Scene3Flow, ...SCENES.flow},
  {id: 'bento', Scene: Scene4Bento, ...SCENES.bento},
  {id: 'outro', Scene: Scene5Outro, ...SCENES.outro},
];

const SceneLayer: FC<{entry: Entry; lead: number}> = ({entry, lead}) => {
  const frame = useCurrentFrame();
  return (
    <Stage opacity={clamp01((frame + 1) / (lead + 1))}>
      <entry.Scene duration={lead + entry.duration} />
    </Stage>
  );
};

export const LaunchFilm: FC = () => (
  <>
    {/* 配乐只挂在全片合成上，分幕合成用作无声预览 */}
    <Audio src={staticFile('audio/zisla-launch.mp3')} />
    {ENTRIES.map((entry, index) => {
      const lead = index > 0 ? CROSSFADE : 0;
      return (
        <Sequence key={entry.id} from={entry.from - lead} durationInFrames={lead + entry.duration} layout="none">
          <SceneLayer entry={entry} lead={lead} />
        </Sequence>
      );
    })}
  </>
);
