import SwiftUI

/// Remote artwork from the F1 image resizer with a neutral placeholder.
struct ArtworkImage: View {
    let pictureID: String?
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        AsyncImage(url: F1Endpoints.image(pictureID, width: width * 2, height: height * 2)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    LinearGradient(colors: [Theme.surface, Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "flag.checkered")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.15))
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }
}

/// Opens the right destination for an item: a page, a session detail page, or playback.
struct ItemLink<Label: View>: View {
    @Environment(AppModel.self) private var model
    let item: CatalogItem
    @ViewBuilder let label: () -> Label

    var body: some View {
        switch item.action {
        case .open(let ref):
            NavigationLink(value: ref, label: label)
        case .play:
            if item.race?.isSession == true || item.isLive {
                NavigationLink(value: item, label: label)
            } else {
                Button(action: { model.play(item) }, label: label)
            }
        case nil:
            label()
        }
    }
}

struct ContentCard: View {
    let item: CatalogItem
    var portrait = false

    private var width: CGFloat { portrait ? Theme.portraitWidth : Theme.landscapeWidth }
    private var height: CGFloat { portrait ? Theme.portraitWidth * 1.5 : Theme.landscapeWidth * 9 / 16 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ItemLink(item: item) {
                ArtworkImage(pictureID: item.pictureID, width: width, height: height)
                    .overlay(alignment: .topLeading) { badges.padding(8) }
                    .overlay(alignment: .bottomTrailing) {
                        if let duration = item.duration, !duration.isEmpty, !item.isLive {
                            Text(duration)
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                                .padding(8)
                        }
                    }
                    .overlay(alignment: .bottom) { progressBar }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .cardButtonStyle()

            if !portrait {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    if let subtitle = secondaryLine {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(width: width, alignment: .leading)
            }
        }
    }

    private var secondaryLine: String? {
        if let start = item.race?.start, item.isUpcoming { return start.sessionTimeText }
        if let flag = item.race?.flag, let name = item.race?.meetingName { return "\(flag) \(name)" }
        return item.subtitle
    }

    @ViewBuilder private var badges: some View {
        HStack(spacing: 6) {
            if item.isLiveNow && item.isLive { Badge(text: "LIVE") }
            else if item.isUpcoming { Badge(text: String(localized: "BINNENKORT"), color: .black.opacity(0.75)) }
            if item.locked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .padding(5)
                    .background(.black.opacity(0.6), in: Circle())
            }
        }
    }

    @ViewBuilder private var progressBar: some View {
        if let resume = item.resumeSeconds, resume > 0, let total = Self.seconds(item.duration), total > 0 {
            GeometryReader { geo in
                Rectangle().fill(Theme.accent)
                    .frame(width: geo.size.width * min(1, resume / total), height: 4)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    /// Parses "1:23:45" or "45:12" durations.
    static func seconds(_ text: String?) -> Double? {
        guard let parts = text?.split(separator: ":").compactMap({ Double($0) }), !parts.isEmpty else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}
