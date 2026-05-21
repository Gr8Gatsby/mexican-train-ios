import SwiftUI

struct KeypadView: View {
    @Binding var value: String
    @Environment(\.theme) private var theme

    private let maxLength = 3
    private let keys: [String] = ["1","2","3","4","5","6","7","8","9","","0","⌫"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                  spacing: 8) {
            ForEach(keys.indices, id: \.self) { i in
                let k = keys[i]
                if k.isEmpty {
                    Color.clear.frame(height: 56)
                } else {
                    Button { tap(k) } label: {
                        Text(k)
                            .font(theme.displayFont(size: k == "⌫" ? 20 : 24))
                            .foregroundStyle(theme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: theme.buttonCornerRadius)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                    }
                    .accessibilityLabel(k == "⌫" ? "Delete" : k)
                }
            }
        }
    }

    private func tap(_ k: String) {
        if k == "⌫" {
            if !value.isEmpty { value.removeLast() }
        } else if value.count < maxLength {
            value.append(k)
        }
    }
}
