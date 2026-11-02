import Foundation
import Testing
@testable import ZislaCore

struct IslandPlacementTests {
    @Test
    func missingFieldsKeepCameraAtTheTopCenter() throws {
        let placement = try JSONDecoder().decode(IslandPlacement.self, from: Data("{}".utf8))
        #expect(placement == IslandPlacement(mode: .camera, edge: .top, offset: 0.5))
    }

    @Test
    func malformedFieldsRecoverIndependently() throws {
        let payloads = [
            #"{"mode":"obsolete","edge":"left","offset":0.2}"#,
            #"{"mode":"custom","edge":false,"offset":0.7}"#,
            #"{"mode":null,"edge":null,"offset":"invalid"}"#,
        ]
        let expected = [
            IslandPlacement(mode: .camera, edge: .left, offset: 0.2),
            IslandPlacement(mode: .custom, edge: .top, offset: 0.7),
            IslandPlacement(),
        ]
        for (payload, placement) in zip(payloads, expected) {
            #expect(try JSONDecoder().decode(IslandPlacement.self, from: Data(payload.utf8)) == placement)
        }
    }

    @Test
    func invalidOffsetsStayFiniteAndWithinTheScreen() throws {
        let inputs: [Double] = [-20, -0.1, 0, 0.5, 1, 1.1, 20, .infinity, -.infinity, .nan]
        let expected: [Double] = [0, 0, 0, 0.5, 1, 1, 1, 0.5, 0.5, 0.5]
        for (input, result) in zip(inputs, expected) {
            var placement = IslandPlacement(offset: input)
            #expect(placement.offset == result)
            placement.offset = input
            #expect(placement.offset == result)
            let encoded = try JSONEncoder().encode(placement)
            #expect(try JSONDecoder().decode(IslandPlacement.self, from: encoded) == placement)
        }
        let decoded = try JSONDecoder().decode(IslandPlacement.self, from: Data(#"{"offset":17}"#.utf8))
        #expect(decoded.offset == 1)
    }

    @Test
    func inwardDistancesRecoverIndependentlyAndRetainUnclampedRequests() throws {
        for value in [nil, "null", "false", #""invalid""#, "-4", "0", "28", "10000"] {
            let field = value.map { #", "inwardDistance":\#($0)"# } ?? ""
            let payload = #"{"mode":"custom","edge":"right","offset":0.7\#(field)}"#
            let decoded = try JSONDecoder().decode(IslandPlacement.self, from: Data(payload.utf8))
            #expect(decoded.mode == .custom && decoded.edge == .right && decoded.offset == 0.7)
            #expect(decoded.inwardDistance == max(0, value.flatMap(Double.init) ?? 0))
            #expect(try JSONDecoder().decode(IslandPlacement.self, from: JSONEncoder().encode(decoded)) == decoded)
        }
        for input: Double in [-1, 0, 28, 10000, .nan, .infinity, -.infinity] {
            var placement = IslandPlacement(mode: .custom, edge: .left, inwardDistance: input)
            let expected = input.isFinite ? max(0, input) : 0
            #expect(placement.inwardDistance == expected)
            placement.inwardDistance = input
            #expect(placement.inwardDistance == expected)
            #expect(try JSONDecoder().decode(IslandPlacement.self, from: JSONEncoder().encode(placement)) == placement)
        }
    }

    @Test
    func edgesAndModesRoundTripWithoutChangingPlacement() throws {
        for mode in IslandPlacementMode.allCases {
            for edge in IslandEdge.allCases {
                #expect(edge.isVertical == [.left, .right].contains(edge))
                for step in 0...20 {
                    let original = IslandPlacement(mode: mode, edge: edge, offset: Double(step) / 20,
                        inwardDistance: Double(step) * 20)
                    let data = try JSONEncoder().encode(original)
                    #expect(try JSONDecoder().decode(IslandPlacement.self, from: data) == original)
                }
            }
        }
        for style in IslandLayoutStyle.allCases {
            let data = try JSONEncoder().encode(style)
            #expect(try JSONDecoder().decode(IslandLayoutStyle.self, from: data) == style)
        }
    }

    @Test
    func seededPlacementRoundTripsRemainFiniteWithoutMutatingOriginals() throws {
        var seed: UInt64 = 0xA11CE
        for _ in 0..<128 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let original = IslandPlacement(mode: IslandPlacementMode.allCases[Int(seed % 2)],
                edge: IslandEdge.allCases[Int((seed >> 8) % 4)],
                offset: Double(seed >> 16) / Double(UInt64.max >> 16) * 5 - 2,
                inwardDistance: Double(seed % 1_000) - 100)
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(IslandPlacement.self, from: encoded)
            #expect(decoded == original)
            #expect(decoded.offset.isFinite && (0...1).contains(decoded.offset))
            #expect(decoded.inwardDistance.isFinite && decoded.inwardDistance >= 0)
            var changed = decoded
            changed.offset = decoded.offset + 2
            changed.inwardDistance += 500
            #expect(original == decoded)
            #expect(changed.offset == 1)
        }
    }

    @Test(arguments: ["[]", "true", "null", "{", "{\"offset\":NaN}"])
    func invalidTopLevelSettingsFailWithoutCreatingPlacement(payload: String) {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(IslandPlacement.self, from: Data(payload.utf8))
        }
    }
}
