import SwiftUI
import PDFKit
import AVKit
import ImageCore

struct MediaComparisonView: View {
    let row: ImageRowModel
    @Environment(\.dismiss) private var dismiss
    @State private var original: AVPlayer?
    @State private var result: AVPlayer?
    private var resultURL: URL? { row.candidate?.file ?? row.outputURL }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(row.record.url.lastPathComponent).font(.headline).lineLimit(1)
                Spacer()
                Button(L("Готово")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            HStack {
                VStack {
                    Text(L("Оригінал"))
                    if row.record.kind == .pdf { PDFPreview(url: row.originalLocation) }
                    else { VideoPlayer(player: original) }
                }
                VStack {
                    Text(L("Результат"))
                    if let resultURL {
                        if row.record.kind == .pdf { PDFPreview(url: resultURL) }
                        else { VideoPlayer(player: result) }
                    }
                }
            }
            if row.record.kind == .video {
                HStack {
                    Button(L("Відтворити обидва"), systemImage: "play.fill") {
                        original?.seek(to: .zero); result?.seek(to: .zero)
                        original?.play(); result?.play()
                    }
                    Button(L("Пауза"), systemImage: "pause.fill") { original?.pause(); result?.pause() }
                }
            }
        }
        .padding(20).frame(width: 960, height: 650)
        .onAppear {
            if row.record.kind == .video {
                original = AVPlayer(url: row.originalLocation)
                if let resultURL { result = AVPlayer(url: resultURL); result?.isMuted = true }
            }
        }
        .onDisappear { original?.pause(); result?.pause() }
    }
}

private struct PDFPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {}
}
