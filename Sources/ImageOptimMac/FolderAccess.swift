import ImageCore
import Foundation
import Observation

@MainActor @Observable final class FolderAccess: Identifiable {
    let id: String
    private let titleKey: LocalizedMessage
    var title: String { L(titleKey) }
    let icon: String
    var url: URL
    var status = L("Ще не обрано")
    var checking = false
    init(directory: FileManager.SearchPathDirectory, title: LocalizedMessage, icon: String) {
        self.id = String(directory.rawValue)
        self.titleKey = title; self.icon = icon
        self.url = FileManager.default.urls(for: directory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
    }
    static func suggested() -> [FolderAccess] {
        [FolderAccess(directory: .desktopDirectory, title: "Робочий стіл", icon: "desktopcomputer"),
         FolderAccess(directory: .documentDirectory, title: "Документи", icon: "doc"),
         FolderAccess(directory: .downloadsDirectory, title: "Викачане", icon: "arrow.down.circle"),
         FolderAccess(directory: .picturesDirectory, title: "Зображення", icon: "photo.on.rectangle")]
    }
}
