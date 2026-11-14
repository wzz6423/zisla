# zstd-swift

**English** | [简体中文](README.zh-CN.md)

A simple Swift wrapper around prebuilt facebook/zstd binaries.

```swift
import Foundation
import zstd

let data = Data("Hello, zstd!".utf8)
let compressedData = try ZStd.compress(data)
let decompressedData = try ZStd.decompress(compressedData)

let compressionOutput = OutputStream(toMemory: ())
try ZStd.compress(src: InputStream(data: data), dst: compressionOutput)
let streamCompressedData = compressionOutput.property(forKey: .dataWrittenToMemoryStreamKey) as! Data

let decompressionOutput = OutputStream(toMemory: ())
try ZStd.decompress(src: InputStream(data: streamCompressedData), dst: decompressionOutput)
let streamDecompressedData = decompressionOutput.property(forKey: .dataWrittenToMemoryStreamKey) as! Data

let fileData = try ZStd.decompress(src: URL(fileURLWithPath: "/path/to/compressed.zst"))
```
