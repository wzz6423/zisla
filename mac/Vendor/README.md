# Vendored dependencies

`Sparkle.xcframework` is extracted without modification from the official Sparkle 2.10.0 binary artifact:

- Source: `https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0`
- Asset: `Sparkle-for-Swift-Package-Manager.zip`
- SHA-256: `17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959`
- License: MIT

The XCFramework is vendored because SwiftPM Git and artifact downloads are not reliable behind every macOS proxy configuration. Update it only after verifying the source archive checksum published in Sparkle's tagged `Package.swift`.

`MediaRemoteAdapter.framework` is built without modification from MediaRemote Adapter 0.7.6:

- Source: `https://github.com/ungive/mediaremote-adapter/releases/tag/v0.7.6`
- Commit: `3ac3d4bdf862c7b5399b4fba4df5689f5c38609a`
- License: BSD-3-Clause, copied to `Resources/MediaRemoteAdapter/LICENSE`

The helper is vendored so packaged builds can read the system Now Playing session on macOS 15.4 and newer without a network-time dependency.

`SkyLightWindow` is vendored from its upstream 1.0.0 source snapshot without modification:

- Source: `https://github.com/Lakr233/SkyLightWindow`
- Version: `1.0.0`
- Commit: `b7bd99f62a0673a99bed4bfd31098ca1dcdd10eb`
- License: MIT, copied to `SkyLightWindow/LICENSE`

The package is local so SwiftPM does not fetch it during normal builds. To update it, manually replace `SkyLightWindow` with a verified upstream snapshot, retain its license, and update the version and commit recorded above.

`zstd.swift` is vendored from its fixed upstream 1.0.2 source snapshot:

- Source: `https://github.com/awxkee/zstd.swift`
- Version: `1.0.2`
- Commit: `475fe3175c1aacccf9f420add35bf55e69936936`
- License: CC0, copied to `zstd.swift/LICENSE.md`
- Bundled binary: upstream `libzstd.xcframework`, including its iOS, Mac Catalyst, simulator, and macOS universal slices

The package is local so SwiftPM does not fetch it during normal builds. To update it, replace `zstd.swift` with a verified upstream snapshot, retain its license and binary slices, and update the version and commit recorded above. The bundled Zstandard library remains covered by `Resources/ThirdPartyLicenses/Zstandard-LICENSE.txt`.
