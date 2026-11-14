# zstd-swift

[English](README.md) | **简体中文**

对预编译 facebook/zstd 二进制库的简单 Swift 封装。

```swift
import Foundation
import zstd

let data = Data("Hello, zstd!".utf8)
let compressedData = try ZStd.compress(data)
let decompressedData = try ZStd.decompress(compressedData)

try ZStd.compress(src: InputStream(data: data), dst: OutputStream(toMemory: ()))
try ZStd.decompress(src: InputStream(data: compressedData), dst: OutputStream(toMemory: ()))

let fileData = try ZStd.decompress(src: URL(fileURLWithPath: "/path/to/compressed.zst"))
```
