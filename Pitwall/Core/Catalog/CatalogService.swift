import Foundation

/// Reads the public F1 TV catalog (menu, pages) and maps it to app models.
struct CatalogService: Sendable {
    var endpoints: F1Endpoints
    var client: HTTPClient = .shared

    func menu() async throws -> [PageRef] {
        let data = try await client.data(endpoints.menu(), retryTransient: true)
        let payload = try HTTPClient.envelope(WirePayload.self, from: data)
        let entries = CatalogMapper.menu(payload)
        guard !entries.isEmpty else { throw APIError.decoding }
        return entries
    }

    func page(_ ref: PageRef) async throws -> CatalogPage {
        let data = try await client.data(try endpoints.page(ref.uri), retryTransient: true)
        let payload = try HTTPClient.envelope(WirePayload.self, from: data)
        return CatalogPage(sections: CatalogMapper.sections(payload))
    }
}

enum CatalogMapper {
    static func menu(_ payload: WirePayload) -> [PageRef] {
        (payload.containers?.values ?? []).compactMap { node in
            guard let metadata = node.metadata,
                  metadata.type != "search",
                  metadata.featureIdentifier != "my_list",
                  let label = metadata.label, !label.isEmpty,
                  let action = node.actions?.values.first(where: { $0.key == "onClick" && $0.targetType == "PAGE" }),
                  let uri = action.uri, !uri.isEmpty else { return nil }
            let href = action.href ?? ""
            guard !href.contains("/search"), !href.contains("/my-list") else { return nil }
            return PageRef(uri: uri, title: label)
        }
    }

    static func item(_ node: WireNode, fallbackID: String) -> CatalogItem {
        let m = node.metadata
        var item = CatalogItem(id: fallbackID)
        switch (m?.contentType ?? m?.objectType ?? "").uppercased() {
        case "VIDEO": item.kind = .video
        case "LAUNCHER": item.kind = .launcher
        case "BUNDLE": item.kind = .bundle
        default: item.kind = .unknown
        }
        item.title = m?.title ?? m?.label ?? ""
        item.subtitle = [m?.titleBrief, m?.label].compactMap { $0 }.first { !$0.isEmpty && $0 != item.title }
        item.summary = m?.longDescription
        item.pictureID = m?.pictureUrl ?? node.platformVariants?.values.first?.pictureUrl
        item.contentSubtype = m?.contentSubtype
        item.duration = m?.uiDuration
        item.locked = m?.locked ?? false
        item.resumeSeconds = node.user?.resume?.playHeadPosition

        if let race = m?.emfAttributes {
            item.race = RaceInfo(
                videoType: race.videoType,
                meetingKey: race.meetingKey?.value,
                meetingName: race.globalMeetingName,
                officialName: race.meetingOfficialName,
                countryName: race.meetingCountryName,
                countryKey: race.meetingCountryKey,
                displayDate: race.meetingDisplayDate,
                round: race.round?.value,
                series: race.series ?? node.properties?.values.first?.series,
                start: race.sessionStartDate?.date,
                end: race.sessionEndDate?.date
            )
        }

        let rawID = m?.contentId?.value ?? node.contentId?.value
        if let rawID, let number = Int64(rawID), number > 0 { item.contentID = String(number) }

        if item.kind == .video, let contentID = item.contentID {
            item.action = .play(PlayTarget(contentID: contentID, channelURI: m?.additionalStreams?.values.first?.playbackUrl))
            item.id = "video:\(contentID)"
        } else if let action = node.actions?.values.first(where: { $0.key == "onClick" && !($0.uri ?? "").isEmpty }), let uri = action.uri {
            item.action = .open(PageRef(uri: uri, title: item.title))
            item.id = "page:\(uri)"
        } else if let id = node.id?.value, id != "0" {
            item.id = "node:\(id)"
        }
        return item
    }

    static func sections(_ payload: WirePayload) -> [CatalogSection] {
        var sections: [CatalogSection] = []
        for (index, node) in (payload.containers?.values ?? []).enumerated() {
            // "Continue watching" and "My list" rows are personal and need a signed-in web session.
            if node.actions?.values.contains(where: { ($0.uri ?? "").contains("/CONTENT/WATCHING/") || ($0.uri ?? "").contains("/USERSELECTIONS/") }) == true { continue }

            let layout = (node.layout ?? "").lowercased()
            let sectionID = node.id?.value ?? "section-\(index)"
            let rawItems = node.retrieveItems?.resultObj?.containers?.values ?? []
            let items = rawItems.enumerated()
                .map { item($0.element, fallbackID: "\(sectionID)-\($0.offset)") }
                .filter { $0.kind != .video || $0.contentID != nil }
            var section = CatalogSection(id: sectionID, title: node.metadata?.label ?? "", style: .landscape, items: items)
            section.pictureID = node.metadata?.pictureUrl

            if let action = node.actions?.values.first(where: { $0.key == "onTitleClick" }), let uri = action.uri, !uri.isEmpty {
                section.viewAll = PageRef(uri: uri, title: section.title)
            }

            switch layout {
            case "hero":
                section.style = .hero; section.title = ""
            case "gp_banner":
                section.style = .banner; section.title = ""
            case "__page_header":
                section.style = .header
                section.items = [item(node, fallbackID: sectionID)]
                section.viewAll = nil
            case "title", "subtitle":
                guard !section.title.isEmpty else { continue }
                section.style = .heading
                section.viewAll = nil
            case "interactive_schedule":
                section.style = .schedule
                section.viewAll = nil
                section.schedule = rawItems.enumerated().compactMap { offset, group in
                    let events = (group.events?.values ?? []).enumerated().map { item($0.element, fallbackID: "\(sectionID)-\(offset)-\($0.offset)") }
                    guard !events.isEmpty else { return nil }
                    let name = group.eventName ?? group.metadata?.label ?? ""
                    return ScheduleGroup(id: "\(sectionID)-\(offset)", name: group.eventShortName ?? name, events: events)
                }
                guard !section.schedule.isEmpty else { continue }
            case "content_item":
                // Single content items are merged into one row.
                let single = item(node, fallbackID: sectionID)
                if let last = sections.indices.last, sections[last].id.hasPrefix("merged-") {
                    sections[last].items.append(single)
                } else {
                    sections.append(CatalogSection(id: "merged-\(sectionID)", title: "", style: .landscape, items: [single]))
                }
                continue
            default:
                section.style = layout.hasPrefix("vertical") ? .portrait : .landscape
            }

            if [.hero, .banner, .landscape, .portrait].contains(section.style), section.items.isEmpty { continue }
            sections.append(section)
        }
        return sections
    }
}
