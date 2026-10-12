import SwiftUI

struct SectionView: View {
    let section: CatalogSection

    var body: some View {
        switch section.style {
        case .hero:
            HeroCarousel(items: section.items)
        case .banner:
            if let item = section.items.first { BannerCard(item: item) }
        case .header:
            if let item = section.items.first { PageHeader(item: item) }
        case .heading:
            Text(section.title)
                .font(.title2.bold())
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.top, 8)
        case .schedule:
            ScheduleSection(section: section)
        case .landscape, .portrait:
            ContentRow(section: section)
        }
    }
}

struct RowHeader: View {
    let title: String
    var viewAll: PageRef?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold())
            Spacer()
            if let viewAll {
                NavigationLink(value: viewAll) {
                    Label("Alles", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                }
                #if !os(tvOS)
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                #endif
            }
        }
        .padding(.horizontal, Theme.horizontalPadding)
    }
}

struct ContentRow: View {
    let section: CatalogSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !section.title.isEmpty { RowHeader(title: section.title, viewAll: section.viewAll) }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.cardSpacing) {
                    ForEach(section.items) { item in
                        ContentCard(item: item, portrait: section.style == .portrait)
                    }
                }
                .padding(.horizontal, Theme.horizontalPadding)
                #if os(tvOS)
                .padding(.vertical, 30)
                #endif
            }
            #if os(tvOS)
            .scrollClipDisabled()
            #endif
        }
    }
}

// MARK: - Hero

struct HeroCarousel: View {
    let items: [CatalogItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Theme.cardSpacing) {
                ForEach(items) { item in
                    HeroCard(item: item)
                        .containerRelativeFrame(.horizontal) { width, _ in
                            #if os(tvOS)
                            return width - Theme.horizontalPadding * 2
                            #else
                            return items.count > 1 ? min(width - Theme.horizontalPadding * 2, 1100) : width - Theme.horizontalPadding * 2
                            #endif
                        }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Theme.horizontalPadding)
            #if os(tvOS)
            .padding(.vertical, 30)
            #endif
        }
        .scrollTargetBehavior(.viewAligned)
        #if os(tvOS)
        .scrollClipDisabled()
        #endif
    }
}

struct HeroCard: View {
    let item: CatalogItem
    var height: CGFloat = Theme.heroHeight

    var body: some View {
        ItemLink(item: item) {
            GeometryReader { geo in
                ArtworkImage(pictureID: item.pictureID, width: geo.size.width, height: geo.size.height)
                    .overlay {
                        LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 8) {
                            if item.isLive && item.isLiveNow { Badge(text: "LIVE") }
                            if let flag = item.race?.flag, let meeting = item.race?.meetingName {
                                Text("\(flag) \(meeting)".uppercased())
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            Text(item.title)
                                .font(.title.bold())
                                .lineLimit(2)
                                .foregroundStyle(.white)
                            if let subtitle = item.subtitle {
                                Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                            }
                        }
                        .padding(Theme.horizontalPadding > 40 ? 40 : 20)
                    }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .cardButtonStyle()
    }
}

struct BannerCard: View {
    let item: CatalogItem
    var body: some View {
        HeroCard(item: item, height: Theme.heroHeight * 0.6)
            .padding(.horizontal, Theme.horizontalPadding)
    }
}

struct PageHeader: View {
    let item: CatalogItem
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                ArtworkImage(pictureID: item.pictureID, width: geo.size.width, height: geo.size.height)
                    .overlay { LinearGradient(colors: [.clear, Theme.background], startPoint: .top, endPoint: .bottom) }
            }
            .frame(height: Theme.heroHeight * 0.8)
            VStack(alignment: .leading, spacing: 8) {
                if let flag = item.race?.flag { Text(flag).font(.largeTitle) }
                Text(item.race?.officialName ?? item.title)
                    .font(.largeTitle.bold())
                    .lineLimit(3)
                if let date = item.race?.displayDate { Text(date).foregroundStyle(.secondary) }
                if let summary = item.summary, !summary.isEmpty {
                    Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(4).frame(maxWidth: 900, alignment: .leading)
                }
            }
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Schedule

struct ScheduleSection: View {
    let section: CatalogSection

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RowHeader(title: section.title.isEmpty ? String(localized: "Programma") : section.title)
            ForEach(section.schedule) { group in
                VStack(alignment: .leading, spacing: 10) {
                    if !group.name.isEmpty {
                        Text(group.name.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Theme.horizontalPadding)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: Theme.cardSpacing) {
                            ForEach(group.events) { event in ScheduleTile(item: event) }
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
    }
}

struct ScheduleTile: View {
    let item: CatalogItem

    var body: some View {
        ItemLink(item: item) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if item.isLive && item.isLiveNow { Badge(text: "LIVE") }
                    else if item.isUpcoming { Badge(text: String(localized: "GEPLAND"), color: .gray) }
                    else if item.kind == .video { Badge(text: "REPLAY", color: Color(white: 0.3)) }
                    Spacer()
                    if item.locked { Image(systemName: "lock.fill").font(.caption) }
                }
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let start = item.race?.start {
                    Text(start.sessionTimeText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(width: Theme.landscapeWidth * 0.8, alignment: .leading)
            .frame(minHeight: 110, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .cardButtonStyle()
    }
}
