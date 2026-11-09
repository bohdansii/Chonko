import Foundation
import Observation
import ImageCore

@MainActor @Observable final class ImageRowModel: Identifiable {
    let record: ImageRecord
    nonisolated var id: String { record.id }
    var startedAt: Date?
    var skipRequested = false
    var selected: Bool {
        didSet { if selected != oldValue { selectionChanged?(selected) } }
    }
    @ObservationIgnored var selectionChanged: (@MainActor (Bool) -> Void)?
    var phase = L("Готово до обробки")
    var progress: Double?
    var remainingSeconds: Double?
    var lastDiagnosticStage = ""
    var lastDiagnosticFraction = -1.0
    let diagnosticID = UUID().uuidString
    var running = false
    var completed = false
    var outputBytes: Int64?
    var outputURL: URL?
    var trashedOriginalURL: URL?
    var originalLocation: URL { trashedOriginalURL ?? record.url }
    var candidate: EncodedCandidate?
    var saveMode: SaveMode = .alongside
    var outputFolder: URL?
    init(_ record: ImageRecord) {
        self.record = record
        selected = record.isEligible
        if let restriction = record.restriction { phase = restriction }
    }
}
