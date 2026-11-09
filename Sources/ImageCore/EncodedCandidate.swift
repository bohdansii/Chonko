import Foundation

public struct EncodedCandidate: Sendable {
    public let source: ImageRecord
    public let directory: URL
    public let file: URL
    public let bytes: Int64
    public let sourceDigest: String
    public let settings: EncodeSettings
    public var mediaFormat: String? = nil
    public var isLarger: Bool { bytes >= source.bytes }
    public var savedBytes: Int64 { source.bytes - bytes }
    public func discard() { try? FileManager.default.removeItem(at: directory) }
}
