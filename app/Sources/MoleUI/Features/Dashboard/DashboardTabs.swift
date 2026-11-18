import MoleKit
import SwiftUI

struct ProcessesTab: View {
    let snapshot: StatusSnapshot

    private static let columns = [
        GridColumn(title: "PID", width: 64),
        GridColumn(title: "名称"),
        GridColumn(title: "CPU%", width: 72, trailing: true),
        GridColumn(title: "内存", width: 96, trailing: true),
    ]

    var body: some View {
        let columns = Self.columns
        VStack(spacing: 0) {
            TableHeader(columns: columns)
            if snapshot.topProcesses.isEmpty {
                EmptyRow(text: "等待进程数据（mo 的第一帧不含进程列表）")
            }
            ForEach(snapshot.topProcesses) { process in
                DataRow {
                    Text("\(process.pid)").font(.mono(11)).foregroundStyle(Tokens.ink2).gridCell(columns[0])
                    VStack(alignment: .leading, spacing: 0) {
                        Text(process.name).font(.ui(13, weight: .semibold)).foregroundStyle(Tokens.ink).lineLimit(1)
                        if process.command != process.name {
                            Text(process.command).font(.ui(10.5)).foregroundStyle(Tokens.muted).lineLimit(1)
                        }
                    }
                    .gridCell(columns[1])
                    Text(Format.decimal(process.cpu)).font(.mono(12, weight: .medium)).gridCell(columns[2])
                    Text(process.memoryBytes.map(Format.bytes) ?? Format.percent(process.memory))
                        .font(.mono(12))
                        .gridCell(columns[3])
                }
            }
            ForEach(snapshot.processAlerts) { alert in
                DataRow {
                    StatusGlyph(kind: .failure)
                    Text("\(alert.name) 持续 \(alert.window) 超过 \(Format.decimal(alert.threshold, digits: 0))% CPU")
                        .font(.ui(11.5, weight: .semibold))
                        .foregroundStyle(Tokens.signalInk)
                    Spacer()
                    Text("PID \(alert.pid)").font(.mono(10)).foregroundStyle(Tokens.muted)
                }
            }
            if let zombies = snapshot.zombieCount, zombies > 0 {
                DataRow {
                    StatusGlyph(kind: .attention)
                    Text("僵尸进程 \(zombies)").font(.ui(11.5, weight: .semibold)).foregroundStyle(Tokens.ink)
                    Text(snapshot.zombieParents.map { "\($0.name) ×\($0.count)" }.joined(separator: " · "))
                        .font(.mono(10))
                        .foregroundStyle(Tokens.muted)
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
    }
}

struct DisksTab: View {
    let snapshot: StatusSnapshot

    private static let columns = [
        GridColumn(title: "", width: 8),
        GridColumn(title: "卷"),
        GridColumn(title: "已用 / 总量", width: 180, trailing: true),
        GridColumn(title: "占用", width: 150),
    ]

    var body: some View {
        let columns = Self.columns
        VStack(spacing: 0) {
            TableHeader(columns: columns)
            ForEach(snapshot.disks, id: \.mount) { disk in
                let glyph = Signals.disk(disk)
                DataRow {
                    StatusGlyph(kind: glyph).gridCell(columns[0])
                    VStack(alignment: .leading, spacing: 0) {
                        Text(disk.mount).font(.mono(12, weight: .semibold)).foregroundStyle(Tokens.ink)
                        Text("\(disk.device) · \(disk.fstype)\(disk.external ? " · 外接" : "")")
                            .font(.ui(10.5))
                            .foregroundStyle(Tokens.muted)
                    }
                    .gridCell(columns[1])
                    Text("\(Format.bytes(disk.used)) / \(Format.bytes(disk.total))").font(.mono(11)).gridCell(columns[2])
                    HStack(spacing: 8) {
                        Meter(fraction: disk.usedPercent / 100, signal: glyph != .done, width: 90)
                        Text(Format.percent(disk.usedPercent))
                            .font(.mono(11, weight: .medium))
                            .foregroundStyle(glyph != .done ? Tokens.signal : Tokens.ink)
                    }
                    .gridCell(columns[3])
                }
            }
            DataRow {
                Text("磁盘 IO").font(.ui(11.5, weight: .semibold)).foregroundStyle(Tokens.ink)
                Spacer()
                Text("读 \(Format.rate(mbPerSecond: snapshot.diskIo.readRate)) · 写 \(Format.rate(mbPerSecond: snapshot.diskIo.writeRate))")
                    .font(.mono(11))
                    .foregroundStyle(Tokens.ink2)
            }
        }
    }
}

struct NetworkTab: View {
    let snapshot: StatusSnapshot

    private static let columns = [
        GridColumn(title: "接口"),
        GridColumn(title: "下行", width: 120, trailing: true),
        GridColumn(title: "上行", width: 120, trailing: true),
    ]

    var body: some View {
        let columns = Self.columns
        VStack(spacing: 0) {
            TableHeader(columns: columns)
            ForEach(snapshot.network) { interface in
                DataRow {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(interface.name).font(.mono(12, weight: .semibold)).foregroundStyle(Tokens.ink)
                        Text(interface.ip.isEmpty ? "未连接" : interface.ip).font(.mono(10.5)).foregroundStyle(Tokens.muted)
                    }
                    .gridCell(columns[0])
                    Text(Format.rate(mbPerSecond: interface.rxRateMbs)).font(.mono(11)).gridCell(columns[1])
                    Text(Format.rate(mbPerSecond: interface.txRateMbs)).font(.mono(11)).gridCell(columns[2])
                }
            }
            KeyValueRow(
                key: "代理",
                value: snapshot.proxy.enabled ? "\(snapshot.proxy.type) \(snapshot.proxy.host)" : "未启用"
            )
        }
    }
}

struct PowerTab: View {
    let snapshot: StatusSnapshot

    var body: some View {
        let thermal = snapshot.thermal
        VStack(spacing: 0) {
            if snapshot.batteries.isEmpty {
                KeyValueRow(key: "电池", value: "—")
            }
            ForEach(Array(snapshot.batteries.enumerated()), id: \.offset) { item in
                let battery = item.element
                KeyValueRow(key: "电池", value: "\(Format.percent(battery.percent, digits: 0)) · \(battery.status) · \(battery.health)")
                KeyValueRow(key: "循环 / 容量", value: "\(battery.cycleCount) 次 · \(battery.capacity)%")
                if !battery.timeLeft.isEmpty { KeyValueRow(key: "剩余时间", value: battery.timeLeft) }
            }
            KeyValueRow(key: "电池温度", value: Format.celsius(thermal.batteryTemp))
            KeyValueRow(key: "CPU 温度", value: Format.celsius(thermal.cpuTemp))
            KeyValueRow(key: "系统功耗", value: Format.watts(thermal.systemPower))
            KeyValueRow(key: "适配器", value: Format.watts(thermal.adapterPower))
            ForEach(Array(snapshot.gpu.enumerated()), id: \.offset) { item in
                let gpu = item.element
                KeyValueRow(key: gpu.name, value: "\(gpu.coreCount) 核 · 占用 \(gpu.usage < 0 ? "—" : Format.percent(gpu.usage))")
            }
        }
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String

    var body: some View {
        DataRow {
            Text(key).font(.ui(11.5)).foregroundStyle(Tokens.ink2)
            Spacer()
            Text(value).font(.mono(11.5, weight: .medium)).foregroundStyle(Tokens.ink)
        }
    }
}
