//
//  MailAccount.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import Foundation

struct MailAccount: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var emailAddress: String
    var provider: MailProvider
    var isActive: Bool
    var authType: AuthenticationType
    
    // IMAP Settings
    var imapServer: String
    var imapPort: Int
    var imapUsername: String
    var imapUseSSL: Bool
    
    // SMTP Settings
    var smtpServer: String
    var smtpPort: Int
    var smtpUsername: String
    var smtpUseSSL: Bool
    
    // Note: Passwords and tokens are now stored in Keychain, not here
    
    init(
        id: UUID = UUID(),
        name: String,
        emailAddress: String,
        provider: MailProvider = .custom,
        isActive: Bool = true,
        authType: AuthenticationType = .password,
        imapServer: String = "",
        imapPort: Int = 993,
        imapUsername: String = "",
        imapUseSSL: Bool = true,
        smtpServer: String = "",
        smtpPort: Int = 587,
        smtpUsername: String = "",
        smtpUseSSL: Bool = true
    ) {
        self.id = id
        self.name = name
        self.emailAddress = emailAddress
        self.provider = provider
        self.isActive = isActive
        self.authType = authType
        self.imapServer = imapServer
        self.imapPort = imapPort
        self.imapUsername = imapUsername
        self.imapUseSSL = imapUseSSL
        self.smtpServer = smtpServer
        self.smtpPort = smtpPort
        self.smtpUsername = smtpUsername
        self.smtpUseSSL = smtpUseSSL
    }
    
    // Retrieve password from Keychain
    var password: String? {
        try? KeychainManager.shared.retrieveAccountPassword(for: id)
    }
    
    // Retrieve OAuth2 token from Keychain
    var oauthToken: OAuth2Token? {
        try? KeychainManager.shared.retrieveOAuth2Token(for: id)
    }
}

enum AuthenticationType: String, Codable {
    case password = "Password"
    case oauth2 = "OAuth2"
}

enum MailProvider: String, Codable, CaseIterable {
    case gmail = "Gmail"
    case outlook = "Outlook"
    case yahoo = "Yahoo"
    case icloud = "iCloud"
    case custom = "Custom"
    
    var icon: String {
        switch self {
        case .gmail: return "envelope.circle.fill"
        case .outlook: return "envelope.circle.fill"
        case .yahoo: return "envelope.circle.fill"
        case .icloud: return "cloud.fill"
        case .custom: return "envelope.fill"
        }
    }
    
    var supportsOAuth2: Bool {
        switch self {
        case .gmail, .outlook, .yahoo:
            return true
        case .icloud, .custom:
            return false
        }
    }
    
    var recommendsOAuth2: Bool {
        // Gmail and Outlook strongly recommend OAuth2
        switch self {
        case .gmail, .outlook:
            return true
        default:
            return false
        }
    }
    
    // Pre-configured settings for common providers
    func defaultSettings(email: String) -> (imap: String, imapPort: Int, smtp: String, smtpPort: Int) {
        switch self {
        case .gmail:
            return ("imap.gmail.com", 993, "smtp.gmail.com", 587)
        case .outlook:
            return ("outlook.office365.com", 993, "smtp.office365.com", 587)
        case .yahoo:
            return ("imap.mail.yahoo.com", 993, "smtp.mail.yahoo.com", 587)
        case .icloud:
            return ("imap.mail.me.com", 993, "smtp.mail.me.com", 587)
        case .custom:
            return ("", 993, "", 587)
        }
    }
}

// MARK: - Sample Account
extension MailAccount {
    static let sample = MailAccount(
        name: "Personal",
        emailAddress: "me@example.com",
        provider: .gmail,
        authType: .password,
        imapServer: "imap.gmail.com",
        imapUsername: "me@example.com",
        smtpServer: "smtp.gmail.com",
        smtpUsername: "me@example.com"
    )
}
