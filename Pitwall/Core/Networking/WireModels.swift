import Foundation

// Decodable mirrors of the F1 TV JSON. Everything is optional and lossy: the
// API changes often and one bad item should never break a whole page.

/// Accepts numbers or strings and stores them as a string.
struct FlexibleID: Decodable, Hashable {
    let value: String
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int64.self) { value = String(number) }
        else if let double = try? container.decode(Double.self) { value = String(Int64(double)) }
        else { value = try container.decode(String.self) }
    }
}

/// Milliseconds since 1970, sent as number or string.
struct FlexibleDate: Decodable {
    let date: Date?
    init(from decoder: Decoder) throws {
        let raw = try FlexibleID(from: decoder)
        if let ms = Double(raw.value), ms > 0 { date = Date(timeIntervalSince1970: ms / 1000) } else { date = nil }
    }
}

/// Decodes an array, skipping elements that fail to decode.
struct Lossy<Element: Decodable>: Decodable {
    let values: [Element]
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result = [Element]()
        while !container.isAtEnd {
            // superDecoder() always advances the index, even when the element is malformed.
            let child = try container.superDecoder()
            if let value = try? Element(from: child) { result.append(value) }
        }
        values = result
    }
}

struct WirePayload: Decodable {
    let containers: Lossy<WireNode>?
    let total: Int?
}

struct WireRetrieve: Decodable {
    let resultObj: WirePayload?
}

struct WireAction: Decodable {
    let key: String?
    let uri: String?
    let href: String?
    let targetType: String?
}

struct WireNode: Decodable {
    let id: FlexibleID?
    let contentId: FlexibleID?
    let layout: String?
    let actions: Lossy<WireAction>?
    let metadata: WireMetadata?
    let platformVariants: Lossy<WireVariant>?
    let properties: Lossy<WireProperty>?
    let retrieveItems: WireRetrieve?
    let eventName: String?
    let eventShortName: String?
    let events: Lossy<WireNode>?
    let user: WireUser?
}

struct WireVariant: Decodable { let pictureUrl: String? }
struct WireProperty: Decodable { let series: String? }
struct WireUser: Decodable { let resume: WireResume? }
struct WireResume: Decodable { let playHeadPosition: Double? }

struct WireMetadata: Decodable {
    let title: String?
    let titleBrief: String?
    let label: String?
    let longDescription: String?
    let pictureUrl: String?
    let contentId: FlexibleID?
    let contentType: String?
    let objectType: String?
    let contentSubtype: String?
    let uiDuration: String?
    let duration: Double?
    let locked: Bool?
    let type: String?
    let featureIdentifier: String?
    let emfAttributes: WireRace?
    let additionalStreams: Lossy<WireStream>?

    private enum CodingKeys: String, CodingKey {
        case title, titleBrief, label, longDescription, pictureUrl, contentId, contentType, objectType
        case contentSubtype, uiDuration, duration, locked, type, emfAttributes, additionalStreams
        case featureIdentifier = "feature_indentifier"
    }
}

struct WireRace: Decodable {
    let videoType: String?
    let meetingKey: FlexibleID?
    let meetingCountryKey: String?
    let meetingCountryName: String?
    let globalMeetingName: String?
    let meetingOfficialName: String?
    let meetingDisplayDate: String?
    let round: FlexibleID?
    let series: String?
    let sessionStartDate: FlexibleDate?
    let sessionEndDate: FlexibleDate?

    private enum CodingKeys: String, CodingKey {
        case videoType = "VideoType"
        case meetingKey = "MeetingKey"
        case meetingCountryKey = "MeetingCountryKey"
        case meetingCountryName = "Meeting_Country_Name"
        case globalMeetingName = "Global_Meeting_Name"
        case meetingOfficialName = "Meeting_Official_Name"
        case meetingDisplayDate = "Meeting_Display_Date"
        case round = "Championship_Meeting_Ordinal"
        case series = "Series"
        case sessionStartDate, sessionEndDate
    }
}

struct WireStream: Decodable {
    let racingNumber: FlexibleID?
    let title: String?
    let driverFirstName: String?
    let driverLastName: String?
    let teamName: String?
    let type: String?
    let playbackUrl: String?
    let driverImg: String?
    let teamImg: String?
    let hex: String?
}

struct WireEntitlement: Decodable {
    let entitlementToken: String
    let url: String
    let streamType: String?
    let drmType: String?
    let licenseURL: String?

    private enum CodingKeys: String, CodingKey { case entitlementToken, url, streamType, drmType, laURL, laUrl }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entitlementToken = try c.decode(String.self, forKey: .entitlementToken)
        url = try c.decode(String.self, forKey: .url)
        streamType = try c.decodeIfPresent(String.self, forKey: .streamType)
        drmType = try c.decodeIfPresent(String.self, forKey: .drmType)
        licenseURL = try c.decodeIfPresent(String.self, forKey: .laURL) ?? c.decodeIfPresent(String.self, forKey: .laUrl)
    }
}
