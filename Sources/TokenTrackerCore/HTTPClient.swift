import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct HTTPClient {
    func getJSON(url: URL, headers: [String: String], timeout: TimeInterval = 5) async throws -> Any {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw UsageError.network("HTTP request failed")
        }
        return try JSONSerialization.jsonObject(with: data)
    }
}

enum UsageError: Error, LocalizedError {
    case missingCredentials
    case invalidResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials: "Missing credentials"
        case .invalidResponse: "Invalid response"
        case .network(let message): message
        }
    }
}
