import Foundation
import Testing

@testable import ZislaKit

struct SystemUptimeTests {
    @Test
    func displayTextFormatsMinutesAndDays() {
        let uptime = TimeInterval((3 * 86_400) + (14 * 3_600) + (48 * 60) + 59)

        #expect(SystemUptime.displayText(for: uptime) == "开机时间： 3天 14小时 48分钟")
    }

    @Test
    func displayTextHandlesZeroAndInvalidValues() {
        #expect(SystemUptime.displayText(for: 0) == "开机时间： 0天 0小时 0分钟")
        #expect(SystemUptime.displayText(for: -.infinity) == "开机时间： 0天 0小时 0分钟")
        #expect(SystemUptime.displayText(for: .nan) == "开机时间： 0天 0小时 0分钟")
    }
}
