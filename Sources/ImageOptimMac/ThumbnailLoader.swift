import Foundation
import ImageIO
import AVFoundation
import CoreGraphics
import ImageCore

enum ThumbnailLoader {
    private static let cache = ThumbnailCache()
    @concurrent static func load(_ url: URL, pixels: Int = 96) async -> Data? {
        guard !Task.isCancelled else { return nil }
        let values = try? FileManager.default.attributesOfItem(atPath: url.path)
        let key = "\(url.path)|\(pixels)|\((values?[.size] as? NSNumber)?.int64Value ?? 0)|\((values?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
        if let data = await cache.lookup(key) { return data }
        guard !Task.isCancelled else { return nil }
        let image: CGImage
        if FileKind.detect(url) == .pdf {
            guard let pdf = CGPDFDocument(url as CFURL), let page = pdf.page(at: 1) else { return nil }
            let bounds = page.getBoxRect(.mediaBox)
            let factor = CGFloat(pixels) / max(bounds.width, bounds.height)
            let width = max(1, Int(bounds.width * factor)), height = max(1, Int(bounds.height * factor))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.concatenate(page.getDrawingTransform(.mediaBox, rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
            guard let rendered = context.makeImage() else { return nil }; image = rendered
        } else if FileKind.detect(url) == .video {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: pixels, height: pixels)
            guard let rendered = try? await generator.image(at: .zero).image else { return nil }; image = rendered
        } else {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let rendered = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: pixels] as CFDictionary) else { return nil }
            image = rendered
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        guard !Task.isCancelled else { return nil }
        let result = data as Data
        await cache.insert(result, key: key)
        return result
    }
}

private actor ThumbnailCache {
    private let storage = NSCache<NSString, NSData>()
    init() { storage.totalCostLimit = 24 * 1024 * 1024; storage.countLimit = 512 }
    func lookup(_ key: String) -> Data? { storage.object(forKey: key as NSString) as Data? }
    func insert(_ data: Data, key: String) { storage.setObject(data as NSData, forKey: key as NSString, cost: data.count) }
}
