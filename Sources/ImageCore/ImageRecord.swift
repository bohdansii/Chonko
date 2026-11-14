import Foundation

public struct ImageRecord: Identifiable, Sendable {
    public let url: URL
    public let root: URL
    public let bytes: Int64
    public let modified: Date
    public let width: Int
    public let height: Int
    public let depth: Int
    public let hasAlpha: Bool
    public let restriction: String?
    public let media: MediaDetails?
    public let requiresSDRConversion: Bool
    public var kind: FileKind { FileKind.detect(url) ?? .images }
    public var id: String { url.path }
    public var isEligible: Bool { restriction == nil }
    public init(url: URL, root: URL, bytes: Int64, modified: Date, width: Int = 0, height: Int = 0, depth: Int = 8, hasAlpha: Bool = false, restriction: String? = nil, media: MediaDetails? = nil, requiresSDRConversion: Bool = false) {
        self.url = url; self.root = root; self.bytes = bytes; self.modified = modified
        self.width = width; self.height = height; self.depth = depth
        self.hasAlpha = hasAlpha; self.restriction = restriction; self.media = media; self.requiresSDRConversion = requiresSDRConversion
    }
}

public enum ImageFailure: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}
