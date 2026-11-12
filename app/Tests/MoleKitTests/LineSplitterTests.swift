import Foundation
import Testing
@testable import MoleKit

@Suite struct LineSplitterTests {
    private func strings(_ lines: [Data]) -> [String] {
        lines.map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func splitsCompleteLines() {
        var splitter = LineSplitter()
        #expect(strings(splitter.append(Data("a\nb\n".utf8))) == ["a", "b"])
    }

    @Test func holdsPartialLineAcrossChunks() {
        var splitter = LineSplitter()
        #expect(splitter.append(Data("{\"x\":".utf8)).isEmpty)
        #expect(strings(splitter.append(Data("1}\n{\"y\"".utf8))) == ["{\"x\":1}"])
        #expect(strings(splitter.append(Data(":2}\n".utf8))) == ["{\"y\":2}"])
    }

    @Test func stripsCarriageReturnAndSkipsBlankLines() {
        var splitter = LineSplitter()
        #expect(strings(splitter.append(Data("a\r\n\n\r\nb\n".utf8))) == ["a", "b"])
    }

    @Test func finishReturnsUnterminatedTailOnce() {
        var splitter = LineSplitter()
        #expect(strings(splitter.append(Data("a\nrest".utf8))) == ["a"])
        #expect(splitter.finish().map { String(decoding: $0, as: UTF8.self) } == "rest")
        #expect(splitter.finish() == nil)
    }
}
