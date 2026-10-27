import Foundation

/// What a file's picture taught the app about it (file-cards spec §1): a video's stream, a photo's EXIF. Every field
/// is optional: the app fills what its read for the picture gave.
public struct FileFacts: Equatable, Sendable, Codable {
    /// Pixels.
    public var width: Int?
    public var height: Int?
    /// Seconds (video).
    public var duration: Double?
    /// The video codec's short name: `HEVC`, `H.264`, `AV1`, `ProRes`.
    public var codec: String?
    public var fps: Double?
    /// Bits per second.
    public var bitrate: Int?
    /// The video's transfer (its colour as delivered): `SDR`, `HLG`, `HDR10`.
    public var transfer: Transfer?
    /// Make and model (photo).
    public var camera: String?
    public var lens: String?
    /// Seconds.
    public var exposure: Double?
    /// The f-number.
    public var aperture: Double?
    public var iso: Int?
    /// Millimetres.
    public var focalLength: Double?
    /// Exposure compensation in EV (`-0.3`, `+1`); nil when the camera wrote none or zero.
    public var exposureBias: Double?
    /// When the photo was taken (DateTimeOriginal).
    public var taken: Date?

    public init(width: Int? = nil, height: Int? = nil, duration: Double? = nil, codec: String? = nil, fps: Double? = nil,
                bitrate: Int? = nil, transfer: Transfer? = nil, camera: String? = nil, lens: String? = nil,
                exposure: Double? = nil, aperture: Double? = nil, iso: Int? = nil, focalLength: Double? = nil,
                exposureBias: Double? = nil, taken: Date? = nil) {
        self.width = width
        self.height = height
        self.duration = duration
        self.codec = codec
        self.fps = fps
        self.bitrate = bitrate
        self.transfer = transfer
        self.camera = camera
        self.lens = lens
        self.exposure = exposure
        self.aperture = aperture
        self.iso = iso
        self.focalLength = focalLength
        self.exposureBias = exposureBias
        self.taken = taken
    }

    /// A video's facts: a codec, a rate or a length.
    public var isVideo: Bool { codec != nil || fps != nil || duration != nil }

    /// The style guide's colour badge (Media UI Iconography D, «Цвет / HDR»): PQ is `HDR10`, ARIB STD-B67 is `HLG`.
    /// Log gammas are not told apart from SDR: the stream does not say.
    public enum Transfer: String, Equatable, Sendable, Codable {
        case sdr = "SDR", hlg = "HLG", hdr10 = "HDR10"
    }
}

/// The words of `FileFacts` on a card, written as the Media UI Iconography style guide (sections D and E) says: the
/// resolution class by the frame's width (`UHD` is 3840, `4K` is 4096), the rate unrounded with its `p`, a non-breaking
/// space between a number and its unit (`35 mm`, `24 MP`), decimal file sizes.
public enum FileFactsText {
    /// Between a number and its unit (guide E, «Единицы»).
    static let nbsp = "\u{00A0}"

    /// A video by its class: `8K`, `6K`, `5K`, `4K` (DCI), `UHD`, `QHD`, `FHD`, `HD`, `SD`, by the long side, so a
    /// 1920 × 800 scope is `FHD` and a turned phone clip keeps its class; a photo `4032 × 3024`.
    public static func resolution(_ f: FileFacts) -> String? {
        guard let w = f.width, let h = f.height, w > 0, h > 0 else { return nil }
        guard f.isVideo else { return "\(w) × \(h)" }
        let long = max(w, h)
        if long >= 7680 { return "8K" }
        if long >= 6000 { return "6K" }
        if long >= 5000 { return "5K" }
        if long >= 4096 { return "4K" }
        if long >= 3840 { return "UHD" }
        if long >= 2560 { return "QHD" }
        if long >= 1920 { return "FHD" }
        if long >= 1280 { return "HD" }
        return "SD"
    }

    /// `UHD · 25p · HEVC · HLG`: what is known of the stream, in the guide's order (class, rate, codec, colour);
    /// SDR is not said.
    public static func stream(_ f: FileFacts) -> String? {
        var parts: [String] = []
        if let r = resolution(f) { parts.append(r) }
        if let fps = f.fps, fps > 0 { parts.append(rate(fps) + "p") }
        if let c = f.codec, !c.isEmpty { parts.append(c) }
        if let t = f.transfer, t != .sdr { parts.append(t.rawValue) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What an exposure value is, for its glyph and colour on a card (the hover strip, Loupe's facts row).
    public enum ExposureKind: Sendable, CaseIterable {
        case shutter, aperture, iso, focalLength, bias
    }

    /// One value of the exposure, as written (`1/250`, `ISO 800`), and what it is.
    public struct ExposureValue: Equatable, Sendable {
        public let text: String
        public let kind: ExposureKind
        public init(_ text: String, _ kind: ExposureKind) {
            self.text = text
            self.kind = kind
        }
    }

    /// The exposure's values as a camera's screen orders them: `1/250`, `f/2.8`, `ISO 800`, `35 mm`, `−0.3 EV`.
    public static func exposureValues(_ f: FileFacts) -> [ExposureValue] {
        var values: [ExposureValue] = []
        if let e = f.exposure, e > 0 { values.append(.init(shutter(e), .shutter)) }
        if let a = f.aperture, a > 0 { values.append(.init("f/" + number(a), .aperture)) }
        if let iso = f.iso, iso > 0 { values.append(.init("ISO" + nbsp + "\(iso)", .iso)) }
        if let mm = f.focalLength, mm > 0 { values.append(.init(number(mm) + nbsp + "mm", .focalLength)) }
        if let ev = f.exposureBias, ev != 0, ev.isFinite { values.append(.init(bias(ev), .bias)) }
        return values
    }

    /// The texts of `exposureValues`.
    public static func exposureParts(_ f: FileFacts) -> [String] { exposureValues(f).map(\.text) }

    /// `1/250 · f/2.8 · ISO 800 · 35 mm · −0.3 EV`: what is known of the exposure.
    public static func exposureLine(_ f: FileFacts) -> String? {
        let parts = exposureParts(f)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// `−0.3 EV`, `+1 EV`: the true minus sign (guide E, «Минус»), one decimal at most.
    public static func bias(_ ev: Double) -> String {
        let r = (ev * 10).rounded() / 10
        let digits = r == r.rounded() ? String(Int(abs(r))) : String(format: "%.1f", abs(r))
        return (r < 0 ? "\u{2212}" : "+") + digits + nbsp + "EV"
    }

    /// `Sony ILCE-7M4 · FE 24-70mm F2.8 GM II`; nil without a camera or a lens.
    public static func cameraLine(_ f: FileFacts) -> String? {
        let parts = [f.camera, f.lens].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The camera's name from EXIF's make and model: the make dropped when the model already starts with it
    /// (`Canon` + `Canon EOS R5`), its company suffix dropped (`NIKON CORPORATION` → `NIKON`).
    public static func camera(make: String?, model: String?) -> String? {
        let model = model?.trimmingCharacters(in: .whitespaces) ?? ""
        var make = make?.trimmingCharacters(in: .whitespaces) ?? ""
        for suffix in [" CORPORATION", " Corporation", " CORP.", " Co., Ltd.", " COMPUTER CO.,LTD."] where make.hasSuffix(suffix) {
            make = String(make.dropLast(suffix.count))
        }
        if model.isEmpty { return make.isEmpty ? nil : make }
        if make.isEmpty || model.lowercased().hasPrefix(make.lowercased()) { return model }
        return make + " " + model
    }

    /// `0:48`, `12:30`, `1:02:10`: a video's length, no leading zero in its first place.
    public static func length(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = total / 60 % 60, sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// The size of a file in decimal units (guide E, «Размер файла»): one decimal under 100, whole from 100:
    /// `4.2 MB`, `24.6 MB`, `148 MB`, `3.2 GB`; under a kilobyte `850 B`.
    public static func size(_ bytes: Int64) -> String {
        var value = Double(bytes)
        guard value >= 1000 else { return "\(bytes)" + nbsp + "B" }
        var unit = 0
        let units = ["KB", "MB", "GB", "TB", "PB"]
        value /= 1000
        // 999.7 KB would print as `1000 KB`: it is `1.0 MB`.
        while unit < units.count - 1, value >= 999.5 {
            value /= 1000
            unit += 1
        }
        let text = value >= 99.95 ? String(Int(value.rounded())) : String(format: "%.1f", value)
        return text + nbsp + units[unit]
    }

    /// The line under a poster's name (file-cards spec §2): a video's stream and size, a photo's exposure (else its
    /// pixels and size); nil when there is nothing to say.
    public static func posterLine(_ f: FileFacts?, bytes: Int64?) -> String? {
        let size = bytes.map(size)
        guard let f else { return nil }
        let main = f.isVideo ? stream(f) : exposureLine(f) ?? resolution(f)
        let withSize = f.isVideo || exposureLine(f) == nil
        let parts = [main, withSize ? size : nil].compactMap { $0 }
        return main == nil ? nil : parts.joined(separator: " · ")
    }

    /// `24 MP`, `8.3 MP`: a photo's megapixels (one decimal under ten); nil without its size.
    public static func megapixels(_ f: FileFacts) -> String? {
        guard let w = f.width, let h = f.height, w > 0, h > 0 else { return nil }
        let mp = Double(w) * Double(h) / 1_000_000
        return (mp >= 10 ? String(Int(mp.rounded())) : number((mp * 10).rounded() / 10)) + nbsp + "MP"
    }

    /// What a badge says, for its colour: the frame's class or size, the rate, the colour (`HLG`, `HDR10`), `RAW`,
    /// the megapixels.
    public enum BadgeKind: Sendable, CaseIterable {
        case resolution, rate, transfer, raw, megapixels
    }

    public struct Badge: Equatable, Sendable {
        public let text: String
        public let kind: BadgeKind
        public init(_ text: String, _ kind: BadgeKind) {
            self.text = text
            self.kind = kind
        }
    }

    /// The badges on a picture (guide F1: at most two, at its top left): a video's class, then its colour when it is
    /// not SDR, else its rate (`UHD HLG`, `FHD 59.94p`); a photo's format when it is RAW, then its megapixels
    /// (`RAW 24 MP`). `format` is the file's extension in capitals.
    public static func badges(_ f: FileFacts?, format: String?) -> [Badge] {
        guard let f else { return [] }
        if f.isVideo {
            var out: [Badge] = []
            if let r = resolution(f) { out.append(.init(r, .resolution)) }
            if let t = f.transfer, t != .sdr {
                out.append(.init(t.rawValue, .transfer))
            } else if let fps = f.fps, fps > 0 {
                out.append(.init(rate(fps) + "p", .rate))
            }
            return out
        }
        var out: [Badge] = []
        if let format, rawFormats.contains(format.uppercased()) { out.append(.init("RAW", .raw)) }
        if let mp = megapixels(f) { out.append(.init(mp, .megapixels)) }
        return out
    }

    static let rawFormats: Set<String> = ["ARW", "CR2", "CR3", "NEF", "NRW", "DNG", "RAF", "ORF", "RW2", "PEF", "SRW", "3FR", "IIQ"]

    /// The line under a video poster that has its badges: the codec and the size (the rest is on the picture).
    public static func videoLineWithBadges(_ f: FileFacts, bytes: Int64?) -> String? {
        let parts = [f.codec, bytes.map(size)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// `1/250` under 0.4 s (the nearest whole denominator), `0.5 s` below a second, `2″` for whole seconds.
    public static func shutter(_ seconds: Double) -> String {
        if seconds < 0.4 { return "1/\(Int((1 / seconds).rounded()))" }
        let r = (seconds * 10).rounded() / 10
        if r >= 1, r == r.rounded() { return "\(Int(r))\u{2033}" }
        return number(seconds) + nbsp + "s"
    }

    /// `23.976`, `29.97`, `59.94`, `25`: never rounded to the whole rate (guide E, «Дробный fps»).
    public static func rate(_ fps: Double) -> String {
        let r = (fps * 1000).rounded() / 1000
        if r == r.rounded() { return String(Int(r)) }
        var s = String(format: "%.3f", r)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }

    /// A number without trailing zeros, at most two decimals: `2.8`, `24`, `0.5`.
    public static func number(_ x: Double) -> String {
        let r = (x * 100).rounded() / 100
        if r == r.rounded() { return String(Int(r)) }
        var s = String(format: "%.2f", r)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }
}
