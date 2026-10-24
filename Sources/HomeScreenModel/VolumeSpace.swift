import Foundation

/// The room a volume has, as the line under the folder's name says it (and a Places card): `1.2 TB free`.
public enum VolumeSpace {
    /// Nil for no answer, or one of nothing (a share that reports 0 has not said how much it has).
    public static func line(free: Int64?) -> String? {
        guard let free, free > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: free, countStyle: .file) + " free"
    }
}
