//
//  CachedEmail.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import Foundation

/// Enhanced email model for caching with IMAP metadata
struct CachedEmail: Identifiable, Codable {
    let id: String                    // Unique identifier (UUID for Email compatibility)
    let messageId: String?            // IMAP Message-ID header (optional)
    let from: String
    let to: [String]
    let subject: String
    let date: Date
    let body: String
    let isHTML: Bool
    let isRead: Bool
    let isStarred: Bool
    let folder: String                // INBOX, Drafts, etc.
    let cachedAt: Date                // When we cached it
    let attachments: [EmailAttachment]
    let hasAttachments: Bool
    
    // Threading metadata
    let inReplyTo: String?
    let references: [String]?
    
    // IMAP metadata for incremental sync
    let imapUID: String               // IMAP UID (sequence number as string for now)
    let flags: [String]               // IMAP flags (\Seen, \Flagged, etc.)
    
    /// Convert to regular Email model for UI compatibility
    func toEmail() -> Email {
        let mailFolder = MailFolder(rawValue: folder) ?? .inbox
        return Email(
            id: UUID(uuidString: id) ?? UUID(),
            from: from,
            to: to,
            subject: subject,
            body: body,
            date: date,
            isRead: isRead,
            isStarred: isStarred,
            folder: mailFolder,
            hasAttachments: hasAttachments,
            attachments: attachments,
            messageId: messageId,
            inReplyTo: inReplyTo,
            references: references
        )
    }
    
    /// Create from Email and IMAP metadata
    init(from email: Email, imapUID: String, flags: [String] = [], messageId: String? = nil, inReplyTo: String? = nil, references: [String]? = nil) {
        self.id = email.id.uuidString
        self.messageId = messageId ?? email.messageId
        self.from = email.from
        self.to = email.to
        self.subject = email.subject
        self.body = email.body
        self.date = email.date
        self.isHTML = email.body.contains("<html") || email.body.contains("<!DOCTYPE")
        self.isRead = email.isRead
        self.isStarred = email.isStarred
        self.folder = email.folder.rawValue
        self.cachedAt = Date()
        self.attachments = email.attachments
        self.hasAttachments = email.hasAttachments
        self.inReplyTo = inReplyTo ?? email.inReplyTo
        self.references = references ?? email.references
        self.imapUID = imapUID
        self.flags = flags
    }
}

/// Cache metadata for tracking sync state
struct CacheMetadata: Codable {
    let folder: String
    let lastSyncDate: Date
    let highestUID: String            // Highest UID we've seen (for incremental sync)
    let totalEmails: Int
    
    init(folder: String, lastSyncDate: Date = Date(), highestUID: String = "0", totalEmails: Int = 0) {
        self.folder = folder
        self.lastSyncDate = lastSyncDate
        self.highestUID = highestUID
        self.totalEmails = totalEmails
    }
}


