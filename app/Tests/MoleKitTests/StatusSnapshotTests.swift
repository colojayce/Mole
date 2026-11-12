import Foundation
import Testing
@testable import MoleKit

@Suite struct StatusSnapshotTests {
    @Test func decodesFullFrame() throws {
        let s = try StatusSnapshot.decode(try Fixture.data("status-full.json"))
        #expect(s.host == "test-mac.local")
        #expect(s.hardware.cpuModel == "Apple M3 Pro")
        #expect(s.healthScore == 88)
        #expect(s.cpu.usage == 28.56)
        #expect(s.cpu.perCore.count == 12)
        #expect(s.cpu.pCoreCount == 6)
        #expect(s.cpu.logicalCpu == 12)
        #expect(s.memory.pressure == "normal")
        #expect(s.memory.total == 38_654_705_664)
        #expect(s.rootDisk?.usedPercent == 91.84)
        #expect(s.diskIo.readRate == 0.2708)
        #expect(s.network.first?.rxRateMbs == 0.0216)
        #expect(s.proxy.type == "SOCKS")
        #expect(s.batteries.first?.cycleCount == 59)
        #expect(s.thermal.batteryTemp == 31.79)
        #expect(s.gpu.first?.usage == -1)
        #expect(s.topProcesses.map(\.pid) == [258, 568, 71910])
        #expect(s.topProcesses.first?.memoryBytes == 88_342_528)
        #expect(s.zombieCount == 7)
        #expect(s.zombieParents.first?.name == "WeChat")
        #expect(s.processAlerts.isEmpty)
        #expect(s.isFastFrame == false)
    }

    @Test func fastFrameTreatsNullArraysAsEmpty() throws {
        let s = try StatusSnapshot.decode(try Fixture.data("status-fast.json"))
        #expect(s.topProcesses.isEmpty)
        #expect(s.gpu.isEmpty)
        #expect(s.batteries.isEmpty)
        #expect(s.zombieParents.isEmpty)
        #expect(s.zombieCount == nil)
        #expect(s.hardware.model.isEmpty)
        #expect(s.isFastFrame)
    }

    @Test func missingOptionalSectionsDecodeToDefaults() throws {
        let json = """
        {"collected_at":"x",
         "cpu":{"usage":1,"per_core":[],"load1":0,"load5":0,"load15":0,"core_count":1,"logical_cpu":1,"p_core_count":0,"e_core_count":0},
         "memory":{"used":1,"total":2,"available":1,"used_percent":50,"swap_used":0,"swap_total":0,"cached":0,"pressure":"warn"}}
        """
        let s = try StatusSnapshot.decode(Data(json.utf8))
        #expect(s.disks.isEmpty)
        #expect(s.network.isEmpty)
        #expect(s.rootDisk == nil)
        #expect(s.hardware.model == "")
        #expect(s.trashSize == 0)
    }

    @Test func rejectsGarbage() {
        #expect(throws: (any Error).self) { try StatusSnapshot.decode(Data("not json".utf8)) }
    }

    @Test func signalThresholds() throws {
        let s = try StatusSnapshot.decode(try Fixture.data("status-full.json"))
        var disk = try #require(s.rootDisk)
        #expect(Signals.disk(disk) == .attention)
        disk.usedPercent = 89.9
        #expect(Signals.disk(disk) == .done)

        var memory = s.memory
        #expect(Signals.memory(memory) == .done)
        memory.pressure = "warn"
        #expect(Signals.memory(memory) == .attention)
        memory.pressure = "critical"
        #expect(Signals.memory(memory) == .failure)

        #expect(Signals.exit(0) == .done)
        #expect(Signals.exit(1) == .failure)
        #expect(Signals.exit(nil) == .failure)
    }
}
