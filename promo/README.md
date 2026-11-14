# zisla launch film

**English** | [简体中文](README.zh-CN.md)

A 160-second, 60 fps product film for zisla, rendered frame by frame with [Remotion](https://www.remotion.dev/) using React, TypeScript, and Tailwind CSS. It covers the website's 12 modules and 19 additional features. The same visual timeline has funk and cinematic soundtrack variants, each available in 1080p and 4K. Layouts, dimensions, and spring parameters come from the native app's source code; all demonstration data is fictional.

## Run locally

```bash
cd promo
npm install
npm run studio
```

`npm run studio` opens Remotion Studio, where you can scrub frame by frame and preview individual scenes. The project has been validated on macOS 27, Node 26, and npm 11.

## Rendering

```bash
npm run render
```

```bash
npm run render:4k
```

Render a single frame:

```bash
npm run still -- out/frame.png --frame=300
```

```bash
npx remotion still Scene3Flow out/scene3.png --frame=200
```

Type checking and automated tests:

```bash
npm run typecheck
npm test
```

- On the first render, Remotion downloads Chrome Headless Shell into `node_modules/.remotion/`.
- `out/` is ignored, and 4K deliverables are not committed. The website's 1080p film and poster are stored in `web/public/media/`.
- Every frame can be rendered independently. Single-frame PNGs can be reproduced byte for byte; encoder behavior means complete MP4 files are not guaranteed to be byte-identical.
- The project does not distribute fonts. It uses the system font stack, so SF Pro is used when rendering on macOS.

## Compositions and timeline

| Composition ID | Dimensions | Frames | Content |
| --- | --- | --- | --- |
| `ZislaLaunchFilm` | 1920×1080 | 9600 | 2 minutes 40 seconds, with Funkorama |
| `ZislaLaunchFilm4K` | 3840×2160 | 9600 | The same funk version in 4K |
| `ZislaLaunchFilmCinematic` | 1920×1080 | 9600 | The same visuals, with The Miracle of Flight |
| `ZislaLaunchFilmCinematic4K` | 3840×2160 | 9600 | The same cinematic version in 4K |
| `Scene1Awakening` | 1920×1080 | 300 | 0–5s, top-edge activation and activity grouped by app |
| `SceneLayouts` | 1920×1080 | 960 | 5–21s, notch, camera, placement along all four edges, and pets |
| `Scene2AICenter` | 1920×1080 | 840 | 21–35s, tasks, daily model statistics, history, and account quotas in two windows |
| `Scene3Flow` | 1920×1080 | 900 | 35–50s, media, handoff tray multi-selection, and video/audio downloads |
| `SceneMail` | 1920×1080 | 480 | 50–58s, reading, composing, sending, and marking all messages read |
| `SceneEveryday` | 1920×1080 | 1440 | 58–82s, notes, clipboard, meetings, location notes, briefings, and voice |
| `SceneCreativeTools` | 1920×1080 | 1920 | 82–114s, screenshots, recording, images, audio, and PDF tools |
| `SceneDesktopTools` | 1920×1080 | 1460 | 114–138.3s, mixing, keyboard, focus, cleaning, system history, and battery |
| `SceneSettings` | 1920×1080 | 1140 | 138.3–157.3s, windows, Quick Actions, permissions, CLI/Skills, Zshell, and full-screen lid-close effect |
| `Scene4Bento` | 1920×1080 | 600 | Standalone preview of the quick tool overview |
| `Scene5Outro` | 1920×1080 | 160 | 157.3–160s, branding, the complete install command, and the matching music credit |

Adjacent scenes use a 16-frame crossfade: the incoming scene starts 16 frames early and fades in over the still-opaque outgoing scene, becoming fully visible at its nominal start. Song progress and the Pomodoro timer use `filmFrame()` to convert to full-film frame numbers. Individual scene compositions are registered with their nominal durations for silent previews. Layout and tool tours in the full film are scaled to scene durations that include crossfades, retaining each scene's final state.

## Soundtracks

Both variants use the continuous first 160 seconds of one complete work, preserving the original arrangement with fades only at the beginning and end. The MP3 files are 44.1 kHz stereo at 320 kbps, reduced by 2 dB overall, with a 0.4-second fade-in and a fade-out from 155.8 to 159.6 seconds.

- Funk: [Funkorama by Kevin MacLeod](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100474). This variant is used by the website player.
- Cinematic: [The Miracle of Flight by Scott Buckley](https://www.scottbuckley.com.au/library/the-miracle-of-flight/).

Both works are released under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The end credits, audio metadata, and website retain the author and source. Use the matching attribution when redistributing the film:

```text
Funkorama by Kevin MacLeod (incompetech.com), licensed under Creative Commons Attribution 4.0.
'The Miracle of Flight' by Scott Buckley - released under CC-BY 4.0. www.scottbuckley.com.au
```

Regenerate the audio after obtaining the original tracks from their authors' pages (requires ffmpeg):

```bash
node tools/make-soundtrack.mjs /absolute/path/Funkorama.mp3 public/audio/zisla-launch.mp3 funk
node tools/make-soundtrack.mjs /absolute/path/The-Miracle-of-Flight.mp3 public/audio/zisla-launch-cinematic.mp3 cinematic
npx remotion render ZislaLaunchFilmCinematic out/zisla-launch-cinematic-1080p60.mp4
npx remotion render ZislaLaunchFilmCinematic4K out/zisla-launch-cinematic-2160p60.mp4
```

Durations come from `src/timeline.ts`; track details and licenses are centralized in `src/soundtrack.ts`.

## Structure

```
promo/
├── public/audio/        # Soundtracks
├── src/
│   ├── timeline.ts      # FPS, ten scene boundaries, crossfade frames, filmFrame()
│   ├── soundtrack.ts    # Tracks, authors, sources, and licenses
│   ├── theme.ts         # Dimensions, colors, and font sizes from the app source
│   ├── motion.ts        # ZislaMotion (inside the island) + FilmMotion (film layer)
│   ├── content.ts       # Fictional sample data and captions
│   ├── LaunchFilm.tsx   # Ten-scene sequencing, crossfades, and soundtrack
│   ├── Root.tsx         # Full-film and individual scene composition registration
│   ├── components/      # Shared island shell, glass, cursor, desktop, terminal, overlays
│   ├── modules/         # Island modules, AI statistics, mail, file tools, system monitoring
│   └── scenes/          # Ten scenes
└── tools/               # Soundtrack processing script and frame-driven tests
```

## Conventions

- Define timing only in `src/timeline.ts`; use `filmFrame()` for readouts shared across scenes.
- The stage is a 1280×720 logical canvas. `Stage` scales it proportionally to the output dimensions (1.5× for 1080p and 3× for 4K).
- Everything is frame-driven: no `Math.random`, `Date.now`, CSS transitions, or `@keyframes`. Rendering a frame independently produces the same result.
- Use `ZislaMotion` inside the island, with parameters matching the app, and `FilmMotion` for emphasis in the film layer.
- Glass uses `backdrop-filter: blur(24px) saturate(180%)` with a 1px inset border. Ancestors must not have opacity or filter applied for `backdrop-filter` to work.
- Sample data and captions are centralized in `src/content.ts`; demonstration strings used by only one scene remain in that scene's file.

## Assets and data

- Tasks, filenames, the song Paper Lanterns and its lyrics, cities, schedules, notes, and paths are original fictional data. They do not come from real local data or include copyrighted lyrics.
- Brand icons reference the app's bundled resources directly (lobehub/lobe-icons, MIT) in `mac/Resources/BrandIcons/`. The zisla icon references `web/public/assets/zisla-icon.png`; no duplicate is stored in promo.
- The bear and chick pets reference the Kenney Animal Pack Redux assets in `mac/Resources/Pets/`, licensed under CC0 1.0. Single-frame assets use the same 1.4-second breathing animation as the app.
- Both soundtracks follow CC BY 4.0, independently of the repository's code license.
- Apple fonts are not committed.

## Fidelity to the app

Dimensions, colors, and spring parameters are taken from the app source. These five details differ from the storyboard draft and follow the actual interface:

1. The token trend chart covers the last 7 days with one point per day (`AIProgressModuleView` passes `days: 7` to `dailyUsageSeries`), rather than 12 hours. The "12-hour chart" description in `mac/Docs/cli-reference.md` differs from the current implementation.
2. Album artwork is stationary inside the island. The spinning record appears only in the film's close-up layer outside the island.
3. The handoff tray's Finder/share controls are the `Share` and `Show` buttons in the header plus the context menu; there is no hover action bar.
4. Completed downloads use an island-shaped bar descending from the top, rather than a card sliding in from the right.
5. Notes use a list on the left and a WYSIWYG editor on the right, with no separate Markdown preview pane.

## License

- Remotion is not MIT-licensed. Its free license covers personal use, for-profit organizations with up to 3 employees, nonprofits, and other specified cases. See https://www.remotion.dev/docs/license .
- The rest of this directory follows the zisla repository's PolyForm Noncommercial 1.0.0 license.
