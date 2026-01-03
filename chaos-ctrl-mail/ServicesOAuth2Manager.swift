//
//  OAuth2Manager.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import Foundation
import AuthenticationServices
import Observation

@Observable
class OAuth2Manager: NSObject {
    var isAuthenticating = false
    var authError: Error?
    
    private var authSession: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<OAuth2Token, Error>?
    
    // MARK: - OAuth2 Configuration
    
    struct OAuth2Config {
        let clientId: String
        let clientSecret: String?
        let authorizationEndpoint: String
        let tokenEndpoint: String
        let redirectURI: String
        let scope: String
        
        static func config(for provider: MailProvider) -> OAuth2Config? {
            switch provider {
            case .gmail:
                return OAuth2Config(
                    clientId: "YOUR_GOOGLE_CLIENT_ID", // Replace with actual client ID
                    clientSecret: "YOUR_GOOGLE_CLIENT_SECRET",
                    authorizationEndpoint: "https://accounts.google.com/o/oauth2/v2/auth",
                    tokenEndpoint: "https://oauth2.googleapis.com/token",
                    redirectURI: "com.chaosctrl.mail:/oauth2redirect",
                    scope: "https://mail.google.com/"
                )
            case .outlook:
                return OAuth2Config(
                    clientId: "YOUR_MICROSOFT_CLIENT_ID",
                    clientSecret: "YOUR_MICROSOFT_CLIENT_SECRET",
                    authorizationEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
                    tokenEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
                    redirectURI: "com.chaosctrl.mail:/oauth2redirect",
                    scope: "https://outlook.office.com/IMAP.AccessAsUser.All https://outlook.office.com/SMTP.Send offline_access"
                )
            case .yahoo:
                // Yahoo OAuth2 configuration
                return OAuth2Config(
                    clientId: "YOUR_YAHOO_CLIENT_ID",
                    clientSecret: "YOUR_YAHOO_CLIENT_SECRET",
                    authorizationEndpoint: "https://api.login.yahoo.com/oauth2/request_auth",
                    tokenEndpoint: "https://api.login.yahoo.com/oauth2/get_token",
                    redirectURI: "com.chaosctrl.mail:/oauth2redirect",
                    scope: "mail-w"
                )
            default:
                return nil
            }
        }
    }
    
    // MARK: - OAuth2 Flow
    
    func authenticate(provider: MailProvider) async throws -> OAuth2Token {
        guard let config = OAuth2Config.config(for: provider) else {
            throw OAuth2Error.unsupportedProvider
        }
        
        isAuthenticating = true
        defer { isAuthenticating = false }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            // Build authorization URL
            let state = UUID().uuidString
            var components = URLComponents(string: config.authorizationEndpoint)!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: config.clientId),
                URLQueryItem(name: "redirect_uri", value: config.redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: config.scope),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent")
            ]
            
            guard let authURL = components.url else {
                continuation.resume(throwing: OAuth2Error.invalidURL)
                return
            }
            
            // Start authentication session
            authSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "com.chaosctrl.mail"
            ) { [weak self] callbackURL, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.continuation?.resume(throwing: error)
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    self.continuation?.resume(throwing: OAuth2Error.noCallbackURL)
                    return
                }
                
                // Extract authorization code
                guard let code = self.extractCode(from: callbackURL) else {
                    self.continuation?.resume(throwing: OAuth2Error.noAuthorizationCode)
                    return
                }
                
                // Exchange code for token
                Task {
                    do {
                        let token = try await self.exchangeCodeForToken(
                            code: code,
                            config: config
                        )
                        self.continuation?.resume(returning: token)
                    } catch {
                        self.continuation?.resume(throwing: error)
                    }
                }
            }
            
            authSession?.presentationContextProvider = self
            authSession?.prefersEphemeralWebBrowserSession = false
            authSession?.start()
        }
    }
    
    private func exchangeCodeForToken(code: String, config: OAuth2Config) async throws -> OAuth2Token {
        var request = URLRequest(url: URL(string: config.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "grant_type", value: "authorization_code")
        ]
        
        if let clientSecret = config.clientSecret {
            components.queryItems?.append(URLQueryItem(name: "client_secret", value: clientSecret))
        }
        
        request.httpBody = components.query?.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuth2Error.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw OAuth2Error.tokenExchangeFailed(statusCode: httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OAuth2Token.self, from: data)
    }
    
    // MARK: - Token Refresh
    
    func refreshToken(_ token: OAuth2Token, config: OAuth2Config) async throws -> OAuth2Token {
        guard let refreshToken = token.refreshToken else {
            throw OAuth2Error.noRefreshToken
        }
        
        var request = URLRequest(url: URL(string: config.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]
        
        if let clientSecret = config.clientSecret {
            components.queryItems?.append(URLQueryItem(name: "client_secret", value: clientSecret))
        }
        
        request.httpBody = components.query?.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OAuth2Error.tokenRefreshFailed
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var newToken = try decoder.decode(OAuth2Token.self, from: data)
        
        // Keep the old refresh token if new one wasn't provided
        if newToken.refreshToken == nil {
            newToken.refreshToken = refreshToken
        }
        
        return newToken
    }
    
    // MARK: - Helper Methods
    
    private func extractCode(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }
        
        return queryItems.first(where: { $0.name == "code" })?.value
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension OAuth2Manager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Get the first window scene
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        
        return windowScene?.windows.first ?? ASPresentationAnchor()
    }
}

// MARK: - OAuth2Token

struct OAuth2Token: Codable {
    let accessToken: String
    var refreshToken: String?
    let expiresIn: Int?
    let tokenType: String
    let scope: String?
    
    var expirationDate: Date? {
        guard let expiresIn = expiresIn else { return nil }
        return Date().addingTimeInterval(TimeInterval(expiresIn))
    }
    
    var isExpired: Bool {
        guard let expirationDate = expirationDate else { return false }
        return Date() >= expirationDate
    }
}

// MARK: - OAuth2Error

enum OAuth2Error: LocalizedError {
    case unsupportedProvider
    case invalidURL
    case noCallbackURL
    case noAuthorizationCode
    case invalidResponse
    case tokenExchangeFailed(statusCode: Int)
    case tokenRefreshFailed
    case noRefreshToken
    
    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "OAuth2 is not supported for this provider"
        case .invalidURL:
            return "Invalid authorization URL"
        case .noCallbackURL:
            return "No callback URL received"
        case .noAuthorizationCode:
            return "No authorization code in callback"
        case .invalidResponse:
            return "Invalid response from server"
        case .tokenExchangeFailed(let statusCode):
            return "Token exchange failed with status code: \(statusCode)"
        case .tokenRefreshFailed:
            return "Failed to refresh access token"
        case .noRefreshToken:
            return "No refresh token available"
        }
    }
}
