import SwiftUI

/// Sheet to open or close feeds, choose a layout and load saved setups.
struct FeedManagerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: MultiviewSession

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Kies tot 9 feeds. De feed met het luidsprekertje heeft geluid; kies een tegel om het geluid te wisselen.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.horizontalPadding)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.landscapeWidth * 0.9), spacing: Theme.cardSpacing)], spacing: Theme.cardSpacing) {
                        ForEach(session.feeds) { feed in
                            FeedTile(feed: feed, isSelected: session.isOpen(feed)) {
                                if session.isOpen(feed) { session.remove(feed.id) } else { session.add(feed) }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.horizontalPadding)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Indeling").font(.title3.bold())
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(MultiviewLayout.allCases) { layout in
                                    Button { session.layout = layout } label: {
                                        Label(layout.displayName, systemImage: layout.symbol)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(session.layout == layout ? Theme.accent : nil)
                                }
                            }
                            #if os(tvOS)
                            .padding(.vertical, 20)
                            #endif
                        }
                    }
                    .padding(.horizontal, Theme.horizontalPadding)

                    if !model.savedSetups.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Opgeslagen setups").font(.title3.bold())
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(model.savedSetups) { setup in
                                        Button {
                                            session.apply(setup)
                                            dismiss()
                                        } label: {
                                            Label("\(setup.name) · \(setup.feedKeys.count)", systemImage: "square.stack.3d.up")
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                #if os(tvOS)
                                .padding(.vertical, 20)
                                #endif
                            }
                        }
                        .padding(.horizontal, Theme.horizontalPadding)
                    }
                }
                .padding(.vertical, 24)
            }
            .navigationTitle("Feeds")
            #if !os(tvOS)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 520)
        #endif
    }
}

#if !os(tvOS)
/// Side panel (iPad/Mac) or bottom list (iPhone) with the session's feeds.
struct FeedPanel: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: MultiviewSession

    var body: some View {
        List {
            Section {
                ForEach(session.feeds) { feed in
                    FeedRow(session: session, feed: feed)
                }
            } header: {
                Text("Feeds")
            } footer: {
                Text("Tik op een feed om te wisselen, of op + om hem naast de andere te zetten.")
            }

            if let focused = session.focused, focused.audioTracks.count > 1 {
                Section("Commentaar") {
                    ForEach(focused.audioTracks) { track in
                        Button {
                            focused.selectAudio(track.id)
                        } label: {
                            HStack {
                                Text(track.name)
                                Spacer()
                                if focused.selectedAudio == track.id { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if session.isMultiview {
                Section("Indeling") {
                    Picker("Indeling", selection: $session.layout) {
                        ForEach(MultiviewLayout.allCases) { layout in
                            Label(layout.displayName, systemImage: layout.symbol).tag(layout)
                        }
                    }
                }
            }

            if !model.savedSetups.isEmpty {
                Section("Opgeslagen setups") {
                    ForEach(model.savedSetups) { setup in
                        Button {
                            session.apply(setup)
                        } label: {
                            Label("\(setup.name) · \(setup.feedKeys.count) feeds", systemImage: "square.stack.3d.up")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #else
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }
}

private struct FeedRow: View {
    @Bindable var session: MultiviewSession
    let feed: Feed

    private var isOpen: Bool { session.isOpen(feed) }
    private var isFocused: Bool { session.focused?.id == feed.id }

    var body: some View {
        HStack(spacing: 10) {
            Button { session.switchTo(feed) } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Theme.color(hex: feed.teamColor) ?? (feed.kind == .main ? Theme.accent : .gray))
                        .frame(width: 3, height: 28)
                    if let number = feed.driverNumber, feed.kind == .onboard {
                        Text("\(number)").font(.callout.monospacedDigit().bold()).frame(width: 28)
                    } else {
                        Image(systemName: feed.symbol).frame(width: 28)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(feed.displayTitle).lineLimit(1)
                        if let team = feed.team, !team.isEmpty {
                            Text(team).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if isOpen {
                        Image(systemName: isFocused ? "speaker.wave.2.fill" : "speaker.slash")
                            .foregroundStyle(isFocused ? Theme.accent : .secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                if isOpen { session.remove(feed.id) } else { session.add(feed) }
            } label: {
                Image(systemName: isOpen ? "minus.circle" : "plus.circle")
                    .foregroundStyle(isOpen ? .secondary : Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(isOpen && session.players.count == 1)
            .help(isOpen ? LocalizedStringKey("Sluit deze feed") : LocalizedStringKey("Voeg toe aan multiview"))
        }
    }
}
#endif
