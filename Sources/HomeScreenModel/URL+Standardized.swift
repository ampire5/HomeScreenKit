import Foundation

extension URL {
    /// `standardizedFileURL`, without its work for an absolute file URL whose path has no `.`, `..` or empty component
    /// and is not under `/private` (which standardizing drops from a path that exists without it, `/private/var` to
    /// `/var`): a listing's own URLs, nearly always, are their own standardized form. Loupe, 2026-10-28: standardizing
    /// 50 000 listed photos took ~55 ms a pass, and a folder's playlist made three passes on the main thread.
    public var quicklyStandardized: URL {
        guard isFileURL, baseURL == nil else { return standardizedFileURL }
        let plain = withUnsafeFileSystemRepresentation { path -> Bool in
            // "/." finds every "." and ".." component (and, harmlessly, a hidden file's name); "//" an empty one.
            guard let path else { return false }
            return strstr(path, "/.") == nil && strstr(path, "//") == nil && strncmp(path, "/private/", 9) != 0
        }
        return plain ? self : standardizedFileURL
    }
}
