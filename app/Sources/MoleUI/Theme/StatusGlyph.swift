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
