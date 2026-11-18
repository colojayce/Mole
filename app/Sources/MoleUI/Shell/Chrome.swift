import SwiftUI

// MARK: - Top bar (56 pt)

struct TopBar<Actions: View>: View {
    let title: String
    var context: String? = nil
    var live: Bool = false
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 11) {
                Text(title).font(.ui(19, weight: .semibold)).tracking(-0.38).foregroundStyle(Tokens.ink)
                if let context {
                    Text(context)
                        .font(.ui(10))
                        .foregroundStyle(Tokens.ink2)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .frame(height: 23)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Tokens.canvas))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Tokens.line))
                }
                if live {
                    HStack(spacing: 6) {
                        LiveDot()
                        Text("实时").font(.ui(10.5)).foregroundStyle(Tokens.muted)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 7) { actions() }
        }
        .padding(.horizontal, 18)
        .frame(height: Tokens.Size.topBar)
        .background(Tokens.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(Tokens.line).frame(height: 1) }
    }
}

// MARK: - Summary band (lead 1.52 : metrics 1)

struct SummaryBand<Lead: View, Metrics: View>: View {
    var height: CGFloat = Tokens.Size.summary
    @ViewBuilder var lead: () -> Lead
    @ViewBuilder var metrics: () -> Metrics

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                lead()
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .frame(width: geometry.size.width * 1.52 / 2.52, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .top)
                Rectangle().fill(Tokens.line).frame(width: 1)
                VStack(spacing: 0) { metrics() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: height)
        .background(Tokens.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(Tokens.line).frame(height: 1) }
    }
}

struct MetricRow<Trailing: View>: View {
    let label: String
    let value: String
    var unit: String? = nil
    var sub: String? = nil
    var subIsSignal = false
    var showsDivider = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            SectionLabel(text: label)
            HStack(alignment: .bottom, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value).font(.mono(18, weight: .medium)).tracking(-0.8).foregroundStyle(Tokens.ink)
                    if let unit { Text(unit).font(.ui(10)).foregroundStyle(Tokens.muted) }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                trailing()
            }
            if let sub {
                Text(sub)
                    .font(.ui(10))
                    .foregroundStyle(subIsSignal ? Tokens.signal : Tokens.muted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if showsDivider { Rectangle().fill(Tokens.line).frame(height: 1) }
        }
    }
}

struct BigNumber: View {
    let value: String
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value).font(.mono(39, weight: .medium)).tracking(-2.1).foregroundStyle(Tokens.ink)
            Text(unit).font(.mono(18, weight: .medium)).foregroundStyle(Tokens.muted)
        }
    }
}

// MARK: - Tabs (48 pt)

struct TabItem<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    var count: String? = nil
    var hot = false
}

struct TabBar<ID: Hashable, Tools: View>: View {
    let tabs: [TabItem<ID>]
    @Binding var selection: ID
    @ViewBuilder var tools: () -> Tools
    @Namespace private var underline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 18) {
                ForEach(tabs) { tab in
                    let active = tab.id == selection
                    Button {
                        withAnimation(reduceMotion ? nil : Tokens.ease(0.24)) { selection = tab.id }
                    } label: {
                        HStack(spacing: 5) {
                            Text(tab.title)
                                .font(.ui(11.5, weight: active ? .semibold : .medium))
                                .foregroundStyle(active ? Tokens.ink : Tokens.muted)
                            if let count = tab.count {
                                Text(count)
                                    .font(.mono(10))
                                    .foregroundStyle(tab.hot ? Tokens.signal : (active ? Tokens.ink2 : Tokens.faint))
                            }
                        }
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .bottom) {
                            if active {
                                Rectangle().fill(Tokens.ink).frame(height: 2)
                                    .matchedGeometryEffect(id: "underline", in: underline)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) { tools() }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(height: Tokens.Size.tabBar)
        .background(Tokens.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(Tokens.line).frame(height: 1) }
    }
}

// MARK: - Table skeleton

struct GridColumn: Hashable, Sendable {
    let title: String
    var width: CGFloat? = nil
    var trailing = false

    var alignment: Alignment { trailing ? .trailing : .leading }
}

extension View {
    /// Fixed-width column when `width` is set, otherwise the column takes the remaining space.
    func gridCell(_ column: GridColumn) -> some View {
        frame(width: column.width, alignment: column.alignment)
            .frame(maxWidth: column.width == nil ? .infinity : nil, alignment: column.alignment)
    }
}

struct TableHeader: View {
    let columns: [GridColumn]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(columns.enumerated()), id: \.offset) { item in
                Text(item.element.title.uppercased())
                    .font(.ui(10, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(Tokens.muted)
                    .gridCell(item.element)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Tokens.Size.tableHeader)
        .background(Tokens.canvas)
        .overlay(alignment: .bottom) { Rectangle().fill(Tokens.line).frame(height: 1) }
    }
}

struct DataRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 12) { content() }
            .padding(.horizontal, 16)
            .frame(height: Tokens.Size.row)
            .background(Tokens.paper)
            .overlay(alignment: .bottom) { Rectangle().fill(Tokens.line.opacity(0.62)).frame(height: 1) }
    }
}

struct EmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.ui(10.5))
            .foregroundStyle(Tokens.muted)
            .frame(maxWidth: .infinity, minHeight: Tokens.Size.row * 2)
    }
}

struct FooterKey: Hashable {
    let key: String
    let label: String
}

struct TableFooter: View {
    let note: String
    var keys: [FooterKey] = []

    var body: some View {
        HStack(spacing: 12) {
            Text(note).lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 9) {
                ForEach(keys, id: \.self) { item in
                    HStack(spacing: 3) {
                        Text(item.key)
                            .padding(.horizontal, 3)
                            .background(RoundedRectangle(cornerRadius: 2).fill(Tokens.paper))
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Tokens.line))
                        Text(item.label)
                    }
                }
            }
        }
        .font(.mono(10))
        .foregroundStyle(Tokens.faint)
        .padding(.horizontal, 16)
        .frame(height: Tokens.Size.footer)
        .background(Tokens.canvas)
        .overlay(alignment: .top) { Rectangle().fill(Tokens.line).frame(height: 1) }
    }
}
