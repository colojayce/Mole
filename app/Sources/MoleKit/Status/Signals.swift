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
