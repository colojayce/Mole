import Foundation

/// Splits a byte stream into lines. A trailing partial line is held until the
/// next chunk arrives; `finish()` hands it over when the stream ends.
/// Lines come back without "\n" or a trailing "\r"; empty lines are skipped.
public struct LineSplitter: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            if line.last == 0x0D { line.removeLast() }
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    public mutating func finish() -> Data? {
        defer { buffer = Data() }
        var rest = buffer
        if rest.last == 0x0D { rest.removeLast() }
        return rest.isEmpty ? nil : Data(rest)
    }
}
