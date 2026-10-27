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
    public var hdr: Bool?
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
    /// When the photo was taken (DateTimeOriginal).
    public var taken: Date?

    public init(width: Int? = nil, height: Int? = nil, duration: Double? = nil, codec: String? = nil, fps: Double? = nil,
                bitrate: Int? = nil, hdr: Bool? = nil, camera: String? = nil, lens: String? = nil,
                exposure: Double? = nil, aperture: Double? = nil, iso: Int? = nil, focalLength: Double? = nil,
                taken: Date? = nil) {
        self.width = width
        self.height = height
        self.duration = duration
        self.codec = codec
        self.fps = fps
        self.bitrate = bitrate
        self.hdr = hdr
        self.camera = camera
        self.lens = lens
        self.exposure = exposure
        self.aperture = aperture
        self.iso = iso
        self.focalLength = focalLength
        self.taken = taken
    }

    /// A video's facts: a codec, a rate or a length.
    public var isVideo: Bool { codec != nil || fps != nil || duration != nil }
}

/// The words of `FileFacts` on a card (file-cards spec §1).
public enum FileFactsText {
    /// A video by its 16:9 line (`720p`, `1080p`, `1440p`, `4K`, `8K`; else `480p`-style); a photo `4032 × 3024`.
    public static func resolution(_ f: FileFacts) -> String? {
        guard let w = f.width, let h = f.height, w > 0, h > 0 else { return nil }
        guard f.isVideo else { return "\(w) × \(h)" }
        // The height a 16:9 frame of this width would have, or the shorter side if taller: 1920 × 800 is 1080p.
        let short = min(w, h), long = max(w, h)
        let line = max(short, long * 9 / 16)
        if line >= 4000 { return "8K" }
        if line >= 2000 { return "4K" }
        if line >= 1400 { return "1440p" }
        if line >= 1000 { return "1080p" }
        if line >= 700 { return "720p" }
        return "\(short)p"
    }

    /// `1080p · HEVC · 60 fps · HDR`: what is known of the stream, in that order.
    public static func stream(_ f: FileFacts) -> String? {
        var parts: [String] = []
        if let r = resolution(f) { parts.append(r) }
        if let c = f.codec, !c.isEmpty { parts.append(c) }
        if let fps = f.fps, fps > 0 { parts.append(rate(fps) + " fps") }
        if f.hdr == true { parts.append("HDR") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// `1/250 · f/2.8 · ISO 400 · 24 mm`: what is known of the exposure.
    public static func exposureLine(_ f: FileFacts) -> String? {
        var parts: [String] = []
        if let e = f.exposure, e > 0 { parts.append(shutter(e)) }
        if let a = f.aperture, a > 0 { parts.append("f/" + number(a)) }
        if let iso = f.iso, iso > 0 { parts.append("ISO \(iso)") }
        if let mm = f.focalLength, mm > 0 { parts.append(number(mm) + " mm") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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

    /// `12:30`, `1:02:10`: a video's length.
    public static func length(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = total / 60 % 60, sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// The size of a file: `1.2 GB`.
    public static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

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
        return (mp >= 10 ? String(Int(mp.rounded())) : number((mp * 10).rounded() / 10)) + " MP"
    }

    /// The badges on a picture (file-cards spec, board «Эскизы файлов» B and video B): a photo's megapixels and RAW;
    /// a video's resolution, HDR and rate (rounded: `60`, `30`, `24`). `format` is the file's extension in capitals.
    public static func badges(_ f: FileFacts?, format: String?) -> [Badge] {
        guard let f else { return [] }
        if f.isVideo {
            var out: [Badge] = []
            if let r = resolution(f) { out.append(Badge(text: r, kind: .resolution)) }
            if f.hdr == true { out.append(Badge(text: "HDR", kind: .hdr)) }
            if let fps = f.fps, fps > 0 { out.append(Badge(text: String(Int(fps.rounded())), unit: "FPS", kind: .rate)) }
            return out
        }
        var out: [Badge] = []
        if let mp = megapixels(f) {
            out.append(Badge(text: String(mp.dropLast(3)), unit: "MP", kind: .megapixels))
        }
        if let format, rawFormats.contains(format.uppercased()) { out.append(Badge(text: "RAW", kind: .raw)) }
        return out
    }

    /// One badge: a value, its unit (drawn smaller after it, as a camera's body marks `30 FPS`), and what it is (its
    /// plate's colour: silver for the size and the rate, gold for HDR, graphite for RAW).
    public struct Badge: Equatable, Sendable {
        public enum Kind: Sendable { case resolution, hdr, rate, megapixels, raw }
        public var text: String
        public var unit: String?
        public var kind: Kind
        public init(text: String, unit: String? = nil, kind: Kind) {
            self.text = text
            self.unit = unit
            self.kind = kind
        }

        /// `30 FPS`, `24 MP`: the badge read as one string (tooltips, tests).
        public var label: String { unit.map { text + " " + $0 } ?? text }
        public var isHighlight: Bool { kind == .hdr }
    }

    static let rawFormats: Set<String> = ["ARW", "CR2", "CR3", "NEF", "NRW", "DNG", "RAF", "ORF", "RW2", "PEF", "SRW", "3FR", "IIQ"]

    /// The line under a video poster that has its badges: the codec and the size (the rest is on the picture).
    public static func videoLineWithBadges(_ f: FileFacts, bytes: Int64?) -> String? {
        let parts = [f.codec, bytes.map(size)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// `1/250` under a second (the nearest whole denominator), else `0.5 s`, `2 s`.
    public static func shutter(_ seconds: Double) -> String {
        if seconds < 0.4 { return "1/\(Int((1 / seconds).rounded()))" }
        return number(seconds) + " s"
    }

    /// `29.97`, `60`, `23.976` → `23.98`.
    static func rate(_ fps: Double) -> String {
        let rounded = (fps * 100).rounded() / 100
        return number(rounded)
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
