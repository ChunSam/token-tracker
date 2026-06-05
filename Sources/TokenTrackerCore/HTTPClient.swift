import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct HTTPClient {
    func getJSON(url: URL, headers: [String: String], timeout: TimeInterval = 5, serviceName: String? = nil) async throws -> Any {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw UsageError.timedOut(service: serviceName)
        } catch {
            throw UsageError.network(message: error.localizedDescription, service: serviceName)
        }

        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw UsageError.httpStatus(code: statusCode, service: serviceName)
        }
        return try JSONSerialization.jsonObject(with: data)
    }
}

public enum UsageError: Error, LocalizedError, Equatable {
    case missingCredentials
    case invalidResponse
    case httpStatus(code: Int, service: String?)
    case timedOut(service: String?)
    case network(message: String, service: String?)

    var isAuthenticationFailure: Bool {
        switch self {
        case .httpStatus(let code, _):
            return code == 401 || code == 403
        case .missingCredentials, .invalidResponse, .timedOut, .network:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Missing credentials"
        case .invalidResponse:
            return "Invalid response"
        case .httpStatus(let code, let service):
            if let service {
                return "HTTP \(code) from \(service)"
            }
            return "HTTP \(code)"
        case .timedOut(let service):
            if let service {
                return "Timed out contacting \(service)"
            }
            return "Timed out"
        case .network(let message, let service):
            if let service {
                return "Network error from \(service): \(message)"
            }
            return message
        }
    }
}
