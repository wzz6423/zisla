import Foundation

public struct ClipboardCalendarDraft: Equatable, Sendable {
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var location: String?
    public var notes: String?

    public init(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        location: String? = nil,
        notes: String? = nil
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
    }
}

public enum ClipboardAssistantService: String, CaseIterable, Sendable {
    case baiduMaps, googleMaps, umetrip, flightAware
    case united, lufthansa, britishAirways
    case railway12306, deutscheBahn, amtrak, sncf
    case kuaidi100, track17, sfExpress, ups, fedEx, dhl, usps

    public var localizedTitleKey: String {
        switch self {
        case .baiduMaps: "百度地图"
        case .googleMaps: "Google Maps"
        case .umetrip: "航旅纵横"
        case .flightAware: "FlightAware"
        case .united: "United Airlines"
        case .lufthansa: "Lufthansa"
        case .britishAirways: "British Airways"
        case .railway12306: "铁路 12306"
        case .deutscheBahn: "Deutsche Bahn"
        case .amtrak: "Amtrak"
        case .sncf: "SNCF"
        case .kuaidi100: "快递100"
        case .track17: "17TRACK"
        case .sfExpress: "顺丰速运"
        case .ups: "UPS"
        case .fedEx: "FedEx"
        case .dhl: "DHL"
        case .usps: "USPS"
        }
    }

}
