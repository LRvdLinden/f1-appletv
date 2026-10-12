import SwiftUI

/// Lays out the session's feeds according to the chosen multiview layout.
struct MultiviewGrid: View {
    @Bindable var session: MultiviewSession

    var body: some View {
        GeometryReader { geo in
            let players = orderedPlayers
            let frames = Self.frames(for: session.effectiveLayout, count: players.count, in: geo.size)
            ZStack(alignment: .topLeading) {
                Color.black
                ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                    if index < frames.count {
                        FeedTileView(session: session, player: player)
                            .frame(width: frames[index].width, height: frames[index].height)
                            .offset(x: frames[index].minX, y: frames[index].minY)
                            .zIndex(session.effectiveLayout == .mainPlusOne && index == 1 ? 1 : 0)
                    }
                }
            }
        }
        .background(.black)
    }

    /// In single mode only the focused feed is shown.
    private var orderedPlayers: [FeedPlayer] {
        if session.effectiveLayout == .single, let focused = session.focused { return [focused] }
        return session.players
    }

    static func frames(for layout: MultiviewLayout, count: Int, in size: CGSize) -> [CGRect] {
        let w = size.width, h = size.height
        let gap: CGFloat = 2
        func grid(_ columns: Int, _ rows: Int) -> [CGRect] {
            let cw = (w - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let ch = (h - gap * CGFloat(rows - 1)) / CGFloat(rows)
            return (0..<(columns * rows)).map { i in
                CGRect(x: CGFloat(i % columns) * (cw + gap), y: CGFloat(i / columns) * (ch + gap), width: cw, height: ch)
            }
        }
        switch layout {
        case .auto, .single:
            return [CGRect(origin: .zero, size: size)]
        case .sideBySide:
            let half = (w - gap) / 2
            let tileH = min(h, half * 9 / 16)
            let y = (h - tileH) / 2
            return [CGRect(x: 0, y: y, width: half, height: tileH), CGRect(x: half + gap, y: y, width: half, height: tileH)]
        case .mainPlusOne:
            let insetW = w * 0.3, insetH = insetW * 9 / 16
            return [CGRect(origin: .zero, size: size),
                    CGRect(x: w - insetW - 24, y: h - insetH - 24, width: insetW, height: insetH)]
        case .mainPlusThree:
            let sideW = (w - gap) * 0.28
            let mainW = w - sideW - gap
            let sideH = (h - gap * 2) / 3
            var frames = [CGRect(x: 0, y: 0, width: mainW, height: h)]
            for i in 0..<3 { frames.append(CGRect(x: mainW + gap, y: CGFloat(i) * (sideH + gap), width: sideW, height: sideH)) }
            return frames
        case .grid2x2:
            return grid(2, 2)
        case .grid3x3:
            return grid(3, 3)
        }
    }
}

/// One feed in the grid: video, label, audio indicator and focus/selection handling.
struct FeedTileView: View {
    @Bindable var session: MultiviewSession
    let player: FeedPlayer

    private var isFocused: Bool { session.focused?.id == player.id }

    var body: some View {
        Button { session.focus(player.id) } label: {
            ZStack {
                PlayerLayerView(player: player.player)
                overlay
            }
            .overlay {
                Rectangle().strokeBorder(isFocused && session.isMultiview ? Theme.accent : .clear, lineWidth: 3)
            }
        }
        .buttonStyle(TileButtonStyle())
        .contextMenu {
            Button { session.makeMain(player.id) } label: { Label("Maak hoofdfeed", systemImage: "arrow.up.left.and.arrow.down.right") }
            Button { session.focus(player.id); session.layout = .single } label: { Label("Alleen deze feed", systemImage: "rectangle") }
            if session.players.count > 1 {
                Button(role: .destructive) { session.remove(player.id) } label: { Label("Sluit feed", systemImage: "xmark") }
            }
        }
    }

    @ViewBuilder private var overlay: some View {
        switch player.state {
        case .loading:
            ProgressView().tint(.white)
        case .failed(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.title2)
                Text(message).font(.caption).multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding()
        case .ready:
            EmptyView()
        }
        if session.isMultiview {
            VStack {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.color(hex: player.feed.teamColor) ?? Theme.accent)
                        .frame(width: 3, height: 14)
                    if let number = player.feed.driverNumber, player.feed.kind == .onboard {
                        Text("\(number)").font(.caption.monospacedDigit().bold())
                    }
                    Text(player.feed.displayTitle).font(.caption.weight(.semibold)).lineLimit(1)
                    Image(systemName: player.mutedFlag ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.caption2)
                        .foregroundStyle(player.mutedFlag ? .white.opacity(0.6) : Theme.accent)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.black.opacity(0.6), in: Capsule())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                Spacer()
            }
        }
    }
}

/// tvOS: subtle scale on focus; elsewhere a plain tap target.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TileBody(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct TileBody: View {
        let label: ButtonStyleConfiguration.Label
        let isPressed: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            label
                #if os(tvOS)
                .overlay { Rectangle().strokeBorder(isFocused ? Color.white : Color.clear, lineWidth: 4) }
                #endif
                .opacity(isPressed ? 0.85 : 1)
        }
    }
}
