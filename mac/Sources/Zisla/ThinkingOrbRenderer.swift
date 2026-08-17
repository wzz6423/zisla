// Ported from thinking-orbs 0.3.1.
//
// MIT License
//
// Copyright (c) 2026 Jakub Antalik
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import SwiftUI

/// The 20px geometry preset from `thinking-orbs` 0.3.1, rendered with a SwiftUI Canvas.
enum ThinkingOrbRenderer {
    struct Dot {
        var x: Double
        var y: Double
        var z: Double
        var radius: Double
        var white: Double
        var alpha: Double = 1
    }

    struct Line {
        var x1: Double
        var y1: Double
        var x2: Double
        var y2: Double
        var white: Double
        var alpha: Double
        var width: Double
    }

    struct Frame {
        var dots: [Dot]
        var lines: [Line]

        var renderedBounds: CGRect {
            var bounds = CGRect.null
            for dot in dots {
                bounds = bounds.union(
                    CGRect(
                        x: dot.x - dot.radius,
                        y: dot.y - dot.radius,
                        width: dot.radius * 2,
                        height: dot.radius * 2
                    )
                )
            }
            for line in lines {
                let inset = line.width / 2
                bounds = bounds.union(
                    CGRect(
                        x: min(line.x1, line.x2) - inset,
                        y: min(line.y1, line.y2) - inset,
                        width: abs(line.x2 - line.x1) + line.width,
                        height: abs(line.y2 - line.y1) + line.width
                    )
                )
            }
            return bounds
        }
    }

    private struct Point3 {
        var x: Double
        var y: Double
        var z: Double
    }

    private struct Projection {
        var sinTilt: Double
        var cosTilt: Double
        var sinYaw: Double
        var cosYaw: Double
        var center: Double
        var scale: Double

        func callAsFunction(_ x: Double, _ y: Double, _ z: Double) -> Point3 {
            let rotatedX = x * cosYaw + z * sinYaw
            let rotatedZ = -x * sinYaw + z * cosYaw
            let rotatedY = y * cosTilt - rotatedZ * sinTilt
            let depth = y * sinTilt + rotatedZ * cosTilt
            return Point3(
                x: center + rotatedX * scale,
                y: center - rotatedY * scale,
                z: depth
            )
        }
    }

    private struct Move {
        var axis: Int
        var lowerBound: Double
        var upperBound: Double
        var angle: Double
    }

    private static let designSize = 20.0
    private static let tau = Double.pi * 2

    static func draw(
        state: ThinkingOrbState,
        into context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        ink: Color
    ) {
        let side = min(size.width, size.height)
        guard side > 0 else { return }

        let frame = frame(state: state, size: designSize, time: time)
        let scale = Double(side) / designSize
        let offsetX = Double((size.width - side) / 2)
        let offsetY = Double((size.height - side) / 2)

        for line in frame.lines {
            var path = Path()
            path.move(to: CGPoint(x: offsetX + line.x1 * scale, y: offsetY + line.y1 * scale))
            path.addLine(to: CGPoint(x: offsetX + line.x2 * scale, y: offsetY + line.y2 * scale))
            context.stroke(
                path,
                with: .color(ink.opacity(inkStrength(white: line.white, alpha: line.alpha))),
                style: StrokeStyle(lineWidth: line.width * scale, lineCap: .round)
            )
        }

        for dot in frame.dots {
            let radius = dot.radius * scale
            let rect = CGRect(
                x: offsetX + dot.x * scale - radius,
                y: offsetY + dot.y * scale - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(ink.opacity(inkStrength(white: dot.white, alpha: dot.alpha)))
            )
        }
    }

    static func frame(state: ThinkingOrbState, size: CGFloat, time: TimeInterval) -> Frame {
        let side = Double(size)
        let resolvedTime = time * state.presetSpeed
        switch state {
        case .working:
            return orbits(size: side, time: resolvedTime)
        case .searching:
            return globe(size: side, time: resolvedTime)
        case .solving:
            return rubik(size: side, time: resolvedTime)
        case .listening:
            return wave(size: side, time: resolvedTime)
        case .connecting:
            return web(size: side, time: resolvedTime)
        case .weaving:
            return braid(size: side, time: resolvedTime)
        case .composing:
            return ribbon(size: side, time: resolvedTime, faceOn: false)
        case .breathing:
            return ribbon(size: side, time: resolvedTime, faceOn: true)
        case .shaping:
            return morph(size: side, time: resolvedTime)
        }
    }

    private static func orbits(size: Double, time: Double) -> Frame {
        let center = size / 2
        let sphereRadius = center * 0.82
        let project = projection(
            yaw: sin(time * 0.12) * Double.pi / 12,
            tilt: 0.3,
            center: center,
            scale: 1
        )
        let radiusScale = radiusScale(size)
        var dots: [Dot] = []

        for orbit in 0..<3 {
            let h1 = hash(Double(orbit), 1.7)
            let h2 = hash(Double(orbit), 5.2)
            let h3 = hash(Double(orbit), 8.9)
            let orbitRadius = sphereRadius * (0.45 + 0.52 * h1)
            let theta = h1 * tau
            let phi = acos(2 * h2 - 1)
            let normalX = sin(phi) * cos(theta)
            let normalY = cos(phi)
            let normalZ = sin(phi) * sin(theta)
            var basisX = -normalY
            var basisY = normalX
            let basisZ = 0.0
            let basisLength = max(0.000_001, hypot(basisX, basisY))
            basisX /= basisLength
            basisY /= basisLength
            let crossX = normalY * basisZ - normalZ * basisY
            let crossY = normalZ * basisX - normalX * basisZ
            let crossZ = normalX * basisY - normalY * basisX
            let speed = (0.25 + 0.55 * h3) * (h3 > 0.5 ? 1 : -1)

            for index in 0..<10 {
                let angle = Double(index) / 10 * tau
                let point = project(
                    (basisX * cos(angle) + crossX * sin(angle)) * orbitRadius,
                    (basisY * cos(angle) + crossY * sin(angle)) * orbitRadius,
                    (basisZ * cos(angle) + crossZ * sin(angle)) * orbitRadius
                )
                let depth = (point.z / orbitRadius + 1) / 2
                dots.append(
                    Dot(
                        x: point.x,
                        y: point.y,
                        z: point.z,
                        radius: 2.16 * radiusScale,
                        white: 0.72,
                        alpha: 0.5 * (0.4 + 0.6 * depth)
                    )
                )
            }

            for particle in 0..<3 {
                let angle = time * speed + Double(particle) / 3 * tau + h2 * 6
                let point = project(
                    (basisX * cos(angle) + crossX * sin(angle)) * orbitRadius,
                    (basisY * cos(angle) + crossY * sin(angle)) * orbitRadius,
                    (basisZ * cos(angle) + crossZ * sin(angle)) * orbitRadius
                )
                let depth = (point.z / orbitRadius + 1) / 2
                dots.append(
                    Dot(
                        x: point.x,
                        y: point.y,
                        z: point.z,
                        radius: (2.88 + 3.84 * depth) * radiusScale,
                        white: 0.3 - 0.22 * depth
                    )
                )
            }
        }
        return finalize(dots: dots)
    }

    private static func globe(size: Double, time: Double) -> Frame {
        let center = size / 2
        let radius = center * 0.82
        let spin = 0.5
        let tilt = 0.4 + 0.06 * sin(time * 0.35)
        let project = projection(yaw: time * spin, tilt: tilt, center: center, scale: radius)
        let scan = time * (spin + (1.7 - spin) * 4.335)
        let radiusScale = radiusScale(size)
        var dots: [Dot] = []

        for ring in 0...6 {
            let latitude = -Double.pi / 2 + Double(ring) / 6 * Double.pi
            let cosLatitude = cos(latitude)
            let sinLatitude = sin(latitude)
            let count = max(1, Int((abs(cosLatitude) * 14).rounded()))
            for index in 0..<count {
                let longitude = Double(index) / Double(count) * tau
                let point = project(
                    cosLatitude * cos(longitude),
                    sinLatitude,
                    cosLatitude * sin(longitude)
                )
                let depth = (point.z + 1) / 2
                let distance = angleDelta(longitude + time * spin, scan)
                let boost = exp(-(distance * distance) / 0.18) * max(0, point.z)
                dots.append(
                    Dot(
                        x: point.x,
                        y: point.y,
                        z: point.z,
                        radius: (1.05 + 2.975 * depth + boost) * radiusScale,
                        white: 0.62 - 0.54 * depth,
                        alpha: 0.45 + 0.55 * min(1, boost)
                    )
                )
            }
        }
        return finalize(dots: dots)
    }

    private static func rubik(size: Double, time: Double) -> Frame {
        let center = size / 2
        let radius = center * 0.82
        let project = projection(
            yaw: time * 0.55,
            tilt: 0.35 + 0.1 * sin(time * 0.9),
            center: center,
            scale: radius
        )
        let radiusScale = radiusScale(size)
        let moves = makeMoves(count: 14)
        let cycle = solveCycle(time: time, count: 14, slotDuration: 0.42, rest: 1.2)
        var dots: [Dot] = []

        for ring in 0...4 {
            let latitude = -Double.pi / 2 + Double(ring) / 4 * Double.pi
            let cosLatitude = cos(latitude)
            let sinLatitude = sin(latitude)
            let count = max(1, Int((abs(cosLatitude) * 12).rounded()))
            for index in 0..<count {
                let longitude = Double(index) / Double(count) * tau
                let moved = applyMoves(
                    Point3(x: cosLatitude * cos(longitude), y: sinLatitude, z: cosLatitude * sin(longitude)),
                    moves: moves,
                    cycle: cycle
                )
                let point = project(moved.point.x, moved.point.y, moved.point.z)
                let depth = (point.z + 1) / 2
                dots.append(
                    Dot(
                        x: point.x,
                        y: point.y,
                        z: point.z,
                        radius: (1.14 + 3.23 * depth + (moved.active ? 0.57 : 0)) * radiusScale,
                        white: 0.62 - 0.54 * depth - (moved.active ? 0.14 : 0)
                    )
                )
            }
        }
        return finalize(dots: dots)
    }

    private static func wave(size: Double, time: Double) -> Frame {
        let center = size / 2
        let radius = center * 0.874
        let project = projection(yaw: time * 0.18, tilt: 0.38, center: center, scale: 1)
        let radiusScale = radiusScale(size)
        var dots: [Dot] = []

        for ring in 0...5 {
            let latitude = -Double.pi / 2 + Double(ring) / 5 * Double.pi
            let cosLatitude = cos(latitude)
            let sinLatitude = sin(latitude)
            let wave = 0.62 * sin(time * 2.1 - Double(ring) * 0.52)
                + 0.38 * sin(time * 1.27 + Double(ring) * 0.83)
            let ringRadius = radius * (0.88 + 0.105 * wave)
            let count = max(1, Int((abs(cosLatitude) * 13).rounded()))
            for index in 0..<count {
                let longitude = Double(index) / Double(count) * tau
                let point = project(
                    cosLatitude * cos(longitude) * ringRadius,
                    sinLatitude * ringRadius,
                    cosLatitude * sin(longitude) * ringRadius
                )
                let depth = (point.z / radius + 1) / 2
                let crest = max(0, wave)
                dots.append(
                    Dot(
                        x: point.x,
                        y: point.y,
                        z: point.z,
                        radius: (0.96 + 2.72 * depth) * (1 + 0.4 * crest) * radiusScale,
                        white: 0.66 - 0.56 * depth - 0.1 * crest
                    )
                )
            }
        }
        return finalize(dots: dots)
    }

    private static func web(size: Double, time: Double) -> Frame {
        let center = size / 2
        let radius = center * 0.8
        let project = projection(yaw: time * 0.12, tilt: 0.32, center: center, scale: radius)
        let radiusScale = radiusScale(size)
        let threshold = 0.72
        var nodes: [Point3] = []

        for index in 0..<8 {
            let direction = fibonacciDirection(index: index, count: 8)
            let x = direction.x + 0.6 * (valueNoise(Double(index) * 0.31 + 9, time * 0.24) - 0.5)
            let y = direction.y + 0.6 * (valueNoise(Double(index) * 0.53 + 27, time * 0.21) - 0.5)
            let z = direction.z + 0.6 * (valueNoise(Double(index) * 0.77 + 55, time * 0.27) - 0.5)
            let length = sqrt(x * x + y * y + z * z)
            nodes.append(Point3(x: x / length, y: y / length, z: z / length))
        }

        var lines: [Line] = []
        for first in nodes.indices {
            for second in nodes.indices where second > first {
                let dx = nodes[first].x - nodes[second].x
                let dy = nodes[first].y - nodes[second].y
                let dz = nodes[first].z - nodes[second].z
                let distance = sqrt(dx * dx + dy * dy + dz * dz)
                guard distance < threshold else { continue }
                let start = project(nodes[first].x, nodes[first].y, nodes[first].z)
                let end = project(nodes[second].x, nodes[second].y, nodes[second].z)
                let depth = ((start.z + end.z) / 2 + 1) / 2
                lines.append(
                    Line(
                        x1: start.x,
                        y1: start.y,
                        x2: end.x,
                        y2: end.y,
                        white: 0.42,
                        alpha: (1 - distance / threshold) * (0.3 + 0.55 * depth),
                        width: max(0.6, 0.8 * radiusScale)
                    )
                )
            }
        }

        var dots = nodes.enumerated().map { index, node in
            let point = project(node.x, node.y, node.z)
            let depth = (point.z + 1) / 2
            let pulse = 1 + 0.25 * sin(time * 1.4 + Double(index) * 2.7)
            return Dot(
                x: point.x,
                y: point.y,
                z: point.z,
                radius: (2.128 + 2.736 * depth) * pulse * radiusScale,
                white: 0.55 - 0.45 * depth
            )
        }

        let segment = floor(time * 0.55)
        let first = Int(floor(hash(segment, 1.7) * 8))
        let second = Int(floor(hash(segment, 4.2) * 8))
        if first != second {
            let progress = fraction(time * 0.55)
            let x = lerp(nodes[first].x, nodes[second].x, progress)
            let y = lerp(nodes[first].y, nodes[second].y, progress)
            let z = lerp(nodes[first].z, nodes[second].z, progress)
            let length = max(0.000_001, sqrt(x * x + y * y + z * z))
            let point = project(x / length, y / length, z / length)
            let depth = (point.z + 1) / 2
            dots.append(
                Dot(
                    x: point.x,
                    y: point.y,
                    z: point.z,
                    radius: (2.128 * 1.5 + 2.736 * depth) * radiusScale,
                    white: 0.05,
                    alpha: 0.5 + 0.5 * depth
                )
            )
        }
        return finalize(dots: dots, lines: lines)
    }

    private static func braid(size: Double, time: Double) -> Frame {
        let center = size / 2
        let radius = center * 0.76
        let project = projection(yaw: time * 0.4, tilt: 0.3, center: center, scale: 1)
        let radiusScale = radiusScale(size)
        var dots: [Dot] = []

        for index in 0..<17 {
            let direction = fibonacciDirection(index: index, count: 17)
            let point = project(direction.x * radius, direction.y * radius, direction.z * radius)
            let depth = (point.z / radius + 1) / 2
            dots.append(
                Dot(
                    x: point.x,
                    y: point.y,
                    z: point.z,
                    radius: 0.8 * radiusScale,
                    white: 0.78,
                    alpha: 0.1 + 0.22 * depth
                )
            )
        }

        for strand in 0..<3 {
            let phase = Double(strand) / 3 * tau
            for index in 0..<6 {
                let vertical = (fraction(Double(index) / 6 + time * 0.045) * 2 - 1) * 0.96
                let surface = sqrt(max(0, 1 - vertical * vertical))
                let endFade = min(1, (1 - abs(vertical)) / 0.1)
                let angle = vertical * Double.pi * 3 + phase
                let weave = 1 + 0.075 * sin(vertical * Double.pi * 6 + phase * 2 + time * 0.8)
                let ringRadius = surface * radius * weave
                let point = project(
                    cos(angle) * ringRadius,
                    vertical * radius * weave,
                    sin(angle) * ringRadius
                )
                let depth = (point.z / radius + 1) / 2
                dots.append(
                    Dot(
                        x: point.x,
                        y: point.y,
                        z: point.z,
                        radius: (1.632 + 2.448 * depth) * radiusScale,
                        white: 0.55 - 0.45 * depth,
                        alpha: endFade * (0.45 + 0.55 * depth)
                    )
                )
            }
        }
        return finalize(dots: dots)
    }

    private static func ribbon(size: Double, time: Double, faceOn: Bool) -> Frame {
        let center = size / 2
        let radius = center * 0.78
        let cameraTilt = 0.3
        let project = projection(yaw: 0, tilt: cameraTilt, center: center, scale: 1)
        let radiusScale = radiusScale(size)
        var dots: [Dot] = []

        if !faceOn {
            for index in 0..<8 {
                let direction = fibonacciDirection(index: index, count: 8)
                let point = project(direction.x * radius, direction.y * radius, direction.z * radius)
                let depth = (point.z / radius + 1) / 2
                dots.append(
                    Dot(
                        x: point.x,
                        y: point.y,
                        z: point.z,
                        radius: 0.8 * radiusScale,
                        white: 0.78,
                        alpha: 0.1 + 0.22 * depth
                    )
                )
            }
        }

        let planeTilt = faceOn ? -cameraTilt : 0.55
        let basisX = 1.0
        let basisY = 0.0
        let basisZ = 0.0
        let crossX = 0.0
        let crossY = cos(planeTilt)
        let crossZ = sin(planeTilt)
        let normalX = 0.0
        let normalY = -sin(planeTilt)
        let normalZ = cos(planeTilt)
        let wobbleMultiplier = faceOn ? 0.565 : 1
        let wobbleAmplitude = 0.23 * wobbleMultiplier
        let baseRadius = faceOn ? radius / (1 + 0.85 * wobbleAmplitude) : radius
        let segmentCount = faceOn ? 15 : 20
        let laneCount = faceOn ? 8 : 10
        let baseDotRadius = faceOn ? 1.7842 : 1.1803
        let depthDotRadius = faceOn ? 2.7574 : 1.8241

        for lane in 0..<laneCount {
            let laneOffset = (Double(lane) - Double(laneCount - 1) / 2) * 0.075
            let edge = abs(Double(lane) - Double(laneCount - 1) / 2) / max(1, Double(laneCount - 1) / 2)
            for segment in 0..<segmentCount {
                let angle = Double(segment) / Double(segmentCount) * tau
                let wobble = (
                    0.16 * sin(angle * 3 - time * 1.7 + Double(lane) * 0.22)
                        + 0.07 * sin(angle * 5 + time * 1.1)
                ) * wobbleMultiplier
                let radial = faceOn ? 1 + wobble : 1
                let offset = faceOn ? laneOffset : laneOffset + wobble
                let x = basisX * cos(angle) + crossX * sin(angle) + normalX * offset
                let y = basisY * cos(angle) + crossY * sin(angle) + normalY * offset
                let z = basisZ * cos(angle) + crossZ * sin(angle) + normalZ * offset
                let length = sqrt(x * x + y * y + z * z)
                let pointRadius = baseRadius * radial
                let point = project(
                    x / length * pointRadius,
                    y / length * pointRadius,
                    z / length * pointRadius
                )
                let depth = (point.z / radius + 1) / 2
                dots.append(
                    Dot(
                        x: point.x,
                        y: point.y,
                        z: point.z,
                        radius: (baseDotRadius + depthDotRadius * depth) * (1 - 0.25 * edge) * radiusScale,
                        white: 0.52 - 0.44 * depth + 0.18 * edge,
                        alpha: 0.4 + 0.6 * depth
                    )
                )
            }
        }
        return finalize(dots: dots)
    }

    private static func morph(size: Double, time: Double) -> Frame {
        let hold = 1.4
        let transition = 0.9
        let segmentDuration = hold + transition
        let cycleTime = time.truncatingRemainder(dividingBy: segmentDuration * 3)
        let shape = Int(floor(cycleTime / segmentDuration))
        let localTime = cycleTime - Double(shape) * segmentDuration
        let rawProgress = localTime > hold ? (localTime - hold) / transition : 0
        let progress = rawProgress * rawProgress * (3 - 2 * rawProgress)
        let spread = 1.45
        let sampleCount = 160
        var samples: [(x: Double, y: Double)] = []

        for index in 0..<sampleCount {
            let amount = Double(index) / Double(sampleCount)
            let start = shapePoint(shape: shape, progress: amount)
            let end = shapePoint(shape: (shape + 1) % 3, progress: amount)
            samples.append(
                (
                    x: lerp(start.x, end.x, progress) * spread,
                    y: lerp(start.y, end.y, progress) * spread
                )
            )
        }

        var lengths: [Double] = []
        var totalLength = 0.0
        for index in 0..<sampleCount {
            let start = samples[index]
            let end = samples[(index + 1) % sampleCount]
            let length = hypot(end.x - start.x, end.y - start.y)
            lengths.append(length)
            totalLength += length
        }

        let dotCount = 18
        let dotRadius = max(0.35, 0.021231 * 1.35 * spread * size)
        let pulse = 1 + 0.02 * sin(localTime * 3.1)
        let center = size / 2
        var dots: [Dot] = []
        var sampleIndex = 0
        var accumulatedLength = 0.0

        for index in 0..<dotCount {
            let target = Double(index) / Double(dotCount) * totalLength
            while sampleIndex < sampleCount - 1 && accumulatedLength + lengths[sampleIndex] < target {
                accumulatedLength += lengths[sampleIndex]
                sampleIndex += 1
            }
            let start = samples[sampleIndex]
            let end = samples[(sampleIndex + 1) % sampleCount]
            let fraction = lengths[sampleIndex] == 0
                ? 0
                : min(1, (target - accumulatedLength) / lengths[sampleIndex])
            dots.append(
                Dot(
                    x: center + lerp(start.x, end.x, fraction) * pulse * size,
                    y: center + lerp(start.y, end.y, fraction) * pulse * size,
                    z: 0,
                    radius: dotRadius,
                    white: 0.1
                )
            )
        }
        return finalize(dots: dots, minimumRadius: 0.25)
    }

    private static func solveCycle(
        time: Double,
        count: Int,
        slotDuration: Double,
        rest: Double
    ) -> (amounts: [Double], active: Int) {
        let duration = 2 * Double(count) * slotDuration + rest
        let cycleTime = time.truncatingRemainder(dividingBy: duration)
        var amounts = Array(repeating: 0.0, count: count)
        var active = -1
        if cycleTime < 2 * Double(count) * slotDuration {
            let slot = Int(floor(cycleTime / slotDuration))
            let progress = (cycleTime - Double(slot) * slotDuration) / slotDuration
            let clamped = min(1, progress / 0.7)
            let eased = 1 - pow(1 - clamped, 3)
            if slot < count {
                for index in 0..<slot { amounts[index] = 1 }
                amounts[slot] = eased
                active = slot
            } else {
                let index = 2 * count - 1 - slot
                for completed in 0..<index { amounts[completed] = 1 }
                amounts[index] = 1 - eased
                active = index
            }
        }
        return (amounts, active)
    }

    private static func makeMoves(count: Int) -> [Move] {
        (0..<count).map { index in
            let axis = min(2, Int(floor(hash(Double(index), 2.3) * 3)))
            let lowerBound = -1 + 0.5 * Double(min(3, Int(floor(hash(Double(index), 5.9) * 4))))
            let direction = hash(Double(index), 7.7) < 0.5 ? 1.0 : -1.0
            return Move(
                axis: axis,
                lowerBound: lowerBound,
                upperBound: lowerBound + 0.5,
                angle: direction * Double.pi / 2
            )
        }
    }

    private static func applyMoves(
        _ point: Point3,
        moves: [Move],
        cycle: (amounts: [Double], active: Int)
    ) -> (point: Point3, active: Bool) {
        var x = point.x
        var y = point.y
        var z = point.z
        var isActive = false

        for index in moves.indices where cycle.amounts[index] > 0 {
            let move = moves[index]
            let coordinate = move.axis == 0 ? x : move.axis == 1 ? y : z
            guard coordinate >= move.lowerBound, coordinate < move.upperBound else { continue }
            if index == cycle.active { isActive = true }
            let angle = move.angle * cycle.amounts[index]
            let cosine = cos(angle)
            let sine = sin(angle)
            switch move.axis {
            case 0:
                let nextY = y * cosine - z * sine
                z = y * sine + z * cosine
                y = nextY
            case 1:
                let nextX = x * cosine + z * sine
                z = -x * sine + z * cosine
                x = nextX
            default:
                let nextX = x * cosine - y * sine
                y = x * sine + y * cosine
                x = nextX
            }
        }
        return (Point3(x: x, y: y, z: z), isActive)
    }

    private static func shapePoint(shape: Int, progress: Double) -> (x: Double, y: Double) {
        switch shape {
        case 1:
            return polygonPoint(
                vertices: [(0, -0.26), (0.24, 0.16), (-0.24, 0.16)],
                progress: progress
            )
        case 2:
            return polygonPoint(
                vertices: [(0, -0.2), (0.2, -0.2), (0.2, 0.2), (-0.2, 0.2), (-0.2, -0.2)],
                progress: progress
            )
        default:
            let angle = -Double.pi / 2 + progress * tau
            return (cos(angle) * 0.24, sin(angle) * 0.24)
        }
    }

    private static func polygonPoint(
        vertices: [(x: Double, y: Double)],
        progress: Double
    ) -> (x: Double, y: Double) {
        let lengths = vertices.indices.map { index in
            let start = vertices[index]
            let end = vertices[(index + 1) % vertices.count]
            return hypot(end.x - start.x, end.y - start.y)
        }
        var target = progress * lengths.reduce(0, +)
        var index = 0
        while index < vertices.count - 1 && target > lengths[index] {
            target -= lengths[index]
            index += 1
        }
        let start = vertices[index]
        let end = vertices[(index + 1) % vertices.count]
        let amount = lengths[index] == 0 ? 0 : min(1, target / lengths[index])
        return (lerp(start.x, end.x, amount), lerp(start.y, end.y, amount))
    }

    private static func finalize(
        dots: [Dot],
        lines: [Line] = [],
        minimumRadius: Double = 0.3
    ) -> Frame {
        let visibleDots = dots.compactMap { dot -> Dot? in
            guard dot.alpha >= 0.02 else { return nil }
            var dot = dot
            dot.radius = max(minimumRadius, dot.radius)
            return dot
        }.sorted { $0.z < $1.z }
        return Frame(
            dots: visibleDots,
            lines: lines.filter { $0.alpha >= 0.02 }
        )
    }

    private static func projection(yaw: Double, tilt: Double, center: Double, scale: Double) -> Projection {
        Projection(
            sinTilt: sin(tilt),
            cosTilt: cos(tilt),
            sinYaw: sin(yaw),
            cosYaw: cos(yaw),
            center: center,
            scale: scale
        )
    }

    private static func fibonacciDirection(index: Int, count: Int) -> Point3 {
        let goldenAngle = Double.pi * (3 - sqrt(5))
        let y = 1 - 2 * (Double(index) + 0.5) / Double(count)
        let radius = sqrt(1 - y * y)
        let angle = Double(index) * goldenAngle
        return Point3(x: radius * cos(angle), y: y, z: radius * sin(angle))
    }

    private static func valueNoise(_ x: Double, _ y: Double) -> Double {
        let integerX = floor(x)
        let integerY = floor(y)
        var fractionX = x - integerX
        var fractionY = y - integerY
        fractionX = fractionX * fractionX * (3 - 2 * fractionX)
        fractionY = fractionY * fractionY * (3 - 2 * fractionY)
        let first = hash(integerX, integerY)
        let second = hash(integerX + 1, integerY)
        let third = hash(integerX, integerY + 1)
        let fourth = hash(integerX + 1, integerY + 1)
        return first
            + (second - first) * fractionX
            + (third - first) * fractionY
            + (first - second - third + fourth) * fractionX * fractionY
    }

    private static func hash(_ first: Double, _ second: Double) -> Double {
        let value = sin(first * 12.9898 + second * 78.233) * 43_758.5453
        return value - floor(value)
    }

    private static func angleDelta(_ first: Double, _ second: Double) -> Double {
        atan2(sin(first - second), cos(first - second))
    }

    private static func fraction(_ value: Double) -> Double {
        value - floor(value)
    }

    private static func lerp(_ first: Double, _ second: Double, _ progress: Double) -> Double {
        first + (second - first) * progress
    }

    private static func radiusScale(_ size: Double) -> Double {
        pow(size / 300, 0.6)
    }

    private static func inkStrength(white: Double, alpha: Double) -> Double {
        min(1, max(0, 1 - white)) * min(1, max(0, alpha))
    }
}

private extension ThinkingOrbState {
    var presetSpeed: Double {
        switch self {
        case .working: 3.9
        case .searching: 2.665
        case .solving: 1.95
        case .listening: 3.998
        case .connecting: 6.63
        case .weaving: 2.75
        case .composing: 3.12
        case .breathing: 3.78
        case .shaping: 2.08
        }
    }
}
