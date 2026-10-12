import Foundation
import AVFoundation

/// Answers FairPlay key requests for one asset: builds the SPC with F1's
/// certificate and exchanges it for a CKC at the licence server.
final class FairPlayKeyDelegate: NSObject, AVContentKeySessionDelegate {
    typealias LicenseFetcher = @MainActor (_ spc: Data, _ assetID: String) async throws -> Data

    private let certificate: Data
    private let fetchLicense: LicenseFetcher
    let queue = DispatchQueue(label: "nl.lrvdlinden.pitwall.fairplay")

    init(certificate: Data, fetchLicense: @escaping LicenseFetcher) {
        self.certificate = certificate
        self.fetchLicense = fetchLicense
    }

    func contentKeySession(_ session: AVContentKeySession, didProvide keyRequest: AVContentKeyRequest) {
        handle(keyRequest)
    }

    func contentKeySession(_ session: AVContentKeySession, didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest) {
        handle(keyRequest)
    }

    func contentKeySession(_ session: AVContentKeySession, contentKeyRequest keyRequest: AVContentKeyRequest, didFailWithError err: Error) {
        #if DEBUG
        print("FairPlay key request failed: \(err)")
        #endif
    }

    static func assetID(from identifier: Any?) -> String? {
        guard let string = identifier as? String, let url = URL(string: string), let host = url.host, !host.isEmpty else { return nil }
        return host.lowercased().hasPrefix("0x") ? String(host.dropFirst(2)) : host
    }

    private func handle(_ keyRequest: AVContentKeyRequest) {
        guard let assetID = Self.assetID(from: keyRequest.identifier) else {
            keyRequest.processContentKeyResponseError(APIError.invalidPlayback)
            return
        }
        let fetch = fetchLicense
        keyRequest.makeStreamingContentKeyRequestData(
            forApp: certificate,
            contentIdentifier: Data(assetID.utf8),
            options: [AVContentKeyRequestProtocolVersionsKey: [1]]
        ) { spc, error in
            guard let spc else {
                keyRequest.processContentKeyResponseError(error ?? APIError.invalidPlayback)
                return
            }
            Task {
                do {
                    let ckc = try await fetch(spc, assetID)
                    keyRequest.processContentKeyResponse(AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckc))
                } catch {
                    keyRequest.processContentKeyResponseError(error)
                }
            }
        }
    }
}
