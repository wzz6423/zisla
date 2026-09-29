import AppKit
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla

struct AIResultSweepAppearanceTests {
    @Test @MainActor
    func resultColorsRemainDeepWithAVisibleGradient() throws {
        for status: AIProgressStatus in [.succeeded, .failed] {
            let bitmap = try renderedBand(status: status, progress: 0.5, width: 240, height: 34, reduceMotion: true)
            let values = try dominantPixels(bitmap, status: status)
            let lit = values.filter { $0 > 0.02 }
            let peak = try #require(lit.max())
            #expect(peak > 0.3, "深色光带仍需要可见的亮芯")
            #expect(peak < 0.53, "主带不能恢复成高亮荧光绿或鲜红")
            #expect(lit.reduce(0, +) / Double(lit.count) < 0.25)
        }
    }

    @Test @MainActor
    func particlesScatterAcrossTheBandInsteadOfFormingTwoEdgeLines() throws {
        for status: AIProgressStatus in [.succeeded, .failed] {
            for (width, height) in [(240, 34), (748, 324)] {
                let pixels = try dominantPixels(renderedBand(
                    status: status, progress: 0.5, width: width, height: height
                ), status: status)
                let texture = particleTexture(pixels, width: width)
                let particlePixels = texture.indices.filter { texture[$0] > 0.015 }
                let occupiedBands = Set(particlePixels.map { $0 % width * 8 / width })
                #expect(occupiedBands.count >= 4, "粒子必须散布在光带内，不能集中成两条竖线")
                #expect(occupiedBands.allSatisfy { (1..<7).contains($0) }, "两侧不能出现脱离光带的亮线")
                #expect(particlePixels.count < width * height / 25, "粒子面积必须稀疏")
                let areas = particleComponents(Set(particlePixels), width: width).map(\.count)
                #expect(areas.count >= 18, "加长的光带中仍需分布足够的小粒子")
                #expect(try #require(areas.max()) <= 5, "单个粒子应保持细小，不能形成大光斑")
            }
        }
    }

    @Test @MainActor
    func movingParticlesReachTheVisibleStripBelowThePhysicalNotch() throws {
        for status: AIProgressStatus in [.succeeded, .failed] {
            var visibleFrames = 0
            for progress in [0.25, 0.375, 0.5, 0.625, 0.75] {
                let pixels = try dominantPixels(renderedBand(
                    status: status, progress: progress, width: 240, height: 34
                ), status: status)
                let texture = particleTexture(pixels, width: 240)
                if texture.suffix(240 * 2).contains(where: { $0 > 0.015 }) {
                    visibleFrames += 1
                }
            }
            #expect(visibleFrames >= 2, "动态粒子也必须经过刘海下方可见的窄条")
        }
    }

    @Test @MainActor
    func particlesMoveIndependentlyWhileFollowingTheBandDeterministically() throws {
        var centers: [Double] = []
        var particlePositions: [[CGPoint]] = []
        let width = 250
        let height = 34
        for progress in [0.4, 0.6] {
            let first = try renderedBand(status: .succeeded, progress: progress, width: width, height: height)
            let second = try renderedBand(status: .succeeded, progress: progress, width: width, height: height)
            let pixels = try dominantPixels(first, status: .succeeded)
            #expect(pixels == (try dominantPixels(second, status: .succeeded)), "同一进度的粒子不能每帧随机闪跳")
            let texture = particleTexture(pixels, width: width)
            let background = zip(pixels.prefix(width), texture.prefix(width)).map { $0 - $1 }
            let total = background.reduce(0, +)
            try #require(total > 0)
            let center = background.indices.reduce(0.0) { $0 + Double($1) * background[$1] } / total
            centers.append(center)
            let particles = particleComponents(Set(texture.indices.filter { texture[$0] > 0.015 }), width: width)
            try #require(particles.count >= 18, "必须有足够的可见粒子来比较运动")
            particlePositions.append(particles.map { points in
                CGPoint(
                    x: Double(points.reduce(0) { $0 + $1 % width }) / Double(points.count) - center,
                    y: Double(points.reduce(0) { $0 + $1 / width }) / Double(points.count)
                )
            })
        }
        #expect(centers[1] - centers[0] > 60, "粒子应跟随光带从左向右移动")
        var bestAlignment = Double.infinity
        for dx in -8...8 {
            for dy in -8...8 {
                let distances = particlePositions[0].map { first in
                    particlePositions[1].map { second in
                        hypot(first.x - second.x + Double(dx), first.y - second.y + Double(dy))
                    }.min()!
                }
                bestAlignment = min(bestAlignment, distances.reduce(0, +) / Double(distances.count))
            }
        }
        #expect(bestAlignment > 1, "扣除整体平移后，粒子仍应有超过一个像素的相对位移")
    }

    @Test @MainActor
    func glowBreathesGentlyDuringTheSingleSweep() throws {
        let width = 500
        let height = 100
        for status: AIProgressStatus in [.succeeded, .failed] {
            var brightness: [Double] = []
            for progress in [0.3, 0.4, 0.5, 0.6, 0.7] {
                let pixels = try dominantPixels(renderedBand(
                    status: status, progress: progress, width: width, height: height
                ), status: status)
                let texture = particleTexture(pixels, width: width)
                let background = zip(pixels, texture).map { $0 - $1 }
                brightness.append(try #require(background.max()))
            }
            #expect(brightness[0] > brightness[2] * 1.05 && brightness[4] > brightness[2] * 1.05,
                    "扫过过程中应有柔和的明暗呼吸起伏")
            #expect(brightness.min()! > brightness.max()! * 0.75, "呼吸不能变成忽明忽灭的闪烁")
            #expect(abs(brightness[0] - brightness[4]) < 0.015)
        }
    }

    @Test @MainActor
    func glowHasABrightCenterAndDarkSymmetricShoulders() throws {
        for status: AIProgressStatus in [.succeeded, .failed] {
            for reduceMotion in [false, true] {
                let width = 240
                let pixels = try dominantPixels(renderedBand(
                    status: status, progress: 0.5, width: width, height: 34, reduceMotion: reduceMotion
                ), status: status)
                let center = pixels.indices.filter { (108..<132).contains($0 % width) }.map { pixels[$0] }.max()!
                let sides = pixels.indices.filter { !(84..<156).contains($0 % width) }.map { pixels[$0] }.max()!
                #expect(center > sides * 1.5, "中心应最亮，不能出现两缘亮、中间暗的双峰")
                if reduceMotion {
                    let row = Array(pixels[17 * width..<18 * width])
                    #expect(zip(row, row.reversed()).allSatisfy { abs($0 - $1) < 0.015 }, "渐变应以中间为峰值对称衰减")
                }
            }
        }
    }

    @Test @MainActor
    func reducedMotionAndFinishedSweepsHaveNoParticleTexture() throws {
        for (progress, reduceMotion) in [(0.5, true), (0.0, false), (1.0, false)] {
            let bitmap = try renderedBand(
                status: .failed, progress: progress, width: 240, height: 34, reduceMotion: reduceMotion
            )
            let pixels = try dominantPixels(bitmap, status: .failed)
            for x in 0..<240 {
                let column = stride(from: x, to: pixels.count, by: 240).map { pixels[$0] }
                #expect(column.max()! - column.min()! < 0.01)
            }
            if progress != 0.5 { #expect(pixels.max()! < 0.01) }
        }
    }

    @MainActor
    private func renderedBand(
        status: AIProgressStatus, progress: Double, width: Int, height: Int, reduceMotion: Bool = false
    ) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: AIResultSweepBand(
            status: status, progress: progress, reduceMotion: reduceMotion
        ).frame(width: CGFloat(width), height: CGFloat(height)).background(.black))
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    private func dominantPixels(_ bitmap: NSBitmapImageRep, status: AIProgressStatus) throws -> [Double] {
        try (0..<bitmap.pixelsHigh).flatMap { y in
            try (0..<bitmap.pixelsWide).map { x in
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                return Double(status == .succeeded ? color.greenComponent : color.redComponent)
            }
        }
    }

    private func particleTexture(_ pixels: [Double], width: Int) -> [Double] {
        let background = (0..<width).map { x in
            stride(from: x, to: pixels.count, by: width).map { pixels[$0] }.min()!
        }
        return pixels.indices.map { pixels[$0] - background[$0 % width] }
    }

    private func particleComponents(_ pixels: Set<Int>, width: Int) -> [[Int]] {
        var remaining = pixels
        var components: [[Int]] = []
        while let start = remaining.popFirst() {
            var pending = [start]
            var component: [Int] = []
            while let point = pending.popLast() {
                component.append(point)
                let neighbors = [point - width, point + width, point - 1, point + 1]
                for neighbor in neighbors where abs(neighbor % width - point % width) <= 1 {
                    if remaining.remove(neighbor) != nil { pending.append(neighbor) }
                }
            }
            components.append(component)
        }
        return components
    }
}
