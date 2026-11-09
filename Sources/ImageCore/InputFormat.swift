import Foundation

public enum InputFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg, png, heic, tiff, webp, avif, gif, bmp, jpeg2000, tga, ico, other
    public var id: Self { self }
    public var title: String {
        switch self { case .jpeg2000: "JPEG 2000"; case .heic: "HEIC / HEIF"; case .other: L("Інші (SVG, RAW, PSD)"); default: rawValue.uppercased() }
    }
    public var extensions: Set<String> {
        switch self {
        case .jpeg: ["jpg", "jpeg"]
        case .heic: ["heic", "heif"]
        case .tiff: ["tif", "tiff"]
        case .jpeg2000: ["jp2", "j2k", "jpf"]
        case .other: ["svg", "dng", "cr2", "cr3", "nef", "arw", "psd", "psb"]
        default: [rawValue]
        }
    }
    public static let defaults = Set<InputFormat>([.jpeg, .png, .heic, .jpeg2000])
}
