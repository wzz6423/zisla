import Foundation

public enum IslandLayoutStyle: String, Codable, CaseIterable, Sendable {
    case notch
    case pill
}

public enum IslandEdge: String, Codable, CaseIterable, Sendable {
    case top
    case bottom
    case left
    case right

    public var isVertical: Bool {
        self == .left || self == .right
    }
}

public enum IslandPlacementMode: String, Codable, CaseIterable, Sendable {
    case camera
    case custom
}

public struct IslandPlacement: Codable, Equatable, Sendable {
    public var mode: IslandPlacementMode
    public var edge: IslandEdge
    /// Screen-relative center, left to right on horizontal edges and bottom to top on vertical edges.
    public var offset: Double {
        didSet { offset = Self.clampedOffset(offset) }
    }
    public var inwardDistance: Double {
        didSet { inwardDistance = Self.validInwardDistance(inwardDistance) }
    }

    public init(
        mode: IslandPlacementMode = .camera,
        edge: IslandEdge = .top,
        offset: Double = 0.5,
        inwardDistance: Double = 0
    ) {
        self.mode = mode
        self.edge = edge
        self.offset = Self.clampedOffset(offset)
        self.inwardDistance = Self.validInwardDistance(inwardDistance)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mode: (try? container.decodeIfPresent(IslandPlacementMode.self, forKey: .mode)) ?? .camera,
            edge: (try? container.decodeIfPresent(IslandEdge.self, forKey: .edge)) ?? .top,
            offset: (try? container.decodeIfPresent(Double.self, forKey: .offset)) ?? 0.5,
            inwardDistance: (try? container.decode(Double.self, forKey: .inwardDistance)) ?? 0
        )
    }

    private static func clampedOffset(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0.5
    }

    private static func validInwardDistance(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }
}
