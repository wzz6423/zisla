import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct ChinaWeatherAlertServiceTests {
    @Test
    func selectsCityStationMatchingSavedProvince() throws {
        let data = Data(
            #"""
            ([
              {"ref":"101050311~heilongjiang~西安区~Xianqu~西安区~Xianqu~453~157000~XAQ~黑龙江"},
              {"ref":"101110101~shaanxi~西安~Xian~西安~Xian~29~710000~XA~陕西"}
            ])
            """#.utf8
        )

        let stationID = try ChinaWeatherAlertService.stationID(
            in: data,
            query: "西安",
            locationName: "陕西省西安市"
        )

        #expect(stationID == "101110101")
    }

    @Test
    func parsesOfficialAlertWithoutInventingExpiry() throws {
        let data = Data(
            #"""
            var alarmDZ101110101 = {
              "w": [{
                "w5":"暴雨",
                "w7":"红色",
                "w8":"202607240900",
                "w11":"20260724090000001.html",
                "w13":"西安市暴雨红色预警"
              }]
            };
            """#.utf8
        )

        let alerts = try ChinaWeatherAlertService.alerts(
            in: data,
            stationID: "101110101",
            region: "陕西省西安市"
        )

        let alert = try #require(alerts.first)
        #expect(alert.severity == .extreme)
        #expect(alert.summary == "西安市暴雨红色预警")
        #expect(alert.source == "中国天气网（中国气象局）")
        #expect(alert.expiresAt == nil)
        #expect(alert.detailsURL.absoluteString.contains("20260724090000001.html"))
    }
}
