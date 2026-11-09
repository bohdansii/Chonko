import Foundation

public enum SaveMode: String, CaseIterable, Identifiable, Sendable {
    case alongside, folder, replace
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .alongside: L("Поруч з оригіналами")
        case .folder: L("В окрему папку")
        case .replace: L("Замінити · оригінали в Кошик")
        }
    }
}
