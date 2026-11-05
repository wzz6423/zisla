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

    @Test(arguments: ["Shanghai", "shanghai", "SHANGHAI"])
    func matchesEnglishStationCityWithoutChoosingAChineseNamesake(query: String) throws {
        let data = Data(#"([{"ref":"101020200~shanghai~闵行~Minhang~闵行~Minhang~21~201100~MH~上海"},{"ref":"101020100~shanghai~上海~Shanghai~上海~Shanghai~21~200000~SH~上海"}])"#.utf8)
        #expect(try ChinaWeatherAlertService.stationID(in: data, query: query, locationName: query) == "101020100")
    }

    @Test
    func sameNamedStationsAreDisambiguatedByTheTrailingProvinceField() throws {
        let data = Data(#"([{"ref":"101060110~jilin~朝阳~Chaoyang~朝阳~Chaoyang~431~130000~CYQ~吉林"},{"ref":"101071201~liaoning~朝阳~Chaoyang~朝阳~Chaoyang~421~122000~CY~辽宁"}])"#.utf8)
        #expect(try ChinaWeatherAlertService.stationID(in: data, query: "朝阳", locationName: "辽宁省朝阳市") == "101071201")
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
