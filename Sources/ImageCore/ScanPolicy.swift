import Foundation

public struct ScanPolicy: Sendable {
    public var excludedFiles: Set<String>
    public var includedExtensions: Set<String>
    public init(excludedFiles: Set<String> = [], includedExtensions: Set<String> = ScanPolicy.imageExtensions) {
        self.excludedFiles = Set(excludedFiles.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        self.includedExtensions = includedExtensions
    }
    public static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "tif", "tiff", "heic", "heif", "avif", "gif", "bmp", "jp2", "j2k", "jpf", "tga", "ico", "svg", "dng", "cr2", "cr3", "nef", "arw", "psd", "psb"]
    private static let protectedRoots = ["/System", "/Library", "/Applications", "/usr", "/bin", "/sbin", "/private", "/dev", "/Network", "/Volumes/Preboot", "/Volumes/Recovery"]
    private static let packageExtensions: Set<String> = ["app", "photoslibrary", "photolibrary", "bundle", "framework", "plugin", "xcodeproj", "xcassets", "backupdb"]
    private static let ignoredDirectories: Set<String> = ["Library", "node_modules", ".git", ".Trash", ".Trashes", ".build", "Backups.backupdb", "Wallpapers", "Desktop Pictures", "ImageOptim Results"]

    public func excludes(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if excludedFiles.contains(path) { return true }
        if Self.protectedRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        return url.pathComponents.contains { component in
            Self.ignoredDirectories.contains(component) || Self.packageExtensions.contains((component as NSString).pathExtension.lowercased())
        }
    }
}
