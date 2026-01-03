//
//  AccountSetupView.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import SwiftUI

struct AccountSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var accountManager: AccountManager
    
    @State private var name: String = ""
    @State private var emailAddress: String = ""
    @State private var selectedProvider: MailProvider = .custom
    @State private var password: String = ""
    @State private var showAdvanced: Bool = false
    @State private var isDiscovering: Bool = false
    @State private var discoveryError: String?
    
    // Advanced settings
    @State private var imapServer: String = ""
    @State private var imapPort: String = "993"
    @State private var imapUsername: String = ""
    @State private var imapPassword: String = ""
    @State private var imapUseSSL: Bool = true
    
    @State private var smtpServer: String = ""
    @State private var smtpPort: String = "587"
    @State private var smtpUsername: String = ""
    @State private var smtpPassword: String = ""
    @State private var smtpUseSSL: Bool = true
    
    var editingAccount: MailAccount?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Account Information") {
                    TextField("Account Name", text: $name)
                        .textContentType(.name)
                    
                    HStack {
                        TextField("Email Address", text: $emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .onChange(of: emailAddress) { _, newValue in
                                // Auto-discover when email is valid
                                if newValue.contains("@") && !newValue.hasSuffix("@") {
                                    Task {
                                        await autoDiscoverSettings()
                                    }
                                }
                            }
                        
                        if isDiscovering {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    
                    if let error = discoveryError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    Picker("Email Provider", selection: $selectedProvider) {
                        ForEach(MailProvider.allCases, id: \.self) { provider in
                            Label(provider.rawValue, systemImage: provider.icon)
                                .tag(provider)
                        }
                    }
                    .onChange(of: selectedProvider) { _, newProvider in
                        updateServerSettings(for: newProvider)
                    }
                    
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
                
                // Show autodiscovery status
                if !imapServer.isEmpty && !isDiscovering {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Settings Discovered", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            
                            Text("Mail server settings have been automatically configured.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                Text("IMAP:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(imapServer)
                                    .font(.caption)
                            }
                            
                            HStack {
                                Text("SMTP:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(smtpServer)
                                    .font(.caption)
                            }
                        }
                    }
                } else if selectedProvider != .custom {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Quick Setup", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            
                            Text("Server settings will be configured automatically for \(selectedProvider.rawValue).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section {
                    Button {
                        showAdvanced.toggle()
                    } label: {
                        Label(
                            showAdvanced ? "Hide Advanced Settings" : "Show Advanced Settings",
                            systemImage: showAdvanced ? "chevron.up" : "chevron.down"
                        )
                    }
                }
                
                if showAdvanced {
                    Section("IMAP Settings (Incoming)") {
                        TextField("IMAP Server", text: $imapServer)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                        
                        TextField("Port", text: $imapPort)
                            .keyboardType(.numberPad)
                        
                        TextField("Username", text: $imapUsername)
                            .textInputAutocapitalization(.never)
                        
                        SecureField("Password", text: $imapPassword)
                        
                        Toggle("Use SSL", isOn: $imapUseSSL)
                    }
                    
                    Section("SMTP Settings (Outgoing)") {
                        TextField("SMTP Server", text: $smtpServer)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                        
                        TextField("Port", text: $smtpPort)
                            .keyboardType(.numberPad)
                        
                        TextField("Username", text: $smtpUsername)
                            .textInputAutocapitalization(.never)
                        
                        SecureField("Password", text: $smtpPassword)
                        
                        Toggle("Use SSL", isOn: $smtpUseSSL)
                    }
                }
            }
            .navigationTitle(editingAccount == nil ? "Add Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingAccount == nil ? "Add" : "Save") {
                        saveAccount()
                    }
                    .disabled(!isValid)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AccountSetupGuideView(provider: selectedProvider)
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                }
            }
        }
        .onAppear {
            if let account = editingAccount {
                loadAccount(account)
            }
        }
    }
    
    private var isValid: Bool {
        !name.isEmpty && !emailAddress.isEmpty && emailAddress.contains("@")
    }
    
    // MARK: - Autodiscovery
    
    private func autoDiscoverSettings() async {
        // Don't auto-discover if manually using a known provider
        guard selectedProvider == .custom else { return }
        
        isDiscovering = true
        discoveryError = nil
        
        do {
            let discovery = MailAccountDiscovery()
            let result = try await discovery.discover(email: emailAddress)
            
            // Update UI with discovered settings
            await MainActor.run {
                imapServer = result.imapServer
                imapPort = "\(result.imapPort)"
                imapUseSSL = result.imapUseSSL
                
                smtpServer = result.smtpServer
                smtpPort = "\(result.smtpPort)"
                smtpUseSSL = result.smtpUseSSL
                
                imapUsername = result.username
                smtpUsername = result.username
                
                if let displayName = result.displayName, name.isEmpty {
                    name = displayName
                }
                
                isDiscovering = false
            }
        } catch {
            await MainActor.run {
                discoveryError = "Could not auto-configure. Please enter settings manually."
                isDiscovering = false
            }
        }
    }
    
    private func updateServerSettings(for provider: MailProvider) {
        let settings = provider.defaultSettings(email: emailAddress)
        imapServer = settings.imap
        imapPort = "\(settings.imapPort)"
        smtpServer = settings.smtp
        smtpPort = "\(settings.smtpPort)"
        
        // Auto-fill usernames with email address
        imapUsername = emailAddress
        smtpUsername = emailAddress
        imapPassword = password
        smtpPassword = password
    }
    
    private func loadAccount(_ account: MailAccount) {
        name = account.name
        emailAddress = account.emailAddress
        selectedProvider = account.provider
        imapServer = account.imapServer
        imapPort = "\(account.imapPort)"
        imapUsername = account.imapUsername
        imapUseSSL = account.imapUseSSL
        smtpServer = account.smtpServer
        smtpPort = "\(account.smtpPort)"
        smtpUsername = account.smtpUsername
        smtpUseSSL = account.smtpUseSSL
        
        // Load password from Keychain
        if let savedPassword = account.password {
            password = savedPassword
            imapPassword = savedPassword
            smtpPassword = savedPassword
        }
    }
    
    private func saveAccount() {
        // Auto-configure if not using custom provider
        if selectedProvider != .custom && !showAdvanced {
            updateServerSettings(for: selectedProvider)
        }
        
        let accountId = editingAccount?.id ?? UUID()
        
        let account = MailAccount(
            id: accountId,
            name: name,
            emailAddress: emailAddress,
            provider: selectedProvider,
            authType: .password,
            imapServer: imapServer,
            imapPort: Int(imapPort) ?? 993,
            imapUsername: imapUsername.isEmpty ? emailAddress : imapUsername,
            imapUseSSL: imapUseSSL,
            smtpServer: smtpServer,
            smtpPort: Int(smtpPort) ?? 587,
            smtpUsername: smtpUsername.isEmpty ? emailAddress : smtpUsername,
            smtpUseSSL: smtpUseSSL
        )
        
        // Save password to Keychain
        let passwordToSave = imapPassword.isEmpty ? password : imapPassword
        if !passwordToSave.isEmpty {
            try? KeychainManager.shared.saveAccountPassword(passwordToSave, for: accountId)
        }
        
        if editingAccount == nil {
            accountManager.addAccount(account)
        } else {
            accountManager.updateAccount(account)
        }
        
        dismiss()
    }
}

#Preview {
    AccountSetupView(accountManager: AccountManager())
}
