# MoleUI 基础（M1–M3）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在本仓库 `app/` 下建出可运行的原生 macOS 前端骨架：能找到并验证 `mo`、实时 Dashboard（`mo status --watch`）、在右侧执行抽屉里用真实终端运行 `mo` 命令、⌘K 命令面板和 ⌘1–⌘9 模块切换。

**Architecture:** SwiftPM 工程，两个目标：`MoleKit`（纯逻辑，Swift Testing 覆盖：子进程运行器、NDJSON 切行、status 模型、定位器、状态服务、命令协调器、面板搜索）和 `MoleUI`（SwiftUI 应用，依赖 MoleKit 和 SwiftTerm）。只读数据走无 TTY 的数据通道并在后台解码；所有可能改动系统的命令走 SwiftTerm 伪终端，交互和安全语义与在终端里直接运行 `mo` 一致。设计依据：`docs/superpowers/specs/2026-11-12-mole-native-ui-design.md`（下称「设计文档」）。

**Tech Stack:** Swift 6.4（CommandLineTools 即可，无需 Xcode）、SwiftUI + Observation、Swift Testing、Synchronization 之外只用 Foundation 的 `NSLock`、SwiftTerm 1.99.3。

## Global Constraints

- 平台：`macOS 15` 起；`swift-tools-version:6.0`，Swift 6 语言模式（严格并发）。
- 唯一第三方依赖：`SwiftTerm`，`exact: "1.99.3"`。走势图、树图、进度条一律用 `Canvas` / 基础 Shape 自己画。
- 本机拉取 SwiftPM 依赖要走代理：`https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890 swift build`（只有第一次解析依赖时需要）。
- `app/` 下不放任何 `*.sh` 文件（`scripts/check.sh` 会扫描全仓库 shell 文件）；打包逻辑写在 `app/Makefile`。Makefile 的命令行必须以 TAB 开头。
- GUI 自己从不删除或移动文件；不传 `--permanent`，`CommandSpec` 构造时直接拒绝它。
- 子进程环境由 `MoleEnvironment.make` 生成：剥掉 `MOLE_TEST_*`、`MO_NO_OPLOG`、`MOLE_DRY_RUN`，PATH 末尾补 `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`，缺 `LANG` 时补 `en_US.UTF-8`。
- 只做浅色：`.preferredColorScheme(.light)`；所有颜色、尺寸、缓动只从 `Theme/Tokens.swift` 取，色值照抄设计文档 5.2。
- 数字、路径、PID、命令、大小、时间一律用 `Font.mono`（SF Mono + `monospacedDigit`）；界面最小字号 10 pt。
- 朱红（`Tokens.signal*`）只用于：磁盘 ≥ 90%、内存压力 warn/critical、进程告警、僵尸进程、非零退出。
- 字节显示用二进制进位、沿用 mo 的单位标签（1 GB = 1024³ B），四舍五入到整单位时进位到下一单位（例如 `1024.0 MB` 显示为 `1.0 GB`）。
- 所有动效在系统「减少动态效果」打开时关闭。
- 提交信息用 `feat(app): …` / `test(app): …` 形式，**不加任何 AI 署名 trailer**（仓库 AGENTS.md 规定）。只在本地提交，不推送。
- 运行测试：`cd app && swift test`；运行应用：`cd app && make run`。开发前仓库根目录要已经 `make build` 过（`bin/status-go`、`bin/analyze-go` 存在，二者已被 `.gitignore` 忽略）。

## 已核实的事实（2026-11-12，本机）

- `mo status --watch --interval 1s`：每个快照一行紧凑 JSON。第一帧是快速帧（`top_processes`、`batteries`、`gpu`、`sensors`、`zombie_parents` 为 `null`，`hardware.*` 为空串），约 30 ms 后出完整帧，之后约 6 s 起每 1.1 s 一帧；`top_processes` 只有 5 个。
- `mole` 在没有 TTY 时经 `run_mole_command` 直接 `exec` 到 `bin/status.sh`，后者再 `exec` 到 `status-go`，所以数据通道拿到的 PID 就是 Go 进程本身，SIGTERM 直接生效；stdout 关闭时 watch 模式自行退出。
- `./mole --version` 第一行为 `Mole version 1.71.0`，退出码 0。本机 PATH 里没有 `mo`，所以定位器优先用打包时写入 Info.plist 的仓库路径。
- SwiftTerm 1.99.3：`LocalProcessTerminalView(frame:)`、`startProcess(executable:args:environment:execName:currentDirectory:)`（`args` 不含 argv0）、`processDelegate: LocalProcessTerminalViewDelegate?`（回调在主队列）、`installColors(_: [SwiftTerm.Color])`（16 色）、`SwiftTerm.Color(red:green:blue:)`（16 位分量）、`font`、`nativeForegroundColor`、`nativeBackgroundColor`、`caretColor`。SwiftPM 只产出一个可执行文件，没有资源包。
- CommandLineTools 能编译 SwiftUI + SwiftTerm，也能跑 Swift Testing（首次构建偶发一次失败，重跑即可）。

## 文件结构

```
app/
├── Package.swift
├── Makefile                         # build / test / bundle / run / clean
├── Info.plist.in                    # make bundle 时把 @MOLE_REPO_PATH@ 换成仓库根路径
├── Sources/
│   ├── MoleKit/
│   │   ├── MoleKitInfo.swift        # 版本常量（脚手架冒烟测试用）
│   │   ├── Parsing/LineSplitter.swift
│   │   ├── Support/Format.swift     # 字节、速率、百分比、温度、功率、时长
│   │   ├── Support/RingBuffer.swift
│   │   ├── Status/StatusSnapshot.swift
│   │   ├── Status/Signals.swift     # 状态字形判定（StatusGlyphKind）
│   │   ├── Status/StatusService.swift
│   │   ├── Runner/DataRunner.swift  # ChildProcess / ProcessRegistry / CommandFailure
│   │   ├── Runner/MoleLocator.swift # MoleInstallation / MoleLocatorError / MoleEnvironment
│   │   ├── Commands/CommandSpec.swift        # CommandSpec / ShellQuote
│   │   ├── Commands/CommandRunCoordinator.swift
│   │   └── Commands/PaletteSearch.swift
│   └── MoleUI/
│       ├── App/MoleUIApp.swift      # @main、AppDelegate、Settings 场景
│       ├── App/SettingsView.swift
│       ├── App/MoleCommands.swift   # ⌘1–⌘9、⌘K 菜单命令
│       ├── Theme/Tokens.swift       # 色彩、尺寸、字体、缓动
│       ├── Theme/Controls.swift     # SectionLabel、LiveDot、EnterOnAppear、MoleButtonStyle
│       ├── Theme/StatusGlyph.swift
│       ├── Shell/Module.swift
│       ├── Shell/AppModel.swift
│       ├── Shell/RootView.swift     # RootView、ModuleHost、SetupStateView
│       ├── Shell/Sidebar.swift
│       ├── Shell/Chrome.swift       # TopBar、SummaryBand、MetricRow、BigNumber、TabBar、表格骨架
│       ├── Shell/PlaceholderModule.swift
│       ├── Shell/Toast.swift
│       ├── Components/Charts.swift  # Sparkline、MicroBars、Meter、CoreHeatmap
│       ├── Components/WindowOcclusionReader.swift
│       ├── Features/Dashboard/DashboardView.swift
│       ├── Features/Dashboard/DashboardTabs.swift
│       ├── Terminal/TerminalTheme.swift
│       ├── Terminal/TerminalHost.swift
│       ├── Terminal/ExecutionDrawer.swift
│       └── Palette/CommandPalette.swift
└── Tests/MoleKitTests/
    ├── Fixtures/status-fast.json
    ├── Fixtures/status-full.json
    ├── TestSupport.swift            # Fixture、waitUntil
    ├── SmokeTests.swift
    ├── LineSplitterTests.swift
    ├── FormatTests.swift
    ├── RingBufferTests.swift
    ├── StatusSnapshotTests.swift
    ├── DataRunnerTests.swift
    ├── MoleLocatorTests.swift
    ├── StatusServiceTests.swift
    ├── CommandRunCoordinatorTests.swift
    └── PaletteSearchTests.swift
```

另外修改：仓库根 `.gitignore`（忽略 `app/.build/`、`app/build/`、`app/.swiftpm/`）。

与设计文档 6.2 的一处差异：`DataRunner` 用加锁的进程登记表而不是 actor。这样子进程启动后同步登记，`terminateAll()` 不会漏掉刚启动的进程，也省掉每次调用的 actor 跳转。（设计文档已同步改写。）

---

### Task 1: 工程脚手架与打包

**Files:**
- Create: `app/Package.swift`
- Create: `app/Makefile`
- Create: `app/Info.plist.in`
- Create: `app/Sources/MoleKit/MoleKitInfo.swift`
- Create: `app/Sources/MoleUI/App/MoleUIApp.swift`
- Create: `app/Tests/MoleKitTests/SmokeTests.swift`
- Modify: `.gitignore`（末尾追加）

**Interfaces:**
- Consumes: 无
- Produces: 目标 `MoleKit`（library）、`MoleUI`（executable）、`MoleKitTests`；`MoleKitInfo.version: String`；`make bundle` 产出 `app/build/MoleUI.app`，其 Info.plist 含键 `MoleRepoPath`（仓库根绝对路径）。

- [ ] **Step 1: 写冒烟测试**

`app/Tests/MoleKitTests/SmokeTests.swift`：

```swift
import Testing
@testable import MoleKit

@Test func packageBuildsAndExposesVersion() {
    #expect(MoleKitInfo.version == "0.1.0")
}
```

- [ ] **Step 2: 写 Package.swift**

`app/Package.swift`：

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MoleUI",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "MoleUI", targets: ["MoleUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.3"),
    ],
    targets: [
        .target(name: "MoleKit"),
        .executableTarget(
            name: "MoleUI",
            dependencies: [
                "MoleKit",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
        .testTarget(
            name: "MoleKitTests",
            dependencies: ["MoleKit"]
        ),
    ]
)
```

- [ ] **Step 3: 运行测试，确认失败**

Run: `cd app && https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890 swift test`
Expected: 编译失败，提示 `cannot find 'MoleKitInfo' in scope`（MoleKit 和 MoleUI 目录还没有源文件时 SwiftPM 也会报目标无源文件，两种失败都算）。

- [ ] **Step 4: 写最小实现**

`app/Sources/MoleKit/MoleKitInfo.swift`：

```swift
/// Version of the MoleUI front end itself (not of `mo`).
public enum MoleKitInfo {
    public static let version = "0.1.0"
}
```

`app/Sources/MoleUI/App/MoleUIApp.swift`（Task 8 会整体替换）：

```swift
import SwiftUI

@main
struct MoleUIApp: App {
    var body: some Scene {
        Window("Mole", id: "main") {
            Text("MoleUI")
                .frame(minWidth: 960, minHeight: 620)
        }
    }
}
```

`app/Info.plist.in`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MoleUI</string>
    <key>CFBundleIdentifier</key>
    <string>local.mole.ui</string>
    <key>CFBundleName</key>
    <string>Mole</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>MoleRepoPath</key>
    <string>@MOLE_REPO_PATH@</string>
</dict>
</plist>
```

`app/Makefile`（每条命令行以 TAB 开头）：

```make
# MoleUI build helpers. Recipe lines must start with a TAB.
SWIFT ?= swift
CONFIG ?= debug
APP_NAME := MoleUI
BUILD_DIR := build
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
REPO_ROOT := $(abspath $(CURDIR)/..)

.PHONY: build test bundle run clean

build:
	$(SWIFT) build -c $(CONFIG)

test:
	$(SWIFT) test

bundle: build
	@bin_dir="$$($(SWIFT) build -c $(CONFIG) --show-bin-path)"; \
	mkdir -p "$(APP_DIR)/Contents/MacOS"; \
	cp "$$bin_dir/$(APP_NAME)" "$(APP_DIR)/Contents/MacOS/$(APP_NAME)"; \
	sed "s|@MOLE_REPO_PATH@|$(REPO_ROOT)|g" Info.plist.in > "$(APP_DIR)/Contents/Info.plist"; \
	codesign --force --sign - "$(APP_DIR)" > /dev/null; \
	echo "Bundled $(APP_DIR) (mole repo: $(REPO_ROOT))"

run: bundle
	open "$(APP_DIR)"

clean:
	rm -rf "$(BUILD_DIR)"
```

`.gitignore` 末尾追加：

```gitignore

# MoleUI (app/) build output
app/.build/
app/build/
app/.swiftpm/
```

- [ ] **Step 5: 运行测试，确认通过**

Run: `cd app && swift test`
Expected: `✔ Test packageBuildsAndExposesVersion() passed`，`Test run with 1 test … passed`。

- [ ] **Step 6: 打包并检查 Info.plist**

Run: `cd app && make bundle && plutil -extract MoleRepoPath raw build/MoleUI.app/Contents/Info.plist`
Expected: 输出 `Bundled build/MoleUI.app (mole repo: /Users/m3bro/GrokProjects/Mole)`，随后打印 `/Users/m3bro/GrokProjects/Mole`。

Run: `cd app && make run`
Expected: 出现一个标题为 Mole、内容为 “MoleUI” 的窗口。手动关闭。

Run: `git status --short`
Expected: 只列出 `.gitignore`、`app/` 下的源文件和 `docs/superpowers/`，不出现 `app/.build` 或 `app/build`。

- [ ] **Step 7: Commit**

```bash
git add .gitignore app/Package.swift app/Makefile app/Info.plist.in app/Sources app/Tests docs/superpowers
git commit -m "feat(app): scaffold the MoleUI SwiftPM project and bundle target"
```

---

### Task 2: NDJSON 切行器

**Files:**
- Create: `app/Sources/MoleKit/Parsing/LineSplitter.swift`
- Test: `app/Tests/MoleKitTests/LineSplitterTests.swift`

**Interfaces:**
- Consumes: 无
- Produces: `public struct LineSplitter: Sendable`，`init()`，`mutating func append(_ chunk: Data) -> [Data]`，`mutating func finish() -> Data?`。返回的每行不含 `\n` 和行尾 `\r`，空行被跳过。

- [ ] **Step 1: 写失败的测试**

`app/Tests/MoleKitTests/LineSplitterTests.swift`：

```swift
import Foundation
import Testing
@testable import MoleKit

@Suite struct LineSplitterTests {
    private func strings(_ lines: [Data]) -> [String] {
        lines.map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func splitsCompleteLines() {
        var splitter = LineSplitter()
        #expect(strings(splitter.append(Data("a\nb\n".utf8))) == ["a", "b"])
    }

    @Test func holdsPartialLineAcrossChunks() {
        var splitter = LineSplitter()
        #expect(splitter.append(Data("{\"x\":".utf8)).isEmpty)
        #expect(strings(splitter.append(Data("1}\n{\"y\"".utf8))) == ["{\"x\":1}"])
        #expect(strings(splitter.append(Data(":2}\n".utf8))) == ["{\"y\":2}"])
    }

    @Test func stripsCarriageReturnAndSkipsBlankLines() {
        var splitter = LineSplitter()
        #expect(strings(splitter.append(Data("a\r\n\n\r\nb\n".utf8))) == ["a", "b"])
    }

    @Test func finishReturnsUnterminatedTailOnce() {
        var splitter = LineSplitter()
        #expect(strings(splitter.append(Data("a\nrest".utf8))) == ["a"])
        #expect(splitter.finish().map { String(decoding: $0, as: UTF8.self) } == "rest")
        #expect(splitter.finish() == nil)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd app && swift test --filter LineSplitterTests`
Expected: 编译失败，`cannot find 'LineSplitter' in scope`。

- [ ] **Step 3: 写实现**

`app/Sources/MoleKit/Parsing/LineSplitter.swift`：

```swift
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
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `cd app && swift test --filter LineSplitterTests`
Expected: 4 个测试全部通过。

- [ ] **Step 5: Commit**

```bash
git add app/Sources/MoleKit/Parsing app/Tests/MoleKitTests/LineSplitterTests.swift
git commit -m "feat(app): add an NDJSON line splitter for streamed mo output"
```

---

### Task 3: 格式化工具与环形缓冲

**Files:**
- Create: `app/Sources/MoleKit/Support/Format.swift`
- Create: `app/Sources/MoleKit/Support/RingBuffer.swift`
- Test: `app/Tests/MoleKitTests/FormatTests.swift`
- Test: `app/Tests/MoleKitTests/RingBufferTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `public enum Format`：`bytesParts(_ value: UInt64) -> (number: String, unit: String)`、`bytes(_ value: UInt64) -> String`、`rate(mbPerSecond: Double) -> String`、`percent(_ value: Double, digits: Int = 1) -> String`、`decimal(_ value: Double, digits: Int = 1) -> String`、`celsius(_ value: Double) -> String`、`watts(_ value: Double) -> String`、`elapsed(_ seconds: Int) -> String`。
  - `public struct RingBuffer<Element: Sendable>: Sendable`：`init(capacity: Int)`、`capacity`、`count`、`append(_:)`、`append(contentsOf:)`、`elements: [Element]`（旧→新）、`last: Element?`。

- [ ] **Step 1: 写失败的测试**

`app/Tests/MoleKitTests/FormatTests.swift`：

```swift
import Testing
@testable import MoleKit

@Suite struct FormatTests {
    @Test func bytesUseBinaryStepsWithMoleLabels() {
        #expect(Format.bytes(0) == "0 B")
        #expect(Format.bytes(1023) == "1023 B")
        #expect(Format.bytes(1024) == "1.0 KB")
        #expect(Format.bytes(38_654_705_664) == "36.0 GB")
        #expect(Format.bytes(494_384_795_648) == "460.4 GB")
    }

    @Test func sizeThatRoundsToAFullUnitReadsAsTheNextUnit() {
        #expect(Format.bytes(1_073_741_823) == "1.0 GB")
        #expect(Format.bytes(1_048_575) == "1.0 MB")
    }

    @Test func bytesPartsSplitNumberAndUnit() {
        let parts = Format.bytesParts(27_892_318_208)
        #expect(parts.number == "26.0")
        #expect(parts.unit == "GB")
    }

    @Test func rateConvertsMegabytesPerSecond() {
        #expect(Format.rate(mbPerSecond: 0) == "0 B/s")
        #expect(Format.rate(mbPerSecond: 0.0216) == "22.1 KB/s")
        #expect(Format.rate(mbPerSecond: -.infinity) == "0 B/s")
    }

    @Test func scalarFormats() {
        #expect(Format.percent(91.84) == "91.8%")
        #expect(Format.percent(7.0, digits: 0) == "7%")
        #expect(Format.decimal(10.704, digits: 2) == "10.70")
        #expect(Format.celsius(0) == "—")
        #expect(Format.celsius(31.79) == "31.8°C")
        #expect(Format.watts(0) == "—")
        #expect(Format.watts(11.241) == "11.2 W")
    }

    @Test func elapsedPadsMinutesAndShowsHoursOnlyWhenNeeded() {
        #expect(Format.elapsed(12) == "00:12")
        #expect(Format.elapsed(3723) == "1:02:03")
        #expect(Format.elapsed(-5) == "00:00")
    }
}
```

`app/Tests/MoleKitTests/RingBufferTests.swift`：

```swift
import Testing
@testable import MoleKit

@Suite struct RingBufferTests {
    @Test func keepsInsertionOrderBelowCapacity() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.append(2)
        #expect(buffer.elements == [1, 2])
        #expect(buffer.count == 2)
        #expect(buffer.last == 2)
    }

    @Test func dropsOldestWhenFull() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(contentsOf: [1, 2, 3, 4, 5])
        #expect(buffer.elements == [3, 4, 5])
        #expect(buffer.count == 3)
        #expect(buffer.last == 5)
    }

    @Test func emptyBufferHasNoLast() {
        let buffer = RingBuffer<Double>(capacity: 2)
        #expect(buffer.last == nil)
        #expect(buffer.elements.isEmpty)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd app && swift test --filter "FormatTests|RingBufferTests"`
Expected: 编译失败，`cannot find 'Format' in scope` / `cannot find 'RingBuffer' in scope`。

- [ ] **Step 3: 写实现**

`app/Sources/MoleKit/Support/Format.swift`：

```swift
import Foundation

/// Display formatting shared by every module. Byte sizes follow mo: binary
/// steps (1 GB = 1024³ B) with KB/MB/GB labels, one decimal from KB up.
public enum Format {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    public static func bytesParts(_ value: UInt64) -> (number: String, unit: String) {
        if value < 1024 { return ("\(value)", "B") }
        var scaled = Double(value)
        var index = 0
        while scaled >= 1024, index < units.count - 1 {
            scaled /= 1024
            index += 1
        }
        var text = String(format: "%.1f", scaled)
        // 1023.96 MB rounds to "1024.0"; show it as the next unit instead.
        if text == "1024.0", index < units.count - 1 {
            index += 1
            text = "1.0"
        }
        return (text, units[index])
    }

    public static func bytes(_ value: UInt64) -> String {
        let parts = bytesParts(value)
        return "\(parts.number) \(parts.unit)"
    }

    /// `mo status` reports network and disk rates in MB/s.
    public static func rate(mbPerSecond: Double) -> String {
        guard mbPerSecond.isFinite, mbPerSecond > 0 else { return "0 B/s" }
        return bytes(UInt64(mbPerSecond * 1_048_576)) + "/s"
    }

    public static func percent(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f%%", value)
    }

    public static func decimal(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", value)
    }

    /// mo reports 0 when a sensor has no reading.
    public static func celsius(_ value: Double) -> String {
        value > 0 ? String(format: "%.1f°C", value) : "—"
    }

    public static func watts(_ value: Double) -> String {
        value > 0 ? String(format: "%.1f W", value) : "—"
    }

    public static func elapsed(_ seconds: Int) -> String {
        let total = max(seconds, 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%02d:%02d", minutes, secs)
    }
}
```

`app/Sources/MoleKit/Support/RingBuffer.swift`：

```swift
/// Fixed-capacity buffer for live series (CPU, network). Appends are O(1);
/// once full, each append overwrites the oldest value.
public struct RingBuffer<Element: Sendable>: Sendable {
    public let capacity: Int
    private var storage: [Element] = []
    private var head = 0 // index of the oldest element once the buffer is full

    public init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be positive")
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    public var count: Int { storage.count }

    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    public mutating func append(contentsOf elements: some Sequence<Element>) {
        for element in elements { append(element) }
    }

    /// Oldest first.
    public var elements: [Element] {
        guard storage.count == capacity, head != 0 else { return storage }
        return Array(storage[head...]) + Array(storage[..<head])
    }

    public var last: Element? {
        guard !storage.isEmpty else { return nil }
        return storage[(head + storage.count - 1) % storage.count]
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `cd app && swift test --filter "FormatTests|RingBufferTests"`
Expected: 9 个测试全部通过。

- [ ] **Step 5: Commit**

```bash
git add app/Sources/MoleKit/Support app/Tests/MoleKitTests/FormatTests.swift app/Tests/MoleKitTests/RingBufferTests.swift
git commit -m "feat(app): add byte/rate formatting and a ring buffer for live series"
```

---

### Task 4: status 快照模型与状态判定

**Files:**
- Create: `app/Sources/MoleKit/Status/StatusSnapshot.swift`
- Create: `app/Sources/MoleKit/Status/Signals.swift`
- Create: `app/Tests/MoleKitTests/Fixtures/status-fast.json`
- Create: `app/Tests/MoleKitTests/Fixtures/status-full.json`
- Create: `app/Tests/MoleKitTests/TestSupport.swift`
- Modify: `app/Package.swift`（测试目标加 `exclude: ["Fixtures"]`）
- Test: `app/Tests/MoleKitTests/StatusSnapshotTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `public struct StatusSnapshot: Decodable, Sendable, Equatable`，`static func decode(_ data: Data) throws -> StatusSnapshot`；属性：`collectedAt: String`、`host`、`platform`、`uptime`、`procs: Int`、`hardware: Hardware`、`healthScore: Int`、`healthScoreMsg`、`cpu: CPU`、`gpu: [GPU]`、`memory: Memory`、`disks: [Disk]`、`trashSize: UInt64`、`diskIo: DiskIO`、`network: [NetworkInterface]`、`proxy: Proxy`、`batteries: [Battery]`、`thermal: Thermal`、`topProcesses: [TopProcess]`、`zombieCount: Int?`、`zombieParents: [ZombieParent]`、`processAlerts: [ProcessAlert]`；计算属性 `isFastFrame: Bool`、`rootDisk: Disk?`。嵌套类型的字段名见下方代码。
  - `public enum StatusGlyphKind { done, pending, attention, failure }`；`public enum Signals`：`disk(_: Disk)`、`memory(_: Memory)`、`exit(_: Int32?)`，`diskAttentionPercent = 90`。
  - 测试辅助：`enum Fixture { static func data(_:) throws -> Data; static func text(_:) throws -> String }`、`@MainActor func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool`。

- [ ] **Step 1: 放入真实 mo 输出样本**

两个样本取自 2026-11-12 本机 `mo status --watch --interval 1s`，已脱敏（主机名、IP、蓝牙设备清空，数组截短）。每个文件就是一行 JSON 加换行。

`app/Tests/MoleKitTests/Fixtures/status-fast.json`：

```json
{"collected_at":"2026-11-12T15:41:26.74785+08:00","host":"test-mac.local","platform":"darwin 27.0.1","uptime":"13d 18h","uptime_seconds":1190525,"procs":993,"hardware":{"model":"","cpu_model":"","total_ram":"","disk_size":"","os_version":"","refresh_rate":""},"health_score":87,"health_score_msg":"Excellent","cpu":{"usage":20.89,"per_core":[44.7,38.8,31.0,24.7,20.1,16.9,12.8,12.7,12.4,12.3,12.2,12.1],"per_core_estimated":false,"load1":12.34,"load5":8.26,"load15":7.78,"core_count":12,"logical_cpu":12,"p_core_count":0,"e_core_count":0},"gpu":null,"memory":{"used":28345073664,"total":38654705664,"available":10309632000,"used_percent":73.33,"swap_used":1175191552,"swap_total":2147483648,"cached":0,"pressure":""},"disks":[{"mount":"/","device":"/dev/disk3s1s1","used":454032166912,"total":494384795648,"used_percent":91.84,"fstype":"apfs","external":false,"smart_status":"unknown"}],"trash_size":0,"trash_approx":false,"disk_io":{"read_rate":0,"write_rate":0},"network":[{"name":"en0","rx_rate_mbs":0.0006,"tx_rate_mbs":0.0006,"ip":"10.0.0.2"},{"name":"en4","rx_rate_mbs":0,"tx_rate_mbs":0,"ip":""}],"network_history":{"rx_history":[0.0006],"tx_history":[0.0006]},"proxy":{"enabled":false,"type":"","host":""},"batteries":null,"thermal":{"cpu_temp":0,"gpu_temp":0,"battery_temp":0,"fan_speed":0,"fan_count":0,"system_power":0,"adapter_power":0,"battery_power":0},"sensors":null,"bluetooth":[],"top_processes":null,"zombie_parents":null,"process_watch":{"enabled":true,"cpu_threshold":100,"window":"5m0s"},"process_alerts":[]}
```

`app/Tests/MoleKitTests/Fixtures/status-full.json`：

```json
{"collected_at":"2026-11-12T15:41:40.903097+08:00","host":"test-mac.local","platform":"darwin 27.0.1","uptime":"13d 18h","uptime_seconds":1190539,"procs":993,"hardware":{"model":"MacBook Pro","cpu_model":"Apple M3 Pro","total_ram":"36.0 GB","disk_size":"460.4 GB","os_version":"macOS 27.0.1","refresh_rate":"120Hz"},"health_score":88,"health_score_msg":"Excellent","cpu":{"usage":28.56,"per_core":[49.5,45.9,38.5,33.6,25.7,23.6,27.5,20.0,13.6,24.5,14.4,25.7],"per_core_estimated":false,"load1":10.7,"load5":8.1,"load15":7.73,"core_count":12,"logical_cpu":12,"p_core_count":6,"e_core_count":6},"gpu":[{"name":"Apple M3 Pro","usage":-1,"memory_used":0,"memory_total":0,"core_count":18,"note":"sppci_vendor_Apple"}],"memory":{"used":27892318208,"total":38654705664,"available":10762387456,"used_percent":72.16,"swap_used":1175191552,"swap_total":2147483648,"cached":6027722752,"pressure":"normal"},"disks":[{"mount":"/","device":"/dev/disk3s1s1","used":454032171008,"total":494384795648,"used_percent":91.84,"fstype":"apfs","external":false,"smart_status":"verified"}],"trash_size":0,"trash_approx":false,"disk_io":{"read_rate":0.2708,"write_rate":0.0143},"network":[{"name":"en0","rx_rate_mbs":0.0216,"tx_rate_mbs":0.0076,"ip":"10.0.0.2"},{"name":"en4","rx_rate_mbs":0,"tx_rate_mbs":0,"ip":""}],"network_history":{"rx_history":[0.0006,0.0659,0.0401,0.0246,0.0201,0.034],"tx_history":[0.0006,0.018,0.0577,0.0138,0.0068,0.0089]},"proxy":{"enabled":true,"type":"SOCKS","host":"127.0.0.1:7890"},"batteries":[{"percent":80,"status":"AC","time_left":"","health":"Good","cycle_count":59,"capacity":98}],"thermal":{"cpu_temp":0,"gpu_temp":0,"battery_temp":31.79,"fan_speed":0,"fan_count":0,"system_power":11.241,"adapter_power":140,"battery_power":0},"sensors":null,"bluetooth":[],"top_processes":[{"pid":258,"ppid":253,"name":"Claude Helper","command":"Claude Helper","cpu":44.8,"memory":0.2,"memory_bytes":88342528},{"pid":568,"ppid":1,"name":"WindowServer","command":"WindowServer","cpu":38.5,"memory":0.4,"memory_bytes":171950080},{"pid":71910,"ppid":35061,"name":"OpenMarket Helper (Renderer)","command":"OpenMarket Helper (Renderer)","cpu":37,"memory":1.9,"memory_bytes":748699648}],"process_collected_at":"2026-11-12T15:41:40.903097+08:00","process_stale":false,"zombie_count":7,"zombie_parents":[{"pid":55800,"name":"WeChat","count":7}],"zombie_parents_complete":true,"process_watch":{"enabled":true,"cpu_threshold":100,"window":"5m0s"},"process_alerts":[]}
```

把 `app/Package.swift` 里的测试目标改为：

```swift
        .testTarget(
            name: "MoleKitTests",
            dependencies: ["MoleKit"],
            exclude: ["Fixtures"]
        ),
```

`app/Tests/MoleKitTests/TestSupport.swift`：

```swift
import Foundation

/// Reads fixtures straight from the source tree, so no SwiftPM resource bundle is needed.
enum Fixture {
    static func url(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }

    static func text(_ name: String) throws -> String {
        String(decoding: try data(name), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Polls `condition` until it holds or `timeout` passes. Runs on the main actor
/// so it can read @MainActor services; the sleeps let their tasks progress.
@MainActor
func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}
```

- [ ] **Step 2: 写失败的测试**

`app/Tests/MoleKitTests/StatusSnapshotTests.swift`：

```swift
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
```

- [ ] **Step 3: 运行测试，确认失败**

Run: `cd app && swift test --filter StatusSnapshotTests`
Expected: 编译失败，`cannot find 'StatusSnapshot' in scope`。

- [ ] **Step 4: 写实现**

`app/Sources/MoleKit/Status/StatusSnapshot.swift`：

```swift
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
```

`app/Sources/MoleKit/Status/Signals.swift`：

```swift
/// The four status glyphs from the Vesper direction (design doc 5.6).
public enum StatusGlyphKind: Sendable, Equatable {
    case done       // grey dot: finished / normal
    case pending    // ink ring: actionable / running
    case attention  // signal ring with core: needs a look
    case failure    // signal diamond: failed / dangerous
}

/// Where vermilion is allowed. Everything else stays ink.
public enum Signals {
    public static let diskAttentionPercent = 90.0

    public static func disk(_ disk: StatusSnapshot.Disk) -> StatusGlyphKind {
        disk.usedPercent >= diskAttentionPercent ? .attention : .done
    }

    public static func memory(_ memory: StatusSnapshot.Memory) -> StatusGlyphKind {
        switch memory.pressure {
        case "critical": .failure
        case "warn": .attention
        default: .done
        }
    }

    /// `nil` means the process was killed by a signal or never started.
    public static func exit(_ code: Int32?) -> StatusGlyphKind {
        code == 0 ? .done : .failure
    }
}
```

- [ ] **Step 5: 运行测试，确认通过**

Run: `cd app && swift test --filter StatusSnapshotTests`
Expected: 5 个测试全部通过。

- [ ] **Step 6: Commit**

```bash
git add app/Package.swift app/Sources/MoleKit/Status app/Tests/MoleKitTests
git commit -m "feat(app): decode mo status snapshots and derive status glyphs"
```

---

### Task 5: 数据通道运行器（DataRunner）

**Files:**
- Create: `app/Sources/MoleKit/Runner/DataRunner.swift`
- Test: `app/Tests/MoleKitTests/DataRunnerTests.swift`

**Interfaces:**
- Consumes: `LineSplitter`（Task 2）、`waitUntil`（Task 4 TestSupport）
- Produces:
  - `public struct CommandFailure: Error, Sendable, Equatable, CustomStringConvertible`：`command: String`、`exitCode: Int32`、`stderr: String`（内部 memberwise init，测试经 `@testable` 可用）。
  - `public final class DataRunner: Sendable`：`init(gracePeriod: Duration = .milliseconds(500))`、`gracePeriod`、`runningCount: Int`、`func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil) async throws -> Data`（非零退出抛 `CommandFailure`，被取消或被 `terminateAll` 结束抛 `CancellationError`）、`func stream(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil) -> AsyncThrowingStream<Data, any Error>`（每个元素一行；消费方停止迭代即终止子进程）、`func terminateAll()`。
  - 终止协议：先 SIGTERM，`gracePeriod` 后仍在运行则 SIGKILL。

- [ ] **Step 1: 写失败的测试**

`app/Tests/MoleKitTests/DataRunnerTests.swift`：

```swift
import Foundation
import Testing
@testable import MoleKit

private let sh = URL(fileURLWithPath: "/bin/sh")
private let sleepBin = URL(fileURLWithPath: "/bin/sleep")

@Suite struct DataRunnerTests {
    @Test func runReturnsStdout() async throws {
        let output = try await DataRunner().run(URL(fileURLWithPath: "/bin/echo"), ["hello"])
        #expect(String(decoding: output, as: UTF8.self) == "hello\n")
    }

    @Test func runThrowsCommandFailureWithStderr() async {
        do {
            _ = try await DataRunner().run(sh, ["-c", "echo oops >&2; exit 3"])
            Issue.record("expected CommandFailure")
        } catch let failure as CommandFailure {
            #expect(failure.exitCode == 3)
            #expect(failure.stderr == "oops\n")
            #expect(failure.description.contains("oops"))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func streamYieldsLinesIncludingUnterminatedTail() async throws {
        var lines: [String] = []
        for try await line in DataRunner().stream(sh, ["-c", "printf 'a\\nb\\nc'"]) {
            lines.append(String(decoding: line, as: UTF8.self))
        }
        #expect(lines == ["a", "b", "c"])
    }

    @Test func streamThrowsAfterDeliveringLinesWhenProcessFails() async {
        var lines: [String] = []
        do {
            for try await line in DataRunner().stream(sh, ["-c", "echo one; exit 2"]) {
                lines.append(String(decoding: line, as: UTF8.self))
            }
            Issue.record("expected CommandFailure")
        } catch let failure as CommandFailure {
            #expect(failure.exitCode == 2)
        } catch {
            Issue.record("unexpected error \(error)")
        }
        #expect(lines == ["one"])
    }

    @Test func cancellingRunTerminatesChild() async {
        let runner = DataRunner()
        let task = Task { try await runner.run(sleepBin, ["30"]) }
        #expect(await waitUntil { runner.runningCount == 1 })
        let started = ContinuousClock.now
        task.cancel()
        let result = await task.result
        #expect(ContinuousClock.now - started < .seconds(3))
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(await waitUntil { runner.runningCount == 0 })
    }

    @Test func breakingOutOfStreamTerminatesChild() async throws {
        let runner = DataRunner()
        var count = 0
        for try await _ in runner.stream(sh, ["-c", "while true; do echo tick; sleep 0.05; done"]) {
            count += 1
            if count == 3 { break }
        }
        #expect(count == 3)
        #expect(await waitUntil { runner.runningCount == 0 })
    }

    @Test func escalatesToSigkillWhenTermIsIgnored() async throws {
        let runner = DataRunner(gracePeriod: .milliseconds(200))
        let task = Task { try await runner.run(sh, ["-c", "trap '' TERM; while true; do sleep 0.05; done"]) }
        #expect(await waitUntil { runner.runningCount == 1 })
        try await Task.sleep(for: .milliseconds(300)) // let sh install the trap
        let started = ContinuousClock.now
        task.cancel()
        _ = await task.result
        let elapsed = ContinuousClock.now - started
        #expect(elapsed >= .milliseconds(150)) // SIGTERM was ignored, so we waited for the grace period
        #expect(elapsed < .seconds(3))
        #expect(await waitUntil { runner.runningCount == 0 })
    }

    @Test func terminateAllStopsEveryChild() async {
        let runner = DataRunner()
        let first = Task { try await runner.run(sleepBin, ["30"]) }
        let second = Task { try await runner.run(sleepBin, ["30"]) }
        #expect(await waitUntil { runner.runningCount == 2 })
        runner.terminateAll()
        _ = await first.result
        _ = await second.result
        #expect(runner.runningCount == 0)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd app && swift test --filter DataRunnerTests`
Expected: 编译失败，`cannot find 'DataRunner' in scope`。

- [ ] **Step 3: 写实现**

`app/Sources/MoleKit/Runner/DataRunner.swift`：

```swift
import Foundation

/// A data-channel command exited non-zero.
public struct CommandFailure: Error, Sendable, Equatable, CustomStringConvertible {
    public let command: String
    public let exitCode: Int32
    public let stderr: String

    public var description: String {
        let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty
            ? "\(command) 退出码 \(exitCode)"
            : "\(command) 退出码 \(exitCode)：\(detail)"
    }
}

/// One child process with piped stdout/stderr and no stdin.
/// All mutable state sits behind `lock`; blocking calls never run on the main thread.
final class ChildProcess: @unchecked Sendable {
    let process = Process()
    let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stderrDone = DispatchGroup()
    private let lock = NSLock()
    private var stderrBuffer = Data()
    private var terminatedByUs = false
    let commandLine: String

    init(executable: URL, arguments: [String], environment: [String: String]?) {
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        commandLine = ([executable.lastPathComponent] + arguments).joined(separator: " ")
    }

    func start() throws {
        try process.run()
        stderrDone.enter()
        let handle = stderrPipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async { [self] in
            let data = (try? handle.readToEnd()) ?? Data()
            lock.withLock { stderrBuffer = Data(data.prefix(65_536)) }
            stderrDone.leave()
        }
    }

    /// Blocks the calling thread until the process exits and stderr is drained.
    func waitForExit() -> Int32 {
        process.waitUntilExit()
        stderrDone.wait()
        return process.terminationStatus
    }

    var stderrText: String { lock.withLock { String(decoding: stderrBuffer, as: UTF8.self) } }
    var wasTerminatedByUs: Bool { lock.withLock { terminatedByUs } }

    /// SIGTERM now, SIGKILL after `grace` if the process is still alive.
    func terminate(grace: Duration) {
        lock.withLock { terminatedByUs = true }
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        let parts = grace.components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) { [self] in
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }
}

/// Children registered synchronously at launch, so `terminateAll` never misses one.
final class ProcessRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var children: [ObjectIdentifier: ChildProcess] = [:]

    func insert(_ child: ChildProcess) { lock.withLock { children[ObjectIdentifier(child)] = child } }
    func remove(_ child: ChildProcess) { lock.withLock { _ = children.removeValue(forKey: ObjectIdentifier(child)) } }
    func all() -> [ChildProcess] { lock.withLock { Array(children.values) } }
    var count: Int { lock.withLock { children.count } }
}

/// Runs read-only `mo` commands without a TTY (design doc 3, data channel).
public final class DataRunner: Sendable {
    public let gracePeriod: Duration
    private let registry = ProcessRegistry()

    public init(gracePeriod: Duration = .milliseconds(500)) {
        self.gracePeriod = gracePeriod
    }

    public var runningCount: Int { registry.count }

    public func run(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> Data {
        let child = ChildProcess(executable: executable, arguments: arguments, environment: environment)
        try child.start()
        registry.insert(child)
        defer { registry.remove(child) }
        let grace = gracePeriod
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, any Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let output = (try? child.stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                    let status = child.waitForExit()
                    if child.wasTerminatedByUs {
                        continuation.resume(throwing: CancellationError())
                    } else if status != 0 {
                        continuation.resume(throwing: CommandFailure(
                            command: child.commandLine, exitCode: status, stderr: child.stderrText))
                    } else {
                        continuation.resume(returning: output)
                    }
                }
            }
        } onCancel: {
            child.terminate(grace: grace)
        }
    }

    public func stream(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String]? = nil
    ) -> AsyncThrowingStream<Data, any Error> {
        let registry = self.registry
        let grace = gracePeriod
        return AsyncThrowingStream { continuation in
            let child = ChildProcess(executable: executable, arguments: arguments, environment: environment)
            do {
                try child.start()
            } catch {
                continuation.finish(throwing: error)
                return
            }
            registry.insert(child)
            continuation.onTermination = { termination in
                if case .cancelled = termination { child.terminate(grace: grace) }
            }
            DispatchQueue.global(qos: .utility).async {
                var splitter = LineSplitter()
                let handle = child.stdoutPipe.fileHandleForReading
                while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                    for line in splitter.append(chunk) { continuation.yield(line) }
                }
                if let tail = splitter.finish() { continuation.yield(tail) }
                let status = child.waitForExit()
                registry.remove(child)
                if status == 0 || child.wasTerminatedByUs {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: CommandFailure(
                        command: child.commandLine, exitCode: status, stderr: child.stderrText))
                }
            }
        }
    }

    /// Called on app termination and when the user stops everything.
    public func terminateAll() {
        for child in registry.all() { child.terminate(grace: gracePeriod) }
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `cd app && swift test --filter DataRunnerTests`
Expected: 8 个测试全部通过，总耗时几秒内。

Run（确认没有遗留进程）: `pgrep -fl "sleep 30"; echo "exit=$?"`
Expected: 没有输出，`exit=1`。

- [ ] **Step 5: Commit**

```bash
git add app/Sources/MoleKit/Runner/DataRunner.swift app/Tests/MoleKitTests/DataRunnerTests.swift
git commit -m "feat(app): add a cancellable data-channel runner with TERM-then-KILL cleanup"
```

---

### Task 6: 定位 mo 与子进程环境

**Files:**
- Create: `app/Sources/MoleKit/Runner/MoleLocator.swift`
- Test: `app/Tests/MoleKitTests/MoleLocatorTests.swift`

**Interfaces:**
- Consumes: `DataRunner.run`、`CommandFailure`（Task 5）
- Produces:
  - `public struct MoleInstallation: Sendable, Equatable`：`executableURL: URL`、`version: String`。
  - `public enum MoleLocatorError: Error, Equatable, CustomStringConvertible`：`.notFound(searched: [String])`、`.notExecutable(path: String)`、`.versionCheckFailed(path: String, detail: String)`；`description` 给出一行原因加一个下一步。
  - `public struct MoleLocator: Sendable`：`init(explicitPath: String?, repoPath: String?, searchPath: String)`、`static let explicitPathDefaultsKey = "MolePath"`、`static let repoPathInfoKey = "MoleRepoPath"`、`static func fromApp(searchPath: String, defaults: UserDefaults = .standard, bundle: Bundle = .main) -> MoleLocator`、`func candidates() -> [String]`、`func locate(using runner: DataRunner, environment: [String: String]) async throws -> MoleInstallation`、`static func parseVersion(_ output: String) -> String?`。
  - `public enum MoleEnvironment`：`static func make(base: [String: String]) -> [String: String]`。

- [ ] **Step 1: 写失败的测试**

`app/Tests/MoleKitTests/MoleLocatorTests.swift`：

```swift
import Foundation
import Testing
@testable import MoleKit

private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("moleui-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes a tiny /bin/sh program (no .sh suffix) and marks it executable unless told not to.
@discardableResult
private func writeProgram(_ dir: URL, _ name: String, _ body: String, executable: Bool = true) throws -> String {
    let url = dir.appendingPathComponent(name)
    try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
    return url.path
}

@Suite struct MoleLocatorTests {
    @Test func candidatesPutRepoFirstAndDropDuplicates() {
        let locator = MoleLocator(explicitPath: nil, repoPath: "/r", searchPath: "/a:/b::/a")
        #expect(locator.candidates() == ["/r/mole", "/a/mo", "/a/mole", "/b/mo", "/b/mole"])
    }

    @Test func explicitPathWins() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let explicit = try writeProgram(dir, "custom-mole", "echo 'Mole version 2.0.0'")
        try writeProgram(dir, "mole", "echo 'Mole version 1.0.0'")
        let locator = MoleLocator(explicitPath: explicit, repoPath: dir.path, searchPath: "")
        let found = try await locator.locate(using: DataRunner(), environment: [:])
        #expect(found.version == "2.0.0")
        #expect(found.executableURL.path == explicit)
    }

    @Test func explicitPathThatIsNotExecutableIsReported() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try writeProgram(dir, "mole", "echo 'Mole version 1.0.0'", executable: false)
        let locator = MoleLocator(explicitPath: path, repoPath: nil, searchPath: "")
        await #expect(throws: MoleLocatorError.notExecutable(path: path)) {
            try await locator.locate(using: DataRunner(), environment: [:])
        }
    }

    @Test func fallsBackFromRepoToPath() async throws {
        let repo = try makeTempDir()
        let bin = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: repo)
            try? FileManager.default.removeItem(at: bin)
        }
        try writeProgram(bin, "mo", "echo 'Mole version 1.71.0'")
        let locator = MoleLocator(explicitPath: nil, repoPath: repo.path, searchPath: bin.path)
        let found = try await locator.locate(using: DataRunner(), environment: [:])
        #expect(found.executableURL.path == bin.appendingPathComponent("mo").path)
        #expect(found.version == "1.71.0")
    }

    @Test func notFoundListsEverythingSearched() async {
        let locator = MoleLocator(explicitPath: nil, repoPath: "/nonexistent-repo", searchPath: "/nonexistent-bin")
        await #expect(throws: MoleLocatorError.notFound(searched: [
            "/nonexistent-repo/mole", "/nonexistent-bin/mo", "/nonexistent-bin/mole",
        ])) {
            try await locator.locate(using: DataRunner(), environment: [:])
        }
    }

    @Test func versionCommandFailureIsReported() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try writeProgram(dir, "mole", "echo broken >&2; exit 1")
        let locator = MoleLocator(explicitPath: path, repoPath: nil, searchPath: "")
        do {
            _ = try await locator.locate(using: DataRunner(), environment: [:])
            Issue.record("expected versionCheckFailed")
        } catch let error as MoleLocatorError {
            guard case .versionCheckFailed(let failedPath, let detail) = error else {
                Issue.record("wrong case \(error)")
                return
            }
            #expect(failedPath == path)
            #expect(detail.contains("broken"))
            #expect(error.description.contains("--version"))
        }
    }

    @Test func parsesVersionLine() {
        #expect(MoleLocator.parseVersion("Mole version 1.71.0\nmacOS: 27.0.1\n") == "1.71.0")
        #expect(MoleLocator.parseVersion("hello") == nil)
    }

    @Test func environmentStripsTestSwitchesAndExtendsPath() {
        let env = MoleEnvironment.make(base: [
            "PATH": "/usr/bin:/custom",
            "MOLE_TEST_NO_AUTH": "1",
            "MOLE_TEST_MODE": "1",
            "MO_NO_OPLOG": "1",
            "MOLE_DRY_RUN": "1",
            "HOME": "/Users/x",
        ])
        #expect(env["MOLE_TEST_NO_AUTH"] == nil)
        #expect(env["MOLE_TEST_MODE"] == nil)
        #expect(env["MO_NO_OPLOG"] == nil)
        #expect(env["MOLE_DRY_RUN"] == nil)
        #expect(env["HOME"] == "/Users/x")
        #expect(env["PATH"] == "/usr/bin:/custom:/opt/homebrew/bin:/usr/local/bin:/bin:/usr/sbin:/sbin")
        #expect(env["LANG"] == "en_US.UTF-8")
        #expect(MoleEnvironment.make(base: ["LANG": "zh_CN.UTF-8"])["LANG"] == "zh_CN.UTF-8")
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd app && swift test --filter MoleLocatorTests`
Expected: 编译失败，`cannot find 'MoleLocator' in scope`。

- [ ] **Step 3: 写实现**

`app/Sources/MoleKit/Runner/MoleLocator.swift`：

```swift
import Foundation

public struct MoleInstallation: Sendable, Equatable {
    public let executableURL: URL
    public let version: String

    public init(executableURL: URL, version: String) {
        self.executableURL = executableURL
        self.version = version
    }
}

/// Every case says what failed and what to do next.
public enum MoleLocatorError: Error, Equatable, CustomStringConvertible {
    case notFound(searched: [String])
    case notExecutable(path: String)
    case versionCheckFailed(path: String, detail: String)

    public var description: String {
        switch self {
        case .notFound(let searched):
            "未找到 mo（已查找 \(searched.count) 个位置：\(searched.joined(separator: "、"))）。在「设置」里填写 mole 的路径，或在仓库的 app 目录运行 make bundle 重新打包。"
        case .notExecutable(let path):
            "\(path) 不可执行。检查文件权限，或在「设置」里改成正确的 mole 路径。"
        case .versionCheckFailed(let path, let detail):
            "运行 \(path) --version 失败：\(detail)。在终端里运行同一条命令查看原因。"
        }
    }
}

/// Environment for every `mo` child process: real-run semantics only.
public enum MoleEnvironment {
    static let strippedKeys: Set<String> = ["MO_NO_OPLOG", "MOLE_DRY_RUN"]
    static let strippedPrefixes = ["MOLE_TEST_"]
    static let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    public static func make(base: [String: String]) -> [String: String] {
        var env = base.filter { entry in
            !strippedKeys.contains(entry.key) && !strippedPrefixes.contains { entry.key.hasPrefix($0) }
        }
        var parts = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        for path in extraPaths where !parts.contains(path) { parts.append(path) }
        env["PATH"] = parts.joined(separator: ":")
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        return env
    }
}

/// Finds the `mo` launcher: explicit setting, then the repo baked into Info.plist,
/// then `mo` / `mole` on PATH. The first executable candidate is verified with `--version`.
public struct MoleLocator: Sendable {
    public static let explicitPathDefaultsKey = "MolePath"
    public static let repoPathInfoKey = "MoleRepoPath"

    public var explicitPath: String?
    public var repoPath: String?
    public var searchPath: String

    public init(explicitPath: String?, repoPath: String?, searchPath: String) {
        self.explicitPath = explicitPath
        self.repoPath = repoPath
        self.searchPath = searchPath
    }

    public static func fromApp(
        searchPath: String,
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) -> MoleLocator {
        let explicit = defaults.string(forKey: explicitPathDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = bundle.object(forInfoDictionaryKey: repoPathInfoKey) as? String
        return MoleLocator(
            explicitPath: (explicit?.isEmpty ?? true) ? nil : explicit,
            repoPath: (repo?.isEmpty ?? true) ? nil : repo,
            searchPath: searchPath
        )
    }

    public func candidates() -> [String] {
        var list: [String] = []
        if let repoPath { list.append((repoPath as NSString).appendingPathComponent("mole")) }
        for dir in searchPath.split(separator: ":") where !dir.isEmpty {
            list.append("\(dir)/mo")
            list.append("\(dir)/mole")
        }
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }

    public func locate(using runner: DataRunner, environment: [String: String]) async throws -> MoleInstallation {
        let fileManager = FileManager.default
        if let explicitPath {
            guard fileManager.isExecutableFile(atPath: explicitPath) else {
                throw MoleLocatorError.notExecutable(path: explicitPath)
            }
            return try await verify(explicitPath, runner: runner, environment: environment)
        }
        let all = candidates()
        guard let path = all.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            throw MoleLocatorError.notFound(searched: all)
        }
        return try await verify(path, runner: runner, environment: environment)
    }

    private func verify(_ path: String, runner: DataRunner, environment: [String: String]) async throws -> MoleInstallation {
        let output: Data
        do {
            output = try await runner.run(URL(fileURLWithPath: path), ["--version"], environment: environment)
        } catch let failure as CommandFailure {
            throw MoleLocatorError.versionCheckFailed(path: path, detail: failure.description)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MoleLocatorError.versionCheckFailed(path: path, detail: String(describing: error))
        }
        guard let version = Self.parseVersion(String(decoding: output, as: UTF8.self)) else {
            throw MoleLocatorError.versionCheckFailed(path: path, detail: "输出里没有 “Mole version” 这一行")
        }
        return MoleInstallation(executableURL: URL(fileURLWithPath: path), version: version)
    }

    public static func parseVersion(_ output: String) -> String? {
        guard let match = output.firstMatch(of: /Mole version (\S+)/) else { return nil }
        return String(match.1)
    }
}
```

注意：`environmentStripsTestSwitchesAndExtendsPath` 里 `/usr/bin` 已在原 PATH 中，所以只追加其余目录，期望值据此写成 `/usr/bin:/custom:/opt/homebrew/bin:/usr/local/bin:/bin:/usr/sbin:/sbin`。

- [ ] **Step 4: 运行测试，确认通过**

Run: `cd app && swift test --filter MoleLocatorTests`
Expected: 8 个测试全部通过。

Run（对真实仓库做一次只读核对）: `./mole --version | head -1`（在仓库根目录）
Expected: `Mole version 1.71.0`，与 `parseVersion` 的格式一致。

- [ ] **Step 5: Commit**

```bash
git add app/Sources/MoleKit/Runner/MoleLocator.swift app/Tests/MoleKitTests/MoleLocatorTests.swift
git commit -m "feat(app): locate and verify mo with an actionable failure message"
```

---

### Task 7: 实时状态服务（StatusService）

**Files:**
- Create: `app/Sources/MoleKit/Status/StatusService.swift`
- Test: `app/Tests/MoleKitTests/StatusServiceTests.swift`

**Interfaces:**
- Consumes: `StatusSnapshot.decode`（Task 4）、`RingBuffer`（Task 3）、`DataRunner.stream`（Task 5）、`CommandFailure`、`waitUntil`、`Fixture`
- Produces:
  - `@MainActor @Observable public final class StatusService`
  - `public enum Phase: Equatable, Sendable { case idle, connecting, live, reconnecting(String), failed(String) }`
  - 只读属性：`phase`、`snapshot: StatusSnapshot?`、`cpuHistory`、`rxHistory`、`txHistory`、`diskReadHistory`、`diskWriteHistory`（均为 `RingBuffer<Double>`，容量 120）、`skippedLines: Int`、`isRunning: Bool`
  - `public typealias LineSource = @Sendable () -> AsyncThrowingStream<Data, any Error>`
  - `init(source: @escaping LineSource, minPublishInterval: Duration = .seconds(1), backoff: [Duration] = [1, 2, 4, 8, 16, 30 秒])`
  - `static func live(runner: DataRunner, executable: URL, environment: [String: String]) -> StatusService`（运行 `status --watch --interval 1s`）
  - `func start()`（幂等）、`func stop()`（终止子进程，保留最后一帧和历史，`phase = .idle`）
  - `nonisolated static let historyCapacity = 120`、`nonisolated static let maxConsecutiveBadLines = 5`
- 行为：解码在后台任务里做；主线程最多每 `minPublishInterval` 发布一次（中间到达的帧只保留最新的那一帧，到点补发）；当前显示的是快速帧时，紧随而来的完整帧立即发布；连续 5 行解析失败进入 `.failed`，不再重连；流结束或报错进入 `.reconnecting` 并按退避重连，收到过有效帧就把退避计数清零。

- [ ] **Step 1: 写失败的测试**

`app/Tests/MoleKitTests/StatusServiceTests.swift`：

```swift
import Foundation
import Testing
@testable import MoleKit

/// Hands out one controllable stream per (re)connect and counts terminations.
final class ScriptedSource: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncThrowingStream<Data, any Error>.Continuation] = []
    private var terminatedCount = 0

    var requests: Int { lock.withLock { continuations.count } }
    var terminations: Int { lock.withLock { terminatedCount } }

    func makeStream() -> AsyncThrowingStream<Data, any Error> {
        let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { self.terminatedCount += 1 }
        }
        lock.withLock { continuations.append(continuation) }
        return stream
    }

    func send(_ line: String) {
        let latest = lock.withLock { continuations.last }
        latest?.yield(Data(line.utf8))
    }

    func finish(throwing error: (any Error)? = nil) {
        let latest = lock.withLock { continuations.last }
        latest?.finish(throwing: error)
    }
}

private func frame(cpu: Double) throws -> String {
    try Fixture.text("status-full.json")
        .replacingOccurrences(of: "\"cpu\":{\"usage\":28.56", with: "\"cpu\":{\"usage\":\(cpu)")
}

@MainActor
@Suite struct StatusServiceTests {
    private func makeService(
        _ source: ScriptedSource,
        interval: Duration = .zero,
        backoff: [Duration] = [.milliseconds(10)]
    ) -> StatusService {
        StatusService(source: { source.makeStream() }, minPublishInterval: interval, backoff: backoff)
    }

    private func isFailed(_ phase: StatusService.Phase) -> Bool {
        if case .failed = phase { true } else { false }
    }

    @Test func publishesFramesAndRecordsHistory() async throws {
        let source = ScriptedSource()
        let service = makeService(source)
        service.start()
        #expect(await waitUntil { source.requests == 1 })
        source.send(try Fixture.text("status-full.json"))
        #expect(await waitUntil { service.snapshot != nil })
        #expect(service.phase == .live)
        #expect(service.cpuHistory.last == 28.56)
        #expect(service.rxHistory.last == 0.0216)
        #expect(service.snapshot?.topProcesses.count == 3)
        service.stop()
    }

    @Test func skipsABadLineAndKeepsStreaming() async throws {
        let source = ScriptedSource()
        let service = makeService(source)
        service.start()
        #expect(await waitUntil { source.requests == 1 })
        source.send("not json")
        source.send(try Fixture.text("status-full.json"))
        #expect(await waitUntil { service.snapshot != nil })
        #expect(service.skippedLines == 1)
        #expect(service.phase == .live)
        service.stop()
    }

    @Test func fiveConsecutiveBadLinesStopWithAFailure() async {
        let source = ScriptedSource()
        let service = makeService(source)
        service.start()
        #expect(await waitUntil { source.requests == 1 })
        for _ in 0..<5 { source.send("garbage") }
        #expect(await waitUntil { isFailed(service.phase) })
        #expect(service.isRunning == false)
        #expect(source.requests == 1) // no reconnect after a parse failure
    }

    @Test func reconnectsWhenTheStreamEnds() async {
        let source = ScriptedSource()
        let service = makeService(source)
        service.start()
        #expect(await waitUntil { source.requests == 1 })
        source.finish(throwing: CommandFailure(command: "mole status", exitCode: 1, stderr: "boom"))
        #expect(await waitUntil { source.requests == 2 })
        service.stop()
    }

    @Test func stopTerminatesTheStreamAndKeepsTheLastFrame() async throws {
        let source = ScriptedSource()
        let service = makeService(source)
        service.start()
        #expect(await waitUntil { source.requests == 1 })
        source.send(try Fixture.text("status-full.json"))
        #expect(await waitUntil { service.snapshot != nil })
        service.stop()
        #expect(service.phase == .idle)
        #expect(service.snapshot != nil)
        #expect(await waitUntil { source.terminations >= 1 })
    }

    @Test func coalescesFramesThatArriveFasterThanTheInterval() async throws {
        let source = ScriptedSource()
        let service = makeService(source, interval: .milliseconds(300))
        service.start()
        #expect(await waitUntil { source.requests == 1 })
        source.send(try frame(cpu: 10))
        #expect(await waitUntil { service.snapshot?.cpu.usage == 10 })
        source.send(try frame(cpu: 50))
        source.send(try frame(cpu: 60))
        try await Task.sleep(for: .milliseconds(60))
        #expect(service.snapshot?.cpu.usage == 10)
        #expect(await waitUntil(timeout: .seconds(1)) { service.snapshot?.cpu.usage == 60 })
        #expect(service.cpuHistory.elements == [10, 60])
        service.stop()
    }

    @Test func fullFrameReplacesTheFastFrameImmediately() async throws {
        let source = ScriptedSource()
        let service = makeService(source, interval: .seconds(10))
        service.start()
        #expect(await waitUntil { source.requests == 1 })
        source.send(try Fixture.text("status-fast.json"))
        #expect(await waitUntil { service.snapshot?.isFastFrame == true })
        source.send(try Fixture.text("status-full.json"))
        #expect(await waitUntil(timeout: .seconds(1)) { service.snapshot?.isFastFrame == false })
        service.stop()
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd app && swift test --filter StatusServiceTests`
Expected: 编译失败，`cannot find 'StatusService' in scope`。

- [ ] **Step 3: 写实现**

`app/Sources/MoleKit/Status/StatusService.swift`：

```swift
import Foundation
import Observation

/// Decoded output of one `mo status --watch` line.
enum StatusFrameEvent: Sendable {
    case frame(StatusSnapshot)
    case badLine
}

/// Owns the `mo status --watch` stream for the Dashboard (design doc 4.1, 7, 8).
/// Decoding runs off the main actor; the main actor sees at most one published
/// snapshot per `minPublishInterval`.
@MainActor
@Observable
public final class StatusService {
    public enum Phase: Equatable, Sendable {
        case idle
        case connecting
        case live
        case reconnecting(String)
        case failed(String)
    }

    public typealias LineSource = @Sendable () -> AsyncThrowingStream<Data, any Error>

    public nonisolated static let historyCapacity = 120
    public nonisolated static let maxConsecutiveBadLines = 5

    public private(set) var phase: Phase = .idle
    public private(set) var snapshot: StatusSnapshot?
    public private(set) var cpuHistory = RingBuffer<Double>(capacity: 120)
    public private(set) var rxHistory = RingBuffer<Double>(capacity: 120)
    public private(set) var txHistory = RingBuffer<Double>(capacity: 120)
    public private(set) var diskReadHistory = RingBuffer<Double>(capacity: 120)
    public private(set) var diskWriteHistory = RingBuffer<Double>(capacity: 120)
    public private(set) var skippedLines = 0

    private let source: LineSource
    private let minPublishInterval: Duration
    private let backoff: [Duration]
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var pending: StatusSnapshot?
    @ObservationIgnored private var lastPublish: ContinuousClock.Instant?

    public init(
        source: @escaping LineSource,
        minPublishInterval: Duration = .seconds(1),
        backoff: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30)]
    ) {
        self.source = source
        self.minPublishInterval = minPublishInterval
        self.backoff = backoff
    }

    public static func live(runner: DataRunner, executable: URL, environment: [String: String]) -> StatusService {
        StatusService(source: {
            runner.stream(executable, ["status", "--watch", "--interval", "1s"], environment: environment)
        })
    }

    public var isRunning: Bool { loopTask != nil }

    public func start() {
        guard loopTask == nil else { return }
        phase = .connecting
        loopTask = Task { [weak self] in await self?.runLoop() }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
        flushTask?.cancel()
        flushTask = nil
        pending = nil
        phase = .idle
    }

    // MARK: - Loop

    private enum Outcome {
        case ended(String)
        case tooManyBadLines
    }

    private func runLoop() async {
        var attempt = 0
        while !Task.isCancelled {
            let (outcome, receivedFrame) = await consume(Self.decodedEvents(source()))
            if Task.isCancelled { return }
            if receivedFrame { attempt = 0 }
            switch outcome {
            case .tooManyBadLines:
                phase = .failed("mo status 连续 \(Self.maxConsecutiveBadLines) 行无法解析。在终端运行 mo status --watch 查看原始输出。")
                loopTask = nil
                return
            case .ended(let reason):
                phase = .reconnecting(reason)
                let delay = backoff.isEmpty ? Duration.seconds(1) : backoff[min(attempt, backoff.count - 1)]
                attempt += 1
                try? await Task.sleep(for: delay)
            }
        }
    }

    private func consume(_ events: AsyncThrowingStream<StatusFrameEvent, any Error>) async -> (Outcome, Bool) {
        var badRun = 0
        var receivedFrame = false
        do {
            for try await event in events {
                switch event {
                case .badLine:
                    skippedLines += 1
                    badRun += 1
                    if badRun >= Self.maxConsecutiveBadLines { return (.tooManyBadLines, receivedFrame) }
                case .frame(let snapshot):
                    badRun = 0
                    receivedFrame = true
                    offer(snapshot)
                }
            }
            return (.ended("mo status 已退出"), receivedFrame)
        } catch {
            return (.ended(String(describing: error)), receivedFrame)
        }
    }

    /// Decodes lines on a detached task. Cancelling the returned stream cancels
    /// the task, which cancels `lines` and so terminates the child process.
    nonisolated static func decodedEvents(
        _ lines: AsyncThrowingStream<Data, any Error>
    ) -> AsyncThrowingStream<StatusFrameEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .utility) {
                do {
                    for try await line in lines {
                        if let snapshot = try? StatusSnapshot.decode(line) {
                            continuation.yield(.frame(snapshot))
                        } else {
                            continuation.yield(.badLine)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Publishing

    private func offer(_ snapshot: StatusSnapshot) {
        let now = ContinuousClock.now
        let showingFastFrame = self.snapshot?.isFastFrame ?? false
        if let last = lastPublish, now - last < minPublishInterval, !showingFastFrame {
            pending = snapshot
            guard flushTask == nil else { return }
            let wait = minPublishInterval - (now - last)
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: wait)
                guard let self, !Task.isCancelled else { return }
                self.flushTask = nil
                if let next = self.pending {
                    self.pending = nil
                    self.publish(next)
                }
            }
        } else {
            publish(snapshot)
        }
    }

    private func publish(_ snapshot: StatusSnapshot) {
        lastPublish = .now
        self.snapshot = snapshot
        phase = .live
        cpuHistory.append(snapshot.cpu.usage)
        rxHistory.append(snapshot.network.reduce(0) { $0 + $1.rxRateMbs })
        txHistory.append(snapshot.network.reduce(0) { $0 + $1.txRateMbs })
        diskReadHistory.append(snapshot.diskIo.readRate)
        diskWriteHistory.append(snapshot.diskIo.writeRate)
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `cd app && swift test --filter StatusServiceTests`
Expected: 7 个测试全部通过。

- [ ] **Step 5: 连跑 3 次排除时序抖动，再跑全部测试**

Run: `cd app && for i in 1 2 3; do swift test --filter StatusServiceTests || exit 1; done`
Expected: 三次都通过。

Run: `cd app && swift test`
Expected: 全部测试通过（此时 1 + 4 + 9 + 5 + 8 + 8 + 7 = 42 个），以测试运行器自己的汇总行为准。

- [ ] **Step 6: Commit**

```bash
git add app/Sources/MoleKit/Status/StatusService.swift app/Tests/MoleKitTests/StatusServiceTests.swift
git commit -m "feat(app): stream mo status with off-main decoding, 1 Hz publishing and backoff"
```

---

### Task 8: 主题 Token 与窗口骨架

**Files:**
- Create: `app/Sources/MoleUI/Theme/Tokens.swift`
- Create: `app/Sources/MoleUI/Theme/Controls.swift`
- Create: `app/Sources/MoleUI/Theme/StatusGlyph.swift`
- Create: `app/Sources/MoleUI/Shell/Module.swift`
- Create: `app/Sources/MoleUI/Shell/AppModel.swift`
- Create: `app/Sources/MoleUI/Shell/RootView.swift`
- Create: `app/Sources/MoleUI/Shell/Sidebar.swift`
- Create: `app/Sources/MoleUI/Shell/Chrome.swift`
- Create: `app/Sources/MoleUI/Shell/PlaceholderModule.swift`
- Create: `app/Sources/MoleUI/App/SettingsView.swift`
- Modify: `app/Sources/MoleUI/App/MoleUIApp.swift`（整体替换）

**Interfaces:**
- Consumes: `MoleLocator`、`MoleEnvironment`、`MoleInstallation`、`DataRunner`（Task 5–6）、`StatusService`（Task 7）、`StatusGlyphKind`、`Format`
- Produces（后续 UI 任务使用）：
  - `Tokens`：颜色 `shell canvas paper ink ink2 muted faint line line2 signal signalInk signalWash signalLine hover rowHover selectedRow track onInkMuted onInkSignal`；`Tokens.Size`：`sidebarWidth gutter radius topBar summary tabBar tableHeader row footer drawerWidth`；`Tokens.ease(_ duration: Double) -> Animation`；`Color(hex: UInt32)`；`Font.mono(_:weight:)`、`Font.ui(_:weight:)`。
  - 控件：`SectionLabel(text:)`、`LiveDot()`、`View.enterOnAppear(delay:)`、`MoleButtonStyle(kind: .primary / .secondary)`、`StatusGlyph(kind:)`。
  - `enum Module: String, CaseIterable, Identifiable`（9 个：`dashboard clean projects installer apps slim space optimize history`），属性 `title symbol group milestone shortcutDigit`；`Module.NavGroup`。
  - `@MainActor @Observable final class AppModel`：`selection: Module`、`setup: Setup`（`.locating / .ready(MoleInstallation) / .failed(String)`）、`installation: MoleInstallation?`、`status: StatusService?`、`environment: [String: String]`、`runner: DataRunner`、`bootstrap() async`、`shutdown()`。
  - 骨架视图：`TopBar(title:context:live:actions:)`、`SummaryBand(height:lead:metrics:)`、`MetricRow(label:value:unit:sub:subIsSignal:showsDivider:trailing:)`、`BigNumber(value:unit:)`、`TabItem<ID>`、`TabBar(tabs:selection:tools:)`、`GridColumn`、`View.gridCell(_:)`、`TableHeader(columns:)`、`DataRow { }`、`EmptyRow(text:)`、`FooterKey`、`TableFooter(note:keys:)`、`SetupStateView`、`ModuleHost`、`PlaceholderModule`。

UI 任务没有单元测试，验收靠编译通过加手动检查清单。

- [ ] **Step 1: 写主题文件**

`app/Sources/MoleUI/Theme/Tokens.swift`：

```swift
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Vesper direction: ink on cool paper, vermilion only for what needs you (design doc 5).
enum Tokens {
    static let shell = Color(hex: 0xE6E7E0)
    static let canvas = Color(hex: 0xF7F8F3)
    static let paper = Color(hex: 0xFCFCF8)
    static let ink = Color(hex: 0x161916)
    static let ink2 = Color(hex: 0x3F453A)
    static let muted = Color(hex: 0x5E6458)
    static let faint = Color(hex: 0x62685C)
    static let line = Color(hex: 0xD8DBD0)
    static let line2 = Color(hex: 0xBFC4B6)
    static let signal = Color(hex: 0xB33B1B)
    static let signalInk = Color(hex: 0x8A2C16)
    static let signalWash = Color(hex: 0xFBF0EA)
    static let signalLine = Color(hex: 0xE7C3B4)
    static let hover = Color(hex: 0xF1F3EA)
    static let rowHover = Color(hex: 0xEDEFE6)
    static let selectedRow = Color(hex: 0xEEF1E4)
    static let track = Color(hex: 0xE4E7DC)
    static let doneDot = Color(hex: 0x8A9082)
    /// Text on an ink background (selected nav row, palette selection, toast).
    static let onInkMuted = Color(hex: 0xAEB4A6)
    static let onInkSignal = Color(hex: 0xF0916E)

    enum Size {
        static let sidebarWidth: CGFloat = 224
        static let gutter: CGFloat = 8
        static let radius: CGFloat = 7
        static let topBar: CGFloat = 56
        static let summary: CGFloat = 224
        static let tabBar: CGFloat = 48
        static let tableHeader: CGFloat = 32
        static let row: CGFloat = 48
        static let footer: CGFloat = 30
        static let drawerWidth: CGFloat = 640
    }

    /// Vesper's cubic-bezier(.2,.8,.25,1).
    static func ease(_ duration: Double) -> Animation {
        .timingCurve(0.2, 0.8, 0.25, 1, duration: duration)
    }
}

extension Font {
    /// Numbers, paths, PIDs, commands, sizes and times.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced).monospacedDigit()
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}
```

`app/Sources/MoleUI/Theme/Controls.swift`：

```swift
import SwiftUI

/// Uppercase group label: MEMORY, RECLAIMABLE, MONITOR.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.ui(10, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(Tokens.muted)
    }
}

/// 5 pt ink dot that breathes every 3.2 s while something is live.
struct LiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bright = false

    var body: some View {
        Circle()
            .fill(Tokens.ink)
            .frame(width: 5, height: 5)
            .opacity(bright ? 0.8 : 0.35)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bright = true }
            }
    }
}

/// Module entrance: fade in and rise 4 pt (design doc 5.8).
struct EnterOnAppear: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 4)
            .onAppear {
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(Tokens.ease(0.4).delay(delay)) { shown = true }
                }
            }
    }
}

extension View {
    func enterOnAppear(delay: Double = 0) -> some View {
        modifier(EnterOnAppear(delay: delay))
    }
}

struct MoleButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind = .secondary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let primary = kind == .primary
        return configuration.label
            .font(.ui(11.5, weight: .medium))
            .foregroundStyle(primary ? Tokens.paper : Tokens.ink)
            .padding(.horizontal, 10)
            .frame(height: 29)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(primary
                        ? (configuration.isPressed ? Color(hex: 0x2A2F27) : Tokens.ink)
                        : (configuration.isPressed ? Tokens.hover : Tokens.paper))
            )
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(primary ? Tokens.ink : Tokens.line2))
            .opacity(isEnabled ? 1 : 0.45)
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}
```

`app/Sources/MoleUI/Theme/StatusGlyph.swift`：

```swift
import MoleKit
import SwiftUI

/// The four status glyphs (design doc 5.6), drawn in an 8 × 8 box.
struct StatusGlyph: View {
    let kind: StatusGlyphKind

    var body: some View {
        Group {
            switch kind {
            case .done:
                Circle().fill(Tokens.doneDot).frame(width: 5, height: 5)
            case .pending:
                Circle().strokeBorder(Tokens.ink, lineWidth: 1.2)
            case .attention:
                ZStack {
                    Circle().strokeBorder(Tokens.signal, lineWidth: 1.2)
                    Circle().fill(Tokens.signal).padding(2)
                }
            case .failure:
                Rectangle().fill(Tokens.signal).frame(width: 6, height: 6).rotationEffect(.degrees(45))
            }
        }
        .frame(width: 8, height: 8)
    }
}
```

- [ ] **Step 2: 写模块定义与应用模型**

`app/Sources/MoleUI/Shell/Module.swift`：

```swift
import SwiftUI

/// Sidebar entries in display order; ⌘1–⌘9 follow this order.
enum Module: String, CaseIterable, Identifiable {
    case dashboard, clean, projects, installer, apps, slim, space, optimize, history

    enum NavGroup: String, CaseIterable {
        case monitor = "MONITOR"
        case reclaim = "RECLAIM"
        case apps = "APPS"
        case disk = "DISK"
        case care = "CARE"
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .clean: "Clean"
        case .projects: "Projects"
        case .installer: "Installer"
        case .apps: "Apps"
        case .slim: "Slim"
        case .space: "Space"
        case .optimize: "Optimize"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.33percent"
        case .clean: "sparkles"
        case .projects: "hammer"
        case .installer: "shippingbox"
        case .apps: "square.grid.2x2"
        case .slim: "scissors"
        case .space: "square.split.2x2"
        case .optimize: "wrench.adjustable"
        case .history: "clock.arrow.circlepath"
        }
    }

    var group: NavGroup {
        switch self {
        case .dashboard: .monitor
        case .clean, .projects, .installer: .reclaim
        case .apps, .slim: .apps
        case .space: .disk
        case .optimize, .history: .care
        }
    }

    /// Milestone that wires the module up (design doc 11).
    var milestone: String {
        switch self {
        case .dashboard: "M2"
        case .apps, .slim, .history: "M4"
        case .clean, .installer: "M5"
        case .space: "M6"
        case .projects, .optimize: "M7"
        }
    }

    var shortcutDigit: Character {
        Character(String((Module.allCases.firstIndex(of: self) ?? 0) + 1))
    }
}
```

`app/Sources/MoleUI/Shell/AppModel.swift`（Task 11、12 会整体替换）：

```swift
import Foundation
import MoleKit
import Observation

@MainActor
@Observable
final class AppModel {
    enum Setup: Equatable {
        case locating
        case ready(MoleInstallation)
        case failed(String)
    }

    var selection: Module = .dashboard
    private(set) var setup: Setup = .locating
    private(set) var status: StatusService?
    private(set) var environment: [String: String] = [:]
    let runner = DataRunner()

    var installation: MoleInstallation? {
        if case .ready(let installation) = setup { installation } else { nil }
    }

    /// Finds and verifies mo. Safe to call again after the user edits Settings.
    func bootstrap() async {
        status?.stop()
        status = nil
        setup = .locating
        let env = MoleEnvironment.make(base: ProcessInfo.processInfo.environment)
        environment = env
        do {
            let locator = MoleLocator.fromApp(searchPath: env["PATH"] ?? "")
            let found = try await locator.locate(using: runner, environment: env)
            status = StatusService.live(runner: runner, executable: found.executableURL, environment: env)
            setup = .ready(found)
        } catch {
            setup = .failed(String(describing: error))
        }
    }

    func shutdown() {
        status?.stop()
        runner.terminateAll()
    }
}
```

- [ ] **Step 3: 写骨架视图**

`app/Sources/MoleUI/Shell/Chrome.swift`：

```swift
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
```

`app/Sources/MoleUI/Shell/Sidebar.swift`（Task 11 会替换其中的 `SidebarFooter`）：

```swift
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
    @State private var hovering = false

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
```

`app/Sources/MoleUI/Shell/PlaceholderModule.swift`（Task 11 会整体替换）：

```swift
import SwiftUI

/// Stand-in for modules that later milestones wire up.
struct PlaceholderModule: View {
    let module: Module

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: module.title, context: "规划中 · \(module.milestone)") { EmptyView() }
            VStack(spacing: 5) {
                Text("\(module.title) 在 \(module.milestone) 接入")
                    .font(.ui(11.5, weight: .semibold))
                    .foregroundStyle(Tokens.ink)
                Text("⌘K 打开命令面板").font(.mono(10)).foregroundStyle(Tokens.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
```

`app/Sources/MoleUI/Shell/RootView.swift`（Task 11、12 会整体替换）：

```swift
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Tokens.Size.gutter) {
            Sidebar()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tokens.canvas)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Size.radius))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Size.radius).strokeBorder(Tokens.line2))
        }
        .padding(Tokens.Size.gutter)
        .background(Tokens.shell)
        .ignoresSafeArea()
    }

    @ViewBuilder private var content: some View {
        switch model.setup {
        case .locating:
            SetupStateView(title: "正在查找 mo…", detail: nil, retry: nil)
        case .failed(let message):
            SetupStateView(title: "找不到可用的 mo", detail: message) {
                Task { await model.bootstrap() }
            }
        case .ready:
            ModuleHost(module: model.selection)
        }
    }
}

struct ModuleHost: View {
    let module: Module

    var body: some View {
        PlaceholderModule(module: module)
            .id(module)
    }
}

struct SetupStateView: View {
    let title: String
    let detail: String?
    let retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            if detail == nil { LiveDot() } else { StatusGlyph(kind: .failure) }
            Text(title).font(.ui(11.5, weight: .semibold)).foregroundStyle(Tokens.ink)
            if let detail {
                Text(detail)
                    .font(.ui(10.5))
                    .foregroundStyle(Tokens.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .textSelection(.enabled)
            }
            if let retry {
                Button("重新查找", action: retry)
                    .buttonStyle(MoleButtonStyle())
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

`app/Sources/MoleUI/App/SettingsView.swift`：

```swift
import MoleKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(MoleLocator.explicitPathDefaultsKey) private var molePath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "mole 路径")
            TextField("", text: $molePath, prompt: Text("留空则自动查找"))
                .textFieldStyle(.roundedBorder)
                .font(.mono(11))
            Text("留空时依次查找：打包时写入的仓库路径、PATH 里的 mo 和 mole。")
                .font(.ui(10))
                .foregroundStyle(Tokens.muted)
            HStack {
                Text(model.installation.map { "当前：\($0.executableURL.path) · \($0.version)" } ?? "当前：未找到")
                    .font(.mono(10))
                    .foregroundStyle(Tokens.ink2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("重新查找") { Task { await model.bootstrap() } }
                    .buttonStyle(MoleButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Tokens.paper)
        .preferredColorScheme(.light)
    }
}
```

把 `app/Sources/MoleUI/App/MoleUIApp.swift` 整体替换为（Task 12 再加 `.commands`）：

```swift
import AppKit
import SwiftUI

@main
struct MoleUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Mole", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1080, minHeight: 680)
                .preferredColorScheme(.light)
                .task {
                    appDelegate.model = model
                    await model.bootstrap()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)

        Settings {
            SettingsView().environment(model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationWillTerminate(_ notification: Notification) {
        // SIGTERM every child; mo status also exits on its own once its stdout closes.
        model?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
```

- [ ] **Step 4: 编译**

Run: `cd app && swift build`
Expected: `Build complete!`，没有错误。若出现 Swift 6 并发诊断，按诊断修正被指出的那一行（例如补 `@MainActor`），不要关闭严格并发。

- [ ] **Step 5: 手动验收**

Run: `cd app && make run`
Expected（逐条核对）：
1. 窗口无标题栏，交通灯落在侧边栏左上；外层是 `#E6E7E0` 冷灰底，右侧内容是圆角 7、描边的卡片。
2. 侧边栏依次是 ◐ MOLE、启动盘卡片、五个分组 MONITOR / RECLAIM / APPS / DISK / CARE 下的 9 个入口；点击入口切换，选中项为墨底纸字，悬停有浅底。
3. 每个入口右侧主区显示「规划中 · M?」顶栏和居中的提示。
4. 侧边栏底部显示 `mo 1.71.0`。
5. 打开「设置」（⌘,），把路径填成 `/nonexistent`，点「重新查找」：主区显示「找不到可用的 mo」和带原因、下一步的一行说明；清空路径再点「重新查找」，恢复正常。
6. 退出应用后运行 `pgrep -fl status-go; echo "exit=$?"`，输出 `exit=1`。

- [ ] **Step 6: Commit**

```bash
git add app/Sources/MoleUI
git commit -m "feat(app): add Vesper theme tokens and the window shell with nine modules"
```

---

### Task 9: Dashboard

**Files:**
- Create: `app/Sources/MoleUI/Components/Charts.swift`
- Create: `app/Sources/MoleUI/Components/WindowOcclusionReader.swift`
- Create: `app/Sources/MoleUI/Features/Dashboard/DashboardView.swift`
- Create: `app/Sources/MoleUI/Features/Dashboard/DashboardTabs.swift`
- Modify: `app/Sources/MoleUI/Shell/RootView.swift`（替换 `ModuleHost`）

**Interfaces:**
- Consumes: `AppModel.status`（Task 8）、`StatusService` 的 `phase snapshot cpuHistory rxHistory start() stop()`（Task 7）、`StatusSnapshot` 各字段与 `Signals`（Task 4）、`Format`（Task 3）、Task 8 的全部骨架视图
- Produces：`Sparkline(values:maxValue:capacity:color:)`、`MicroBars(values:count:)`、`Meter(fraction:signal:width:)`、`CoreHeatmap(perCore:)`、`WindowOcclusionReader(onChange:)`、`DashboardView`、`DashboardTab`。Task 11 之后的模块可以直接复用这些图表组件。
- 行为：Dashboard 出现时 `status.start()`，离开（切换模块）、窗口最小化或被完全遮挡时 `status.stop()`；只读，不开抽屉；实时刷新不触发行动画。

- [ ] **Step 1: 写图表组件**

`app/Sources/MoleUI/Components/Charts.swift`：

```swift
import SwiftUI

/// Right-aligned line chart over a fixed window: the newest value sits at the right edge.
struct Sparkline: View {
    let values: [Double]
    var maxValue: Double? = nil
    var capacity: Int = 120
    var color: Color = Tokens.ink

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let top = max(maxValue ?? (values.max() ?? 1), 0.0001)
            let step = size.width / CGFloat(max(capacity - 1, 1))
            let offset = CGFloat(max(capacity - values.count, 0)) * step
            var path = Path()
            for (index, value) in values.suffix(capacity).enumerated() {
                let ratio = CGFloat(min(max(value / top, 0), 1))
                let point = CGPoint(x: offset + CGFloat(index) * step, y: size.height - 1 - ratio * (size.height - 2))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        }
    }
}

/// Small bar strip; the newest bar is darker (Vesper microbars).
struct MicroBars: View {
    let values: [Double]
    var count = 24

    var body: some View {
        Canvas { context, size in
            let recent = Array(values.suffix(count))
            guard !recent.isEmpty else { return }
            let top = max(recent.max() ?? 0, 0.0001)
            let gap: CGFloat = 1.5
            let width = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
            let start = count - recent.count
            for (index, value) in recent.enumerated() {
                let height = max(2, CGFloat(value / top) * size.height)
                let rect = CGRect(x: CGFloat(start + index) * (width + gap), y: size.height - height, width: width, height: height)
                let opacity = index == recent.count - 1 ? 0.72 : 0.17
                context.fill(Path(rect), with: .color(Tokens.ink.opacity(opacity)))
            }
        }
        .frame(width: 96, height: 23)
    }
}

/// 3 pt progress track; vermilion only when the value is a risk.
struct Meter: View {
    let fraction: Double
    var signal = false
    var width: CGFloat = 150

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Tokens.track)
            RoundedRectangle(cornerRadius: 2)
                .fill(signal ? Tokens.signal : Tokens.ink.opacity(0.8))
                .frame(width: width * CGFloat(min(max(fraction, 0), 1)))
        }
        .frame(width: width, height: 3)
    }
}

/// One cell per logical core, ink density = utilisation. Never vermilion: a busy core is not a risk.
struct CoreHeatmap: View {
    let perCore: [Double]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(perCore.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Tokens.ink.opacity(0.08 + 0.8 * min(max(perCore[index], 0), 100) / 100))
                    .frame(width: 9, height: 14)
            }
        }
    }
}
```

`app/Sources/MoleUI/Components/WindowOcclusionReader.swift`：

```swift
import AppKit
import SwiftUI

/// Reports whether the hosting window is visible (not minimised, not fully covered).
struct WindowOcclusionReader: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
    }

    final class ObserverView: NSView {
        var onChange: (@MainActor (Bool) -> Void)?
        private var token: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token {
                NotificationCenter.default.removeObserver(token)
                self.token = nil
            }
            guard let window else { return }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window else { return }
                    self.onChange?(window.occlusionState.contains(.visible))
                }
            }
        }
    }
}
```

- [ ] **Step 2: 写 Dashboard 视图**

`app/Sources/MoleUI/Features/Dashboard/DashboardView.swift`：

```swift
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
    @State private var tab: DashboardTab = .processes

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
```

`app/Sources/MoleUI/Features/Dashboard/DashboardTabs.swift`：

```swift
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
```

把 `app/Sources/MoleUI/Shell/RootView.swift` 里的 `ModuleHost` 整个替换为：

```swift
struct ModuleHost: View {
    let module: Module

    var body: some View {
        Group {
            switch module {
            case .dashboard: DashboardView()
            default: PlaceholderModule(module: module)
            }
        }
        .id(module)
    }
}
```

- [ ] **Step 3: 编译**

Run: `cd app && swift build`
Expected: `Build complete!`。

- [ ] **Step 4: 手动验收与性能检查**

Run: `cd app && make run`
Expected（逐条核对）：
1. 1 秒内出现 Dashboard：顶栏显示 `MacBook Pro · Apple M3 Pro · macOS 27.0.1 · 运行 …` 和呼吸点「实时」；侧边栏 Dashboard 右侧出现健康分。
2. 摘要带左侧是 CPU 大数字、load、核数、走势线（从右向左逐帧增长）、每核热力条；右侧三行依次是 MEMORY、STARTUP DISK、NETWORK。启动盘当前 91.8%，所以它的数值下方说明和进度条为朱红，其余为墨色。
3. 页签「进程 · 磁盘 · 网络 · 电源」可切换，下划线滑动；进程页显示 5 个进程，有僵尸进程时末行带朱红圆环；磁盘页计数为朱红。
4. 数字全部为等宽字体，刷新时列宽不跳动。

性能检查（应用保持在 Dashboard 并可见）：

Run: `pgrep -fl status-go`
Expected: 恰好一个 `…/bin/status-go status --watch --interval 1s` 进程（argv0 可能显示为 status-go）。

Run: `top -l 4 -s 2 -pid "$(pgrep -x MoleUI)" -stats pid,command,cpu`
Expected: 后三次采样 MoleUI 的 CPU 都低于 5%。（设计文档的主线程 < 2% 预算用 Instruments 的 Time Profiler 复核，记录结果即可，不阻塞本任务。）

切换到 Clean 后运行 `sleep 2; pgrep -fl status-go; echo "exit=$?"`
Expected: `exit=1`（离开 Dashboard 即停止 status 进程）。

切回 Dashboard，再把窗口最小化，运行 `sleep 2; pgrep -fl status-go; echo "exit=$?"`
Expected: `exit=1`；恢复窗口后 1 秒内数据继续刷新，走势线保留之前的历史。

- [ ] **Step 5: Commit**

```bash
git add app/Sources/MoleUI
git commit -m "feat(app): add the live Dashboard backed by mo status --watch"
```

---

### Task 10: 命令规格与执行协调器

**Files:**
- Create: `app/Sources/MoleKit/Commands/CommandSpec.swift`
- Create: `app/Sources/MoleKit/Commands/CommandRunCoordinator.swift`
- Test: `app/Tests/MoleKitTests/CommandRunCoordinatorTests.swift`

**Interfaces:**
- Consumes: `Signals.exit`、`StatusGlyphKind`（Task 4）
- Produces:
  - `public struct CommandSpec: Sendable, Equatable, Identifiable`：`static let forbiddenArguments: Set<String> = ["--permanent"]`、`init?(arguments: [String], title: String, mutatesSystem: Bool, id: UUID = UUID())`（参数为空或含禁用参数时返回 nil）、`id`、`arguments`（不含 `mo` 本身）、`title`、`mutatesSystem`、`commandText`（如 `mo clean --dry-run`）、`displayLine`（`$ ` + commandText）。
  - `public enum ShellQuote { static func quote(_ value: String) -> String }`：仅含 `[A-Za-z0-9-_./=:@%+,]` 时原样返回，否则用单引号包裹。
  - `@MainActor @Observable public final class CommandRunCoordinator`：`enum State { idle, running(CommandSpec, startedAt: Date), finished(CommandSpec, exitCode: Int32?, duration: TimeInterval) }`；只读 `state`、`completedRuns: Int`、`recent: [CommandSpec]`（最近 5 条不改动系统的命令，按参数去重，新的在前）、`isDrawerPresented: Bool`；计算属性 `current: CommandSpec?`、`isRunning: Bool`、`glyph: StatusGlyphKind`；方法 `@discardableResult begin(_:now:) -> Bool`（已有命令在运行时返回 false 且不改任何状态）、`finish(_ id: UUID, exitCode: Int32?, now: Date = Date())`（id 不符或未在运行时忽略）、`presentDrawer()`、`@discardableResult dismissDrawer() -> Bool`（运行中拒绝）。

- [ ] **Step 1: 写失败的测试**

`app/Tests/MoleKitTests/CommandRunCoordinatorTests.swift`：

```swift
import Foundation
import Testing
@testable import MoleKit

@Suite struct CommandSpecTests {
    @Test func refusesPermanentAndEmptyArguments() {
        #expect(CommandSpec(arguments: ["uninstall", "--permanent", "Slack"], title: "x", mutatesSystem: true) == nil)
        #expect(CommandSpec(arguments: [], title: "x", mutatesSystem: false) == nil)
        #expect(CommandSpec(arguments: ["clean", "--dry-run"], title: "x", mutatesSystem: false) != nil)
    }

    @Test func quotesArgumentsForDisplay() throws {
        let spec = try #require(CommandSpec(
            arguments: ["uninstall", "--dry-run", "腾讯会议", "Bob's App"],
            title: "预览卸载",
            mutatesSystem: false
        ))
        #expect(spec.commandText == "mo uninstall --dry-run '腾讯会议' 'Bob'\\''s App'")
        #expect(spec.displayLine == "$ " + spec.commandText)
        #expect(ShellQuote.quote("") == "''")
        #expect(ShellQuote.quote("--interval=1s") == "--interval=1s")
    }
}

@MainActor
@Suite struct CommandRunCoordinatorTests {
    private func spec(_ arguments: [String], mutates: Bool = false) -> CommandSpec {
        CommandSpec(arguments: arguments, title: arguments.joined(separator: " "), mutatesSystem: mutates)!
    }

    @Test func runsOneCommandAtATime() {
        let runs = CommandRunCoordinator()
        let first = spec(["clean", "--dry-run"])
        let start = Date(timeIntervalSince1970: 100)
        #expect(runs.begin(first, now: start))
        #expect(runs.isRunning)
        #expect(runs.isDrawerPresented)
        #expect(runs.current == first)
        #expect(runs.glyph == .pending)

        #expect(runs.begin(spec(["optimize", "--dry-run"])) == false)
        #expect(runs.current == first)

        runs.finish(first.id, exitCode: 0, now: start.addingTimeInterval(12))
        #expect(runs.state == .finished(first, exitCode: 0, duration: 12))
        #expect(runs.completedRuns == 1)
        #expect(runs.glyph == .done)
        #expect(runs.begin(spec(["optimize", "--dry-run"])))
    }

    @Test func nonZeroOrMissingExitIsAFailure() {
        let runs = CommandRunCoordinator()
        let command = spec(["purge", "--dry-run"])
        runs.begin(command)
        runs.finish(command.id, exitCode: nil)
        #expect(runs.glyph == .failure)
    }

    @Test func ignoresFinishForAnotherCommandOrWhenIdle() {
        let runs = CommandRunCoordinator()
        runs.finish(UUID(), exitCode: 0)
        #expect(runs.state == .idle)
        #expect(runs.completedRuns == 0)

        let command = spec(["clean", "--dry-run"])
        runs.begin(command)
        runs.finish(UUID(), exitCode: 0)
        #expect(runs.isRunning)
    }

    @Test func drawerCannotCloseWhileRunning() {
        let runs = CommandRunCoordinator()
        let command = spec(["clean", "--dry-run"])
        runs.begin(command)
        #expect(runs.dismissDrawer() == false)
        #expect(runs.isDrawerPresented)
        runs.finish(command.id, exitCode: 1)
        #expect(runs.dismissDrawer())
        #expect(runs.isDrawerPresented == false)
        runs.presentDrawer()
        #expect(runs.isDrawerPresented)
    }

    @Test func recentKeepsFiveReadOnlyCommandsNewestFirst() {
        let runs = CommandRunCoordinator()
        func run(_ command: CommandSpec) {
            runs.begin(command)
            runs.finish(command.id, exitCode: 0)
        }
        run(spec(["clean"], mutates: true))
        for name in ["a", "b", "c", "d", "e", "f"] { run(spec([name, "--dry-run"])) }
        run(spec(["c", "--dry-run"]))
        #expect(runs.recent.map(\.arguments.first) == ["c", "f", "e", "d", "b"])
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd app && swift test --filter "CommandSpecTests|CommandRunCoordinatorTests"`
Expected: 编译失败，`cannot find 'CommandSpec' in scope`。

- [ ] **Step 3: 写实现**

`app/Sources/MoleKit/Commands/CommandSpec.swift`：

```swift
import Foundation

/// A `mo` invocation for the terminal channel. `arguments` excludes `mo` itself.
public struct CommandSpec: Sendable, Equatable, Identifiable {
    /// The GUI never bypasses the Trash (design doc 3).
    public static let forbiddenArguments: Set<String> = ["--permanent"]

    public let id: UUID
    public let arguments: [String]
    public let title: String
    public let mutatesSystem: Bool

    public init?(arguments: [String], title: String, mutatesSystem: Bool, id: UUID = UUID()) {
        guard !arguments.isEmpty,
              !arguments.contains(where: { Self.forbiddenArguments.contains($0) })
        else { return nil }
        self.id = id
        self.arguments = arguments
        self.title = title
        self.mutatesSystem = mutatesSystem
    }

    /// Copy-pasteable form, e.g. `mo uninstall --dry-run '腾讯会议'`.
    public var commandText: String {
        (["mo"] + arguments.map(ShellQuote.quote)).joined(separator: " ")
    }

    public var displayLine: String { "$ " + commandText }
}

public enum ShellQuote {
    private static let safe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./=:@%+,")

    public static func quote(_ value: String) -> String {
        if !value.isEmpty, value.allSatisfy({ safe.contains($0) }) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
```

`app/Sources/MoleKit/Commands/CommandRunCoordinator.swift`：

```swift
import Foundation
import Observation

/// Single-slot state for the execution drawer: one terminal command at a time
/// (mo holds its own locks and sudo session, so parallel runs gain nothing).
@MainActor
@Observable
public final class CommandRunCoordinator {
    public enum State: Equatable, Sendable {
        case idle
        case running(CommandSpec, startedAt: Date)
        case finished(CommandSpec, exitCode: Int32?, duration: TimeInterval)
    }

    public nonisolated static let recentLimit = 5

    public private(set) var state: State = .idle
    /// Increments after every finished command; modules watch it to refresh stale data.
    public private(set) var completedRuns = 0
    public private(set) var recent: [CommandSpec] = []
    public private(set) var isDrawerPresented = false

    public init() {}

    public var current: CommandSpec? {
        switch state {
        case .idle: nil
        case .running(let spec, _), .finished(let spec, _, _): spec
        }
    }

    public var isRunning: Bool {
        if case .running = state { true } else { false }
    }

    public var glyph: StatusGlyphKind {
        switch state {
        case .idle: .done
        case .running: .pending
        case .finished(_, let exitCode, _): Signals.exit(exitCode)
        }
    }

    @discardableResult
    public func begin(_ spec: CommandSpec, now: Date = Date()) -> Bool {
        guard !isRunning else { return false }
        state = .running(spec, startedAt: now)
        isDrawerPresented = true
        if !spec.mutatesSystem {
            recent.removeAll { $0.arguments == spec.arguments }
            recent.insert(spec, at: 0)
            if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
        }
        return true
    }

    public func finish(_ id: UUID, exitCode: Int32?, now: Date = Date()) {
        guard case .running(let spec, let startedAt) = state, spec.id == id else { return }
        state = .finished(spec, exitCode: exitCode, duration: now.timeIntervalSince(startedAt))
        completedRuns += 1
    }

    public func presentDrawer() {
        if current != nil { isDrawerPresented = true }
    }

    /// Refused while a command runs: the PTY must stay visible until mo exits.
    @discardableResult
    public func dismissDrawer() -> Bool {
        guard !isRunning else { return false }
        isDrawerPresented = false
        return true
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `cd app && swift test --filter "CommandSpecTests|CommandRunCoordinatorTests"`
Expected: 7 个测试全部通过。

- [ ] **Step 5: Commit**

```bash
git add app/Sources/MoleKit/Commands app/Tests/MoleKitTests/CommandRunCoordinatorTests.swift
git commit -m "feat(app): add command specs and a single-slot run coordinator"
```

---

### Task 11: 执行抽屉（SwiftTerm）

**Files:**
- Create: `app/Sources/MoleUI/Terminal/TerminalTheme.swift`
- Create: `app/Sources/MoleUI/Terminal/TerminalHost.swift`
- Create: `app/Sources/MoleUI/Terminal/ExecutionDrawer.swift`
- Modify: `app/Sources/MoleUI/Shell/Module.swift`（加 `previewArguments`）
- Modify: `app/Sources/MoleUI/Shell/AppModel.swift`（整体替换）
- Modify: `app/Sources/MoleUI/Shell/RootView.swift`（替换 `RootView`）
- Modify: `app/Sources/MoleUI/Shell/PlaceholderModule.swift`（整体替换）
- Modify: `app/Sources/MoleUI/Shell/Sidebar.swift`（替换 `SidebarFooter`）

**Interfaces:**
- Consumes: `CommandSpec`、`CommandRunCoordinator`（Task 10）、`AppModel.environment / installation`（Task 8）、`Format.elapsed`、`Signals.exit`、`StatusGlyph`
- Produces:
  - `AppModel.runs: CommandRunCoordinator`；`@discardableResult AppModel.run(_ arguments: [String], title: String, mutatesSystem: Bool) -> Bool`（Task 12 会在其中加忙碌提示）。
  - `Module.previewArguments: [String]?`：clean `["clean","--dry-run"]`、projects `["purge","--dry-run"]`、installer `["installer","--dry-run"]`、slim `["slim","--dry-run"]`、optimize `["optimize","--dry-run"]`，其余为 nil。
  - `ExecutionDrawer(runs:installation:)`、`TerminalHost(spec:executable:environment:onExit:)`、`RunStatusChip(state:)`、`TerminalTheme.apply(to:)`。
- 行为：抽屉从右侧滑入（0.32 s，移位加淡入），四周留 8 pt；抽屉头显示 `$ mo …`、复制按钮、状态标签（运行中 + 计时 / 退出码，非零为朱红）、关闭按钮；运行中关闭按钮禁用；每条命令一个全新的终端视图（`.id(spec.id)`）；退出码回传 `runs.finish`。M3 只接入 dry-run 预览命令，真正改动系统的执行按钮留给各模块里程碑。

- [ ] **Step 1: 写终端主题与宿主**

`app/Sources/MoleUI/Terminal/TerminalTheme.swift`：

```swift
import AppKit
import SwiftTerm

/// The terminal is the only dark surface: ink background, paper text,
/// low-saturation ANSI colours. Red uses Vesper's on-ink signal (#F0916E),
/// because #B33B1B on ink is too dark to read.
enum TerminalTheme {
    static let backgroundHex: UInt32 = 0x161916 // Tokens.ink
    static let foregroundHex: UInt32 = 0xFCFCF8 // Tokens.paper

    /// black, red, green, yellow, blue, magenta, cyan, white, then the bright variants.
    static let ansiHex: [UInt32] = [
        0x161916, 0xF0916E, 0x9DB38A, 0xD8C27A, 0x8FA8C0, 0xB89AB5, 0x8DB8B0, 0xD5DACD,
        0x62685C, 0xF4A88B, 0xB5C9A2, 0xE6D396, 0xA9BFD4, 0xCCB2C9, 0xA6CCC4, 0xFCFCF8,
    ]

    @MainActor
    static func apply(to view: TerminalView) {
        view.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        view.nativeBackgroundColor = nsColor(backgroundHex)
        view.nativeForegroundColor = nsColor(foregroundHex)
        view.caretColor = nsColor(foregroundHex)
        view.installColors(ansiHex.map(terminalColor))
    }

    static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// SwiftTerm colours take 16-bit components.
    static func terminalColor(_ hex: UInt32) -> SwiftTerm.Color {
        SwiftTerm.Color(
            red: UInt16((hex >> 16) & 0xFF) * 257,
            green: UInt16((hex >> 8) & 0xFF) * 257,
            blue: UInt16(hex & 0xFF) * 257
        )
    }
}
```

`app/Sources/MoleUI/Terminal/TerminalHost.swift`：

```swift
import AppKit
import MoleKit
import SwiftTerm
import SwiftUI

/// Runs one `mo` command in a real PTY. sudo prompts, y/N confirmations and
/// Space-to-skip all behave exactly as in Terminal.app.
struct TerminalHost: NSViewRepresentable {
    let spec: CommandSpec
    let executable: URL
    let environment: [String: String]
    let onExit: @MainActor (Int32?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onExit: onExit)
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        TerminalTheme.apply(to: view)
        view.processDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
        context.coordinator.onExit = onExit
        guard context.coordinator.startedID != spec.id else { return }
        context.coordinator.startedID = spec.id
        var env = environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        view.startProcess(
            executable: executable.path,
            args: spec.arguments,
            environment: env.map { "\($0.key)=\($0.value)" },
            execName: nil,
            currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
        Task { @MainActor in view.window?.makeFirstResponder(view) }
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency LocalProcessTerminalViewDelegate {
        var onExit: @MainActor (Int32?) -> Void
        var startedID: UUID?

        init(onExit: @escaping @MainActor (Int32?) -> Void) {
            self.onExit = onExit
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            onExit(exitCode)
        }

        func processFailedToStart(source: TerminalView, error: LocalProcessError) {
            onExit(nil)
        }
    }
}
```

- [ ] **Step 2: 写执行抽屉**

`app/Sources/MoleUI/Terminal/ExecutionDrawer.swift`：

```swift
import AppKit
import MoleKit
import SwiftUI

struct ExecutionDrawer: View {
    @Environment(AppModel.self) private var model
    let runs: CommandRunCoordinator
    let installation: MoleInstallation
    @State private var copied = false

    var body: some View {
        if let spec = runs.current {
            VStack(spacing: 0) {
                header(spec)
                TerminalHost(
                    spec: spec,
                    executable: installation.executableURL,
                    environment: model.environment
                ) { exitCode in
                    runs.finish(spec.id, exitCode: exitCode)
                }
                .id(spec.id)
                .padding(10)
                .background(Tokens.ink)
            }
            .frame(width: Tokens.Size.drawerWidth)
            .frame(maxHeight: .infinity)
            .background(Tokens.paper)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Size.radius))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Size.radius).strokeBorder(Tokens.line2))
            .shadow(color: Tokens.ink.opacity(0.08), radius: 2, y: 2)
            .shadow(color: Tokens.ink.opacity(0.3), radius: 45, y: 30)
        }
    }

    private func header(_ spec: CommandSpec) -> some View {
        HStack(spacing: 8) {
            Text(spec.displayLine)
                .font(.mono(11, weight: .medium))
                .foregroundStyle(Tokens.ink2)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(spec.commandText, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Tokens.muted)
            .help("复制命令")
            Spacer(minLength: 8)
            RunStatusChip(state: runs.state)
            Button {
                runs.dismissDrawer()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(runs.isRunning ? Tokens.line2 : Tokens.ink2)
            .disabled(runs.isRunning)
            .keyboardShortcut(.cancelAction)
            .help(runs.isRunning ? "命令运行中，结束后才能关闭" : "关闭（Esc）")
        }
        .padding(.leading, 17)
        .padding(.trailing, 12)
        .frame(height: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(Tokens.line).frame(height: 1) }
    }
}

struct RunStatusChip: View {
    let state: CommandRunCoordinator.State

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .running(_, let startedAt):
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                chip(.pending, "运行中 · \(Format.elapsed(Int(context.date.timeIntervalSince(startedAt))))", signal: false)
            }
        case .finished(_, let exitCode, let duration):
            chip(
                Signals.exit(exitCode),
                "\(exitCode.map { "退出 \($0)" } ?? "已中断") · \(Format.elapsed(Int(duration)))",
                signal: exitCode != 0
            )
        }
    }

    private func chip(_ glyph: StatusGlyphKind, _ text: String, signal: Bool) -> some View {
        HStack(spacing: 5) {
            StatusGlyph(kind: glyph)
            Text(text).font(.mono(10, weight: .semibold))
        }
        .foregroundStyle(signal ? Tokens.signalInk : Tokens.ink2)
        .padding(.horizontal, 7)
        .frame(height: 21)
        .background(RoundedRectangle(cornerRadius: 2).fill(signal ? Tokens.signalWash : Tokens.canvas))
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(signal ? Tokens.signalLine : Tokens.line))
    }
}
```

- [ ] **Step 3: 接入模型、根视图、占位模块和侧边栏**

在 `app/Sources/MoleUI/Shell/Module.swift` 的 `enum Module` 内、`shortcutDigit` 之后加入：

```swift
    /// Read-only preview available before the module's own milestone lands.
    var previewArguments: [String]? {
        switch self {
        case .clean: ["clean", "--dry-run"]
        case .projects: ["purge", "--dry-run"]
        case .installer: ["installer", "--dry-run"]
        case .slim: ["slim", "--dry-run"]
        case .optimize: ["optimize", "--dry-run"]
        case .dashboard, .apps, .space, .history: nil
        }
    }
```

把 `app/Sources/MoleUI/Shell/AppModel.swift` 整体替换为：

```swift
import Foundation
import MoleKit
import Observation

@MainActor
@Observable
final class AppModel {
    enum Setup: Equatable {
        case locating
        case ready(MoleInstallation)
        case failed(String)
    }

    var selection: Module = .dashboard
    private(set) var setup: Setup = .locating
    private(set) var status: StatusService?
    private(set) var environment: [String: String] = [:]
    let runner = DataRunner()
    let runs = CommandRunCoordinator()

    var installation: MoleInstallation? {
        if case .ready(let installation) = setup { installation } else { nil }
    }

    /// Finds and verifies mo. Safe to call again after the user edits Settings.
    func bootstrap() async {
        status?.stop()
        status = nil
        setup = .locating
        let env = MoleEnvironment.make(base: ProcessInfo.processInfo.environment)
        environment = env
        do {
            let locator = MoleLocator.fromApp(searchPath: env["PATH"] ?? "")
            let found = try await locator.locate(using: runner, environment: env)
            status = StatusService.live(runner: runner, executable: found.executableURL, environment: env)
            setup = .ready(found)
        } catch {
            setup = .failed(String(describing: error))
        }
    }

    /// Starts a command in the execution drawer. Returns false when mo is not ready,
    /// the spec is refused (for example `--permanent`), or another command is still running.
    @discardableResult
    func run(_ arguments: [String], title: String, mutatesSystem: Bool) -> Bool {
        guard installation != nil,
              let spec = CommandSpec(arguments: arguments, title: title, mutatesSystem: mutatesSystem)
        else { return false }
        guard runs.begin(spec) else {
            runs.presentDrawer()
            return false
        }
        return true
    }

    func shutdown() {
        status?.stop()
        runner.terminateAll()
    }
}
```

把 `app/Sources/MoleUI/Shell/RootView.swift` 里的 `RootView` 整个替换为（`ModuleHost`、`SetupStateView` 保持不变）：

```swift
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Tokens.Size.gutter) {
            Sidebar()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tokens.canvas)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Size.radius))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Size.radius).strokeBorder(Tokens.line2))
        }
        .padding(Tokens.Size.gutter)
        .background(Tokens.shell)
        .overlay(alignment: .trailing) { drawer }
        .animation(reduceMotion ? nil : Tokens.ease(0.32), value: model.runs.isDrawerPresented)
        .ignoresSafeArea()
    }

    @ViewBuilder private var content: some View {
        switch model.setup {
        case .locating:
            SetupStateView(title: "正在查找 mo…", detail: nil, retry: nil)
        case .failed(let message):
            SetupStateView(title: "找不到可用的 mo", detail: message) {
                Task { await model.bootstrap() }
            }
        case .ready:
            ModuleHost(module: model.selection)
        }
    }

    @ViewBuilder private var drawer: some View {
        if model.runs.isDrawerPresented, let installation = model.installation {
            ExecutionDrawer(runs: model.runs, installation: installation)
                .padding(Tokens.Size.gutter)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}
```

把 `app/Sources/MoleUI/Shell/PlaceholderModule.swift` 整体替换为：

```swift
import SwiftUI

/// Stand-in for modules that later milestones wire up. Modules with a dry-run
/// preview can already run it in the execution drawer.
struct PlaceholderModule: View {
    @Environment(AppModel.self) private var model
    let module: Module

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: module.title, context: "规划中 · \(module.milestone)") {
                if let arguments = module.previewArguments {
                    Button {
                        model.run(arguments, title: "\(module.title) 预览", mutatesSystem: false)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "eye").font(.system(size: 11))
                            Text("预览")
                        }
                    }
                    .buttonStyle(MoleButtonStyle())
                    .disabled(model.runs.isRunning)
                    .help("mo " + arguments.joined(separator: " "))
                }
            }
            VStack(spacing: 5) {
                Text("\(module.title) 在 \(module.milestone) 接入")
                    .font(.ui(11.5, weight: .semibold))
                    .foregroundStyle(Tokens.ink)
                if let arguments = module.previewArguments {
                    Text("预览会在右侧抽屉里运行 mo \(arguments.joined(separator: " "))")
                        .font(.mono(10))
                        .foregroundStyle(Tokens.muted)
                } else {
                    Text("⌘K 打开命令面板").font(.mono(10)).foregroundStyle(Tokens.muted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
```

把 `app/Sources/MoleUI/Shell/Sidebar.swift` 里的 `SidebarFooter` 整个替换为：

```swift
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
```

- [ ] **Step 4: 编译**

Run: `cd app && swift build`
Expected: `Build complete!`。

- [ ] **Step 5: 手动验收（只运行 dry-run 命令）**

Run: `cd app && make run`
Expected（逐条核对）：
1. 切到 Optimize，点「预览」：抽屉从右侧滑入，抽屉头为 `$ mo optimize --dry-run`，状态标签「运行中 · 00:0x」每秒递增；终端里是 mo 的彩色输出，红色可读（偏浅朱红）。
2. 运行中关闭按钮为灰色不可点；侧边栏底部出现墨色圆环加 `mo optimize --dry-run`；其他模块的「预览」按钮置灰。
3. 若 mo 要求输入 sudo 密码或确认，在终端里直接输入可以正常交互。
4. 命令结束后状态标签变为「退出 0 · 00:xx」（非零时为朱红底），侧边栏圆环变为灰点；点关闭按钮（或按 Esc）抽屉滑出。若 Esc 被终端吞掉，记录下来，✕ 按钮仍可用。
5. 点侧边栏底部的命令行，抽屉重新打开并显示上次的输出。
6. 再运行 Clean 的「预览」：抽屉里是全新的终端，没有上一条命令的输出。
7. 点复制按钮，图标变成对勾；在终端粘贴得到 `mo clean --dry-run`。
8. 运行中退出应用（⌘Q），再运行 `pgrep -fl "mole clean"; echo "exit=$?"`，输出 `exit=1`。

- [ ] **Step 6: Commit**

```bash
git add app/Sources/MoleUI
git commit -m "feat(app): run mo commands in a SwiftTerm execution drawer"
```

---

### Task 12: 命令面板、快捷键与轻提示

**Files:**
- Create: `app/Sources/MoleKit/Commands/PaletteSearch.swift`
- Test: `app/Tests/MoleKitTests/PaletteSearchTests.swift`
- Create: `app/Sources/MoleUI/Palette/CommandPalette.swift`
- Create: `app/Sources/MoleUI/Shell/Toast.swift`
- Create: `app/Sources/MoleUI/App/MoleCommands.swift`
- Modify: `app/Sources/MoleUI/Shell/AppModel.swift`（整体替换）
- Modify: `app/Sources/MoleUI/Shell/RootView.swift`（替换 `RootView`）
- Modify: `app/Sources/MoleUI/App/MoleUIApp.swift`（加 `.commands`）

**Interfaces:**
- Consumes: `Module`（`title group shortcutDigit previewArguments`）、`AppModel.run`、`CommandRunCoordinator.recent / current`
- Produces:
  - `public struct PaletteEntry: Sendable, Equatable, Identifiable`：`id group title meta keywords`，`init(id:group:title:meta:keywords: [String] = [])`。
  - `public enum PaletteSearch { static func filter(_ entries: [PaletteEntry], query: String) -> [PaletteEntry] }`：忽略大小写；整串前缀 3 分 > 词首前缀 2 分 > 包含 1 分 > 子序列 0 分；在 title、meta、keywords 中取最高分；同分保持原顺序；空查询原样返回。
  - `AppModel`：`isPaletteOpen: Bool`、`toast: String?`、`showToast(_:)`、`paletteEntries: [PaletteEntry]`（分组「前往 / 操作 / 最近」）、`performPaletteEntry(_ id: String)`。
  - 菜单命令：「前往」菜单内 9 个模块 ⌘1–⌘9，「命令面板」⌘K。

- [ ] **Step 1: 写失败的测试**

`app/Tests/MoleKitTests/PaletteSearchTests.swift`：

```swift
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

    @Test func emptyQueryKeepsEveryEntryInOrder() {
        #expect(PaletteSearch.filter(entries, query: "  ").map(\.id) == entries.map(\.id))
    }

    @Test func ranksPrefixThenWordStartThenContainsThenSubsequence() {
        #expect(PaletteSearch.filter(entries, query: "cl").map(\.id) == ["clean", "preview", "disk", "uncle", "calendar"])
    }

    @Test func matchesMetaAndIgnoresCase() {
        #expect(PaletteSearch.filter(entries, query: "DRY").map(\.id) == ["preview"])
        #expect(PaletteSearch.filter(entries, query: "zzz").isEmpty)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd app && swift test --filter PaletteSearchTests`
Expected: 编译失败，`cannot find 'PaletteEntry' in scope`。

- [ ] **Step 3: 写实现**

`app/Sources/MoleKit/Commands/PaletteSearch.swift`：

```swift
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
```

核对 `ranksPrefixThenWordStart…` 的期望：`Clean`（前缀 3）、`Clean 预览`（前缀 3，原序在后）、`Disk cleanup`（词首 2）、`Uncle`（包含 1）、`Calendar`（子序列 c…l，0），`Space` 不匹配。

- [ ] **Step 4: 运行测试，确认通过**

Run: `cd app && swift test --filter PaletteSearchTests`
Expected: 3 个测试全部通过。

- [ ] **Step 5: 写面板、提示和菜单命令**

`app/Sources/MoleUI/Palette/CommandPalette.swift`：

```swift
import MoleKit
import SwiftUI

struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var selectedIndex = 0
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
```

`app/Sources/MoleUI/Shell/Toast.swift`：

```swift
import SwiftUI

struct ToastView: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(hex: 0xC4C9BD)).frame(width: 5, height: 5)
            Text(text).font(.ui(11))
        }
        .foregroundStyle(Tokens.paper)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 3).fill(Tokens.ink))
        .shadow(color: Tokens.ink.opacity(0.35), radius: 18, y: 12)
    }
}
```

`app/Sources/MoleUI/App/MoleCommands.swift`：

```swift
import SwiftUI

struct MoleCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("前往") {
            ForEach(Module.allCases) { module in
                Button(module.title) { model.selection = module }
                    .keyboardShortcut(KeyEquivalent(module.shortcutDigit), modifiers: .command)
            }
            Divider()
            Button("命令面板") { model.isPaletteOpen.toggle() }
                .keyboardShortcut("k", modifiers: .command)
        }
    }
}
```

- [ ] **Step 6: 接入模型、根视图和应用入口**

把 `app/Sources/MoleUI/Shell/AppModel.swift` 整体替换为：

```swift
import Foundation
import MoleKit
import Observation

@MainActor
@Observable
final class AppModel {
    enum Setup: Equatable {
        case locating
        case ready(MoleInstallation)
        case failed(String)
    }

    var selection: Module = .dashboard
    var isPaletteOpen = false
    private(set) var toast: String?
    private(set) var setup: Setup = .locating
    private(set) var status: StatusService?
    private(set) var environment: [String: String] = [:]
    let runner = DataRunner()
    let runs = CommandRunCoordinator()
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    var installation: MoleInstallation? {
        if case .ready(let installation) = setup { installation } else { nil }
    }

    /// Finds and verifies mo. Safe to call again after the user edits Settings.
    func bootstrap() async {
        status?.stop()
        status = nil
        setup = .locating
        let env = MoleEnvironment.make(base: ProcessInfo.processInfo.environment)
        environment = env
        do {
            let locator = MoleLocator.fromApp(searchPath: env["PATH"] ?? "")
            let found = try await locator.locate(using: runner, environment: env)
            status = StatusService.live(runner: runner, executable: found.executableURL, environment: env)
            setup = .ready(found)
        } catch {
            setup = .failed(String(describing: error))
        }
    }

    /// Starts a command in the execution drawer. Returns false when mo is not ready,
    /// the spec is refused (for example `--permanent`), or another command is still running.
    @discardableResult
    func run(_ arguments: [String], title: String, mutatesSystem: Bool) -> Bool {
        guard installation != nil,
              let spec = CommandSpec(arguments: arguments, title: title, mutatesSystem: mutatesSystem)
        else { return false }
        guard runs.begin(spec) else {
            showToast("已有命令在运行：\(runs.current?.commandText ?? "")")
            runs.presentDrawer()
            return false
        }
        return true
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: - Command palette

    var paletteEntries: [PaletteEntry] {
        var entries = Module.allCases.map { module in
            PaletteEntry(
                id: "go.\(module.rawValue)",
                group: "前往",
                title: module.title,
                meta: "⌘\(module.shortcutDigit)",
                keywords: [module.group.rawValue]
            )
        }
        entries += Module.allCases.compactMap { module in
            module.previewArguments.map { arguments in
                PaletteEntry(
                    id: "run.\(module.rawValue)",
                    group: "操作",
                    title: "\(module.title) 预览",
                    meta: "mo " + arguments.joined(separator: " "),
                    keywords: ["preview", "dry-run"]
                )
            }
        }
        entries += runs.recent.map { spec in
            PaletteEntry(id: "recent.\(spec.id.uuidString)", group: "最近", title: spec.title, meta: spec.commandText)
        }
        return entries
    }

    func performPaletteEntry(_ id: String) {
        if id.hasPrefix("go."), let module = Module(rawValue: String(id.dropFirst(3))) {
            selection = module
        } else if id.hasPrefix("run."),
                  let module = Module(rawValue: String(id.dropFirst(4))),
                  let arguments = module.previewArguments {
            run(arguments, title: "\(module.title) 预览", mutatesSystem: false)
        } else if id.hasPrefix("recent."),
                  let spec = runs.recent.first(where: { "recent.\($0.id.uuidString)" == id }) {
            run(spec.arguments, title: spec.title, mutatesSystem: spec.mutatesSystem)
        }
    }

    func shutdown() {
        status?.stop()
        runner.terminateAll()
    }
}
```

把 `app/Sources/MoleUI/Shell/RootView.swift` 里的 `RootView` 整个替换为：

```swift
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Tokens.Size.gutter) {
            Sidebar()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tokens.canvas)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Size.radius))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Size.radius).strokeBorder(Tokens.line2))
        }
        .padding(Tokens.Size.gutter)
        .background(Tokens.shell)
        .overlay(alignment: .trailing) { drawer }
        .overlay(alignment: .top) { palette }
        .overlay(alignment: .bottomLeading) { toast }
        .animation(reduceMotion ? nil : Tokens.ease(0.32), value: model.runs.isDrawerPresented)
        .animation(reduceMotion ? nil : Tokens.ease(0.18), value: model.isPaletteOpen)
        .animation(reduceMotion ? nil : Tokens.ease(0.22), value: model.toast)
        .ignoresSafeArea()
    }

    @ViewBuilder private var content: some View {
        switch model.setup {
        case .locating:
            SetupStateView(title: "正在查找 mo…", detail: nil, retry: nil)
        case .failed(let message):
            SetupStateView(title: "找不到可用的 mo", detail: message) {
                Task { await model.bootstrap() }
            }
        case .ready:
            ModuleHost(module: model.selection)
        }
    }

    @ViewBuilder private var drawer: some View {
        if model.runs.isDrawerPresented, let installation = model.installation {
            ExecutionDrawer(runs: model.runs, installation: installation)
                .padding(Tokens.Size.gutter)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    @ViewBuilder private var palette: some View {
        if model.isPaletteOpen {
            ZStack(alignment: .top) {
                Tokens.ink.opacity(0.06)
                    .contentShape(Rectangle())
                    .onTapGesture { model.isPaletteOpen = false }
                CommandPalette()
                    .padding(.top, 108)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.992, anchor: .top)))
        }
    }

    @ViewBuilder private var toast: some View {
        if let text = model.toast {
            ToastView(text: text)
                .padding(.leading, Tokens.Size.sidebarWidth + Tokens.Size.gutter * 3)
                .padding(.bottom, 18)
                .transition(.opacity.combined(with: .offset(y: 8)))
        }
    }
}
```

在 `app/Sources/MoleUI/App/MoleUIApp.swift` 中，`.defaultSize(width: 1280, height: 800)` 之后加一行：

```swift
        .commands { MoleCommands(model: model) }
```

- [ ] **Step 7: 编译并跑全部测试**

Run: `cd app && swift build && swift test`
Expected: `Build complete!`；测试全部通过（此时共 52 个：前 42 个 + CommandSpec 2 + Coordinator 5 + PaletteSearch 3），以测试运行器的汇总行为准。

- [ ] **Step 8: 手动验收**

Run: `cd app && make run`
Expected（逐条核对）：
1. ⌘1–⌘9 依次切换 9 个模块；菜单栏「前往」里能看到这 9 项和「命令面板 ⌘K」。
2. ⌘K 打开面板：距顶部约 108 pt，输入框自动聚焦，分组依次为 前往 / 操作；输入 `opt` 时 Optimize 和 Optimize 预览排在最前；↑↓ 移动选中行（墨底纸字），⏎ 执行，Esc 或点击面板外关闭。
3. 在面板里选「Optimize 预览」：面板关闭、执行抽屉打开并开始运行；结束后再开面板，出现「最近」分组和这条命令。
4. 命令运行中，从另一个模块点「预览」（按钮被禁用时改用 ⌘K 选另一条预览）：左下角出现墨底提示「已有命令在运行：mo …」，约 2.4 秒后消失。
5. 系统设置里打开「减少动态效果」后重开应用：抽屉、面板、提示、模块进入都没有动画。

- [ ] **Step 9: Commit**

```bash
git add app/Sources app/Tests
git commit -m "feat(app): add the command palette, module shortcuts and toasts"
```

---

## M1–M3 验收

全部任务完成后，由执行者运行并记录结果：

1. `cd app && swift test`：以运行器汇总行为准，52 个测试全部通过。
2. `cd app && for i in 1 2 3; do swift test --filter "StatusServiceTests|DataRunnerTests" || exit 1; done`：三次全部通过（这两组涉及异步和子进程）。
3. 在仓库根目录运行 `git status --short`：没有未提交的 `app/` 文件，没有 `app/.build`、`app/build`。
4. 性能：Dashboard 可见时 `top` 采样 MoleUI CPU < 5%，用 Instruments Time Profiler 记录一次主线程占用（设计文档预算 < 2%）；离开 Dashboard 或最小化 2 秒后 `pgrep status-go` 无输出。
5. 冷启动：`make run` 后窗口在 300 ms 内出现（目测或用 Instruments 的 App Launch 模板记录）。
6. 安全：`grep -rn -- "--permanent\|MOLE_TEST_\|MO_NO_OPLOG" app/Sources` 只命中 `CommandSpec.forbiddenArguments` 和 `MoleEnvironment` 的剥离列表。

## 后续计划（不在本计划内）

M3 完成后按设计文档第 11 节各写一份计划：M4（Apps：`uninstall --list`、预览与卸载、Slim；History：`history --json` 时间线与 `completedRuns` 刷新）、M5（Clean：dry-run 加 `clean-list.txt` 解析、原生预览、白名单编辑、Installer）、M6（Space：`analyze --json`、树图、下钻、LRU 缓存、目标卷切换）、M7（Projects 与 Optimize 的原生预览和配置文件编辑）。
