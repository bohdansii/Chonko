import SwiftUI
import AVKit
import ImageCore

struct VideoPreviewView: View {
    let preview: VideoPreview
    @Environment(\.dismiss) private var dismiss
    @State private var original: AVPlayer?
    @State private var result: AVPlayer?
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(L("Тестовий фрагмент")).font(.headline)
                Spacer()
                Button(L("Готово")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            HStack {
                VStack { Text(L("Оригінал")); VideoPlayer(player: original) }
                VStack { Text(L("Результат")); VideoPlayer(player: result) }
            }
            Text(L("Бітрейт: \(Int(preview.bitratePercent))% від початкового. Це короткий фрагмент, а не повний результат."))
            if let score = preview.similarity {
                Text("SSIM: \(score.formatted(.number.precision(.fractionLength(4))))")
                Text(L("Технічна оцінка схожості, не відсоток якості й не гарантія відсутності видимих змін. Порівняй фрагмент самостійно."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button(L("Відтворити обидва"), systemImage: "play.fill") {
                    Task {
                        await original?.seek(to: CMTime(seconds: preview.start, preferredTimescale: 600))
                        await result?.seek(to: .zero)
                        original?.play(); result?.play()
                    }
                }
                Button(L("Пауза"), systemImage: "pause.fill") { original?.pause(); result?.pause() }
            }
        }
        .padding(20).frame(width: 960, height: 650)
        .onAppear {
            original = AVPlayer(url: preview.original)
            original?.seek(to: CMTime(seconds: preview.start, preferredTimescale: 600))
            original?.currentItem?.forwardPlaybackEndTime = CMTime(seconds: preview.start + preview.duration, preferredTimescale: 600)
            result = AVPlayer(url: preview.file); result?.isMuted = true
        }
        .onDisappear { original?.pause(); result?.pause(); preview.discard() }
    }
}
