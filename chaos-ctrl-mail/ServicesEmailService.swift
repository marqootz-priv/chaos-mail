//
//  EmailService.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import Foundation
import Observation

@Observable
class EmailService {
    var isConnected: Bool = false
    var isSyncing: Bool = false
    var lastSyncDate: Date?
    var syncError: Error?
    
    private var imapSession: IMAPSession?
    private var smtpSession: SMTPSession?
    
    // MARK: - Connection
    
    func connect(account: MailAccount) async throws {
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            // Get password from Keychain
            guard let password = account.password else {
                throw EmailServiceError.invalidCredentials
            }
            
            // Initialize IMAP session
            imapSession = IMAPSession(
                server: account.imapServer,
                port: account.imapPort,
                username: account.imapUsername,
                password: password,
                useSSL: account.imapUseSSL
            )
            
            try await imapSession?.connect()
            
            // Initialize SMTP session
            smtpSession = SMTPSession(
                server: account.smtpServer,
                port: account.smtpPort,
                username: account.smtpUsername,
                password: password,
                useSSL: account.smtpUseSSL
            )
            
            try await smtpSession?.connect()
            
            isConnected = true
            syncError = nil
        } catch {
            isConnected = false
            syncError = error
            throw error
        }
    }
    
    func disconnect() async {
        await imapSession?.disconnect()
        await smtpSession?.disconnect()
        isConnected = false
    }
    
    // MARK: - Fetch Emails
    
    func fetchEmails(folder: MailFolder, limit: Int = 50) async throws -> [Email] {
        guard let session = imapSession, isConnected else {
            throw EmailServiceError.notConnected
        }
        
        let folderName = mapFolderToIMAP(folder)
        return try await session.fetchMessages(from: folderName, limit: limit)
    }
    
    func fetchEmail(id: String) async throws -> Email {
        guard let session = imapSession, isConnected else {
            throw EmailServiceError.notConnected
        }
        
        return try await session.fetchMessage(id: id)
    }
    
    // MARK: - Email Operations
    
    func markAsRead(email: Email) async throws {
        guard let session = imapSession, isConnected else {
            throw EmailServiceError.notConnected
        }
        
        try await session.markAsRead(messageId: email.id.uuidString)
    }
    
    func markAsUnread(email: Email) async throws {
        guard let session = imapSession, isConnected else {
            throw EmailServiceError.notConnected
        }
        
        try await session.markAsUnread(messageId: email.id.uuidString)
    }
    
    func moveEmail(email: Email, to folder: MailFolder) async throws {
        guard let session = imapSession, isConnected else {
            throw EmailServiceError.notConnected
        }
        
        let targetFolder = mapFolderToIMAP(folder)
        try await session.moveMessage(messageId: email.id.uuidString, to: targetFolder)
    }
    
    func deleteEmail(email: Email, permanently: Bool = false) async throws {
        guard let session = imapSession, isConnected else {
            throw EmailServiceError.notConnected
        }
        
        if permanently {
            try await session.deleteMessage(messageId: email.id.uuidString)
        } else {
            try await moveEmail(email: email, to: .trash)
        }
    }
    
    // MARK: - Send Email
    
    func sendEmail(to: [String], subject: String, body: String, from: String) async throws {
        guard let session = smtpSession, isConnected else {
            throw EmailServiceError.notConnected
        }
        
        try await session.sendMessage(
            from: from,
            to: to,
            subject: subject,
            body: body
        )
    }
    
    // MARK: - Sync
    
    func syncAllFolders() async throws -> [MailFolder: [Email]] {
        var results: [MailFolder: [Email]] = [:]
        
        for folder in MailFolder.allCases {
            do {
                let emails = try await fetchEmails(folder: folder)
                results[folder] = emails
            } catch {
                print("Failed to sync folder \(folder.rawValue): \(error)")
                // Continue with other folders
            }
        }
        
        lastSyncDate = Date()
        return results
    }
    
    // MARK: - Helper Methods
    
    private func mapFolderToIMAP(_ folder: MailFolder) -> String {
        switch folder {
        case .inbox: return "INBOX"
        case .sent: return "Sent"
        case .drafts: return "Drafts"
        case .trash: return "Trash"
        case .spam: return "Spam"
        case .archive: return "Archive"
        }
    }
}

enum EmailServiceError: LocalizedError {
    case notConnected
    case authenticationFailed
    case networkError(Error)
    case invalidCredentials
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to email server"
        case .authenticationFailed:
            return "Authentication failed. Please check your credentials."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidCredentials:
            return "Invalid username or password"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}
