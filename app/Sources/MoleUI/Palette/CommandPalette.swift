import MoleKit
import SwiftUI

struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @ViewState private var query = ""
    @ViewState private var selectedIndex = 0
    @FocusState private var focused: Bool

    var body: some View {
        let results = PaletteSearch.filter(model.paletteEntries, query: query)
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Tokens.muted)
                TextField("", text: $query, prompt: Text("前往模块或运行预览命令…"))
                    .textFieldStyle(.plain)
                    .font(.ui(13.5))
                    .focused($focused)
                    .onSubmit { activate(results) }
                    .onKeyPress(.downArrow) { move(1, count: results.count); return .handled }
                    .onKeyPress(.upArrow) { move(-1, count: results.count); return .handled }
                    .onExitCommand { model.isPaletteOpen = false }
                Text("esc").font(.mono(10)).foregroundStyle(Tokens.faint)
            }
            .padding(.horizontal, 13)
            .frame(height: 52)
            .overlay(alignment: .bottom) { Rectangle().fill(Tokens.line).frame(height: 1) }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if results.isEmpty {
                            VStack(spacing: 2) {
                                Text("没有匹配的命令").font(.ui(11, weight: .semibold)).foregroundStyle(Tokens.ink)
                                Text("试试模块名，或 dry-run").font(.ui(10)).foregroundStyle(Tokens.muted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                        }
                        ForEach(Array(results.enumerated()), id: \.element.id) { item in
                            if item.offset == 0 || results[item.offset - 1].group != item.element.group {
                                Text(item.element.group.uppercased())
                                    .font(.ui(10, weight: .semibold))
                                    .tracking(1)
                                    .foregroundStyle(Tokens.faint)
                                    .padding(.horizontal, 9)
                                    .padding(.top, item.offset == 0 ? 5 : 9)
                                    .padding(.bottom, 4)
                            }
                            PaletteRow(entry: item.element, selected: item.offset == selectedIndex)
                                .id(item.element.id)
                                .onTapGesture {
                                    selectedIndex = item.offset
                                    activate(results)
                                }
                        }
                    }
                    .padding(5)
                }
                .frame(maxHeight: 424)
                .onChange(of: selectedIndex) { _, index in
                    if results.indices.contains(index) { proxy.scrollTo(results[index].id) }
                }
            }

            HStack(spacing: 10) {
                Text("↑↓ 选择 · ⏎ 执行 · esc 关闭")
                Spacer()
                Text("\(results.count) 项")
            }
            .font(.mono(10))
            .foregroundStyle(Tokens.muted)
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(Tokens.canvas)
            .overlay(alignment: .top) { Rectangle().fill(Tokens.line).frame(height: 1) }
        }
        .frame(width: 636)
        .background(Tokens.paper)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Size.radius))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Size.radius).strokeBorder(Tokens.line2))
        .shadow(color: Tokens.ink.opacity(0.1), radius: 2, y: 2)
        .shadow(color: Tokens.ink.opacity(0.35), radius: 45, y: 28)
        .onAppear { focused = true }
        .onChange(of: query) { selectedIndex = 0 }
    }

    private func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func activate(_ results: [PaletteEntry]) {
        guard results.indices.contains(selectedIndex) else { return }
        let id = results[selectedIndex].id
        model.isPaletteOpen = false
        model.performPaletteEntry(id)
    }
}

struct PaletteRow: View {
    let entry: PaletteEntry
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.title)
                .font(.ui(11.5, weight: .medium))
                .foregroundStyle(selected ? Tokens.paper : Tokens.ink2)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(entry.meta)
                .font(.mono(10))
                .foregroundStyle(selected ? Tokens.onInkMuted : Tokens.faint)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 3).fill(selected ? Tokens.ink : Color.clear))
        .contentShape(Rectangle())
    }
}
