import Foundation
import ImageIO

public enum OutputFormat: String, CaseIterable, Identifiable, Sendable {
    case webp, avif, heic, png, jpeg, tiff, jpeg2000
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .webp: "WebP"
        case .jpeg2000: "JPEG 2000"
        default: rawValue.uppercased()
        }
    }
    public var fileExtension: String {
        switch self { case .jpeg: "jpg"; case .jpeg2000: "jp2"; default: rawValue }
    }
    public var imageIOType: String? {
        switch self {
        case .webp: nil
        case .avif: "public.avif"
        case .heic: "public.heic"
        case .png: "public.png"
        case .jpeg: "public.jpeg"
        case .tiff: "public.tiff"
        case .jpeg2000: "public.jpeg-2000"
        }
    }
    private static let systemEncoders = Set(CGImageDestinationCopyTypeIdentifiers() as! [String])
    public var isAvailable: Bool { imageIOType.map { Self.systemEncoders.contains($0) } ?? true }
    public var alwaysLossless: Bool { self == .png || self == .tiff }
    public var supportsLossless: Bool { alwaysLossless || self == .webp || self == .jpeg2000 }
    public var canChooseLossless: Bool { supportsLossless && !alwaysLossless }
    public var qualityMaximum: Int { self == .avif || self == .jpeg2000 ? 99 : 100 }
    public var suggestedQuality: Int {
        switch self { case .avif: 60; case .jpeg: 80; default: 75 }
    }
    public var shortDescription: String {
        switch self {
        case .webp: L("Для компактних фото й графіки, зокрема з прозорістю.")
        case .avif: L("Для компактного зберігання й сучасного вебу.")
        case .heic: L("Для фотографій у середовищі Apple.")
        case .png: L("Для скриншотів і прозорої графіки без втрат.")
        case .jpeg: L("Для фотографій із широкою сумісністю.")
        case .tiff: L("Для редагування й зберігання без втрат.")
        case .jpeg2000: L("Для спеціалізованих програм та архівів.")
        }
    }
    public var qualitySummary: String {
        switch self {
        case .webp: L("75 — стандарт Google. Навіть 100 тут не означає «без втрат».")
        case .avif: L("Діапазон 1–99. Режим AVIF без втрат у цій збірці недоступний.")
        case .heic, .jpeg: L("100 — найвище налаштування цього кодека, а не гарантія «без втрат».")
        case .png, .tiff: L("Завжди без втрат — повзунок якості не потрібен.")
        case .jpeg2000: L("1–99 — із втратами; без втрат — окремим перемикачем.")
        }
    }
    public var qualityExplanation: String {
        switch self {
        case .webp:
            L("Шкала libwebp: 1–100. Більше число зазвичай означає більше деталей і більший файл. 75 — стандарт Google. Навіть 100 у цьому режимі не є стисненням без втрат; для нього ввімкни окремий перемикач.")
        case .avif:
            L("Шкала цієї реалізації: 1–99, передається ImageIO як 0,01–0,99. У перевіреному системному кодеку значення 1,00 не створює AVIF, тому 100 не пропонуємо. Це обмеження кодека, а не стандарту AVIF. У цьому застосунку AVIF поки лише з втратами. 60 в AVIF не еквівалентне 60 у JPEG або WebP.")
        case .heic:
            L("Шкала ImageIO: 1–100 → 0,01–1,00. 100 задає найвищу якість цього системного кодека, але не гарантує піксельної тотожності. Тому для HEIC не пропонуємо режим «без втрат». Число не можна прямо порівнювати з якістю JPEG, WebP чи AVIF.")
        case .png:
            L("PNG стискається без втрат: декодовані пікселі не погіршуються. Повзунок якості не потрібен. Менший файл не гарантований — перетворення фотографії JPEG на PNG часто збільшує вагу.")
        case .jpeg:
            L("Шкала ImageIO: 1–100 → 0,01–1,00. Це налаштування кодека, а не відсоток збережених деталей. Навіть 100 не робить звичайний JPEG форматом без втрат. Повторне кодування JPEG може додатково погіршити зображення.")
        case .tiff:
            L("Використовуємо LZW — стиснення без втрат. Повзунка якості немає: пікселі не спрощуються, змінюється спосіб їх запису. TIFF може залишитися великим і не є типовим форматом для сайтів.")
        case .jpeg2000:
            L("Два окремі режими: без втрат або якість 1–99. У системному кодеку 1,00 використовується для режиму без втрат, тому він доступний через перемикач, а не як 100 на повзунку. Шкала lossy не еквівалентна шкалі звичайного JPEG.")
        }
    }
    public var startingPoint: String {
        self == .webp ? L("75 — офіційне значення Google за замовчуванням. З нього варто почати порівняння.") : L("\(suggestedQuality) — наша стартова точка, не універсальна рекомендація Apple. Перевір обличчя, текст, градієнти та дрібні деталі; за потреби підвищ якість.")
    }
    public var explanation: String {
        switch self {
        case .webp: L("WebP — формат Google для фото й графіки. Підтримує прозорість, стиснення з втратами та окремий режим без втрат. Обмежений 8 бітами на канал і 16 383 пікселями на сторону.")
        case .png: L("PNG — формат зі стисненням без втрат і підтримкою прозорості. Підходить для скриншотів, схем і графіки. Для фотографій результат може бути великим.")
        case .jpeg: L("JPEG — формат для фотографій із широкою сумісністю. Стиснення з втратами; прозорість не підтримується. Зображення з прозорістю застосунок пропускає.")
        case .avif: L("AVIF зберігає зображення за допомогою AV1. Підходить для компактних фото та графіки, підтримує прозорість. Стандарт також підтримує HDR і lossless, але ця версія застосунку конвертує лише статичні 8-бітні SDR-зображення з втратами. Кодування може тривати довше, ніж у простіших форматів.")
        case .heic: L("HEIC — варіант контейнера HEIF зі стисненням HEVC, поширений на пристроях Apple. Зручно для локального зберігання фото; перед передаванням перевір сумісність програми отримувача. Читаємо HEIC/HEIF, нові файли записуємо з розширенням .heic.")
        case .tiff: L("TIFF — формат для зберігання растрових зображень і роботи у графічних програмах. Тут записуємо один кадр із LZW без втрат. Підтримує прозорість, але часто важить більше за сучасні формати для вебу.")
        case .jpeg2000: L("JPEG 2000 (.jp2) — окремий від звичайного JPEG формат із вейвлетним стисненням. Підтримує прозорість і режими з втратами та без них. Корисний для спеціалізованих архівів і програм; сумісність потрібно перевіряти.")
        }
    }
    public var documentation: URL {
        switch self {
        case .webp: URL(string: "https://developers.google.com/speed/webp/docs/cwebp")!
        case .png: URL(string: "https://www.w3.org/TR/png-3/")!
        case .jpeg: URL(string: "https://developer.apple.com/documentation/imageio/kcgimagedestinationlossycompressionquality")!
        case .avif: URL(string: "https://aomedia.org/specifications/avif/")!
        case .heic: URL(string: "https://support.apple.com/116944")!
        case .tiff: URL(string: "https://developer.apple.com/documentation/imageio/kcgimagepropertytiffcompression")!
        case .jpeg2000: URL(string: "https://jpeg.org/jpeg2000/")!
        }
    }
    public var qualityDocumentation: URL {
        self == .webp || alwaysLossless ? documentation : URL(string: "https://developer.apple.com/documentation/imageio/kcgimagedestinationlossycompressionquality")!
    }
}

public struct EncodeSettings: Sendable {
    public var format: OutputFormat
    public var lossless: Bool
    public var quality: Int
    public var preserveMetadata: Bool
    public init(format: OutputFormat = .webp, lossless: Bool = false, quality: Int = 75, preserveMetadata: Bool = true) {
        self.format = format
        self.lossless = lossless || format.alwaysLossless
        self.quality = min(format.qualityMaximum, max(1, quality))
        self.preserveMetadata = preserveMetadata
    }
    public var webpArguments: [String] {
        var args = ["-progress", "-mt", "-m", "4", "-metadata", preserveMetadata ? "all" : "icc"]
        if lossless { args += ["-lossless", "-exact", "-q", "75"] }
        else { args += ["-q", String(quality), "-alpha_q", "100"] }
        return args
    }
}
