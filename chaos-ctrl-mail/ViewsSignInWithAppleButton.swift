//
//  SignInWithAppleButton.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import SwiftUI
import AuthenticationServices

/// SwiftUI wrapper for ASAuthorizationAppleIDButton
struct SignInWithAppleButton: View {
    let onRequest: () -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void
    
    var buttonType: ASAuthorizationAppleIDButton.ButtonType = .signIn
    var buttonStyle: ASAuthorizationAppleIDButton.Style = .black
    
    var body: some View {
        SignInWithAppleButtonRepresentable(
            buttonType: buttonType,
            buttonStyle: buttonStyle,
            onRequest: onRequest,
            onCompletion: onCompletion
        )
        .frame(height: 50)
        .frame(maxWidth: 375) // Apple's maximum button width
        .cornerRadius(8)
    }
}

// MARK: - UIViewRepresentable

struct SignInWithAppleButtonRepresentable: UIViewRepresentable {
    let buttonType: ASAuthorizationAppleIDButton.ButtonType
    let buttonStyle: ASAuthorizationAppleIDButton.Style
    let onRequest: () -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void
    
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType: buttonType,
            authorizationButtonStyle: buttonStyle
        )
        
        button.cornerRadius = 8
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleButtonPress),
            for: .touchUpInside
        )
        
        return button
    }
    
    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            onRequest: onRequest,
            onCompletion: onCompletion
        )
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        let onRequest: () -> Void
        let onCompletion: (Result<ASAuthorization, Error>) -> Void
        
        init(onRequest: @escaping () -> Void, onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void) {
            self.onRequest = onRequest
            self.onCompletion = onCompletion
        }
        
        @objc func handleButtonPress() {
            onRequest()
            
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
        
        // MARK: - ASAuthorizationControllerDelegate
        
        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            onCompletion(.success(authorization))
        }
        
        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            onCompletion(.failure(error))
        }
        
        // MARK: - ASAuthorizationControllerPresentationContextProviding
        
        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
            
            return windowScene?.windows.first ?? ASPresentationAnchor()
        }
    }
}

// MARK: - Button Style Extensions

extension SignInWithAppleButton {
    /// Creates a Sign In button with default black style
    static func signIn(onRequest: @escaping () -> Void, onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void) -> some View {
        SignInWithAppleButton(
            onRequest: onRequest,
            onCompletion: onCompletion,
            buttonType: .signIn,
            buttonStyle: .black
        )
    }
    
    /// Creates a Continue button with default black style
    static func `continue`(onRequest: @escaping () -> Void, onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void) -> some View {
        SignInWithAppleButton(
            onRequest: onRequest,
            onCompletion: onCompletion,
            buttonType: .continue,
            buttonStyle: .black
        )
    }
    
    /// Creates a Sign Up button with default black style
    static func signUp(onRequest: @escaping () -> Void, onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void) -> some View {
        SignInWithAppleButton(
            onRequest: onRequest,
            onCompletion: onCompletion,
            buttonType: .signUp,
            buttonStyle: .black
        )
    }
}

#Preview("Sign In - Black") {
    SignInWithAppleButton(
        onRequest: {
            print("Sign in requested")
        },
        onCompletion: { result in
            switch result {
            case .success:
                print("Success")
            case .failure(let error):
                print("Error: \(error)")
            }
        },
        buttonType: .signIn,
        buttonStyle: .black
    )
    .padding()
}

#Preview("Sign In - White") {
    ZStack {
        Color.blue
        SignInWithAppleButton(
            onRequest: {},
            onCompletion: { _ in },
            buttonType: .signIn,
            buttonStyle: .white
        )
        .padding()
    }
}

#Preview("Continue - White Outline") {
    SignInWithAppleButton(
        onRequest: {},
        onCompletion: { _ in },
        buttonType: .continue,
        buttonStyle: .whiteOutline
    )
    .padding()
}
