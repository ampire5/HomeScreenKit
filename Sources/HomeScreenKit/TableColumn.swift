import AppKit
import HomeScreenModel

/// User-facing facts already supplied by the browser's source. No file access is performed here.
enum TableColumn: String, CaseIterable {
    case name, inside, dates, viewed, size
    case format, width, height, megapixels, taken, camera, lens, shutter, aperture, iso, focalLength, exposureBias
    case colorSpace, orientation, progressive, typeIdentifier
    case duration, codec, fps, bitrate, transfer
    case photos, folders, insidePhotos, first, last, seen, visited, newPhotos, done, readingDirection

    static let standard: Set<Self> = [.name, .inside, .dates, .viewed, .size]
    func isAvailable(for media: FileStyle.MediaKind) -> Bool {
        switch self {
        case .duration, .codec, .fps, .bitrate, .transfer:
            return media == .video
        case .megapixels, .taken, .camera, .lens, .shutter, .aperture, .iso, .focalLength, .exposureBias,
             .colorSpace, .orientation, .progressive, .photos, .insidePhotos, .first, .last, .seen, .newPhotos,
             .readingDirection:
            return media == .photo
        default:
            return true
        }
    }

    var title: String {
        switch self {
        case .name: "Name"
        case .inside: "Inside"
        case .dates: "Dates"
        case .viewed: "Viewed"
        case .size: "Size"
        case .format: "Format"
        case .width: "Width"
        case .height: "Height"
        case .megapixels: "Megapixels"
        case .taken: "Date Taken"
        case .camera: "Camera"
        case .lens: "Lens"
        case .shutter: "Shutter Speed"
        case .aperture: "Aperture"
        case .iso: "ISO"
        case .focalLength: "Focal Length"
        case .exposureBias: "Exposure Bias"
        case .colorSpace: "Colour Profile"
        case .orientation: "Orientation"
        case .progressive: "Progressive"
        case .typeIdentifier: "Content Type"
        case .duration: "Duration"
        case .codec: "Codec"
        case .fps: "Frame Rate"
        case .bitrate: "Bitrate"
        case .transfer: "Dynamic Range"
        case .photos: "Photos"
        case .folders: "Subfolders"
        case .insidePhotos: "Photos in Subfolders"
        case .first: "Earliest Photo"
        case .last: "Latest Photo"
        case .seen: "Photos Viewed"
        case .visited: "Last Viewed"
        case .newPhotos: "New Photos"
        case .done: "Completed"
        case .readingDirection: "Reading Direction"
        }
    }
    var width: CGFloat {
        switch self {
        case .name: 160
        case .inside: 64
        case .dates: 118
        case .viewed: 104
        case .size: 76
        case .camera, .lens, .typeIdentifier: 200
        case .taken, .visited: 160
        case .first, .last: 118
        case .colorSpace, .insidePhotos, .readingDirection: 150
        default: max(84, CGFloat(title.count) * 7 + 16)
        }
    }
    private static let date: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()
    func text(for item: HomeCardItem) -> String {
        let f = item.facts, s = item.summary
        func number(_ value: Double?, suffix: String = "") -> String {
            guard let value, value.isFinite else { return "" }
            return FileFactsText.number(value) + suffix
        }
        func integer(_ value: Int?) -> String { value.map(String.init) ?? "" }
        func date(_ value: Date?) -> String { value.map(Self.date.string(from:)) ?? "" }
        switch self {
        case .name: return item.title
        case .inside, .dates, .viewed, .size: return "" // Existing rich cells.
        case .format: return item.format ?? ""
        case .width: return integer(f?.width)
        case .height: return integer(f?.height)
        case .megapixels: return f.flatMap(FileFactsText.megapixels) ?? ""
        case .taken: return date(f?.taken)
        case .camera: return f?.camera ?? ""
        case .lens: return f?.lens ?? ""
        case .shutter: return f?.exposure.flatMap { $0.isFinite && $0 > 0 ? FileFactsText.shutter($0) : nil } ?? ""
        case .aperture: return f?.aperture.map { "f/" + FileFactsText.number($0) } ?? ""
        case .iso: return integer(f?.iso)
        case .focalLength: return number(f?.focalLength, suffix: " mm")
        case .exposureBias: return f?.exposureBias.flatMap { $0.isFinite ? FileFactsText.bias($0) : nil } ?? ""
        case .colorSpace: return f?.colorSpace ?? ""
        case .orientation: return integer(f?.orientation)
        case .progressive: return f?.progressive.map { $0 ? "Yes" : "No" } ?? ""
        case .typeIdentifier: return f?.typeIdentifier ?? ""
        case .duration: return f?.duration.flatMap { $0.isFinite && $0 >= 0 ? FileFactsText.length($0) : nil } ?? ""
        case .codec: return f?.codec ?? ""
        case .fps: return f?.fps.flatMap { $0.isFinite && $0 > 0 ? FileFactsText.rate($0) : nil } ?? ""
        case .bitrate: return f?.bitrate.map { FileFactsText.number(Double($0) / 1_000_000) + " Mbps" } ?? ""
        case .transfer: return f?.transfer?.rawValue ?? ""
        case .photos: return integer(s?.photos ?? item.count)
        case .folders: return integer(s?.folders)
        case .insidePhotos: return s?.insidePhotos.map { (s?.insideIncomplete == true ? "≥ " : "") + String($0) } ?? ""
        case .first: return date(s?.first)
        case .last: return date(s?.last)
        case .seen: return integer(s?.seen)
        case .visited: return date(item.lastViewedAt ?? s?.visited)
        case .newPhotos: return s.map { String($0.new) } ?? ""
        case .done: return s.map { $0.done ? "Yes" : "No" } ?? ""
        case .readingDirection: return s.map { $0.rightToLeft ? "Right to Left" : "Left to Right" } ?? ""
        }
    }
}
