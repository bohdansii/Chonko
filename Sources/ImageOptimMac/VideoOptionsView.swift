import SwiftUI
import ImageCore

struct VideoOptionsView: View {
    @Bindable var model: AppModel
    var body: some View {
        Section(L("Відео")) {
            HStack(alignment: .center) {
                Text(L("Обробка"))
                Spacer(minLength: 12)
                Picker(L("Обробка"), selection: $model.videoSettings.mode) {
                    ForEach(VideoEncodingMode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.regular).fixedSize()
            }
            .onChange(of: model.videoSettings.mode) { _, mode in
                if mode == .compact { model.videoSettings.codec = .hevc }
            }
            HStack(alignment: .center) {
                Text(L("Кодек"))
                Spacer(minLength: 12)
                Picker(L("Кодек"), selection: $model.videoSettings.codec) {
                    ForEach(VideoCodec.allCases) { codec in
                        Text(codec.title).tag(codec).disabled(model.videoSettings.mode == .compact && codec == .h264)
                    }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.regular).fixedSize()
            }
        }
        Section(L("Розмір відео")) {
            HStack(alignment: .center) {
                Text(L("Сила стиснення"))
                Spacer(minLength: 12)
                Picker(L("Сила стиснення"), selection: $model.videoSettings.bitratePercent) {
                    Text(L("Легке")).tag(70.0)
                    Text(L("Збалансоване")).tag(50.0)
                    Text(L("Сильне")).tag(30.0)
                    if ![30.0, 50.0, 70.0].contains(model.videoSettings.bitratePercent) {
                        Text(L("Автопідібране")).tag(model.videoSettings.bitratePercent)
                    }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.regular)
                .fixedSize()
            }
            HStack(alignment: .center) {
                Text(L("Роздільність"))
                Spacer(minLength: 12)
                Picker(L("Роздільність"), selection: $model.videoSettings.maximumHeight) {
                    Text(L("Залишити початкову")).tag(0)
                    Text("1080p").tag(1080)
                    Text("720p").tag(720)
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.regular)
                .fixedSize()
            }
            Button(L("Перевірити фрагмент…"), systemImage: "play.rectangle") { model.previewVideo(automatic: false) }
                .disabled(model.chosen.isEmpty)
            Button(L("Підібрати стиснення…"), systemImage: "wand.and.stars") { model.previewVideo(automatic: true) }
                .disabled(model.chosen.isEmpty)
            DisclosureGroup(L("Докладніше про відео")) {
                Text(L("Швидко: апаратний кодек Apple для щоденної роботи. Ретельніше: програмний HEVC з одним проходом; повільніше, але може краще зберігати деталі за тієї самої ваги."))
                Text(L("Почни зі збалансованого стиснення. Легке краще зберігає деталі, сильне робить файл меншим, але зміни можуть бути помітнішими."))
                Text(L("Легке залишає 70% початкового бітрейту, збалансоване — 50%, сильне — 30%. Це кількість даних відео, а не відсоток якості. Розмір залежить також від звуку."))
                Text(L("Автопідбір перевіряє три короткі фрагменти й до трьох бітрейтів за SSIM. Це приблизна підказка; кінцевий результат потрібно оцінити візуально."))
                Text(L("Менший бітрейт може погіршити деталі. Зменшення у кілька разів без помітної різниці можливе не для кожного файла."))
                Text(L("Частоту кадрів і звукові доріжки зберігаємо. Якщо звук несумісний з MP4, файл буде пропущено з поясненням."))
                Text(L("HDR, Dolby Vision, прозорість, субтитри та складні доріжки поки пропускаються. Оригінали залишаються."))
                Text(L("Перевіряємо тривалість, доріжки та декодування всього результату. Нові режими спочатку зберігають копії поруч."))
            }
        }
    }
}
