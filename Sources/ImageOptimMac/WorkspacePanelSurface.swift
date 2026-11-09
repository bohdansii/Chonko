import SwiftUI

struct WorkspacePanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.45),
                        in: .rect(cornerRadius: 24))
            .background(WorkspacePanelBackdrop())
            .clipShape(.rect(cornerRadius: 24))
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}
