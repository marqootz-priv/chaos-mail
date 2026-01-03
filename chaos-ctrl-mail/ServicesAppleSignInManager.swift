//
//  AppleSignInManager.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import Foundation
import AuthenticationServices
import Observation

@Observable
class AppleSignInManager: NSObject {
    var isAuthenticating = false
    var authError: Error?
    var currentUser: AppleUser?
    
    private var continuation: CheckedContinuation<AppleUser, Error>?
    
    // MARK: - Apple User Model
    
    struct AppleUser {
        let userIdentifier: String
        let email: String?
        let fullName: PersonNameComponents?
        let identityToken: String
        let authorizationCode: String
        let realUserStatus: ASUserDetectionStatus
        
        var displayName: String {
            if let fullName = fullName {
                let formatter = PersonNameComponentsFormatter()
                formatter.style = .default
                return formatter.string(from: fullName)
            }
            return email?.components(separatedBy: "@").first ?? "Apple User"
        }
        
        var isHiddenEmail: Bool {
            email?.contains("@privaterelay.appleid.com") ?? false
        }
    }
    
    // MARK: - Sign In
    
    /// Initiates Sign in with Apple flow
    func signIn() async throws -> AppleUser {
        isAuthenticating = true
        authError = nil
        
        defer { isAuthenticating = false }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
    
    // MARK: - Check Credential State
    
    /// Checks if a user is still authenticated with Apple ID
    func checkCredentialState(for userIdentifier: String) async throws -> ASAuthorizationAppleIDProvider.CredentialState {
        let provider = ASAuthorizationAppleIDProvider()
        
        return try await withCheckedThrowingContinuation { continuation in
            provider.getCredentialState(forUserID: userIdentifier) { state, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: state)
                }
            }
        }
    }
    
    // MARK: - Sign Out
    
    func signOut() {
        currentUser = nil
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: AppleSignInError.invalidCredential)
            return
        }
        
        // Extract identity token
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            continuation?.resume(throwing: AppleSignInError.missingIdentityToken)
            return
        }
        
        // Extract authorization code
        guard let authorizationCodeData = credential.authorizationCode,
              let authorizationCode = String(data: authorizationCodeData, encoding: .utf8) else {
            continuation?.resume(throwing: AppleSignInError.missingAuthorizationCode)
            return
        }
        
        // Create user object
        let user = AppleUser(
            userIdentifier: credential.user,
            email: credential.email,
            fullName: credential.fullName,
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            realUserStatus: credential.realUserStatus
        )
        
        currentUser = user
        continuation?.resume(returning: user)
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        authError = error
        
        if let authError = error as? ASAuthorizationError {
            switch authError.code {
            case .canceled:
                continuation?.resume(throwing: AppleSignInError.userCanceled)
            case .failed:
                continuation?.resume(throwing: AppleSignInError.authorizationFailed)
            case .invalidResponse:
                continuation?.resume(throwing: AppleSignInError.invalidResponse)
            case .notHandled:
                continuation?.resume(throwing: AppleSignInError.notHandled)
            case .unknown:
                continuation?.resume(throwing: AppleSignInError.unknown)
            @unknown default:
                continuation?.resume(throwing: AppleSignInError.unknown)
            }
        } else {
            continuation?.resume(throwing: error)
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Get the first window scene
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        
        return windowScene?.windows.first ?? ASPresentationAnchor()
    }
}

// MARK: - Error Types

enum AppleSignInError: LocalizedError {
    case invalidCredential
    case missingIdentityToken
    case missingAuthorizationCode
    case userCanceled
    case authorizationFailed
    case invalidResponse
    case notHandled
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Invalid Apple ID credential received"
        case .missingIdentityToken:
            return "Missing identity token"
        case .missingAuthorizationCode:
            return "Missing authorization code"
        case .userCanceled:
            return "Sign in was canceled"
        case .authorizationFailed:
            return "Authorization failed"
        case .invalidResponse:
            return "Invalid response from Apple"
        case .notHandled:
            return "Sign in not handled"
        case .unknown:
            return "Unknown error occurred"
        }
    }
}
