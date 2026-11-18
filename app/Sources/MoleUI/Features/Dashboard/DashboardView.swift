import MoleKit
import SwiftUI

enum DashboardTab: String, CaseIterable, Hashable {
    case processes, disks, network, power

    var title: String {
        switch self {
        case .processes: "进程"
        case .disks: "磁盘"
        case .network: "网络"
        case .power: "电源"
        }
    }
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let status = model.status {
            DashboardContent(status: status)
                .onAppear { status.start() }
                .onDisappear { status.stop() }
                .background(
                    WindowOcclusionReader { visible in
                        if visible { status.start() } else { status.stop() }
                    }
                )
        }
    }
}

struct DashboardContent: View {
    let status: StatusService
    @ViewState private var tab: DashboardTab = .processes

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Dashboard", context: context, live: status.phase == .live) { EmptyView() }
                .enterOnAppear()
            if let snapshot = status.snapshot {
                SummaryBand {
                    CPULead(snapshot: snapshot, history: status.cpuHistory.elements)
                } metrics: {
                    memoryRow(snapshot)
                    diskRow(snapshot)
                    networkRow(snapshot)
                }
                .enterOnAppear(delay: 0.04)
                VStack(spacing: 0) {
                    TabBar(tabs: tabs(snapshot), selection: $tab) { EmptyView() }
                    ScrollView { tabContent(snapshot) }
                        .background(Tokens.paper)
                    TableFooter(
                        note: "按 CPU 排序 · mo status --watch --interval 1s",
                        keys: [FooterKey(key: "⌘K", label: "命令"), FooterKey(key: "⌘1–9", label: "模块")]
                    )
                }
                .enterOnAppear(delay: 0.08)
            } else {
                StatusPhaseView(status: status)
            }
        }
    }

    private var context: String? {
        if case .reconnecting = status.phase { return "重连中" }
        guard let s = status.snapshot else { return nil }
        let parts = [
            s.hardware.model,
            s.hardware.cpuModel,
            s.hardware.osVersion,
            s.uptime.isEmpty ? "" : "运行 \(s.uptime)",
        ].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func tabs(_ s: StatusSnapshot) -> [TabItem<DashboardTab>] {
        [
            TabItem(id: .processes, title: DashboardTab.processes.title, count: "\(s.topProcesses.count)",
                    hot: !s.processAlerts.isEmpty || (s.zombieCount ?? 0) > 0),
            TabItem(id: .disks, title: DashboardTab.disks.title, count: "\(s.disks.count)",
                    hot: s.disks.contains { Signals.disk($0) != .done }),
            TabItem(id: .network, title: DashboardTab.network.title, count: "\(s.network.count)"),
            TabItem(id: .power, title: DashboardTab.power.title),
        ]
    }

    @ViewBuilder private func tabContent(_ s: StatusSnapshot) -> some View {
        switch tab {
        case .processes: ProcessesTab(snapshot: s)
        case .disks: DisksTab(snapshot: s)
        case .network: NetworkTab(snapshot: s)
        case .power: PowerTab(snapshot: s)
        }
    }

    private func memoryRow(_ s: StatusSnapshot) -> some View {
        let memory = s.memory
        let used = Format.bytesParts(memory.used)
        let glyph = Signals.memory(memory)
        let pressure = memory.pressure.isEmpty ? "—" : memory.pressure
        return MetricRow(
            label: "Memory",
            value: used.number,
            unit: "\(used.unit) / \(Format.bytes(memory.total))",
            sub: "压力 \(pressure) · swap \(Format.bytes(memory.swapUsed))",
            subIsSignal: glyph != .done
        ) {
            Meter(fraction: memory.usedPercent / 100, signal: glyph == .failure)
        }
    }

    @ViewBuilder private func diskRow(_ s: StatusSnapshot) -> some View {
        if let disk = s.rootDisk {
            let glyph = Signals.disk(disk)
            let free = disk.total > disk.used ? disk.total - disk.used : 0
            MetricRow(
                label: "Startup Disk",
                value: Format.decimal(disk.usedPercent),
                unit: "%",
                sub: "可用 \(Format.bytes(free)) · 废纸篓 \(Format.bytes(s.trashSize))",
                subIsSignal: glyph != .done
            ) {
                Meter(fraction: disk.usedPercent / 100, signal: glyph != .done)
            }
        } else {
            MetricRow(label: "Startup Disk", value: "—") { EmptyView() }
        }
    }

    private func networkRow(_ s: StatusSnapshot) -> some View {
        let rx = s.network.reduce(0) { $0 + $1.rxRateMbs }
        let tx = s.network.reduce(0) { $0 + $1.txRateMbs }
        let proxy = s.proxy.enabled ? " · 代理 \(s.proxy.type)" : ""
        return MetricRow(
            label: "Network",
            value: Format.rate(mbPerSecond: rx),
            unit: "↓",
            sub: "↑ \(Format.rate(mbPerSecond: tx))\(proxy)",
            showsDivider: false
        ) {
            MicroBars(values: status.rxHistory.elements)
        }
    }
}

struct CPULead: View {
    let snapshot: StatusSnapshot
    let history: [Double]

    var body: some View {
        let cpu = snapshot.cpu
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "CPU")
                Spacer()
                Text("load \(Format.decimal(cpu.load1, digits: 2)) · \(Format.decimal(cpu.load5, digits: 2)) · \(Format.decimal(cpu.load15, digits: 2))")
                    .font(.mono(10))
                    .foregroundStyle(Tokens.ink2)
            }
            BigNumber(value: Format.decimal(cpu.usage), unit: "%")
                .padding(.top, 2)
            Text(coreSummary)
                .font(.ui(10.5))
                .foregroundStyle(Tokens.muted)
                .lineLimit(1)
            Sparkline(values: history, maxValue: 100, capacity: StatusService.historyCapacity)
                .frame(height: 70)
                .padding(.top, 8)
            HStack(spacing: 8) {
                CoreHeatmap(perCore: cpu.perCore)
                Spacer()
                Text("近 \(StatusService.historyCapacity) 帧").font(.mono(10)).foregroundStyle(Tokens.faint)
            }
            .padding(.top, 6)
        }
    }

    private var coreSummary: String {
        let cpu = snapshot.cpu
        var parts = ["\(cpu.logicalCpu) 核"]
        if cpu.pCoreCount > 0 { parts.append("P\(cpu.pCoreCount) E\(cpu.eCoreCount)") }
        if snapshot.healthScore > 0 { parts.append("健康分 \(snapshot.healthScore) \(snapshot.healthScoreMsg)") }
        return parts.joined(separator: " · ")
    }
}

struct StatusPhaseView: View {
    let status: StatusService

    var body: some View {
        VStack(spacing: 6) {
            switch status.phase {
            case .failed(let message):
                StatusGlyph(kind: .failure)
                Text("Dashboard 已停止").font(.ui(11.5, weight: .semibold)).foregroundStyle(Tokens.ink)
                Text(message)
                    .font(.ui(10.5))
                    .foregroundStyle(Tokens.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .textSelection(.enabled)
                Button("重试") {
                    status.stop()
                    status.start()
                }
                .buttonStyle(MoleButtonStyle())
                .padding(.top, 4)
            case .reconnecting(let reason):
                LiveDot()
                Text("mo status 已断开，正在重连").font(.ui(11.5, weight: .semibold)).foregroundStyle(Tokens.ink)
                Text(reason).font(.ui(10.5)).foregroundStyle(Tokens.muted).frame(maxWidth: 380)
            default:
                LiveDot()
                Text("正在连接 mo status…").font(.ui(11.5, weight: .semibold)).foregroundStyle(Tokens.ink)
                Text("mo status --watch --interval 1s").font(.mono(10)).foregroundStyle(Tokens.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
