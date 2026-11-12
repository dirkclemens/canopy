import SwiftUI

/// Lightweight tokenizers that colour pretty-printed JSON and XML.
enum SyntaxHighlighter {
    /// Larger payloads are shown without highlighting to keep the UI responsive.
    static let maxLength = 200_000

    enum Token {
        case key, string, number, keyword, punctuation, tag, attribute, comment, plain

        var color: Color {
            switch self {
            case .key: Color(nsColor: .systemPurple)
            case .string: Color(nsColor: .systemRed)
            case .number: Color(nsColor: .systemBlue)
            case .keyword: Color(nsColor: .systemPink)
            case .punctuation: .secondary
            case .tag: Color(nsColor: .systemTeal)
            case .attribute: Color(nsColor: .systemOrange)
            case .comment: Color(nsColor: .systemGreen)
            case .plain: .primary
            }
        }
    }

    static func highlight(_ text: String, as format: PayloadFormat) -> AttributedString {
        guard text.utf16.count <= maxLength else { return AttributedString(text) }
        let tokens: [(Substring, Token)] = switch format {
        case .json: tokenizeJSON(text)
        case .xml: tokenizeXML(text)
        default: [(text[...], .plain)]
        }
        var result = AttributedString()
        for (piece, token) in tokens {
            var part = AttributedString(piece)
            if token != .plain { part.foregroundColor = token.color }
            result.append(part)
        }
        return result
    }

    // MARK: JSON

    static func tokenizeJSON(_ text: String) -> [(Substring, Token)] {
        var tokens: [(Substring, Token)] = []
        var index = text.startIndex
        var plainStart = index

        func flushPlain(upTo end: String.Index) {
            if plainStart < end { tokens.append((text[plainStart..<end], .plain)) }
        }

        while index < text.endIndex {
            let char = text[index]
            if char == "\"" {
                flushPlain(upTo: index)
                var end = text.index(after: index)
                var escaped = false
                while end < text.endIndex {
                    let c = text[end]
                    if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { break }
                    end = text.index(after: end)
                }
                if end < text.endIndex { end = text.index(after: end) }
                // A string followed by ':' is an object key.
                var lookahead = end
                while lookahead < text.endIndex, text[lookahead].isWhitespace { lookahead = text.index(after: lookahead) }
                let isKey = lookahead < text.endIndex && text[lookahead] == ":"
                tokens.append((text[index..<end], isKey ? .key : .string))
                index = end
                plainStart = index
            } else if char == "-" || char.isNumber {
                flushPlain(upTo: index)
                var end = index
                while end < text.endIndex, "+-.eE0123456789".contains(text[end]) { end = text.index(after: end) }
                tokens.append((text[index..<end], .number))
                index = end
                plainStart = index
            } else if char.isLetter {
                flushPlain(upTo: index)
                var end = index
                while end < text.endIndex, text[end].isLetter { end = text.index(after: end) }
                tokens.append((text[index..<end], .keyword))
                index = end
                plainStart = index
            } else if "{}[],:".contains(char) {
                flushPlain(upTo: index)
                let end = text.index(after: index)
                tokens.append((text[index..<end], .punctuation))
                index = end
                plainStart = index
            } else {
                index = text.index(after: index)
            }
        }
        flushPlain(upTo: text.endIndex)
        return tokens
    }

    // MARK: XML

    static func tokenizeXML(_ text: String) -> [(Substring, Token)] {
        var tokens: [(Substring, Token)] = []
        var index = text.startIndex

        while index < text.endIndex {
            if text[index...].hasPrefix("<!--") {
                let end = text.range(of: "-->", range: index..<text.endIndex)?.upperBound ?? text.endIndex
                tokens.append((text[index..<end], .comment))
                index = end
            } else if text[index] == "<" {
                let end = text[index...].firstIndex(of: ">").map { text.index(after: $0) } ?? text.endIndex
                tokens.append(contentsOf: tokenizeTag(text[index..<end]))
                index = end
            } else {
                let end = text[index...].firstIndex(of: "<") ?? text.endIndex
                tokens.append((text[index..<end], .plain))
                index = end
            }
        }
        return tokens
    }

    /// Splits `<name attr="value">` into tag name, attributes and values.
    private static func tokenizeTag(_ tag: Substring) -> [(Substring, Token)] {
        var tokens: [(Substring, Token)] = []
        var index = tag.startIndex
        var nameDone = false
        while index < tag.endIndex {
            let char = tag[index]
            if char == "\"" || char == "'" {
                let close = tag[tag.index(after: index)...].firstIndex(of: char).map { tag.index(after: $0) } ?? tag.endIndex
                tokens.append((tag[index..<close], .string))
                index = close
            } else if "<>/?=!".contains(char) {
                tokens.append((tag[index...index], .punctuation))
                index = tag.index(after: index)
            } else if char.isWhitespace {
                let end = tag[index...].firstIndex { !$0.isWhitespace } ?? tag.endIndex
                tokens.append((tag[index..<end], .plain))
                index = end
            } else {
                let end = tag[index...].firstIndex { $0.isWhitespace || "<>/?=!\"'".contains($0) } ?? tag.endIndex
                tokens.append((tag[index..<end], nameDone ? .attribute : .tag))
                nameDone = true
                index = end
            }
        }
        return tokens
    }
}
