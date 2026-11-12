import {Config} from '@remotion/cli/config';
import {enableTailwind} from '@remotion/tailwind-v4';

Config.setVideoImageFormat('jpeg');
Config.setJpegQuality(92);
Config.setChromiumOpenGlRenderer('angle');
Config.overrideBundlerConfig((currentConfiguration) => enableTailwind(currentConfiguration));
