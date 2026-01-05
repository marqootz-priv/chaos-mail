import Foundation

struct ConversationThread: Identifiable, Hashable {
    let id: String
    let subject: String
    let participantEmails: [String]
    let messages: [ConversationMessage]    // sorted by timestamp ascending
    let createdAt: Date
    let updatedAt: Date
    let isUnread: Bool
    let isStarred: Bool
    let folder: MailFolder
}

struct ConversationMessage: Identifiable, Hashable {
    let id: String                         // message UID / Email.id
    let from: String
    let displayName: String
    let timestamp: Date
    let extractedBody: String
    let fullEmail: Email
    let isRead: Bool
    let quotedText: String?
}

/// Responsible for grouping emails into threaded conversations and extracting readable snippets.
struct ThreadManager {
    
    func createThreads(from emails: [Email]) -> [ConversationThread] {
        guard !emails.isEmpty else { return [] }
        
        // Group by threading headers first, fallback to normalized subject.
        var buckets: [String: [Email]] = [:]
        
        for email in emails {
            let baseSubject = normalizeSubject(email.subject)
            let key: String
            
            if let inReply = email.inReplyTo?.lowercased(), !inReply.isEmpty {
                key = "reply:\(inReply)"
            } else if let msgId = email.messageId?.lowercased(), !msgId.isEmpty {
                key = "mid:\(msgId)"
            } else {
                key = "subj:\(baseSubject.lowercased())"
            }
            
            buckets[key, default: []].append(email)
        }
        
        var threads: [ConversationThread] = []
        
        for (_, group) in buckets {
            guard !group.isEmpty else { continue }
            
            let sorted = group.sorted { $0.date < $1.date } // oldest -> newest
            let messages: [ConversationMessage] = sorted.map { email in
                ConversationMessage(
                    id: email.messageId ?? email.id.uuidString,
                    from: email.from,
                    displayName: extractDisplayName(from: email.from),
                    timestamp: email.date,
                    extractedBody: extractMainResponse(from: email.body, isHTML: isHTML(email.body)),
                    fullEmail: email,
                    isRead: email.isRead,
                    quotedText: extractQuotedText(from: email.body, isHTML: isHTML(email.body))
                )
            }
            
            let createdAt = sorted.first?.date ?? Date()
            let updatedAt = sorted.last?.date ?? createdAt
            let participants = Array(Set(sorted.map { $0.from }))
            let subject = normalizeSubject(sorted.last?.subject ?? "(no subject)")
            let isUnread = sorted.contains { !$0.isRead }
            let isStarred = sorted.contains { $0.isStarred }
            let folder = sorted.last?.folder ?? .inbox
            
            threads.append(
                ConversationThread(
                    id: messages.last?.id ?? UUID().uuidString,
                    subject: subject,
                    participantEmails: participants,
                    messages: messages,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    isUnread: isUnread,
                    isStarred: isStarred,
                    folder: folder
                )
            )
        }
        
        return threads.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    // MARK: - Helpers
    
    func normalizeSubject(_ subject: String) -> String {
        var normalized = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove reply/forward prefixes (case-insensitive)
        let patterns = ["^re:\\s*", "^fwd?:\\s*", "^fw:\\s*", "^aw:\\s*", "^vs:\\s*"]
        for pattern in patterns {
            normalized = normalized.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func extractDisplayName(from email: String) -> String {
        if let ltIndex = email.firstIndex(of: "<") {
            let name = String(email[..<ltIndex]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        let parts = email.components(separatedBy: "@")
        return parts.first?.capitalized ?? email
    }
    
    func isHTML(_ body: String) -> Bool {
        let lower = body.lowercased()
        return lower.contains("<html") || lower.contains("<div") || lower.contains("<body")
    }
    
    func extractMainResponse(from body: String, isHTML: Bool) -> String {
        if isHTML {
            return extractFromHTML(body)
        } else {
            return extractFromPlainText(body)
        }
    }
    
    private func extractFromPlainText(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        var inQuote = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") ||
                (trimmed.hasPrefix("On ") && trimmed.contains("wrote:")) ||
                trimmed.hasPrefix("-----Original Message-----") {
                inQuote = true
            }
            
            if !inQuote && !trimmed.isEmpty {
                result.append(line)
            }
        }
        
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractFromHTML(_ html: String) -> String {
        var cleaned = html
        // Gmail quote blocks
        cleaned = cleaned.replacingOccurrences(
            of: #"<div class="gmail_quote">.*?</div>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Outlook reply/forward block
        cleaned = cleaned.replacingOccurrences(
            of: #"<div id="divRplyFwd">.*?</div>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Generic blockquotes
        cleaned = cleaned.replacingOccurrences(
            of: #"<blockquote[^>]*>.*?</blockquote>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Strip remaining HTML to produce text snippet
        cleaned = cleaned.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func extractQuotedText(from body: String, isHTML: Bool) -> String? {
        if isHTML {
            // Extract blockquote if present
            if let range = body.range(of: #"<blockquote[^>]*>.*?</blockquote>"#, options: [.regularExpression, .caseInsensitive]) {
                return String(body[range])
            }
            // Gmail quote
            if let range = body.range(of: #"<div class="gmail_quote">.*?</div>"#, options: [.regularExpression, .caseInsensitive]) {
                return String(body[range])
            }
        } else {
            // Plain-text quoted section
            if let quoteStart = body.range(of: "On ", options: .caseInsensitive),
               body[quoteStart.lowerBound...].contains("wrote:") {
                return String(body[quoteStart.lowerBound...])
            }
        }
        return nil
    }
}

