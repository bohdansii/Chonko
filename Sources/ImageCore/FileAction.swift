import Foundation

public enum FileAction: Sendable {
    case trash
    case move(URL)
}

public struct FileActionReport: Sendable {
    public var succeeded = Set<String>()
    public var failures: [String: String] = [:]
    public var cancelled = false
}
