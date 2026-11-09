import Foundation

public struct MediaProcessFailure: LocalizedError, Sendable {
    public let tool: String
    public let status: Int32?
    public let timedOut: Bool
    public let output: String
    public var errorDescription: String? {
        timedOut ? L("Інструмент перевищив час очікування. Оригінал збережено.") : L("Не вдалося обробити файл. Оригінал збережено. ") + output
    }
    public var diagnosticSummary: String {
        // The bundled tools receive private snapshots, but strip absolute paths before export.
        let redacted = output.replacingOccurrences(of: #"/[^\s\"'<>]+"#, with: "[path]", options: .regularExpression)
        return "tool=\(tool), exit=\(status.map(String.init) ?? "none"), timeout=\(timedOut); " + redacted
    }
}
