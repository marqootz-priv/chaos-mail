//
//  QuickAccountSetupView.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import SwiftUI
import AuthenticationServices

struct QuickAccountSetupView: View {
    @Bindable var accountManager: AccountManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var accountName: String = ""
    @State private var isDiscovering: Bool = false
    @State private var isConnecting: Bool = false
    @State private var discoveredSettings: MailAccountDiscovery.DiscoveryResult?
    @State private var errorMessage: String?
    @State private var showAdvancedSetup: Bool = false
    @State private var showManualEntry: Bool = false
    @State private var googleSignInManager = GoogleSignInManager()
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [.blue.opacity(0.1), .purple.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Header
                        VStack(spacing: 16) {
                            Image(systemName: "envelope.circle.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(.blue.gradient)
                            
                            Text("Add Your Email")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            
                            Text("Enter your email and password\nWe'll configure everything automatically")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)
                        
                        // Social Sign-In Options
                        VStack(spacing: 12) {
                            // Sign in with Apple
                            SignInWithAppleButton(
                                onRequest: {
                                    // Request is handled automatically by the button
                                },
                                onCompletion: { result in
                                    Task {
                                        await handleAppleSignIn(result: result)
                                    }
                                }
                            )
                            .frame(height: 50)
                            
                            // Sign in with Google
                            SignInWithGoogleButton {
                                Task {
                                    await handleGoogleSignIn()
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        // Divider
                        HStack {
                            Rectangle()
                                .fill(.secondary.opacity(0.3))
                                .frame(height: 1)
                            Text("or")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Rectangle()
                                .fill(.secondary.opacity(0.3))
                                .frame(height: 1)
                        }
                        .padding(.horizontal, 24)
                        
                        // Manual email entry (show only if user taps "or")
                        if showManualEntry {
                            manualEntrySection
                            
                            // Discovery status
                            if let settings = discoveredSettings {
                                discoveryStatusView(settings: settings)
                            }
                            
                            // Error message
                            if let error = errorMessage {
                                errorMessageView(error: error)
                            }
                            
                            // Action buttons
                            actionButtonsSection
                        } else {
                            Button {
                                withAnimation {
                                    showManualEntry = true
                                }
                            } label: {
                                Text("Sign in with Email")
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                            }
                        }
                        
                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAdvancedSetup) {
                AccountSetupView(accountManager: accountManager)
            }
        }
    }
    
    // MARK: - Manual Entry Section
    
    @ViewBuilder
    private var manualEntrySection: some View {
        VStack(spacing: 20) {
            // Email field
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    
                    TextField("Email Address", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .onChange(of: email) { _, newValue in
                            if newValue.contains("@") && !newValue.hasSuffix("@") {
                                Task {
                                    await discoverSettings()
                                }
                            }
                        }
                    
                    if isDiscovering {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if discoveredSettings != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .padding()
                .background(.ultraThickMaterial)
                .cornerRadius(12)
            }
            
            // Account name (optional)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "tag.fill")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    
                    TextField("Account Name (Optional)", text: $accountName)
                        .textContentType(.name)
                }
                .padding()
                .background(.ultraThickMaterial)
                .cornerRadius(12)
            }
            
            // Password field
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
                .padding()
                .background(.ultraThickMaterial)
                .cornerRadius(12)
            }
        }
        .padding(.horizontal, 24)
    }
    
    @ViewBuilder
    private func discoveryStatusView(settings: MailAccountDiscovery.DiscoveryResult) -> some View {
        VStack(spacing: 12) {
            Label("Settings Discovered!", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            
            VStack(spacing: 8) {
                HStack {
                    Text("IMAP:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(settings.imapServer)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("SMTP:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(settings.smtpServer)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .padding()
            .background(.green.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.horizontal, 24)
    }
    
    @ViewBuilder
    private func errorMessageView(error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.orange.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal, 24)
    }
    
    // MARK: - View Helpers
    
    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            Button {
                Task {
                    await addAccount()
                }
            } label: {
                HStack {
                    if isConnecting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Continue")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isValid ? AnyShapeStyle(Color.blue.gradient) : AnyShapeStyle(Color.gray.opacity(0.3)))
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
            .disabled(!isValid || isConnecting)
            
            Button {
                showAdvancedSetup = true
            } label: {
                Text("Advanced Setup")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 24)
    }
}

extension QuickAccountSetupView {
    
    private var isValid: Bool {
        !email.isEmpty && 
        email.contains("@") && 
        !password.isEmpty &&
        (discoveredSettings != nil || !email.hasSuffix("@"))
    }
    
    // MARK: - Apple Sign In
    
    private func handleAppleSignIn(result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                await MainActor.run {
                    errorMessage = "Invalid Apple ID credential"
                }
                return
            }
            
            await MainActor.run {
                isConnecting = true
            }
            
            // Extract user information
            let userEmail = credential.email ?? "\(credential.user)@privaterelay.appleid.com"
            let userName = credential.fullName.map { components in
                let formatter = PersonNameComponentsFormatter()
                return formatter.string(from: components)
            } ?? "Apple User"
            
            // Check if this is a Hide My Email address
            let isHiddenEmail = userEmail.contains("@privaterelay.appleid.com")
            
            // Create account with Apple ID
            let accountId = UUID()
            
            // For Apple Sign In, we need to handle it differently since there's no traditional IMAP/SMTP
            // In a real app, you'd integrate with your backend to exchange the Apple ID token
            // For now, we'll show that the Apple account was added
            
            let account = MailAccount(
                id: accountId,
                name: userName,
                emailAddress: userEmail,
                provider: .custom,
                authType: .oauth2,
                imapServer: "apple-signin", // Special marker
                imapPort: 993,
                imapUsername: credential.user,
                imapUseSSL: true,
                smtpServer: "apple-signin",
                smtpPort: 587,
                smtpUsername: credential.user,
                smtpUseSSL: true
            )
            
            // Store Apple ID credential info securely
            if let identityToken = credential.identityToken,
               let tokenString = String(data: identityToken, encoding: .utf8) {
                
                // Save OAuth2 token (using Apple's identity token)
                let token = OAuth2Token(
                    accessToken: tokenString,
                    refreshToken: nil,
                    expiresIn: nil,
                    tokenType: "Apple",
                    scope: nil
                )
                
                try? KeychainManager.shared.saveOAuth2Token(token, for: accountId)
            }
            
            await MainActor.run {
                accountManager.addAccount(account)
                isConnecting = false
                
                // Show success message
                if isHiddenEmail {
                    errorMessage = "✓ Signed in with Apple (Hide My Email enabled)"
                } else {
                    errorMessage = nil
                }
                
                // Dismiss after brief delay
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    dismiss()
                }
            }
            
        case .failure(let error):
            await MainActor.run {
                if (error as? ASAuthorizationError)?.code == .canceled {
                    errorMessage = nil // User canceled, don't show error
                } else {
                    errorMessage = "Sign in failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Google Sign In
    
    private func handleGoogleSignIn() async {
        await MainActor.run {
            isConnecting = true
            errorMessage = nil
        }
        
        do {
            // Step 1: Sign in with Google to get tokens
            let googleUser = try await googleSignInManager.signIn()
            
            // Step 2: Verify with your backend
            let backendResponse = try await BackendService.shared.verifyGoogleToken(
                idToken: googleUser.idToken,
                accessToken: googleUser.accessToken,
                refreshToken: googleUser.refreshToken
            )
            
            // Step 3: Create local account
            let accountId = UUID()
            
            // Use email configuration from backend if provided
            let imapServer: String
            let imapPort: Int
            let smtpServer: String
            let smtpPort: Int
            
            if let config = backendResponse.emailConfiguration {
                imapServer = config.imapServer
                imapPort = config.imapPort
                smtpServer = config.smtpServer
                smtpPort = config.smtpPort
            } else {
                // Default Gmail configuration
                imapServer = "imap.gmail.com"
                imapPort = 993
                smtpServer = "smtp.gmail.com"
                smtpPort = 587
            }
            
            let account = MailAccount(
                id: accountId,
                name: googleUser.displayName,
                emailAddress: googleUser.email,
                provider: .gmail,
                authType: .oauth2,
                imapServer: imapServer,
                imapPort: imapPort,
                imapUsername: googleUser.email,
                imapUseSSL: true,
                smtpServer: smtpServer,
                smtpPort: smtpPort,
                smtpUsername: googleUser.email,
                smtpUseSSL: true
            )
            
            // Step 4: Save OAuth2 tokens
            let token = OAuth2Token(
                accessToken: googleUser.accessToken,
                refreshToken: googleUser.refreshToken,
                expiresIn: 3600, // Google tokens typically expire in 1 hour
                tokenType: "Bearer",
                scope: "email profile https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.send"
            )
            
            try? KeychainManager.shared.saveOAuth2Token(token, for: accountId)
            
            await MainActor.run {
                accountManager.addAccount(account)
                isConnecting = false
                errorMessage = backendResponse.isNewAccount ? "✓ New Google account linked!" : "✓ Google account connected!"
                
                // Dismiss after brief delay
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    dismiss()
                }
            }
            
        } catch let error as GoogleSignInError {
            await MainActor.run {
                isConnecting = false
                switch error {
                case .userCanceled:
                    errorMessage = nil
                case .invalidAuthorizationURL:
                    errorMessage = "Configuration error. Please check Google OAuth settings."
                case .tokenExchangeFailed:
                    errorMessage = "Failed to authenticate with Google. Please try again."
                case .backendVerificationFailed:
                    errorMessage = "Could not verify your account with our servers."
                default:
                    errorMessage = "Google sign in failed: \(error.localizedDescription)"
                }
            }
        } catch let error as BackendError {
            await MainActor.run {
                isConnecting = false
                errorMessage = "Backend error: \(error.localizedDescription)"
            }
        } catch {
            await MainActor.run {
                isConnecting = false
                errorMessage = "Sign in failed: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Discovery
    
    private func discoverSettings() async {
        isDiscovering = true
        errorMessage = nil
        discoveredSettings = nil
        
        do {
            let discovery = MailAccountDiscovery()
            let result = try await discovery.discover(email: email)
            
            await MainActor.run {
                discoveredSettings = result
                
                // Auto-fill account name if empty
                if accountName.isEmpty, let displayName = result.displayName {
                    accountName = displayName
                } else if accountName.isEmpty {
                    // Extract domain for account name
                    let domain = email.components(separatedBy: "@").last ?? "Email"
                    accountName = domain.capitalized
                }
                
                isDiscovering = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Couldn't auto-configure. Using standard settings."
                isDiscovering = false
                
                // Fallback to common patterns
                let domain = email.components(separatedBy: "@").last ?? ""
                discoveredSettings = MailAccountDiscovery.DiscoveryResult(
                    imapServer: "imap.\(domain)",
                    smtpServer: "smtp.\(domain)",
                    username: email
                )
            }
        }
    }
    
    // MARK: - Add Account
    
    private func addAccount() async {
        guard let settings = discoveredSettings else { return }
        
        isConnecting = true
        errorMessage = nil
        
        let accountId = UUID()
        let finalAccountName = accountName.isEmpty ? "My Account" : accountName
        
        // Create account
        let account = MailAccount(
            id: accountId,
            name: finalAccountName,
            emailAddress: email,
            provider: detectProvider(from: email),
            authType: .password,
            imapServer: settings.imapServer,
            imapPort: settings.imapPort,
            imapUsername: settings.username,
            imapUseSSL: settings.imapUseSSL,
            smtpServer: settings.smtpServer,
            smtpPort: settings.smtpPort,
            smtpUsername: settings.username,
            smtpUseSSL: settings.smtpUseSSL
        )
        
        // Save password to Keychain
        do {
            try KeychainManager.shared.saveAccountPassword(password, for: accountId)
            
            // Add account
            await MainActor.run {
                accountManager.addAccount(account)
                isConnecting = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to save credentials: \(error.localizedDescription)"
                isConnecting = false
            }
        }
    }
    
    private func detectProvider(from email: String) -> MailProvider {
        let domain = email.components(separatedBy: "@").last?.lowercased() ?? ""
        
        if domain.contains("gmail") {
            return .gmail
        } else if domain.contains("outlook") || domain.contains("hotmail") || domain.contains("live") {
            return .outlook
        } else if domain.contains("yahoo") {
            return .yahoo
        } else if domain.contains("icloud") || domain.contains("me.com") || domain.contains("mac.com") {
            return .icloud
        } else {
            return .custom
        }
    }
}

#Preview {
    QuickAccountSetupView(accountManager: AccountManager())
}
