import Foundation
import Synchronization

public struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
    let key: String
    let arguments: [String]
    public init(stringLiteral value: String) { key = value; arguments = [] }
    public init(stringInterpolation: StringInterpolation) { key = stringInterpolation.key; arguments = stringInterpolation.arguments }
    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity); arguments.reserveCapacity(interpolationCount) }
        public mutating func appendLiteral(_ literal: String) { key += literal }
        public mutating func appendInterpolation<T>(_ value: T) { key += "{\(arguments.count)}"; arguments.append(String(describing: value)) }
    }
}

public enum ImageLocalization {
    private struct State { var english: [String: String] = [:]; var useEnglish = false }
    private static let translations = Mutex(State())
    private static let placeholderExpression = try! NSRegularExpression(pattern: "\\{(\\d+)\\}")
    public static func configure(language: String, resourceURL: URL?) {
        var values: [String: String] = [:]
        if let url = resourceURL?.appendingPathComponent("en.json"),
           let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([String: String].self, from: data) { values = decoded }
        translations.withLock { $0 = State(english: values, useEnglish: language == "en") }
    }
    public static func relocalize(_ text: String) -> String {
        translations.withLock { state in
            let key = state.english.first(where: { $0.value == text })?.key ?? text
            return state.useEnglish ? state.english[key] ?? text : key
        }
    }
    public static var locale: Locale { translations.withLock { Locale(identifier: $0.useEnglish ? "en" : "uk") } }
    static func text(_ message: LocalizedMessage) -> String {
        let template = translations.withLock { $0.useEnglish ? $0.english[message.key] ?? message.key : message.key }
        // Split first, so a filename containing a placeholder cannot change another argument.
        var result = template
        for match in placeholderExpression.matches(in: template, range: NSRange(template.startIndex..., in: template)).reversed() {
            guard let range = Range(match.range(at: 1), in: template), let index = Int(template[range]), message.arguments.indices.contains(index),
                  let whole = Range(match.range, in: result) else { continue }
            result.replaceSubrange(whole, with: message.arguments[index])
        }
        return result
    }
}

public func L(_ message: LocalizedMessage) -> String { ImageLocalization.text(message) }

public func formatBytes(_ value: Int64) -> String {
    value.formatted(ByteCountFormatStyle(style: .file, spellsOutZero: false, locale: ImageLocalization.locale))
}

public func formatDate(_ value: Date, includeTime: Bool = false) -> String {
    value.formatted(Date.FormatStyle(date: .abbreviated, time: includeTime ? .shortened : .omitted, locale: ImageLocalization.locale))
}
