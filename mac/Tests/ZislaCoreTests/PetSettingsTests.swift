import Foundation
import Testing
@testable import ZislaCore

struct PetSettingsTests {
    private static let retiredIDs = [
        "cow", "dog", "duck", "frog", "horse", "monkey", "owl",
        "panda", "parrot", "penguin", "pig", "rabbit", "sloth", "whale",
    ]

    @Test
    func newAndMissingSettingsSelectChiikawa() throws {
        #expect(FeatureSettings.default.petID == "chiikawa")
        for json in ["{}", #"{"petID":null}"#] {
            let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(json.utf8))
            #expect(settings.petID == "chiikawa")
            #expect(settings.petEnabled)
            #expect(settings.petSide == .left)
            #expect(settings.petSelectionMode == .fixed)
            #expect(settings.petRandomPool == nil)
            #expect(settings.petRotationInterval == nil)
        }
    }

    @Test
    func unknownModeAndInvalidIntervalKeepTheFixedPetAndOtherSettings() throws {
        let data = Data(#"{"petID":"bear","petSide":"right","petSelectionMode":"future","petRotationInterval":"bad","petRandomPool":"bad"}"#.utf8)
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(settings.petSelectionMode == .fixed)
        #expect(settings.petRotationInterval == nil)
        #expect(settings.petRandomPool == nil)
        #expect(settings.petID == "bear")
        #expect(settings.petSide == .right)
    }

    @Test
    func customIntervalAndPoolRoundTripAndUseTheSupportedDurationRange() throws {
        var settings = FeatureSettings(petID: "chick", petSelectionMode: .randomRotation,
                                       petRandomPool: ["bear", "user-test"], petRotationInterval: 3_661)
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored == settings)
        settings.petRotationInterval = 0
        #expect(settings.petRotationInterval == 1)
        settings.petRotationInterval = 500_000
        #expect(settings.petRotationInterval == UserCareInterval.maximumSeconds)
        settings.petRotationInterval = nil
        #expect(settings.petRotationInterval == nil)
    }

    @Test
    func aLocalDayKeepsItsPetAcrossRestartsAndPoolEdits() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let evening = try Date("2026-11-27T15:59:00Z", strategy: .iso8601)
        let midnight = evening.addingTimeInterval(60)
        let initial = try #require(PetRotationSelection.resolve(
            previous: nil, candidates: ["user-test"], interval: nil, at: evening, calendar: calendar
        ))
        let previous = try JSONDecoder().decode(PetRotationSelection.self, from: JSONEncoder().encode(initial))
        #expect(previous.nextRotation(after: evening, calendar: calendar) == midnight)
        let pool: Set<String> = ["bear", "user-test"]
        let before = PetRotationSelection.resolve(previous: previous, candidates: pool, interval: nil,
                                                  at: midnight.addingTimeInterval(-1), calendar: calendar)
        #expect(before == initial)
        let next = PetRotationSelection.resolve(previous: before, candidates: pool, interval: nil, at: midnight, calendar: calendar)
        #expect(next?.petID == "bear")
        let removed = PetRotationSelection.resolve(previous: next, candidates: ["user-test"], interval: nil, at: midnight, calendar: calendar)
        #expect(removed?.petID == "user-test")
    }

    @Test
    func aTimeZoneChangeOnlyRotatesWhenTheCivilDateChanges() throws {
        var calendar = Calendar(identifier: .gregorian)
        let now = try Date("2026-11-27T16:00:00Z", strategy: .iso8601)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let first = PetRotationSelection.resolve(previous: nil, candidates: ["bear"], interval: nil, at: now, calendar: calendar)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let pool: Set<String> = ["bear", "chick"]
        #expect(PetRotationSelection.resolve(previous: first, candidates: pool, interval: nil, at: now, calendar: calendar) == first)
        calendar.timeZone = .gmt
        #expect(PetRotationSelection.resolve(previous: first, candidates: pool, interval: nil, at: now, calendar: calendar)?.petID == "chick")
    }

    @Test
    func intervalChangesKeepThePetAndMissedPeriodsOnlyAdvanceOnce() throws {
        let start = try Date("2026-11-27T23:59:58Z", strategy: .iso8601)
        let pool: Set<String> = ["bear", "chick"]
        let daily = PetRotationSelection.resolve(previous: nil, candidates: ["bear"], interval: nil, at: start)
        let first = try #require(PetRotationSelection.resolve(previous: daily, candidates: pool, interval: 5, at: start))
        #expect(first.petID == "bear")
        #expect(first.nextRotation(after: start) == start.addingTimeInterval(5))
        let before = start.addingTimeInterval(4)
        #expect(PetRotationSelection.resolve(previous: first, candidates: pool, interval: 5, at: before) == first)
        #expect(first.nextRotation(after: before) == start.addingTimeInterval(5))
        let longer = try #require(PetRotationSelection.resolve(previous: first, candidates: pool, interval: 10, at: before))
        #expect(longer.petID == first.petID)
        #expect(longer.nextRotation(after: before) == before.addingTimeInterval(10))
        let saved = try JSONDecoder().decode(PetRotationSelection.self, from: JSONEncoder().encode(longer))
        let late = start.addingTimeInterval(74)
        let rotated = try #require(PetRotationSelection.resolve(previous: saved, candidates: pool, interval: 10, at: late))
        #expect(rotated.petID == "chick")
        #expect(rotated.nextRotation(after: late) == late.addingTimeInterval(10))
        #expect(PetRotationSelection.resolve(previous: rotated, candidates: pool, interval: 10, at: late) == rotated)
        let rewound = try #require(PetRotationSelection.resolve(previous: rotated, candidates: pool, interval: 10, at: start))
        #expect(rewound.petID == rotated.petID)
        #expect(rewound.nextRotation(after: start) == start.addingTimeInterval(10))
        let resumedDaily = try #require(PetRotationSelection.resolve(previous: rewound, candidates: pool, interval: nil, at: late))
        #expect(resumedDaily.petID == rewound.petID)
    }

    @Test(arguments: [["kirby", "chiikawa"], ["bear", "chick"]])
    func missingEntriesLeaveOnlyAvailablePetsInAnExplicitPool(library: [String]) throws {
        var settings = FeatureSettings(petSelectionMode: .randomRotation)
        #expect(settings.petRotationCandidates(availableIDs: library) == Set(library))
        #expect(settings.petRandomPool == nil)
        settings.petRandomPool = ["missing", "user-test"]
        #expect(settings.petRotationCandidates(availableIDs: []).isEmpty)
        #expect(settings.petRandomPool == ["missing", "user-test"])
        #expect(settings.petRotationCandidates(availableIDs: library + ["user-test"]) == ["user-test"])
        #expect(settings.petRandomPool == ["user-test"])
        let fallback = library.contains("chiikawa") ? "chiikawa" : "bear"
        #expect(settings.petRotationCandidates(availableIDs: library) == [fallback])
        #expect(settings.petRandomPool == [fallback])
    }

    @Test(arguments: retiredIDs, [false, true])
    func retiredSelectionMigratesWithoutChangingPetOptions(id: String, enabled: Bool) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "petID": id, "petEnabled": enabled, "petSide": "right",
        ])
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(settings.petID == "chiikawa")
        #expect(settings.petEnabled == enabled)
        #expect(settings.petSide == .right)

        let restored = try JSONDecoder().decode(
            FeatureSettings.self, from: JSONEncoder().encode(settings)
        )
        #expect(restored.petID == "chiikawa")
        #expect(restored.petEnabled == enabled)
        #expect(restored.petSide == .right)
    }

    @Test(arguments: [
        "bear", "chick", "chiikawa", "kirby", "pikachu", "toothless", "boba",
        "orange-capybara", "coffee-capybara", "box-capybara", "mallow-cat", "orange-tabby",
        "calico-cat", "shiba-inu", "corgi", "golden-retriever", "lop-rabbit", "byte-bunny",
        "blue-button-bunny", "red-panda", "scarf-hamster", "penguin-chick", "blue-boba-axolotl",
        "milk-tea-koala", "mellow-otter", "moonlight-fox", "hedgehog",
    ])
    func retainedAndNewSelectionsRoundTrip(id: String) throws {
        let settings = FeatureSettings(petEnabled: false, petID: id, petSide: .right)
        let restored = try JSONDecoder().decode(
            FeatureSettings.self, from: JSONEncoder().encode(settings)
        )
        #expect(restored.petID == id)
        #expect(!restored.petEnabled)
        #expect(restored.petSide == .right)
    }

    @Test(arguments: ["", "custom-pet", "future-pet", "user-d6c8b8b6-6c02-4e42-8784-23e6b41c6053"])
    func unrelatedIdentifiersAreNotRewritten(id: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["petID": id])
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(settings.petID == id)
    }

    @Test(arguments: [#"{"petID":42}"#, #"{"petID":false}"#, #"{"petID":[]}"#])
    func invalidSelectionTypesStillFailDecoding(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FeatureSettings.self, from: Data(json.utf8))
        }
    }
}
