import Foundation

private final class FixtureBundleToken {}

enum Fixture {
    nonisolated static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: FixtureBundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw URLError(.fileDoesNotExist)
        }
        return try Data(contentsOf: url)
    }
}

/// Clock values in November 2026, US Eastern Standard Time.
nonisolated func marketTime(day: Int, hour: Int, minute: Int = 0) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: -18_000)
    components.year = 2026
    components.month = 11
    components.day = day
    components.hour = hour
    components.minute = minute
    return components.date!
}

/// Deterministic generator, so a failing randomized case can be reproduced.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
