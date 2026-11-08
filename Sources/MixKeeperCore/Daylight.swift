import Foundation

public struct Coordinate: Equatable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// 用系統時區表的城市座標當「所在地」，不需要定位權限。
public enum ZoneTab {
    public static func coordinate(for zone: String, table: String) -> Coordinate? {
        for line in table.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: "\t")
            guard parts.count >= 3, parts[2] == zone else { continue }
            return parse(String(parts[1]))
        }
        return nil
    }

    public static func current() -> Coordinate? {
        guard let table = try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8) else { return nil }
        return coordinate(for: TimeZone.current.identifier, table: table)
    }

    /// ISO 6709：+DDMM+DDDMM 或 +DDMMSS+DDDMMSS。
    static func parse(_ text: String) -> Coordinate? {
        guard let split = text.dropFirst().firstIndex(where: { $0 == "+" || $0 == "-" }) else { return nil }
        func value(_ part: Substring, degreeDigits: Int) -> Double? {
            guard let sign = part.first, sign == "+" || sign == "-" else { return nil }
            let digits = Array(part.dropFirst())
            guard digits.count >= degreeDigits + 2,
                  let degrees = Double(String(digits[0..<degreeDigits])),
                  let minutes = Double(String(digits[degreeDigits..<degreeDigits + 2])) else { return nil }
            let seconds = digits.count >= degreeDigits + 4 ? Double(String(digits[degreeDigits + 2..<degreeDigits + 4])) ?? 0 : 0
            let total = degrees + minutes / 60 + seconds / 3600
            return sign == "-" ? -total : total
        }
        guard let lat = value(text[..<split], degreeDigits: 2), let lon = value(text[split...], degreeDigits: 3) else { return nil }
        return Coordinate(latitude: lat, longitude: lon)
    }
}

public enum Daylight: String {
    case day, night

    /// 太陽高度角高於 −4° 算白天（民用曙暮光的前半段還算亮）。
    public static func at(_ date: Date, _ coordinate: Coordinate?, calendar: Calendar = .current) -> Daylight {
        guard let coordinate else {
            let hour = calendar.component(.hour, from: date)
            return (6..<18).contains(hour) ? .day : .night
        }
        return sunAltitude(date, coordinate) > -4 ? .day : .night
    }

    /// 簡化版太陽位置公式，誤差約數分鐘，夠判斷白天晚上。
    public static func sunAltitude(_ date: Date, _ c: Coordinate) -> Double {
        let rad = Double.pi / 180
        let d = date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545.0
        let g = (357.529 + 0.98560028 * d) * rad
        let q = 280.459 + 0.98564736 * d
        let l = (q + 1.915 * sin(g) + 0.020 * sin(2 * g)) * rad
        let e = (23.439 - 0.00000036 * d) * rad
        let ra = atan2(cos(e) * sin(l), cos(l))
        let dec = asin(sin(e) * sin(l))
        let gmst = (18.697374558 + 24.06570982441908 * d).truncatingRemainder(dividingBy: 24)
        let hourAngle = (gmst * 15 + c.longitude) * rad - ra
        let lat = c.latitude * rad
        return asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(hourAngle)) / rad
    }
}
