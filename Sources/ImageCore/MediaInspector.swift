import Foundation
import PDFKit
import CoreGraphics

public enum MediaInspector {
    @concurrent public static func inspect(url: URL, root: URL, bytes: Int64, modified: Date, tools: MediaTools) async -> ImageRecord {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attributes[.referenceCount] as? Int ?? 1) <= 1 else { throw ImageFailure.message(L("Файл має жорсткі посилання: пропущено для безпечної заміни.")) }
            switch FileKind.detect(url) {
            case .pdf: return try inspectPDF(url: url, root: root, bytes: bytes, modified: modified)
            case .video: return try await inspectVideo(url: url, root: root, bytes: bytes, modified: modified, tools: tools)
            default: return ImageScanner.inspect(url: url, root: root, bytes: bytes, modified: modified)
            }
        } catch {
            return ImageRecord(url: url, root: root, bytes: bytes, modified: modified, restriction: error.localizedDescription)
        }
    }

    public static func inspectPDF(url: URL, root: URL, bytes: Int64, modified: Date) throws -> ImageRecord {
        guard let document = PDFDocument(url: url), document.pageCount > 0,
              let cg = CGPDFDocument(url as CFURL), let catalog = cg.catalog else {
            throw ImageFailure.message(L("Не вдалося прочитати PDF."))
        }
        guard !document.isEncrypted else { throw ImageFailure.message(L("Захищений PDF пропущено. Паролі та шифрування не змінюємо.")) }
        var entry: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(catalog, "AcroForm", &entry) || CGPDFDictionaryGetDictionary(catalog, "Perms", &entry) {
            throw ImageFailure.message(L("PDF містить форми або цифровий підпис. Оригінал залишаємо."))
        }
        var details = MediaDetails(); details.pages = document.pageCount
        for key in ["StructTreeRoot", "OCProperties", "Names", "Outlines"] {
            if CGPDFDictionaryGetDictionary(catalog, key, &entry) { details.hasProtectedFeatures = true }
        }
        var intents: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(catalog, "OutputIntents", &intents) { details.hasProtectedFeatures = true }
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            if document.page(at: index)?.annotations.isEmpty == false { details.hasProtectedFeatures = true }
        }
        return ImageRecord(url: url, root: root, bytes: bytes, modified: modified, media: details)
    }

    @concurrent public static func inspectVideo(url: URL, root: URL, bytes: Int64, modified: Date, tools: MediaTools) async throws -> ImageRecord {
        let data = try await ExternalProcess.run(tools.tool("ffprobe"), ["-v", "error", "-show_streams", "-show_format", "-of", "json", url.path], timeout: .seconds(30))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let streams = json["streams"] as? [[String: Any]] ?? []
        let videos = streams.filter { $0["codec_type"] as? String == "video" }
        let audio = streams.filter { $0["codec_type"] as? String == "audio" }
        guard videos.count == 1, let video = videos.first,
              streams.allSatisfy({ ["video", "audio"].contains($0["codec_type"] as? String ?? "") }) else {
            throw ImageFailure.message(L("Кілька відеодоріжок, субтитри або службові доріжки поки пропускаються, щоб їх не втратити."))
        }
        let format = json["format"] as? [String: Any] ?? [:]
        func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? Double(value as? String ?? "") ?? 0 }
        let duration = max(number(video["duration"]), number(format["duration"]))
        guard duration.isFinite, duration > 0, let width = video["width"] as? Int, let height = video["height"] as? Int,
              width > 0, height > 0, Int64(width) * Int64(height) <= 40_000_000 else {
            throw ImageFailure.message(L("Невідома тривалість або непідтримувані розміри відео."))
        }
        let sourceCodec = video["codec_name"] as? String ?? ""
        guard ["h264", "hevc", "mpeg4", "prores"].contains(sourceCodec) else { throw ImageFailure.message(L("Відеокодек \(sourceCodec) поки не підтримується.")) }
        let pixelFormat = video["pix_fmt"] as? String ?? ""
        let transfer = video["color_transfer"] as? String ?? ""
        let sideData = video["side_data_list"] as? [[String: Any]] ?? []
        if ["smpte2084", "arib-std-b67"].contains(transfer) || pixelFormat.contains("10") || pixelFormat.contains("12") || pixelFormat.contains("alpha") || pixelFormat.contains("yuva") || sideData.contains(where: { ($0["side_data_type"] as? String ?? "").contains("DOVI") }) {
            throw ImageFailure.message(L("HDR, Dolby Vision, понад 8 біт або прозорість відео поки пропускаються для захисту кольорів."))
        }
        if let field = video["field_order"] as? String, field != "progressive" && field != "unknown" {
            throw ImageFailure.message(L("Черезрядкове відео потребує окремої обробки; оригінал залишаємо."))
        }
        let rotation = Int(number(sideData.first(where: { $0["rotation"] != nil })?["rotation"]))
        let rateParts = (video["avg_frame_rate"] as? String ?? "0/1").split(separator: "/").compactMap { Double($0) }
        let rate = rateParts.count == 2 && rateParts[1] != 0 ? rateParts[0] / rateParts[1] : 0
        var details = MediaDetails()
        details.duration = duration; details.frameRate = rate
        details.bitrate = Int64(number(video["bit_rate"]))
        if details.bitrate <= 0 {
            let total = max(number(format["bit_rate"]), Double(bytes) * 8 / duration)
            details.bitrate = Int64(max(100_000, total - audio.reduce(0) { $0 + number($1["bit_rate"]) }))
        }
        details.codec = video["codec_name"] as? String ?? ""
        details.pixelFormat = pixelFormat; details.audioStreams = audio.count; details.rotation = rotation
        let rotated = abs(rotation) % 180 == 90
        return ImageRecord(url: url, root: root, bytes: bytes, modified: modified, width: rotated ? height : width, height: rotated ? width : height, media: details)
    }
}
