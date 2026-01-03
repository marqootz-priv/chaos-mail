//
//  BackendService.swift
//  chaos-ctrl-mail
//

import Foundation

class BackendService {
    static let shared = BackendService()
    private let baseURL = "https://your-backend-api.com"
    private init() {}
    
    func verifyGoogleToken(idToken: String, accessToken: String, refreshToken: String?) async throws -> BackendAccountResponse {
        let endpoint = "\(baseURL)/auth/google/verify"
        guard let url = URL(string: endpoint) else {
            throw BackendError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = GoogleTokenRequest(idToken: idToken, accessToken: accessToken, refreshToken: refreshToken)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(BackendErrorResponse.self, from: data) {
                throw BackendError.serverError(message: errorResponse.message)
            }
            throw BackendError.httpError(statusCode: httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(BackendAccountResponse.self, from: data)
    }
}

struct GoogleTokenRequest: Codable {
    let idToken: String
    let accessToken: String
    let refreshToken: String?
}

struct BackendAccountResponse: Codable {
    let accountId: String
    let userId: String
    let email: String
    let provider: String
    let isNewAccount: Bool
    let emailConfiguration: EmailConfiguration?
    
    struct EmailConfiguration: Codable {
        let imapServer: String
        let imapPort: Int
        let smtpServer: String
        let smtpPort: Int
        let useSSL: Bool
    }
}

struct BackendErrorResponse: Codable {
    let error: String
    let message: String
    let statusCode: Int?
}

enum BackendError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case serverError(message: String)
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid backend URL"
        case .invalidResponse: return "Invalid response from server"
        case .httpError(let code): return "Server error: HTTP \(code)"
        case .serverError(let msg): return "Server error: \(msg)"
        case .decodingError: return "Could not decode server response"
        }
    }
}
