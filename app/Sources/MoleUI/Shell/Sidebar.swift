import MoleKit
import SwiftUI

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                BrandMark()
                Text("MOLE").font(.ui(11, weight: .bold)).tracking(2.2).foregroundStyle(Tokens.ink)
            }
            .padding(.horizontal, 4)
            .padding(.top, 34) // clears the traffic lights of the hidden title bar

            VolumeCard(disk: model.status?.snapshot?.rootDisk)
                .padding(.top, 15)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Module.NavGroup.allCases, id: \.self) { group in
                        Text(group.rawValue)
                            .font(.ui(10, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(Tokens.faint)
                            .padding(.horizontal, 9)
                            .padding(.top, group == .monitor ? 0 : 15)
                            .padding(.bottom, 5)
                        ForEach(Module.allCases.filter { $0.group == group }) { module in
                            NavRow(
                                module: module,
                                selected: model.selection == module,
                                badge: badge(for: module)
                            ) {
                                model.selection = module
                            }
                        }
                    }
                }
            }
            .padding(.top, 17)

            SidebarFooter()
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 10)
        .frame(width: Tokens.Size.sidebarWidth)
    }

    private func badge(for module: Module) -> String? {
        switch module {
        case .dashboard:
            guard let score = model.status?.snapshot?.healthScore, score > 0 else { return nil }
            return "\(score)"
        default:
            return nil
        }
    }
}

/// Half-filled circle: the Mole mark used in the sidebar.
struct BrandMark: View {
    var body: some View {
        ZStack {
            Circle().fill(Tokens.ink)
            Rectangle().fill(Tokens.paper).frame(width: 7).offset(x: 3.5)
        }
        .frame(width: 14, height: 14)
        .clipShape(Circle())
    }
}

/// Target volume card. M1–M3 show the startup disk; switching volumes lands with Space (M6).
struct VolumeCard: View {
    let disk: StatusSnapshot.Disk?

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "internaldrive")
                .font(.system(size: 11))
                .foregroundStyle(Tokens.paper)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 3).fill(Tokens.ink))
            VStack(alignment: .leading, spacing: 1) {
                Text("启动盘").font(.ui(12, weight: .semibold)).foregroundStyle(Tokens.ink)
                Text(usage).font(.mono(10)).foregroundStyle(Tokens.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let disk { StatusGlyph(kind: Signals.disk(disk)) }
        }
        .padding(.horizontal, 9)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 4).fill(Tokens.paper))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Tokens.line))
    }

    private var usage: String {
        guard let disk else { return "—" }
        return "\(Format.bytes(disk.used)) / \(Format.bytes(disk.total))"
    }
}

struct NavRow: View {
    let module: Module
    let selected: Bool
    var badge: String? = nil
    var hot = false
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: module.symbol)
                    .font(.system(size: 12))
                    .frame(width: 15)
                    .foregroundStyle(selected ? Tokens.paper : Tokens.muted)
                Text(module.title)
                    .font(.ui(12, weight: .medium))
                    .foregroundStyle(selected ? Tokens.paper : Tokens.ink2)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.mono(10, weight: hot ? .semibold : .regular))
                        .foregroundStyle(badgeColor)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 31)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(selected ? Tokens.ink : (hovering ? Tokens.rowHover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var badgeColor: Color {
        if hot { return selected ? Tokens.onInkSignal : Tokens.signal }
        return selected ? Tokens.onInkMuted : Tokens.muted
    }
}

struct SidebarFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(Tokens.line).frame(height: 1)
            if let spec = model.runs.current {
                Button {
                    model.runs.presentDrawer()
                } label: {
                    HStack(spacing: 6) {
                        StatusGlyph(kind: model.runs.glyph)
                        Text(spec.commandText)
                            .font(.mono(10))
                            .foregroundStyle(Tokens.ink2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)
                    .frame(height: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("打开执行抽屉")
            }
            HStack(spacing: 6) {
                if model.status?.phase == .live { LiveDot() }
                Text(model.installation.map { "mo \($0.version)" } ?? "mo —")
                    .font(.mono(10))
                    .foregroundStyle(Tokens.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        }
        .padding(.top, 10)
    }
}
