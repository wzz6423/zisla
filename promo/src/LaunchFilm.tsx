import type {FC} from 'react';
import {Audio, Sequence, staticFile, useCurrentFrame} from 'remotion';
import {Stage} from './components/Stage';
import {CursorOpacityContext} from './components/Cursor';
import {Scene1Awakening} from './scenes/Scene1Awakening';
import {SceneLayouts} from './scenes/SceneLayouts';
import {Scene2AICenter} from './scenes/Scene2AICenter';
import {Scene3Flow} from './scenes/Scene3Flow';
import {SceneMail} from './scenes/SceneMail';
import {SceneEveryday} from './scenes/SceneEveryday';
import {SceneCreativeTools} from './scenes/SceneCreativeTools';
import {SceneDesktopTools} from './scenes/SceneDesktopTools';
import {SceneSettings} from './scenes/SceneSettings';
import {Scene5Outro} from './scenes/Scene5Outro';
import {CROSSFADE, SCENES} from './timeline';
import {clamp01} from './theme';
import {soundtracks} from './soundtrack';
import type {SoundtrackVariant} from './soundtrack';

type Entry = {
  id: string;
  Scene: FC<{duration?: number; globalFrom?: number; music?: SoundtrackVariant}>;
  from: number;
  duration: number;
};

// Keep the outgoing scene opaque until the incoming scene finishes its crossfade.
export const ENTRIES: readonly Entry[] = [
  {id: 'awakening', Scene: Scene1Awakening, ...SCENES.awakening},
  {id: 'layouts', Scene: SceneLayouts, ...SCENES.layouts},
  {id: 'aiCenter', Scene: Scene2AICenter, ...SCENES.aiCenter},
  {id: 'flow', Scene: Scene3Flow, ...SCENES.flow},
  {id: 'mail', Scene: SceneMail, ...SCENES.mail},
  {id: 'everyday', Scene: SceneEveryday, ...SCENES.everyday},
  {id: 'creative', Scene: SceneCreativeTools, ...SCENES.creative},
  {id: 'desktop', Scene: SceneDesktopTools, ...SCENES.desktop},
  {id: 'settings', Scene: SceneSettings, ...SCENES.settings},
  {id: 'outro', Scene: Scene5Outro, ...SCENES.outro},
];

export const SceneLayer: FC<{entry: Entry; lead: number; music: SoundtrackVariant}> = ({entry, lead, music}) => {
  const frame = useCurrentFrame();
  return (
    <CursorOpacityContext.Provider value={frame < lead ? 0 : 1}>
      <Stage opacity={clamp01((frame + 1) / (lead + 1))}>
      <entry.Scene duration={lead + entry.duration} globalFrom={entry.from - lead} music={music} />
      </Stage>
    </CursorOpacityContext.Provider>
  );
};

export const LaunchFilm: FC<{music?: SoundtrackVariant}> = ({music = 'funk'}) => (
  <>
    {/* Scene compositions remain silent so the soundtrack is never duplicated. */}
    <Audio src={staticFile(soundtracks[music].audio)} />
    {ENTRIES.map((entry, index) => {
      const lead = index > 0 ? CROSSFADE : 0;
      return (
        <Sequence key={entry.id} from={entry.from - lead} durationInFrames={lead + entry.duration} layout="none">
          <SceneLayer entry={entry} lead={lead} music={music} />
        </Sequence>
      );
    })}
  </>
);
