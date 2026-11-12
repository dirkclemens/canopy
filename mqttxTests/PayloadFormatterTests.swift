import Foundation
import Testing
@testable import mqttx

@Suite("Payload-Formatierung")
struct PayloadFormatterTests {

    @Test(arguments: [
        ("", PayloadKind.empty),
        ("42", .number),
        (" -3.5e2 ", .number),
        ("{\"a\":1}", .json),
        ("[1,2]", .json),
        ("<root><a>1</a></root>", .xml),
        ("hello world", .text),
        ("{kein json", .text),
    ])
    func detect(_ payload: String, _ expected: PayloadKind) {
        #expect(PayloadFormatter.detect(Data(payload.utf8)) == expected)
    }

    @Test func detectsBinary() {
        #expect(PayloadFormatter.detect(Data([0xff, 0xfe, 0x00, 0x01])) == .binary)
        #expect(PayloadFormatter.detect(Data([0x41, 0x00, 0x42])) == .binary)
    }

    @Test func autoFormat() {
        #expect(PayloadFormatter.autoFormat(for: Data("{\"a\":1}".utf8)) == .json)
        #expect(PayloadFormatter.autoFormat(for: Data("<a/>".utf8)) == .xml)
        #expect(PayloadFormatter.autoFormat(for: Data([0xff, 0x00])) == .hex)
        #expect(PayloadFormatter.autoFormat(for: Data("plain".utf8)) == .raw)
    }

    @Test func prettyJSONSortsKeys() throws {
        let pretty = try #require(PayloadFormatter.prettyJSON(Data("{\"b\":1,\"a\":\"x/y\"}".utf8)))
        #expect(pretty.contains("\n"))
        let a = try #require(pretty.range(of: "\"a\""))
        let b = try #require(pretty.range(of: "\"b\""))
        #expect(a.lowerBound < b.lowerBound)
        #expect(pretty.contains("x/y"))   // slashes not escaped
    }

    @Test func invalidJSONShowsWarning() {
        let rendered = PayloadFormatter.render(Data("nope".utf8), as: .json)
        #expect(rendered.hasPrefix("⚠︎"))
        #expect(rendered.hasSuffix("nope"))
    }

    @Test func prettyXML() throws {
        let pretty = try #require(PayloadFormatter.prettyXML(Data("<a><b>1</b></a>".utf8)))
        #expect(pretty.contains("\n"))
        #expect(pretty.contains("<b>1</b>"))
    }

    @Test func hexDump() {
        let dump = PayloadFormatter.hexDump(Data("ABCDEFGHIJKLMNOPQ".utf8))
        let lines = dump.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("00000000  41 42 43"))
        #expect(lines[0].hasSuffix("|ABCDEFGHIJKLMNOP|"))
        #expect(lines[1].hasPrefix("00000010  51"))
        #expect(lines[1].hasSuffix("|Q|"))
    }

    @Test func otherRenderings() {
        let data = Data([0x01, 0xff])
        #expect(PayloadFormatter.render(data, as: .base64) == "Af8=")
        #expect(PayloadFormatter.render(data, as: .binary) == "00000001 11111111")
        #expect(PayloadFormatter.render(data, as: .decimal) == "1 255")
    }

    @Test func rawTextFallsBackToLatin1() {
        #expect(PayloadFormatter.rawText(Data([0x48, 0xe9])) == "Hé")
    }
}

@Suite("Syntax-Highlighting")
struct SyntaxHighlighterTests {
    @Test func jsonTokensCoverInput() {
        let text = "{\n  \"key\" : \"va\\\"lue\",\n  \"n\" : -1.5e3,\n  \"b\" : true\n}"
        let tokens = SyntaxHighlighter.tokenizeJSON(text)
        #expect(tokens.map { String($0.0) }.joined() == text)
        let keys = tokens.filter { if case .key = $0.1 { true } else { false } }.map { String($0.0) }
        #expect(keys == ["\"key\"", "\"n\"", "\"b\""])
        #expect(tokens.contains { String($0.0) == "\"va\\\"lue\"" })
        #expect(tokens.contains { String($0.0) == "-1.5e3" })
    }

    @Test func xmlTokensCoverInput() {
        let text = "<?xml version=\"1.0\"?>\n<a x='1'><!-- c --><b>text</b></a>"
        let tokens = SyntaxHighlighter.tokenizeXML(text)
        #expect(tokens.map { String($0.0) }.joined() == text)
        #expect(tokens.contains { String($0.0) == "<!-- c -->" })
        #expect(tokens.contains { String($0.0) == "text" })
    }
}
