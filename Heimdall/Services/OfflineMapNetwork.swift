import Foundation

/// This policy covers MapLibre's URL session, not other apps or iOS services.
enum OfflineMapNetwork {
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineMapProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return configuration
    }
}

/// Reject remote map requests, including missing-glyph or style fallbacks.
final class OfflineMapProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        ["http", "https"].contains(request.url?.scheme?.lowercased() ?? "")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
