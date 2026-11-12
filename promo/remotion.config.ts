import {Config} from '@remotion/cli/config';
import {enableTailwind} from '@remotion/tailwind-v4';

Config.setVideoImageFormat('jpeg');
Config.setJpegQuality(92);
Config.setChromiumOpenGlRenderer('angle');
Config.overrideBundlerConfig((currentConfiguration) => enableTailwind({
  ...currentConfiguration,
  // Imported app assets live outside promo; relative development URLs escape the Studio server.
  output: {...currentConfiguration.output, assetModuleFilename: '[hash][ext]'},
}));
