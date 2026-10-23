import CoreGraphics
import Foundation

final class RecordingExportGIFWriter {
    private let handle: FileHandle
    private let width: Int
    private let height: Int
    private let frameRate: Int
    private let duration: Double?
    private var frameIndex = 0

    init(url: URL, size: CGSize, frameRate: Int, duration: Double? = nil) throws {
        width = Int(size.width)
        height = Int(size.height)
        self.frameRate = frameRate
        self.duration = duration
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw ScreenRecordingExportError.encoderFailure
        }
        handle = try FileHandle(forWritingTo: url)
        var header = Data("GIF89a".utf8)
        header.append(contentsOf: Self.word(width))
        header.append(contentsOf: Self.word(height))
        header.append(contentsOf: [0xF7, 0, 0])
        for index in 0..<256 {
            header.append(UInt8(((index >> 5) & 7) * 255 / 7))
            header.append(UInt8(((index >> 2) & 7) * 255 / 7))
            header.append(UInt8((index & 3) * 255 / 3))
        }
        header.append(contentsOf: [0x21, 0xFF, 0x0B])
        header.append(Data("NETSCAPE2.0".utf8))
        header.append(contentsOf: [3, 1, 0, 0, 0])
        try handle.write(contentsOf: header)
    }

    deinit { try? handle.close() }

    func append(_ image: CGImage) throws {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        try rgba.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw ScreenRecordingExportError.cannotRender
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var indices = [UInt8](repeating: 0, count: width * height)
        for pixel in indices.indices {
            if pixel.isMultiple(of: width * 16) { try Task.checkCancellation() }
            let base = pixel * 4
            indices[pixel] = (rgba[base] & 0xE0) | ((rgba[base + 1] & 0xE0) >> 3) | (rgba[base + 2] >> 6)
        }
        let start = Int((Double(frameIndex) * 100 / Double(frameRate)).rounded())
        let frameEnd = Double(frameIndex + 1) / Double(frameRate)
        let end = Int((min(frameEnd, duration ?? frameEnd) * 100).rounded())
        var frame = Data([0x21, 0xF9, 4, 4])
        frame.append(contentsOf: Self.word(end - start))
        frame.append(contentsOf: [0, 0, 0x2C, 0, 0, 0, 0])
        frame.append(contentsOf: Self.word(width))
        frame.append(contentsOf: Self.word(height))
        frame.append(contentsOf: [0, 8])
        let compressed = try Self.lzw(indices)
        var cursor = 0
        while cursor < compressed.count {
            let count = min(255, compressed.count - cursor)
            frame.append(UInt8(count))
            frame.append(contentsOf: compressed[cursor..<cursor + count])
            cursor += count
        }
        frame.append(0)
        try handle.write(contentsOf: frame)
        frameIndex += 1
    }

    func finish() throws {
        try handle.write(contentsOf: Data([0x3B]))
        try handle.close()
    }

    static func lzw(_ pixels: [UInt8]) throws -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(pixels.count / 2)
        var bits: UInt32 = 0
        var bitCount = 0
        var dictionary: [Int: Int] = [:]
        dictionary.reserveCapacity(4_096)
        var nextCode = 258
        var codeSize = 9
        func emit(_ code: Int) {
            bits |= UInt32(code) << bitCount
            bitCount += codeSize
            while bitCount >= 8 {
                output.append(UInt8(bits & 0xFF))
                bits >>= 8
                bitCount -= 8
            }
        }
        emit(256)
        var prefix = Int(pixels[0])
        for (index, byte) in pixels.dropFirst().enumerated() {
            if index.isMultiple(of: 65_536) { try Task.checkCancellation() }
            let key = (prefix << 8) | Int(byte)
            if let code = dictionary[key] { prefix = code; continue }
            emit(prefix)
            if nextCode < 4_096 {
                dictionary[key] = nextCode
                nextCode += 1
                // The decoder learns one dictionary entry after the encoder.
                if nextCode > (1 << codeSize), codeSize < 12 { codeSize += 1 }
            } else {
                emit(256)
                dictionary.removeAll(keepingCapacity: true)
                codeSize = 9
                nextCode = 258
            }
            prefix = Int(byte)
        }
        emit(prefix)
        emit(257)
        if bitCount > 0 { output.append(UInt8(bits & 0xFF)) }
        return output
    }

    private static func word(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
    }
}
