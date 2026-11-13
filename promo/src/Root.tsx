import type {FC} from 'react';
import {Composition} from 'remotion';
import './index.css';
import {LaunchFilm} from './LaunchFilm';
import {Stage} from './components/Stage';
import {Scene1Awakening} from './scenes/Scene1Awakening';
import {SceneLayouts} from './scenes/SceneLayouts';
import {Scene2AICenter} from './scenes/Scene2AICenter';
import {Scene3Flow} from './scenes/Scene3Flow';
import {SceneMail} from './scenes/SceneMail';
import {SceneEveryday} from './scenes/SceneEveryday';
import {Scene4Bento} from './scenes/Scene4Bento';
import {SceneCreativeTools} from './scenes/SceneCreativeTools';
import {SceneDesktopTools} from './scenes/SceneDesktopTools';
import {SceneSettings} from './scenes/SceneSettings';
import {Scene5Outro} from './scenes/Scene5Outro';
import {FPS, SCENES, TOTAL_FRAMES} from './timeline';

const staged = (Scene: FC<{duration?: number}>, duration: number): FC => () => (
  <Stage>
    <Scene duration={duration} />
  </Stage>
);

const scenes = [
  {id: 'Scene1Awakening', component: staged(Scene1Awakening, SCENES.awakening.duration), duration: SCENES.awakening.duration},
  {id: 'SceneLayouts', component: staged(SceneLayouts, SCENES.layouts.duration), duration: SCENES.layouts.duration},
  {id: 'Scene2AICenter', component: staged(Scene2AICenter, SCENES.aiCenter.duration), duration: SCENES.aiCenter.duration},
  {id: 'Scene3Flow', component: staged(Scene3Flow, SCENES.flow.duration), duration: SCENES.flow.duration},
  {id: 'SceneMail', component: staged(SceneMail, SCENES.mail.duration), duration: SCENES.mail.duration},
  {id: 'SceneEveryday', component: staged(SceneEveryday, SCENES.everyday.duration), duration: SCENES.everyday.duration},
  {id: 'Scene4Bento', component: staged(Scene4Bento, 600), duration: 600},
  {id: 'SceneCreativeTools', component: staged(SceneCreativeTools, SCENES.creative.duration), duration: SCENES.creative.duration},
  {id: 'SceneDesktopTools', component: staged(SceneDesktopTools, SCENES.desktop.duration), duration: SCENES.desktop.duration},
  {id: 'SceneSettings', component: staged(SceneSettings, SCENES.settings.duration), duration: SCENES.settings.duration},
  {id: 'Scene5Outro', component: staged(Scene5Outro, SCENES.outro.duration), duration: SCENES.outro.duration},
] as const;

export const RemotionRoot = () => (
  <>
    <Composition id="ZislaLaunchFilm" component={LaunchFilm} durationInFrames={TOTAL_FRAMES} fps={FPS} width={1920} height={1080} />
    <Composition id="ZislaLaunchFilm4K" component={LaunchFilm} durationInFrames={TOTAL_FRAMES} fps={FPS} width={3840} height={2160} />
    <Composition id="ZislaLaunchFilmCinematic" component={LaunchFilm} defaultProps={{music: 'cinematic' as const}} durationInFrames={TOTAL_FRAMES} fps={FPS} width={1920} height={1080} />
    <Composition id="ZislaLaunchFilmCinematic4K" component={LaunchFilm} defaultProps={{music: 'cinematic' as const}} durationInFrames={TOTAL_FRAMES} fps={FPS} width={3840} height={2160} />
    {scenes.map((scene) => (
      <Composition key={scene.id} id={scene.id} component={scene.component} durationInFrames={scene.duration} fps={FPS} width={1920} height={1080} />
    ))}
  </>
);
