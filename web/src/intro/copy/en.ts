import type { IntroCopy } from './copy';

/** English is the fallback base. */
export const en: IntroCopy = {
  meta: {
    title: 'zisla · Introduction',
    description:
      'A looping animation introducing zisla, the on-demand macOS workspace that expands from the top edge of the screen.',
  },
  kicker: 'NATIVE macOS WORKSPACE',
  headline: 'Move to the top.<br><em>It is already open.</em>',
  lede: 'A workspace that shows up when you need it, then gets out of the way.',
  scene: 'Top center of the screen · No click required',
  chapters: {
    1: {
      kicker: 'ON DEMAND',
      title: 'One place at the top edge',
      body: 'Move the pointer to the top center of the screen and it expands from the notch. It never takes focus from the app you are using.',
      module: 'Home',
    },
    2: {
      kicker: 'AI WORKFLOW',
      title: 'AI status without the transcript',
      body: 'Tasks from CLIs, desktop apps and IDEs land in one view with live progress. zisla reads status metadata, never prompts or replies.',
      module: 'AI Monitoring',
    },
    3: {
      kicker: 'INSTANT ACCESS',
      title: 'Copy once, find it forever',
      body: 'Clipboard history and the file shelf collect what you copy or download. Filter by type, send to Quick Notes, or reveal in Finder.',
      module: 'Clipboard',
      moduleAlt: 'Shelf',
    },
    4: {
      kicker: 'LOCAL',
      title: 'Kept on your Mac',
      body: 'CPU, memory, network, battery, plus local PDF tools. Clipboard recognition runs on-device and nothing leaves the Mac unless you start it.',
      module: 'System',
      moduleAlt: 'Toolbox',
    },
  },
  outro: {
    kicker: 'ZISLA',
    title: 'Screenshots, voice,<br><em>keyboard sounds, one workspace.</em>',
    body: 'Native, open source, and out of the way until you need it.',
    cta: 'Download zisla',
  },
  ui: {
    play: 'Play',
    pause: 'Pause',
    replay: 'Replay',
    timeline: 'Film timeline',
    language: 'Interface language',
    reduceMotion: 'Reduce motion',
    screenReaderSummary: 'Introduction film for zisla',
    chapterOf: 'Chapter {current} of {total}',
    download: 'Download',
  },
};
