# Mole 原生 macOS 前端（MoleUI）设计

- 日期：2026-11-12
- 状态：执行层定为混合方案 C，视觉定为 Vesper 方向，待评审
- 用途：仅自用，不发布、不商业化
- 位置：本仓库 `app/` 目录

## 1. 目标与非目标

### 目标

- 原生 Swift/SwiftUI 的 Mac 应用，所有底层能力都调用 `mo` 命令行，GUI 不自行实现清理、卸载或删除逻辑。
- 信息组织参考 Mole Mac；视觉沿用 Oil UI「Vesper · 账目总控」的思路（见第 5 节）：墨色写在冷纸上，朱红只留给真正需要处理的事。极客感来自等宽数字、高密度表格、命令面板和执行终端，而不是深色背景。
- 性能优先：空闲时零后台开销，实时页面主线程刷新不超过 1 Hz，长扫描可随时取消。

### 非目标（MVP 不做）

- 不修改 Mole 的 shell 和 Go 代码（除非后续迭代单独立项）。
- 不在 GUI 内直接删除或移动任何文件，删除只发生在 `mo` 子进程里。
- 不做后台常驻、通知、定时任务或菜单栏（菜单栏放到后续迭代评估）。
- 不追求与 Mole Mac 功能对齐。

## 2. 关键约束：mo 的输出能力

| 命令 | 输出 | GUI 策略 |
|---|---|---|
| `mo status --watch --interval 1s` | NDJSON，每行一个完整快照（`MetricsSnapshot`，见 `cmd/status/metrics.go`） | 原生渲染 |
| `mo status --json` | 单次 JSON | 冷启动首帧可选 |
| `mo analyze --json <path>` | `{scan_status, path, entries[], large_files[], total_size, total_files}`（见 `cmd/analyze/json.go`） | 原生渲染 |
| `mo uninstall --list` | JSON 数组：`name, bundle_id, source, uninstall_name, path, size`（size 常为 `--`） | 原生渲染 |
| `mo history --json [--limit N]` | `{logs, limit, sessions[], deletions[]}` | 原生渲染 |
| `mo clean --dry-run` | 终端文本，同时写出 `~/.config/mole/clean-list.txt` | 原生预览（解析清单文件），执行走终端 |
| `optimize` / `purge` / `installer` / `slim` / `uninstall <app>` | 只有终端文本、交互确认、sudo 提示 | 预览和执行都在内嵌终端；能解析的预览逐步原生化 |

`clean-list.txt` 格式：`=== 分区名 ===` 是分区标题，下面每行一条 `<路径>  # <人类可读大小>[附注]` 或 `<路径>  # size unknown`。

前置条件：`cmd/status` 和 `cmd/analyze` 的 Go 二进制需要先编译出来（`make build`），否则 `mo status` / `mo analyze` 会提示 "Bundled ... binary not found"。

## 3. 执行模型（方案 C：混合）

两种执行通道，GUI 里每个操作明确属于其中一种：

1. **数据通道（Data）**：无 TTY 的 `Process`，stdout 走管道，按行切分后在后台解码 JSON/NDJSON。只用于只读命令（status / analyze / `uninstall --list` / history），以及能在无 TTY 下运行的 dry-run。
2. **终端通道（Terminal）**：基于 SwiftTerm 的伪终端（PTY），在右侧滑出的执行抽屉里运行真实的 `mo` 命令。所有会改动系统的命令都走这个通道，sudo 密码、`y/N` 确认、Space 跳过特权清理等交互原样保留，安全语义和直接在终端里运行完全一致。

破坏性操作的统一流程：

```
[原生预览]（dry-run 结果，能解析就原生展示，否则显示终端输出）
     → 用户点击「执行」
     → 执行抽屉从右侧滑出，抽屉头显示完整命令行（例如 $ mo clean），在 PTY 中运行
     → 进程退出后：读取退出码，刷新 History，重新拉取相关模块数据
```

规则：

- GUI 不传 `--permanent`，也不提供传它的入口；默认移到废纸篓的行为保持不变。
- GUI 不设置 `MOLE_TEST_*`、`MO_NO_OPLOG` 等环境变量，子进程继承用户的正常环境（PATH 补上 `/opt/homebrew/bin`、`/usr/local/bin`）。
- 同一时刻只允许一个终端通道命令在运行（Mole 本身有锁和 sudo 会话，并发没有意义），其余执行按钮置灰。

## 4. 功能模块

7 个功能模块，侧边栏共 9 个入口（Installer 和 Slim 是独立入口，见 5.4），按侧边栏顺序对应快捷键 ⌘1–⌘9：Dashboard、Clean、Projects、Installer、Apps、Slim、Space、Optimize、History。

### 4.1 Dashboard（`status --watch`）

- 顶栏：健康分和说明、主机名、型号、macOS 版本、运行时长。
- 卡片：CPU（总占用、负载、每核热力条，区分 P/E 核）、GPU、内存（已用、内存压力、swap、缓存）、磁盘（每个卷的用量，加 IO 读写走势）、网络（每块网卡的上下行走势、代理状态）、电池、温度和传感器、废纸篓大小。
- 进程表：`top_processes`，列为 PID / 名称 / CPU% / 内存。mo 只返回 CPU 占用最高的 5 个进程（2026-11-12 实测），所以表格下方的页签改为 进程 · 磁盘 · 网络 · 电源，分别展示 `top_processes` 加僵尸进程和进程告警、`disks` 加 `disk_io`、`network` 加 `proxy`、`batteries` 加 `thermal`。
- 实测的数据特点（解码和展示都要处理）：
  - 第一帧是「快速帧」，`top_processes`、`batteries`、`gpu`、`sensors` 等数组为 `null`，硬件字段为空字符串；紧接着出完整帧，之后约 6 s 才开始按 1.1 s 左右的间隔出帧。
  - GPU `usage` 为 −1 表示未知；温度和风扇为 0 表示没有读数，显示「—」。
  - `network_history` 自带上下行历史数组，可以直接填充网络走势图的初始值。
- 只读，不提供结束进程等操作（不属于 Mole 的范围）。

### 4.2 Clean（`clean`、`installer`）

- 「扫描」：用终端通道在后台（抽屉收起）运行 `mo clean --dry-run`，完成后解析 `clean-list.txt`。
- 预览视图：按分区折叠，每个分区显示条目数和合计大小，条目列出路径、大小、附注；支持搜索，右键「在 Finder 中显示」。
- 「执行」：在终端通道运行 `mo clean`。
- 白名单：直接编辑 `~/.config/mole/whitelist`（纯文本编辑器加保存），不新增 mo 参数。
- Installer（侧边栏独立入口）：预览和执行都用终端通道运行 `mo installer --dry-run` / `mo installer`。

说明：预览是执行前那一刻的快照，实际执行由 mo 重新扫描，结果以终端输出为准。界面上要注明这一点，不让用户误以为「只会删列表里的东西」。

### 4.3 Apps（`uninstall`、`slim`）

- 列表：`mo uninstall --list` 结果，可搜索、可多选，按来源分组。大小不在列表加载时计算。
- 「预览卸载」：终端通道运行 `mo uninstall --dry-run <uninstall_name...>`。
- 「卸载」：终端通道运行 `mo uninstall <uninstall_name...>`，由 mo 负责确认和数据选择（`--with-data` 作为一个勾选项传入）。
- 参数用 `Process.arguments` 数组逐个传递，不拼接 shell 字符串（App 名可能带空格或中文，例如「腾讯会议」）。
- Slim（侧边栏独立入口）：`mo slim --dry-run` 预览，`mo slim` 执行，都走终端通道。

### 4.4 Space（`analyze --json`）

- 入口：根目录概览（`mo analyze --json` 不带路径）和外接卷入口（`/Volumes`）。
- 双视图：左边树图（treemap），右边可排序列表，二者联动选中；列表列为名称 / 大小 / 占比 / 最近访问时间 / 可清理标记。
- 下钻：双击进入子目录，就是对子路径再跑一次 `mo analyze --json <path>`；面包屑导航，⌫ 返回上级。
- 大文件面板：`large_files`。
- MVP 只读：提供「在 Finder 中显示」和复制路径，不提供删除（要删除，需要先给 mo 补一个能写操作日志的入口，放到后续迭代）。

### 4.5 Projects（`purge`）

- 显示 `~/.config/mole/purge_paths` 里的扫描目录，支持编辑这个文件。
- 预览：终端通道运行 `mo purge --dry-run`；执行：`mo purge`（交互式选择留在终端里完成）。

### 4.6 Optimize（`optimize`）

- 预览：终端通道运行 `mo optimize --dry-run`；执行：`mo optimize`。
- 白名单：直接编辑 `~/.config/mole/whitelist_optimize`（路径见 `lib/manage/whitelist.sh` 中的 `WHITELIST_CONFIG_OPTIMIZE`）。

### 4.7 History（`history --json`）

- 会话时间线：命令、开始时间、条目数、大小，以及动作分布（removed / trashed / skipped / failed / rebuilt）。
- 删除明细表，可按命令和时间筛选。
- 每次终端通道命令结束后自动刷新。

### 后续迭代（不在 MVP）

Touch ID（`touchid`）、`update` 和版本检查、外接卷清理（`clean --external`）、Space 内删除、菜单栏迷你状态、`completion` / `remove`、把 optimize / purge 等的 dry-run 解析成原生预览，以及按需给个别命令加 JSON 输出。

## 5. 视觉与布局（Vesper 方向）

参考：Oil UI 案例「Vesper · 账目总控」（`ui.oiloil.org/works/vesper-ledger/`），API 计费后台，样式表开头写着 *Ink on cool paper; vermilion is reserved for money that is actually stuck.* 这里只借它的设计思路、版式骨架和色彩纪律，不搬它的品牌标识和文案。

### 5.1 北极星

**墨色写在冷纸上，朱红只留给真正需要你处理的事。**

- 界面主体只有墨色加几层冷灰纸色，状态主要靠字形和图形区分，不靠颜色。
- 朱红（signal）只出现在这些地方：磁盘使用率 ≥ 90%、内存压力 critical、进程告警、僵尸进程、History 里的 failed、终端命令非零退出、会改动系统的执行按钮旁那个 5 pt 的风险点。「可清理」「可卸载」是常态，不用朱红。
- 极客感来自：所有数字用 SF Mono 等宽表格数字、高密度表格、⌘K 命令面板、每个操作都显示出它对应的那条 `mo` 命令、表格底栏的快捷键提示、执行抽屉里真实的终端。

### 5.2 色彩 Token（取自 Vesper 原值）

| Token | 色值 | 用途 |
|---|---|---|
| `shell` | `#E6E7E0` | 窗口底色、侧边栏背景 |
| `canvas` | `#F7F8F3` | 主内容卡片、表头、底栏 |
| `paper` | `#FCFCF8` | 顶栏、摘要带、表格行、抽屉 |
| `ink` | `#161916` | 主文字、选中态、主按钮、终端背景 |
| `ink2` | `#3F453A` | 次级文字 |
| `muted` | `#5E6458` | 标签、辅助说明 |
| `faint` | `#62685C` | 分组标题、快捷键提示 |
| `line` / `line2` | `#D8DBD0` / `#BFC4B6` | 分隔线 / 控件描边 |
| `signal` / `signalInk` | `#B33B1B` / `#8A2C16` | 风险数值 / 风险文字 |
| `signalWash` / `signalLine` | `#FBF0EA` / `#E7C3B4` | 告警条底色 / 描边 |

- MVP 只做浅色，固定 `.preferredColorScheme(.light)`；全部颜色集中在 `Theme/Tokens.swift`，以后加深色版只改这一处。
- 终端是界面上唯一的深色面：`ink` 底、`paper` 字，ANSI 色映射到一套低饱和配色，红色映射到 `signal`。

### 5.3 字体与尺寸

- 正文：SF Pro（系统字体），基准 13 pt。数字、路径、PID、命令、大小、时间一律用 SF Mono 加 `.monospacedDigit()`。
- 层级：页面标题 19 pt semibold，字距 −0.02em；摘要大数字 39 pt medium，字距 −0.055em，单位缩小并用 `muted` 色（如 `18.2` + `GB`）；指标值 18 pt；行内主文字 13 pt semibold；辅助文字 10.5 pt。
- 分组标签：全大写、字距约 0.09em、`muted` 色，例如 `RECLAIMABLE`、`MEMORY`。
- 原生适配：Vesper 网页里 8.5–9.5 px 的小字在 macOS 上统一提到 10 pt，保证可读。

### 5.4 窗口骨架

```
┌ shell #E6E7E0 ─────────────────────────────────────────────────────────────┐
│ ● ● ●                 ┌ canvas，圆角 7，描边 line2 ─────────────────────────┐ │
│ ◐ MOLE                │ 顶栏 56pt：标题 · 上下文标签 · ● 实时   [⌘K 搜索] [次要] [■ 主操作 ·] │
│ ┌ Macintosh HD   ▾ ┐  ├──────────────────────────────┬──────────────────────┤ │
│ │ 已用 412 / 494 GB │  │ 摘要带 224pt                  │ 指标 1               │ │
│ └──────────────────┘  │ 标签 + 大数字 + 走势图        ├──────────────────────┤ │
│ MONITOR               │                              │ 指标 2               │ │
│ ▣ Dashboard     92    │ (左 1.52 : 右 1)              ├──────────────────────┤ │
│ RECLAIM               │                              │ 指标 3               │ │
│ ▢ Clean      18.2G    ├──────────────────────────────┴──────────────────────┤ │
│ ▢ Projects    6.4G    │ 页签栏 48pt：分类 计数 ─── [搜索] [筛选]              │ │
│ ▢ Installer    3      │ 筛选条：key: value ×                                │ │
│ APPS                  │ 表头 32pt  全大写小字                                │ │
│ ▢ Apps         142    │ 行 48pt  ……                                         │ │
│ ▢ Slim          11    │                                                     │ │
│ DISK                  │                                                     │ │
│ ▢ Space               │ 底栏 30pt：排序说明 · ↑↓ 选择 · ⏎ 详情 · ⌘K       │ │
│ CARE                  └─────────────────────────────────────────────────────┘ │
│ ▢ Optimize                                                                     │
│ ▢ History      ◆2                                                              │
│ ─────────────────                                                              │
│ LAST RUN  ●                                                                    │
│ 今天 14:02 · 释放 3.1 GB                                                        │
│ mo 1.71.0      sudo: 未缓存                                                     │
└────────────────────────────────────────────────────────────────────────────────┘
```

- 窗口：`.windowStyle(.hiddenTitleBar)`，内容区铺满，交通灯落在侧边栏上；外层 8 pt 间距，侧边栏宽 224 pt（窗口宽 < 1240 pt 时收为 204 pt）。
- 侧边栏：Mole 自己的标识加字距 0.2em 的 `MOLE` 字标；Vesper 的「工作区切换器」在这里对应**目标卷切换器**（启动盘或 `/Volumes` 下的外接卷，显示已用和总容量），它决定 Space 和后续外接卷清理的作用范围。导航分组 `MONITOR / RECLAIM / APPS / DISK / CARE`，右侧计数用 mono：Clean 和 Projects 显示上次预览出的可回收量，Apps 显示数量，History 有失败时用朱红显示失败数。选中项是墨底纸字。
- 侧边栏底部：上次运行（来自 history 第一条会话，Dashboard 流在跑时带呼吸点）、`mo` 版本、sudo 会话状态。
- 主内容是一张 canvas 卡片，固定三层：顶栏 → 摘要带 → 页签 + 表格 + 底栏。每个模块都往这个骨架里填内容，不另起版式。
- 主操作按钮是墨底，会改动系统的操作在按钮内带朱红风险点和 mono 数额，例如 `■ 执行清理 · 18.2 GB ·`。

### 5.5 各模块怎么填骨架

| 模块 | 顶栏主操作 | 摘要带左（大数字 + 图） | 摘要带右（3 个指标） | 页签 / 表格 | 右侧抽屉 |
|---|---|---|---|---|---|
| Dashboard | 无（只读） | `CPU` 当前占用 + 120 s 走势，虚线叠 load1 | 内存（进度条 + 压力）/ 启动盘（进度条）/ 网络（上下行小柱） | 页签 进程 · 磁盘 · 网络 · 电源（见 4.1） | 无，只读不开抽屉 |
| Clean | 扫描 / 执行清理 | `RECLAIMABLE` 可回收总量 + 近 30 次清理释放量柱图（来自 history） | 条目数 / 最大分区 / 上次清理 | 页签为分区；行：路径、分区、大小、附注 | 执行抽屉 |
| Apps | 预览卸载 / 卸载（多选时显示个数） | `INSTALLED` 应用数 + 来源分布条 | 已选 / 最近卸载 / Slim 可回收 | 页签 全部 · App · Homebrew；行：名称 + bundle id、路径、来源 | 预览抽屉（dry-run 输出）→ 同一抽屉内执行 |
| Space | 刷新 / 在 Finder 中显示 | 摘要带换成树图，高度增至约 300 pt；左上叠路径面包屑和总大小 | 树图右侧 3 个指标：条目数 / 可清理合计 / 最大项 | 页签 目录 · 大文件；行：名称、大小、占比条、最近访问 | 无 |
| Projects | 扫描 / 执行清理 | `ARTIFACTS` 可回收量 | 项目数 / 扫描目录数 / 最大项目 | 扫描目录列表（可编辑） | 执行抽屉 |
| Optimize | 预览 / 执行 | 上次优化时间 + 动作计数 | removed / rebuilt / skipped | 预览输出或任务列表 | 执行抽屉 |
| History | 无 | `RECLAIMED · 30D` 累计释放 + 每日柱图，失败日打朱红菱形 | 会话数 / 删除条目 / 失败数 | 页签按命令；行：时间、命令、条目数、大小、动作分布 | 会话详情抽屉（对应的 deletions 明细） |

### 5.6 状态字形（借 Vesper 的发票状态语法）

| 字形 | 含义 | 例子 |
|---|---|---|
| 灰色实心小圆点 | 已完成 / 正常 | 已清理的会话、内存压力 normal |
| 墨色空心圆环 | 待处理 / 可操作 | 可清理条目、可卸载 App |
| 朱红圆环加实心芯 | 需要注意 | 磁盘 ≥ 90%、内存压力 warn |
| 朱红菱形 | 失败 / 危险 | failed 动作、非零退出、critical、进程告警 |

### 5.7 抽屉、面板与浮层

- **执行抽屉**：从右侧滑出的浮动卡片，宽 640 pt，四周留 8 pt，圆角 7，带 Vesper 的大阴影。抽屉头 52 pt：左侧是 mono 命令行 `$ mo clean`（可复制），右侧是状态标签（运行中 / 退出 0 / 朱红的「退出 1」）和运行时长；抽屉体就是 SwiftTerm 终端（`ink` 底）。运行中不能关闭，结束后 Esc 关闭。宽 640 pt、SF Mono 11 pt 时约 90 列，够 mo 的输出。
- **详情抽屉**：同一外壳，抽屉体换成原生内容（History 会话明细、Apps 预览摘要）。告警条用 `signalWash` 底、`signalLine` 描边。
- **命令面板（⌘K）**：宽 636 pt，距顶部 108 pt；分组为「前往 / 操作 / 最近命令」；每项右侧是 mono 元信息（例如 `mo clean --dry-run`）和快捷键；选中项墨底纸字。
- **Toast**：左下角，墨底纸字，用于「已复制命令」「预览已更新」这类轻提示。
- **筛选条**：`key: value ×` 小标签，后面跟「清除全部」和 mono 计数。

### 5.8 动效

- 缓动曲线统一用 Vesper 的 `cubic-bezier(.2,.8,.25,1)`，SwiftUI 里写成 `.timingCurve(0.2, 0.8, 0.25, 1)`。
- 模块进入：顶栏、摘要带、表格依次淡入上移 4 pt，各间隔 40 ms，时长 0.4 s。
- 表格行：只在首次加载时逐行淡入，每行间隔 24 ms，总延迟不超过 260 ms；实时刷新的行不做动画。
- 页签下划线滑动 0.24 s；抽屉滑入 0.32 s（位移 18 pt 加淡入）；命令面板 0.18 s（缩放 0.992 → 1）。
- 实时状态点 3.2 s 呼吸一次。
- 系统开启「减少动态效果」时，以上全部关闭。

### 5.9 视觉方案的性能约束

- 不用毛玻璃和 vibrancy（Vesper 本来就是平涂纸色），渲染更省。
- 大阴影只给抽屉、命令面板和弹窗这几个浮层，表格行和卡片只用 1 pt 分隔线。
- 行高固定 48 pt，懒加载列表可以直接按行高定位，不用测量。
- 「行淡入」只在首次加载触发；Dashboard 每秒的刷新只改数字和走势，不触发布局动画。

## 6. 架构

```
app/
├── Package.swift                 # SwiftPM，不引入 .xcodeproj
├── Sources/
│   ├── MoleKit/                  # 纯逻辑层，可单测，不依赖 SwiftUI
│   │   ├── Runner/               # MoleLocator, DataRunner, LineSplitter
│   │   ├── Models/               # StatusSnapshot, AnalyzeResult, AppEntry, HistoryReport, CleanPreview
│   │   ├── Parsers/              # NDJSON 解码, CleanListParser, 人类可读大小解析
│   │   └── Services/             # StatusService, AnalyzeService, AppsService, HistoryService, CleanService
│   └── MoleUI/                   # SwiftUI 应用
│       ├── App/                  # 入口, 窗口, 侧边栏, 命令面板, 快捷键
│       ├── Theme/                # Tokens（色彩、字号、间距、缓动）, 状态字形
│       ├── Shell/                # 侧边栏, 顶栏, 摘要带, 页签表格骨架, 浮动抽屉外壳, Toast
│       ├── Terminal/             # SwiftTerm 封装, ExecutionDrawer, TerminalSession
│       ├── Components/           # Sparkline, MicroBars, Meter, CoreHeatmap, Treemap, MetricRow
│       └── Features/             # Dashboard/ Clean/ Apps/ Space/ Projects/ Optimize/ History/
├── Tests/MoleKitTests/           # 解析器与服务单测，fixtures 来自真实 mo 输出
└── Makefile                      # build / run / bundle（组装 .app 和 Info.plist）
```

- 平台：macOS 15+，Swift 6 严格并发，`@Observable`。
- 依赖：仅 SwiftTerm（SPM）。走势小图和树图自己用 `Canvas` 绘制，不引入图表库。
- 不开沙盒：需要启动 `mo`、读写 `~/.config/mole`、读取 `~/Library/Logs/mole`。
- 工程形态：SwiftPM 可执行目标加 `make bundle` 组装 `.app`，避免 `.xcodeproj` 带来的大段合并冲突，也方便命令行构建。`app/` 下不放 `*.sh`，因为 `scripts/check.sh` 会扫描全仓库的 shell 文件；组装逻辑写在 Makefile 里。

### 6.1 MoleLocator

查找顺序：设置里指定的路径 → 本仓库的 `./mole`（开发模式，路径由设置或构建时注入）→ PATH 中的 `mo`（补上 Homebrew 路径）。启动时运行 `mo --version` 验证，失败时在界面上显示原因和下一步（例如「未找到 mo，请在设置中指定路径」，或「status 二进制缺失，请在仓库运行 make build」）。

### 6.2 DataRunner

- 线程安全的类，子进程登记在加锁的登记表里（不用 actor）：启动后同步登记，`terminateAll()` 不会漏掉刚启动的进程，也省掉每次调用的 actor 跳转。
- `run(args) async throws -> Data`：一次性命令。
- `stream(args) -> AsyncThrowingStream<Data, Error>`：按 `\n` 切行，给 `--watch` 用。
- 每个子进程记下 PID，取消时先发 SIGTERM，500 ms 后仍未退出则 SIGKILL；App 退出时（`applicationWillTerminate`）回收全部子进程。
- stderr 单独收集，进程非零退出时附在错误里显示。

### 6.3 TerminalSession

- 封装 SwiftTerm 的 `LocalProcessTerminalView`，对外暴露 `start(args)`、`state`（idle / running / exited(code)）和 `onExit` 回调。
- 执行抽屉显示完整命令行、运行时长和退出码；运行中不能关闭（见 5.7）。
- 「后台扫描」（例如 Clean 的 dry-run）也走 PTY，但不打开抽屉，进度显示在顶栏的上下文标签位（例如「扫描中 · 00:12」）；需要时点它打开抽屉查看原始输出。

## 7. 数据流

- **Dashboard**：视图出现时 → `StatusService.start()` → 启动 `mo status --watch --interval 1s` → 后台 actor 逐行解码 → 写入环形缓冲（每项指标 120 个点）→ 每秒最多一次合并成一个快照，交给 `@MainActor` 模型。视图消失、窗口最小化或被完全遮挡（`NSWindow.occlusionState`）时 → `stop()` 终止进程，缓冲保留。
- **Space**：路径变化 → 取消在途扫描 → 先查内存 LRU 缓存（键为路径，最多 64 条，可手动刷新）→ 未命中就运行 `mo analyze --json <path>` → 解码 → 计算树图布局（后台）→ 渲染。
- **Apps / History**：首次进入模块时加载；终端通道命令结束后标记为过期，下次可见时重新加载。
- **Clean**：dry-run 结束（退出码 0）→ 读取并解析 `clean-list.txt` → 生成 `CleanPreview`。

## 8. 性能设计

1. 按需启动：App 启动时只做 `mo --version` 验证，其余进程在模块首次可见时才拉起。
2. status 流随可见性启停，后台 CPU 为零；不用 SIGSTOP 暂停，直接终止再重启，逻辑简单，重新出首帧大约 1 s 可以接受。
3. 解码和布局都在后台 actor；主线程只接收合并后的不可变快照。
4. 进程表按 PID 保持稳定 ID，SwiftUI 只做差量更新；行数上限取 mo 返回的数量。
5. 走势小图：固定长度的环形缓冲，用 `Canvas` 一次画出一条 `Path`；每秒最多重绘一次。
6. 树图：用 squarified 算法在后台布局，只画面积 ≥ 4×4 pt 的块，更小的合并成「其他」；悬停命中测试用预先算好的矩形数组。
7. 列表超过约 2,000 行时使用 `Table` / `List`（惰性加载）；如果 SwiftUI `Table` 实测掉帧，就换成 `NSTableView` 封装。
8. 扫描可取消：Space 切换路径、离开 Clean 页面都会终止在途的数据通道进程。
9. 性能预算：冷启动到窗口出现 < 300 ms；Dashboard 稳态主线程占用 < 2%（Instruments 测量）；Space 切换到已缓存的路径 < 50 ms。

## 9. 错误处理

- 每个模块有三种状态：加载中 / 内容 / 错误。错误态显示一行原因和一个具体的下一步（与 Mole 的「拒绝时要说明原因和下一步」原则一致）。
- NDJSON 某一行解码失败：跳过这一行并计数，不中断流；连续 5 行失败才进入错误态。
- 子进程意外退出：Dashboard 自动重启，带退避（1 s、2 s、4 s，最多 30 s）；其他模块显示错误和「重试」按钮。
- 终端通道非零退出：抽屉保持展开，显示退出码；不尝试解析文本来判断成败。
- 字段缺失或新增：模型的可选字段都声明为 `Optional`，解码器容忍未知字段，以应对 mo 升级。

## 10. 测试

- `MoleKitTests`（`swift test`）：
  - NDJSON 切行（跨块的半行、空行、CRLF）。
  - `StatusSnapshot` / `AnalyzeResult` / `AppEntry` / `HistoryReport` 解码，fixtures 取自真实的 `mo ... --json` 输出，存在 `Tests/MoleKitTests/Fixtures/`。
  - `CleanListParser`：分区、`size unknown`、附注、路径含空格或 `#`。
  - 人类可读大小解析（`1.2GB`、`512KB`、`0B`）。
  - DataRunner 的取消和回收：用 `/bin/sleep` 等替身进程验证 SIGTERM / SIGKILL 和不留僵尸进程。
- UI：手动验收清单（每个模块的加载、错误、取消路径），在第一个里程碑的计划里列出。
- 安全验证：开发期间执行类按钮只对 dry-run 命令做真实联调；真实执行由用户本人手动触发。

## 11. 里程碑

1. **M1 骨架**：`app/` 工程、MoleLocator、DataRunner、Theme Token、Shell 骨架（侧边栏、顶栏、摘要带、页签表格、抽屉外壳）和空模块、`make run`。
2. **M2 Dashboard**：status 流、卡片、走势小图、进程表、可见性启停。
3. **M3 终端通道**：执行抽屉（SwiftTerm）、TerminalSession、单命令互斥、退出回调、命令面板。
4. **M4 Apps 与 History**：`uninstall --list`、预览和卸载、history 时间线。
5. **M5 Clean**：dry-run 加清单解析、原生预览、执行、白名单编辑、Installer 入口。
6. **M6 Space**：analyze JSON、树图、下钻、缓存。
7. **M7 Projects 与 Optimize**：终端通道包装、配置文件编辑。

## 12. 与本仓库的关系

- `app/` 是新增目录，不改动现有的 shell / Go 代码和测试。
- 构建产物（`app/.build/`、`app/build/`）加进 `.gitignore`。
- CI：`.github/workflows/*.yml` 的路径过滤包含 `'**'`，所以 `app/` 的改动会触发 Mole 的 CI。如果推送到 GitHub fork，就在各个 workflow 的 `paths` 中加上 `'!app/**'`；只在本地使用则不需要改。
- 同步上游 tw93/Mole 时，`app/` 不会产生冲突；唯一可能冲突的是 `.gitignore` 和 workflow 的路径过滤。
