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
