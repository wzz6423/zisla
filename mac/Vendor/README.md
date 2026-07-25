# Vendored dependencies

`Sparkle.xcframework` is extracted without modification from the official Sparkle 2.9.4 binary artifact:

- Source: `https://github.com/sparkle-project/Sparkle/releases/tag/2.9.4`
- Asset: `Sparkle-for-Swift-Package-Manager.zip`
- SHA-256: `cb6fdbdc8884f15d62a616e79face92b08322410fd2d425edc6596ccbf4ba3b0`
- License: MIT

The XCFramework is vendored because SwiftPM Git and artifact downloads are not reliable behind every macOS proxy configuration. Update it only after verifying the source archive checksum published in Sparkle's tagged `Package.swift`.

`MediaRemoteAdapter.framework` is built without modification from MediaRemote Adapter 0.7.6:

- Source: `https://github.com/ungive/mediaremote-adapter/releases/tag/v0.7.6`
- Commit: `3ac3d4bdf862c7b5399b4fba4df5689f5c38609a`
- License: BSD-3-Clause, copied to `Resources/MediaRemoteAdapter/LICENSE`

The helper is vendored so packaged builds can read the system Now Playing session on macOS 15.4 and newer without a network-time dependency.
