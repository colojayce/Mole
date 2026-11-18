public struct PaletteEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let group: String
    public let title: String
    public let meta: String
    public let keywords: [String]

    public init(id: String, group: String, title: String, meta: String, keywords: [String] = []) {
        self.id = id
        self.group = group
        self.title = title
        self.meta = meta
        self.keywords = keywords
    }
}

public enum PaletteSearch {
    public static func filter(_ entries: [PaletteEntry], query: String) -> [PaletteEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return entries }
        var scored: [(score: Int, index: Int, entry: PaletteEntry)] = []
        for (index, entry) in entries.enumerated() {
            let fields = [entry.title, entry.meta] + entry.keywords
            if let best = fields.compactMap({ score($0.lowercased(), needle) }).max() {
                scored.append((best, index, entry))
            }
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        return scored.map(\.entry)
    }

    static func score(_ text: String, _ query: String) -> Int? {
        if text.hasPrefix(query) { return 3 }
        let words = text.split(whereSeparator: { " -/·".contains($0) })
        if words.contains(where: { $0.hasPrefix(query) }) { return 2 }
        if text.contains(query) { return 1 }
        var remaining = query.makeIterator()
        var next = remaining.next()
        for character in text where character == next {
            next = remaining.next()
        }
        return next == nil ? 0 : nil
    }
}
