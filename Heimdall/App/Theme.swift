import SwiftUI

enum Theme {
    static let background = Color(red: 0.047, green: 0.066, blue: 0.07)
    static let panel = Color(red: 0.083, green: 0.105, blue: 0.11)
    static let line = Color.white.opacity(0.09)
    static let accent = Color(red: 0.75, green: 0.86, blue: 0.55)
    static let muted = Color(red: 0.56, green: 0.62, blue: 0.62)
}

extension TacticalLayer {
    var color: Color {
        switch self {
        case .blue: Color(red: 0.36, green: 0.68, blue: 1)
        case .red: Color(red: 1, green: 0.40, blue: 0.43)
        case .tac: Theme.accent
        }
    }
}

struct PanelButton: View {
    let symbol: String
    let label: String
    var active = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(active ? Theme.background : .white)
                .frame(width: 46, height: 46)
                .background(active ? Theme.accent : Theme.panel, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Theme.line))
        }.accessibilityLabel(label)
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.8).foregroundStyle(Theme.muted)
    }
}
