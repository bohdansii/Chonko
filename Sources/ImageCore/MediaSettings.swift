import Foundation

public enum FileKind: String, CaseIterable, Identifiable, Sendable {
    case images, pdf, video
    public var id: String { rawValue }
    public var title: String {
        switch self { case .images: L("Зображення"); case .pdf: "PDF"; case .video: L("Відео") }
    }
    public var extensions: Set<String> {
        switch self {
        case .images: ScanPolicy.imageExtensions
        case .pdf: ["pdf"]
        case .video: ["mp4", "mov", "m4v"]
        }
    }
    public static func detect(_ url: URL) -> FileKind? {
        allCases.first { $0.extensions.contains(url.pathExtension.lowercased()) }
    }
}

public enum PDFProfile: String, CaseIterable, Identifiable, Sendable {
    case preserve, balanced, smaller
    public var id: String { rawValue }
    public var title: String {
        switch self { case .preserve: L("Зберегти якість"); case .balanced: L("Збалансовано"); case .smaller: L("Сильніше стиснення") }
    }
    public var dpi: Int { self == .smaller ? 120 : 180 }
    public var jpegQFactor: Double { self == .smaller ? 0.76 : 0.4 }
}

public enum VideoEncodingMode: String, CaseIterable, Identifiable, Sendable {
    case fast, compact
    public var id: String { rawValue }
    public var title: String { self == .fast ? L("Швидко") : L("Ретельніше") }
}
public enum VideoCodec: String, CaseIterable, Identifiable, Sendable {
    case hevc, h264
    public var id: String { rawValue }
    public var title: String { self == .hevc ? "HEVC / H.265" : "H.264" }
}
public struct VideoSettings: Sendable {
    public var mode: VideoEncodingMode = .fast
    public var codec: VideoCodec = .hevc
    /// Target video bitrate as a percentage of the source, separate from visual quality.
    public var bitratePercent: Double = 50
    public var maximumHeight: Int = 0
    public init() {}
    public func targetBitrate(source: Int64) -> Int64 {
        max(100_000, Int64(Double(source) * min(95, max(10, bitratePercent)) / 100))
    }
}
public struct MediaDetails: Sendable {
    public var pages: Int = 0
    public var hasProtectedFeatures = false
    public var duration: Double = 0
    public var frameRate: Double = 0
    public var bitrate: Int64 = 0
    public var codec: String = ""
    public var pixelFormat: String = ""
    public var audioStreams: Int = 0
    public var rotation: Int = 0
    public init() {}
}
public struct MediaTools: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func tool(_ name: String) -> URL { directory.appendingPathComponent(name) }
}
