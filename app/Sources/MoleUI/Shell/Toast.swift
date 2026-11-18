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
