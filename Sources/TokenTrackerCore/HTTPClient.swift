import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
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
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0
            throw UsageError.httpStatus(
                code: statusCode,
                service: serviceName,
                retryAfter: retryAfterInterval(from: httpResponse?.value(forHTTPHeaderField: "Retry-After"))
            )
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private func retryAfterInterval(from value: String?) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(value) {
            return max(0, seconds)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else {
            return nil
        }
        return max(0, date.timeIntervalSinceNow)
    }
}

public enum UsageError: Error, LocalizedError, Equatable {
    case missingCredentials
    case invalidResponse
    case httpStatus(code: Int, service: String?, retryAfter: TimeInterval?)
    case timedOut(service: String?)
    case network(message: String, service: String?)

    var isAuthenticationFailure: Bool {
        switch self {
        case .httpStatus(let code, _, _):
            return code == 401 || code == 403
        case .missingCredentials, .invalidResponse, .timedOut, .network:
            return false
        }
    }

    var rateLimitRetryAfter: TimeInterval? {
        switch self {
        case .httpStatus(429, _, let retryAfter):
            return retryAfter
        case .missingCredentials, .invalidResponse, .httpStatus, .timedOut, .network:
            return nil
        }
    }

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Missing credentials"
        case .invalidResponse:
            return "Invalid response"
        case .httpStatus(let code, let service, let retryAfter):
            let prefix: String
            if let service {
                prefix = "HTTP \(code) from \(service)"
            } else {
                prefix = "HTTP \(code)"
            }
            if code == 429, let retryAfter {
                return "\(prefix); retrying after \(Self.formatRetryAfter(retryAfter))"
            }
            return prefix
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

    private static func formatRetryAfter(_ retryAfter: TimeInterval) -> String {
        let seconds = max(0, Int(ceil(retryAfter)))
        if seconds < 60 {
            return "\(seconds)s"
        }

        let minutes = Int(ceil(Double(seconds) / 60.0))
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
    }
}
