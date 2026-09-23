import Foundation

enum ClipboardAssistantIdentifierPatterns {
    static let flightLabel = #"航班(?:号|號|編號)?|便名|フライト(?:番号)?|航空便|항공편(?:명|\s*번호)?|편명|flight(?:\s*(?:number|no\.?))?|numéro\s+de\s+vol|n[°º]\s*de\s*vol|vol|flug(?:nummer)?|número\s+de\s+vuelo|vuelo|número\s+do\s+voo|voo|numero\s+del\s+volo|volo|vlucht(?:nummer)?|номер\s+рейса|рейс|رقم\s+الرحلة|رحلة(?:\s+طيران)?|หมายเลขเที่ยวบิน|เที่ยวบิน(?:ที่)?|nomor\s+penerbangan|penerbangan|số\s+hiệu\s+chuyến\s+bay|số\s+chuyến\s+bay|chuyến\s+bay|uçuş(?:\s+numarası)?"#
    static let trainLabel = #"车次|列车|火车|高铁|車次|列車(?:番号)?|火車|高鐵|電車|新幹線|열차(?:\s*번호)?|기차|train(?:\s*(?:number|no\.?))?|numéro\s+du\s+train|n[°º]\s*de\s*train|zug(?:nummer)?|número\s+de\s+tren|tren(?:\s+numarası)?|número\s+do\s+(?:trem|comboio)|trem|comboio|numero\s+(?:del\s+)?treno|treno|trein(?:nummer)?|номер\s+поезда|поезд|رقم\s+القطار|قطار|ขบวนรถ(?:ไฟ)?(?:ที่)?|รถไฟ(?:ขบวน)?|nomor\s+kereta(?:\s+api)?|kereta(?:\s+api)?|số\s+hiệu\s+tàu|số\s+tàu|tàu(?:\s+hỏa)?"#
    static let trackingLabel = #"快[递遞](?:单号|單號)?|[运運][单單](?:号|號)?|物流(?:单号|單號)?|追蹤號碼|追跡番号|お問い合わせ番号|送り状番号|伝票番号|운송장(?:\s*번호)?|송장\s*번호|배송조회|tracking(?:\s*(?:number|no\.?))?|waybill|numéro\s+de\s+suivi|n[°º]\s*de\s*suivi|suivi|sendungs(?:nummer|-?nr\.?)|paketnummer|número\s+de\s+seguimiento|número\s+de\s+guía|seguimiento|código\s+de\s+rastre(?:io|amento)|rastreamento|numero\s+di\s+tracciamento|codice\s+di\s+spedizione|tracciamento|trackingnummer|pakketnummer|zendingsnummer|трек(?:-номер)?|номер\s+отслеживания|почтовый\s+идентификатор|رقم\s+التتبع|رقم\s+الشحنة|เลขพัสดุ|หมายเลขติดตาม|เลขติดตาม|nomor\s+resi|nomor\s+pelacakan|resi|mã\s+vận\s+đơn|số\s+vận\s+đơn|kargo\s+takip\s+numarası|takip\s+numarası|gönderi\s+numarası"#
    static let phoneLabel = #"电话号码|電話號碼|电话|電話番号|電話|手机号|手機號碼|휴대폰(?:\s*번호)?|전화(?:\s*번호)?|phone(?:\s*number)?|mobile(?:\s*number)?|telephone|tel\.?|téléphone|numéro\s+de\s+téléphone|telefonnummer|telefon(?:\s+numarası)?|teléfono|número\s+de\s+teléfono|telefone|número\s+de\s+telefone|telefono|numero\s+di\s+telefono|telefoon(?:nummer)?|номер\s+телефона|телефон|رقم\s+الهاتف|هاتف|เบอร์โทรศัพท์|หมายเลขโทรศัพท์|โทรศัพท์|nomor\s+telepon|telepon|số\s+điện\s+thoại"#

    static func splitLabel(_ text: String, pattern: String) -> (label: String?, value: String) {
        let regex = try! NSRegularExpression(pattern: "(?i)^(?:" + pattern + #")(?=$|[\h:：#\p{Nd}+＋(（]|[A-Z]{2,3}\h*\p{Nd})\h*[:：#]?\h*"#)
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return (nil, text)
        }
        let range = Range(match.range, in: text)!
        return (String(text[range]).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ":：#"))), String(text[range.upperBound...]))
    }

    static func decimalDigits(_ text: String) -> String {
        String(text.map { character in
            guard character.unicodeScalars.allSatisfy({ $0.properties.generalCategory == .decimalNumber }),
                  let digit = character.wholeNumberValue else { return character }
            return Character(String(digit))
        })
    }
}
