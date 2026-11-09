import SwiftUI

struct WorkspaceGlass: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.94),
                        in: .rect(cornerRadius: 24))

    }
}
