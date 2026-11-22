import Foundation
import ImageIO
import CoreGraphics

enum ImageResizer {
    static func writePNG(input: URL, output: URL, width: Int, height: Int, hasAlpha: Bool, preserveMetadata: Bool) throws {
        try Task.checkCancellation()
        guard width > 0, height > 0,
              let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: false,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw ImageFailure.message(L("Не вдалося підготувати зображення для зменшення.")) }
        let color = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        let alpha: CGImageAlphaInfo = hasAlpha ? .premultipliedLast : .noneSkipLast
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: color, bitmapInfo: alpha.rawValue) else {
            throw ImageFailure.message(L("Не вистачає пам’яті для зміни розмірів. Оригінал збережено."))
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        try Task.checkCancellation()
        guard let resized = context.makeImage(), let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil) else {
            throw ImageFailure.message(L("Не вдалося створити зменшену копію."))
        }
        let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        var properties = preserveMetadata ? original : [:]
        properties[kCGImagePropertyOrientation] = original[kCGImagePropertyOrientation]
        properties[kCGImagePropertyPixelWidth] = width
        properties[kCGImagePropertyPixelHeight] = height
        if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = width
            exif[kCGImagePropertyExifPixelYDimension] = height
            properties[kCGImagePropertyExifDictionary] = exif
        }
        CGImageDestinationAddImage(destination, resized, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageFailure.message(L("Не вдалося записати зменшене зображення. Оригінал збережено.")) }
    }
}
