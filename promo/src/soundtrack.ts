export const soundtracks = {
  funk: {
    title: 'Funkorama',
    artist: 'Kevin MacLeod',
    license: 'CC BY 4.0',
    licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
    source: 'https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100474',
    creditSite: 'incompetech.com',
    attribution: 'Funkorama by Kevin MacLeod (incompetech.com), licensed under Creative Commons Attribution 4.0.',
    audio: 'audio/zisla-launch.mp3',
  },
  cinematic: {
    title: 'The Miracle of Flight',
    artist: 'Scott Buckley',
    license: 'CC BY 4.0',
    licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
    source: 'https://www.scottbuckley.com.au/library/the-miracle-of-flight/',
    creditSite: 'scottbuckley.com.au',
    attribution: "'The Miracle of Flight' by Scott Buckley - released under CC-BY 4.0. www.scottbuckley.com.au",
    audio: 'audio/zisla-launch-cinematic.mp3',
  },
} as const;

export type SoundtrackVariant = keyof typeof soundtracks;
export const soundtrack = soundtracks.funk;
