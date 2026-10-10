import Foundation

struct APIError: LocalizedError {
    var message: String
    var status: Int?
    var errorDescription: String? {
        message
    }
}

@MainActor struct APIClient {
    var baseURL: String
    func request<T: Decodable>(_ path: String, body: Data? = nil, token: String? = nil) async throws -> T {
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path), ["https", "http"].contains(url.scheme), url.host != nil else { throw APIError(message: "Enter a valid server URL in Connection settings.") }
        var request = URLRequest(url: url); request.timeoutInterval = 30
        if let body { request.httpMethod = "POST"; request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Server unavailable. Your offline records are saved."
            throw APIError(message: message, status: (response as? HTTPURLResponse)?.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
