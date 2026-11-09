import Foundation
import ImageCore

struct DiagnosticEvent: Codable, Sendable, Identifiable {
    var id = UUID()
    var date = Date()
    let operation: String
    let message: String
    let domain: String?
    let code: Int?
    let details: String?

    init(operation: String, message: String, error: Error? = nil) {
        self.operation = operation
        self.message = message
        details = (error as? MediaProcessFailure)?.diagnosticSummary
        if let error {
            let ns = error as NSError
            let safeDomains = ["NSCocoaErrorDomain", "NSPOSIXErrorDomain", "NSOSStatusErrorDomain", "NSURLErrorDomain"]
            domain = safeDomains.contains(ns.domain) ? ns.domain : "ApplicationError"
            code = ns.code
        } else {
            domain = nil
            code = nil
        }
    }
}
