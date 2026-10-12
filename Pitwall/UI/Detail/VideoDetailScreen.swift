import SwiftUI

/// Session page: artwork, info, play buttons and the feed picker for multiview.
struct VideoDetailScreen: View {
    @Environment(AppModel.self) private var model
    let item: CatalogItem

    @State private var details: VideoDetails?
    @State private var error: String?
    @State private var selected: [String] = []
    @State private var askStart = false

    private var current: CatalogItem { details?.item ?? item }
    private var contentID: String? {
        if case .play(let target) = item.action { return target.contentID }
        return item.contentID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                actions
                if let error, model.account.isSignedIn {
                    Text(error).foregroundStyle(.secondary)
                }
                if let details, details.feeds.count > 1 {
                    FeedSelectionGrid(feeds: details.feeds, selected: $selected)
                }
            }
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        #if !os(tvOS)
        .navigationTitle(current.title)
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: model.account.isSignedIn) { await load() }
        .confirmationDialog("Waar wil je beginnen?", isPresented: $askStart, titleVisibility: .visible) {
            Button("Live") { start(fromBeginning: false) }
            Button("Vanaf het begin") { start(fromBeginning: true) }
            Button("Annuleren", role: .cancel) {}
        }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                ArtworkImage(pictureID: current.pictureID, width: geo.size.width, height: geo.size.height)
                    .overlay { LinearGradient(colors: [.clear, Theme.background], startPoint: .center, endPoint: .bottom) }
            }
            .frame(height: Theme.heroHeight)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if current.isLive && current.isLiveNow { Badge(text: "LIVE") }
                    if let flag = current.race?.flag { Text(flag) }
                    if let meeting = current.race?.meetingName {
                        Text(meeting.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    }
                    if let round = current.race?.round, round != "0" {
                        Text("· RONDE \(round)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    }
                }
                Text(current.title).font(.largeTitle.bold()).lineLimit(3)
                if let start = current.race?.start {
                    Label(start.sessionTimeText, systemImage: "calendar").foregroundStyle(.secondary)
                }
                if let summary = current.summary, !summary.isEmpty {
                    Text(summary).foregroundStyle(.secondary).frame(maxWidth: 900, alignment: .leading)
                }
            }
            .padding(.horizontal, Theme.horizontalPadding)
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 16) {
            if !model.account.isSignedIn {
                Button { model.showLogin = true } label: {
                    Label("Inloggen om te kijken", systemImage: "person.crop.circle")
                }
                .buttonStyle(.borderedProminent)
            } else if current.isUpcoming && !current.isLiveNow {
                Label("Begint \(current.race?.start?.sessionTimeText ?? "")", systemImage: "clock")
                    .foregroundStyle(.secondary)
            } else {
                Button { primaryAction() } label: {
                    Label(selected.count > 1 ? "Multiview (\(selected.count))" : (current.isLive ? "Kijk live" : "Afspelen"),
                          systemImage: selected.count > 1 ? "rectangle.split.2x2.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)

                if current.isLive {
                    Button { start(fromBeginning: true) } label: {
                        Label("Vanaf begin", systemImage: "backward.end.fill")
                    }
                    .buttonStyle(.bordered)
                } else if let resume = current.resumeSeconds, resume > 30 {
                    Text("Verder vanaf \(Duration.seconds(resume).formatted(.time(pattern: .hourMinuteSecond)))")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if !model.savedSetups.isEmpty, let details {
                    Menu {
                        ForEach(model.savedSetups) { setup in
                            Button(setup.name) {
                                let targets = setup.feedKeys.compactMap { key in details.feeds.first { $0.setupKey == key }?.target }
                                guard let id = contentID, !targets.isEmpty else { return }
                                model.play(PlaybackRequest(contentID: id, title: current.title, feedTargets: targets))
                            }
                        }
                    } label: {
                        Label("Setups", systemImage: "square.stack.3d.up")
                    }
                }
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, Theme.horizontalPadding)
    }

    private func primaryAction() {
        if current.isLive && model.settings.liveStart == .ask { askStart = true; return }
        start(fromBeginning: current.isLive && model.settings.liveStart == .beginning)
    }

    private func start(fromBeginning: Bool) {
        guard let id = contentID else { return }
        var request = PlaybackRequest(contentID: id, title: current.title, fromBeginning: fromBeginning)
        if !selected.isEmpty { request.feedTargets = selected }
        else if case .play(let target) = item.action, let channel = target.channelURI { request.feedTargets = [channel] }
        model.play(request)
    }

    private func load() async {
        guard model.account.isSignedIn, let id = contentID else { return }
        do {
            details = try await model.playback.details(contentID: id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Toggle grid of available feeds (main, F1 Live, data, onboards).
struct FeedSelectionGrid: View {
    let feeds: [Feed]
    @Binding var selected: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Feeds").font(.title3.bold())
                Text("Kies er meerdere voor multiview").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if !selected.isEmpty {
                    Button("Wis selectie") { selected.removeAll() }
                        #if !os(tvOS)
                        .buttonStyle(.plain).foregroundStyle(Theme.accent)
                        #endif
                }
            }
            .padding(.horizontal, Theme.horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.cardSpacing) {
                    ForEach(feeds) { feed in
                        FeedTile(feed: feed, isSelected: selected.contains(feed.target)) {
                            if let index = selected.firstIndex(of: feed.target) { selected.remove(at: index) }
                            else if selected.count < 9 { selected.append(feed.target) }
                        }
                    }
                }
                .padding(.horizontal, Theme.horizontalPadding)
                #if os(tvOS)
                .padding(.vertical, 24)
                #endif
            }
            #if os(tvOS)
            .scrollClipDisabled()
            #endif
        }
    }
}

struct FeedTile: View {
    let feed: Feed
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.color(hex: feed.teamColor) ?? (feed.kind == .main ? Theme.accent : .gray))
                    .frame(width: 4, height: 40)
                if let number = feed.driverNumber, feed.kind == .onboard {
                    Text("\(number)").font(.title3.monospacedDigit().bold()).frame(minWidth: 36)
                } else {
                    Image(systemName: feed.symbol).font(.title3).frame(minWidth: 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(feed.displayTitle).font(.headline).lineLimit(1)
                    if let team = feed.team, !team.isEmpty {
                        Text(team).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isSelected ? Theme.accent : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: Theme.landscapeWidth * 0.9)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .cardButtonStyle()
    }
}
