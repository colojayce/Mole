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
