import SwiftUI

enum Theme {
    static let accent = Color(red: 0.93, green: 0.11, blue: 0.14)
    static let background = Color(red: 0.06, green: 0.06, blue: 0.08)
    static let surface = Color(white: 0.13)
    static let live = Color(red: 0.93, green: 0.11, blue: 0.14)

    #if os(tvOS)
    static let landscapeWidth: CGFloat = 420
    static let portraitWidth: CGFloat = 250
    static let heroHeight: CGFloat = 640
    static let rowSpacing: CGFloat = 48
    static let horizontalPadding: CGFloat = 80
    static let cardSpacing: CGFloat = 40
    #elseif os(macOS)
    static let landscapeWidth: CGFloat = 290
    static let portraitWidth: CGFloat = 170
    static let heroHeight: CGFloat = 420
    static let rowSpacing: CGFloat = 28
    static let horizontalPadding: CGFloat = 28
    static let cardSpacing: CGFloat = 18
    #else
    static let landscapeWidth: CGFloat = 260
    static let portraitWidth: CGFloat = 150
    static let heroHeight: CGFloat = 300
    static let rowSpacing: CGFloat = 26
    static let horizontalPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 14
    #endif

    static func color(hex: String?) -> Color? {
        guard var hex = hex?.trimmingCharacters(in: .whitespaces), !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension View {
    /// Card look: tvOS lift-on-focus, plain elsewhere.
    @ViewBuilder
    func cardButtonStyle() -> some View {
        #if os(tvOS)
        self.buttonStyle(.card)
        #else
        self.buttonStyle(.plain)
        #endif
    }
}

/// Small coloured badge ("LIVE", "4K", …).
struct Badge: View {
    let text: String
    var color: Color = Theme.live
    var body: some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
    }
}

struct LoadingView: View {
    var title: LocalizedStringKey = "Laden…"
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)
            if let retry {
                Button("Opnieuw proberen", action: retry)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Date {
    var sessionTimeText: String {
        formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }
}
