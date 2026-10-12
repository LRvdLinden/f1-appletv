import Foundation

/// Errors surfaced by the F1 TV backend and the app's own validation.
enum APIError: LocalizedError, Equatable {
    case http(Int)
    case backend(String)
    case decoding
    case notSignedIn
    case invalidPlayback
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .http(401), .http(403):
            return String(localized: "Je F1 TV-sessie is verlopen. Log opnieuw in.")
        case .http(let code):
            return String(localized: "F1 TV gaf een fout (HTTP \(code)).")
        case .backend(let code):
            return String(localized: "F1 TV weigerde het verzoek (\(code)).")
        case .decoding:
            return String(localized: "Het antwoord van F1 TV kon niet worden gelezen.")
        case .notSignedIn:
            return String(localized: "Log in met je F1 TV-account om dit te bekijken.")
        case .invalidPlayback:
            return String(localized: "Deze stream is niet beschikbaar voor je abonnement.")
        case .invalidURL:
            return String(localized: "Ongeldige link.")
        }
    }
}

/// Thin async wrapper around URLSession that maps status codes to `APIError`.
struct HTTPClient: Sendable {
    let session: URLSession

    static let shared: HTTPClient = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.urlCache = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        return HTTPClient(session: URLSession(configuration: configuration))
    }()

    func data(_ request: URLRequest, retryTransient: Bool = false) async throws -> Data {
        do {
            return try await send(request)
        } catch {
            guard retryTransient, Self.isTransient(error) else { throw error }
            try await Task.sleep(nanoseconds: 600_000_000)
            return try await send(request)
        }
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.decoding }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        return data
    }

    static func isTransient(_ error: Error) -> Bool {
        if case APIError.http(let code) = error { return [502, 503, 504].contains(code) }
        let code = (error as NSError).code
        return [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost].contains(code)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch {
            #if DEBUG
            print("Decoding \(T.self) failed: \(error)")
            #endif
            throw APIError.decoding
        }
    }

    /// Decodes the `{ resultCode, resultObj }` envelope used by the F1 TV content API.
    static func envelope<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let envelope = try decode(Envelope<T>.self, from: data)
        guard envelope.resultCode == "OK" else { throw APIError.backend(envelope.resultCode) }
        guard let payload = envelope.resultObj else { throw APIError.decoding }
        return payload
    }
}

struct Envelope<Payload: Decodable>: Decodable {
    let resultCode: String
    let resultObj: Payload?

    private enum CodingKeys: String, CodingKey { case resultCode, resultObj }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resultCode = (try? container.decode(String.self, forKey: .resultCode)) ?? "UNKNOWN"
        resultObj = resultCode == "OK" ? try container.decodeIfPresent(Payload.self, forKey: .resultObj) : nil
    }
}
