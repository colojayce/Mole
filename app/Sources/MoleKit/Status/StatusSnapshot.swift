import Foundation

/// One frame of `mo status --json` / `--watch` (see cmd/status/metrics.go).
/// Keys are snake_case on the wire and decoded with `.convertFromSnakeCase`.
/// Top-level arrays may be `null` (the fast first frame); they decode as empty.
/// Fields the UI does not use (bluetooth, sensors, network_history, …) are ignored.
public struct StatusSnapshot: Decodable, Sendable, Equatable {
    public var collectedAt: String
    public var host: String
    public var platform: String
    public var uptime: String
    public var procs: Int
    public var hardware: Hardware
    public var healthScore: Int
    public var healthScoreMsg: String
    public var cpu: CPU
    public var gpu: [GPU]
    public var memory: Memory
    public var disks: [Disk]
    public var trashSize: UInt64
    public var diskIo: DiskIO
    public var network: [NetworkInterface]
    public var proxy: Proxy
    public var batteries: [Battery]
    public var thermal: Thermal
    public var topProcesses: [TopProcess]
    public var zombieCount: Int?
    public var zombieParents: [ZombieParent]
    public var processAlerts: [ProcessAlert]

    /// mo's first frame comes from a fast collector: no process list, blank hardware.
    public var isFastFrame: Bool { topProcesses.isEmpty && hardware.model.isEmpty }

    public var rootDisk: Disk? { disks.first { $0.mount == "/" } ?? disks.first }

    enum CodingKeys: String, CodingKey {
        case collectedAt, host, platform, uptime, procs, hardware, healthScore, healthScoreMsg
        case cpu, gpu, memory, disks, trashSize, diskIo, network, proxy, batteries, thermal
        case topProcesses, zombieCount, zombieParents, processAlerts
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        collectedAt = try c.decode(String.self, forKey: .collectedAt)
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        platform = try c.decodeIfPresent(String.self, forKey: .platform) ?? ""
        uptime = try c.decodeIfPresent(String.self, forKey: .uptime) ?? ""
        procs = try c.decodeIfPresent(Int.self, forKey: .procs) ?? 0
        hardware = try c.decodeIfPresent(Hardware.self, forKey: .hardware) ?? Hardware()
        healthScore = try c.decodeIfPresent(Int.self, forKey: .healthScore) ?? 0
        healthScoreMsg = try c.decodeIfPresent(String.self, forKey: .healthScoreMsg) ?? ""
        cpu = try c.decode(CPU.self, forKey: .cpu)
        gpu = try c.decodeArray(GPU.self, forKey: .gpu)
        memory = try c.decode(Memory.self, forKey: .memory)
        disks = try c.decodeArray(Disk.self, forKey: .disks)
        trashSize = try c.decodeIfPresent(UInt64.self, forKey: .trashSize) ?? 0
        diskIo = try c.decodeIfPresent(DiskIO.self, forKey: .diskIo) ?? DiskIO()
        network = try c.decodeArray(NetworkInterface.self, forKey: .network)
        proxy = try c.decodeIfPresent(Proxy.self, forKey: .proxy) ?? Proxy()
        batteries = try c.decodeArray(Battery.self, forKey: .batteries)
        thermal = try c.decodeIfPresent(Thermal.self, forKey: .thermal) ?? Thermal()
        topProcesses = try c.decodeArray(TopProcess.self, forKey: .topProcesses)
        zombieCount = try c.decodeIfPresent(Int.self, forKey: .zombieCount)
        zombieParents = try c.decodeArray(ZombieParent.self, forKey: .zombieParents)
        processAlerts = try c.decodeArray(ProcessAlert.self, forKey: .processAlerts)
    }

    /// Decodes one NDJSON line (or one `--json` document). A new decoder per call
    /// keeps this free of shared mutable state; at 1 Hz the cost is negligible.
    public static func decode(_ data: Data) throws -> StatusSnapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(StatusSnapshot.self, from: data)
    }

    public struct Hardware: Decodable, Sendable, Equatable {
        public var model = ""
        public var cpuModel = ""
        public var totalRam = ""
        public var diskSize = ""
        public var osVersion = ""
        public var refreshRate = ""
    }

    public struct CPU: Decodable, Sendable, Equatable {
        public var usage: Double
        public var perCore: [Double]
        public var load1: Double
        public var load5: Double
        public var load15: Double
        public var coreCount: Int
        public var logicalCpu: Int
        public var pCoreCount: Int
        public var eCoreCount: Int
    }

    public struct GPU: Decodable, Sendable, Equatable {
        public var name: String
        /// -1 means mo could not read utilisation.
        public var usage: Double
        public var coreCount: Int
    }

    public struct Memory: Decodable, Sendable, Equatable {
        public var used: UInt64
        public var total: UInt64
        public var available: UInt64
        public var usedPercent: Double
        public var swapUsed: UInt64
        public var swapTotal: UInt64
        public var cached: UInt64
        /// "normal", "warn", "critical", or "" in the fast frame.
        public var pressure: String
    }

    public struct Disk: Decodable, Sendable, Equatable {
        public var mount: String
        public var device: String
        public var used: UInt64
        public var total: UInt64
        public var usedPercent: Double
        public var fstype: String
        public var external: Bool
    }

    public struct DiskIO: Decodable, Sendable, Equatable {
        public var readRate: Double = 0  // MB/s
        public var writeRate: Double = 0 // MB/s
    }

    public struct NetworkInterface: Decodable, Sendable, Equatable, Identifiable {
        public var name: String
        public var rxRateMbs: Double
        public var txRateMbs: Double
        public var ip: String
        public var id: String { name }
    }

    public struct Proxy: Decodable, Sendable, Equatable {
        public var enabled = false
        public var type = ""
        public var host = ""
    }

    public struct Battery: Decodable, Sendable, Equatable {
        public var percent: Double
        public var status: String
        public var timeLeft: String
        public var health: String
        public var cycleCount: Int
        public var capacity: Int
    }

    public struct Thermal: Decodable, Sendable, Equatable {
        public var cpuTemp: Double = 0
        public var gpuTemp: Double = 0
        public var batteryTemp: Double = 0
        public var fanSpeed: Int = 0
        public var fanCount: Int = 0
        public var systemPower: Double = 0
        public var adapterPower: Double = 0
        public var batteryPower: Double = 0
    }

    public struct TopProcess: Decodable, Sendable, Equatable, Identifiable {
        public var pid: Int
        public var ppid: Int
        public var name: String
        public var command: String
        public var cpu: Double
        public var memory: Double
        public var memoryBytes: UInt64?
        public var id: Int { pid }
    }

    public struct ZombieParent: Decodable, Sendable, Equatable {
        public var pid: Int
        public var name: String
        public var count: Int
    }

    public struct ProcessAlert: Decodable, Sendable, Equatable, Identifiable {
        public var pid: Int
        public var name: String
        public var cpu: Double
        public var threshold: Double
        public var window: String
        public var triggeredAt: String
        public var status: String
        public var id: String { "\(pid)-\(triggeredAt)" }
    }
}

extension KeyedDecodingContainer {
    /// `null` and a missing key both decode as an empty array.
    func decodeArray<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> [T] {
        try decodeIfPresent([T].self, forKey: key) ?? []
    }
}
