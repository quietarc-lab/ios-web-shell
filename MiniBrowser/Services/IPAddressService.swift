import Foundation

struct IPAddressService {
    struct Response: Decodable {
        let ip: String
    }

    enum ServiceError: Error {
        case invalidResponse
        case invalidIPv4
    }

    let endpoint: URL
    let timeout: TimeInterval

    init(endpoint: URL = URL(string: "https://api.ipify.org?format=json")!,
         timeout: TimeInterval = 8) {
        self.endpoint = endpoint
        self.timeout = timeout
    }

    func fetchIPv4(userAgent: String? = nil) async throws -> String {
        let request = Self.makeRequest(endpoint: endpoint,
                                       timeout: timeout,
                                       userAgent: userAgent)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw ServiceError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard Self.isIPv4(decoded.ip) else { throw ServiceError.invalidIPv4 }
        return decoded.ip
    }

    static func isIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty,
                  part.allSatisfy(\.isNumber),
                  let number = Int(part),
                  (0...255).contains(number) else { return false }
            return part == "0" || !part.hasPrefix("0")
        }
    }

    static func makeRequest(endpoint: URL,
                            timeout: TimeInterval,
                            userAgent: String?) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = timeout
        if let userAgent, !userAgent.isEmpty {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        return request
    }
}
