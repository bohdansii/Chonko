import Foundation
import Testing
import ImageCore
@testable import ImageOptimMac

@MainActor struct DiagnosticsTests {
    @Test func exportedReportIncludesRuntimeContextAndSafeCodecFailure() async throws {
        let center = DiagnosticCenter()
        do {
            _ = try await ExternalProcess.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "echo 'encoder failed /Users/private/secret.mp4'; exit 7"])
        } catch { center.record("video", "Pass 2 failed", error: error) }
        let data = try await center.exportData()
        let report = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(report["sessionID"] != nil && report["build"] != nil && report["memoryBytes"] != nil)
        let events = try #require(report["events"] as? [[String: Any]])
        let details = try #require(events.last?["details"] as? String)
        #expect(details.contains("exit=7") && details.contains("encoder failed"))
        #expect(!details.contains("secret.mp4") && !details.contains("/Users/private"))
    }

    @Test func journalIsBoundedPersistentAndExcludesErrorUserInfo() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "events.json")
        let center = DiagnosticCenter(fileURL: file)
        let error = NSError(domain: NSCocoaErrorDomain, code: 260, userInfo: [
            NSLocalizedDescriptionKey: "Private photo family-secret.jpg",
            NSFilePathErrorKey: "/Users/private/Photos/family-secret.jpg"
        ])
        for _ in 0..<205 { center.record("scan", "Image inspection failed", error: error) }
        await center.flush()
        #expect(center.events.count == 200)
        let report = try String(decoding: await center.exportData(), as: UTF8.self)
        #expect(!report.contains("family-secret") && !report.contains("/Users/") && !report.contains("Private photo"))
        let reloaded = DiagnosticCenter(fileURL: file)
        await reloaded.reload()
        #expect(reloaded.events.count == 200)
        reloaded.clear()
        await reloaded.flush()
        let cleared = DiagnosticCenter(fileURL: file)
        await cleared.reload()
        #expect(cleared.events.isEmpty)
    }
}
