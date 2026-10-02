# Third-Party Notices

Zed token usage decoding uses zstd.swift v1.0.2 and Zstandard:

https://github.com/awxkee/zstd.swift
https://github.com/facebook/zstd

The zstd.swift wrapper is CC0; Zstandard is licensed under the BSD 3-Clause
License. See `Zstandard-LICENSE.txt` in this directory.

The Apple mobile-device battery reader is adapted from MacTools at commit
`cfac26ade8e88ee967cf8ed300211d0498079336`:

https://github.com/ggbond268/MacTools

Copyright 2026 MacTools contributors. Licensed under the Apache License 2.0.
See `MacTools-LICENSE.txt` in this directory.

The combined menu bar icon geometry, drawing paths, status mappings, and
appearance options and Bluetooth audio drawing are adapted from:

https://github.com/lingyired/status-trio

Pinned revision: `2b0571a51c70fab0f1176db1eb0c32a8d7f2b4ad`.
The original files are `UI/Icon/StatusIconGeometry.swift`,
`UI/Icon/StatusIconRenderer.swift`, `UI/StatusBarController.swift`,
`Models/StatusMappings.swift`,
`Models/RingStrokeStyle.swift`, `Models/BatteryIconOptions.swift`,
`Models/VolumeIconOptions.swift`, `Models/ConnectionIconOptions.swift`,
`Models/StatusSnapshot.swift`, `Models/MenuBarStatus.swift`, and
`Models/BluetoothAudioIconOptions.swift` under
`Sources/StatusTrioCore`.

The geometry directly retains the upstream path definitions and coordinates;
its added drawing calculation sizes the battery-header gap. The renderer
reuses the upstream battery and volume strokes and SF Symbol drawing code.

The local snapshot renames types, connects Zisla's battery and telemetry
snapshots, gives Low Power Mode color precedence, treats missing readings as
unavailable, and retains the battery, Wi-Fi, Bluetooth audio replacement,
and bottom-level menu bar paths. Bluetooth device identity and battery data
come from Zisla's existing audio-output service. The battery ring reports the
computer; the white headphone symbol appears briefly on connection. The menu
bar uses the upstream square canvas, uniform drawing transform, and
AppKit variable-length status item sizing. The local header retains Zisla's
combined lightning and percentage layout with additional ring spacing and
centers the enlarged percentage together with its lightning glyph.
Accessory battery levels remain limited to the existing connection notice. Dock rendering, charging animations, network management,
arbitrary Bluetooth-device pinning, and the upstream application's UI are
not included. No remote dependency is needed to build or render these icons.

Copyright 2026 lingyired. Licensed under the Apache License 2.0. See
`MenuBarIcon-LICENSE.txt` and `MenuBarIcon-NOTICE.txt` in this directory.

The lid angle reader and the lid-close depth effect are adapted from Mac Duo at
commit `88cb939b6f286487887b32e7c8f529604d340c6c`:

https://github.com/sumimakito/Mac-Duo

Copyright 2026 Makito. Licensed under the Apache License 2.0. See
`MacDuo-LICENSE.txt` in this directory.

The bundled Emoji alias catalog is generated from Unicode CLDR 48.2 and
Unicode Emoji 17.0 data:

https://github.com/unicode-org/cldr
https://github.com/unicode-org/cldr-json

Copyright 1991-2026 Unicode, Inc. Licensed under Unicode License V3. See
`Unicode-CLDR-LICENSE.txt` in this directory.
