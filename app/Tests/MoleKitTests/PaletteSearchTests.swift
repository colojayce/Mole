import Testing
@testable import MoleKit

@Suite struct PaletteSearchTests {
    private let entries = [
        PaletteEntry(id: "uncle", group: "g", title: "Uncle", meta: ""),
        PaletteEntry(id: "clean", group: "g", title: "Clean", meta: "⌘2"),
        PaletteEntry(id: "disk", group: "g", title: "Disk cleanup", meta: ""),
        PaletteEntry(id: "calendar", group: "g", title: "Calendar", meta: ""),
        PaletteEntry(id: "space", group: "g", title: "Space", meta: ""),
        PaletteEntry(id: "preview", group: "g", title: "Clean 预览", meta: "mo clean --dry-run"),
    ]


    @Test func ranksPrefixThenWordStartThenContainsThenSubsequence() {
        #expect(PaletteSearch.filter(entries, query: "cl").map(\.id) == ["clean", "preview", "disk", "uncle", "calendar"])
    }

    @Test func matchesMetaAndIgnoresCase() {
        #expect(PaletteSearch.filter(entries, query: "DRY").map(\.id) == ["preview"])
        #expect(PaletteSearch.filter(entries, query: "zzz").isEmpty)
    }
}
