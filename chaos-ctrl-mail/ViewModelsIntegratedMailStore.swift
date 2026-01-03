//
//  IntegratedMailStore.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import Foundation
import Observation

@Observable
class IntegratedMailStore {
    var emails: [Email] = []
    var selectedFolder: MailFolder = .inbox
    var selectedEmail: Email?
    var searchText: String = ""
    
    var emailService: EmailService
    var accountManager: AccountManager
    var oauth2Manager = OAuth2Manager()
    
    var isSyncing: Bool = false
    var lastError: Error?
    
    init(emailService: EmailService = EmailService(), accountManager: AccountManager) {
        self.emailService = emailService
        self.accountManager = accountManager
    }
    
    // MARK: - Connection
    
    func connectToAccount(_ account: MailAccount) async throws {
        guard let password = account.password else {
            throw EmailServiceError.invalidCredentials
        }
        
        try await emailService.connect(account: account)
        try await syncCurrentFolder()
    }
    
    func connectWithOAuth2(_ account: MailAccount) async throws {
        // Check if we have a valid token
        if let token = account.oauthToken, !token.isExpired {
            // Use existing token
            try await useOAuth2Token(token, for: account)
        } else if let token = account.oauthToken, let config = OAuth2Manager.OAuth2Config.config(for: account.provider) {
            // Refresh token
            let newToken = try await oauth2Manager.refreshToken(token, config: config)
            try KeychainManager.shared.saveOAuth2Token(newToken, for: account.id)
            try await useOAuth2Token(newToken, for: account)
        } else {
            // Authenticate with OAuth2
            let token = try await oauth2Manager.authenticate(provider: account.provider)
            try KeychainManager.shared.saveOAuth2Token(token, for: account.id)
            try await useOAuth2Token(token, for: account)
        }
        
        try await syncCurrentFolder()
    }
    
    private func useOAuth2Token(_ token: OAuth2Token, for account: MailAccount) async throws {
        // Create a modified account with OAuth2 access token
        var modifiedAccount = account
        // Store the access token temporarily for this session
        // In production, you'd pass this to the IMAP/SMTP sessions
        try await emailService.connect(account: modifiedAccount)
    }
    
    func disconnect() async {
        await emailService.disconnect()
    }
    
    // MARK: - Sync
    
    func syncCurrentFolder() async throws {
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            let fetchedEmails = try await emailService.fetchEmails(folder: selectedFolder)
            emails = fetchedEmails
            lastError = nil
        } catch {
            lastError = error
            throw error
        }
    }
    
    func syncAllFolders() async throws {
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            let results = try await emailService.syncAllFolders()
            // Merge all emails
            emails = results.values.flatMap { $0 }
            lastError = nil
        } catch {
            lastError = error
            throw error
        }
    }
    
    // MARK: - Filtered Emails
    
    var filteredEmails: [Email] {
        var filtered = emails.filter { $0.folder == selectedFolder }
        
        if !searchText.isEmpty {
            filtered = filtered.filter { email in
                email.subject.localizedCaseInsensitiveContains(searchText) ||
                email.from.localizedCaseInsensitiveContains(searchText) ||
                email.body.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filtered.sorted { $0.date > $1.date }
    }
    
    var unreadCount: [MailFolder: Int] {
        var counts: [MailFolder: Int] = [:]
        for folder in MailFolder.allCases {
            counts[folder] = emails.filter { $0.folder == folder && !$0.isRead }.count
        }
        return counts
    }
    
    // MARK: - Email Operations
    
    func toggleRead(email: Email) async throws {
        if email.isRead {
            try await emailService.markAsUnread(email: email)
        } else {
            try await emailService.markAsRead(email: email)
        }
        
        if let index = emails.firstIndex(where: { $0.id == email.id }) {
            emails[index].isRead.toggle()
        }
    }
    
    func toggleStarred(email: Email) {
        // Local only for now - would need IMAP flag support
        if let index = emails.firstIndex(where: { $0.id == email.id }) {
            emails[index].isStarred.toggle()
        }
    }
    
    func moveToFolder(email: Email, folder: MailFolder) async throws {
        try await emailService.moveEmail(email: email, to: folder)
        
        if let index = emails.firstIndex(where: { $0.id == email.id }) {
            emails[index].folder = folder
            if selectedEmail?.id == email.id {
                selectedEmail = nil
            }
        }
    }
    
    func deleteEmail(email: Email) async throws {
        if email.folder == .trash {
            try await emailService.deleteEmail(email: email, permanently: true)
            emails.removeAll { $0.id == email.id }
        } else {
            try await emailService.deleteEmail(email: email, permanently: false)
            if let index = emails.firstIndex(where: { $0.id == email.id }) {
                emails[index].folder = .trash
            }
        }
        
        if selectedEmail?.id == email.id {
            selectedEmail = nil
        }
    }
    
    func sendEmail(to: [String], subject: String, body: String) async throws {
        guard let account = accountManager.selectedAccount else {
            throw EmailServiceError.notConnected
        }
        
        try await emailService.sendEmail(
            to: to,
            subject: subject,
            body: body,
            from: account.emailAddress
        )
        
        // Add to sent folder locally
        let sentEmail = Email(
            from: account.emailAddress,
            to: to,
            subject: subject,
            body: body,
            date: Date(),
            isRead: true,
            folder: .sent
        )
        emails.append(sentEmail)
    }
}
