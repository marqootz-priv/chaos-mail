//
//  Email.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import Foundation

struct Email: Identifiable, Hashable, Codable {
    let id: UUID
    let from: String
    let to: [String]
    let subject: String
    let body: String
    let date: Date
    var isRead: Bool
    var isStarred: Bool
    var folder: MailFolder
    var hasAttachments: Bool
    var attachments: [EmailAttachment]
    
    /// Clean text preview for list view (strips HTML, limits length)
    var preview: String {
        var text = body
        
        // Remove <style> tags and their content (CSS)
        text = text.replacingOccurrences(of: #"(?is)<style[^>]*>.*?</style>"#, with: " ", options: .regularExpression)
        
        // Remove <script> tags and their content
        text = text.replacingOccurrences(of: #"(?is)<script[^>]*>.*?</script>"#, with: " ", options: .regularExpression)
        
        // Remove inline style attributes from HTML tags (style="...")
        text = text.replacingOccurrences(of: #"\s+style\s*=\s*"[^"]*""#, with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"\s+style\s*=\s*'[^']*'"#, with: "", options: [.regularExpression, .caseInsensitive])
        
        // Remove any remaining CSS-like blocks (e.g., { property: value; })
        text = text.replacingOccurrences(of: #"\{[^}]{0,100}\}"#, with: " ", options: .regularExpression)
        
        // Strip HTML tags
        text = text.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: [.regularExpression, .caseInsensitive])
        
        // Decode HTML entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        
        // Decode numeric HTML entities (decimal: &#160; or hex: &#xa0;)
        // Pattern: &#123; or &#x7B; (case insensitive for hex)
        if let regex = try? NSRegularExpression(pattern: #"&#([0-9]+);|&#x([0-9a-fA-F]+);"#, options: []) {
            let nsString = text as NSString
            var decodedText = text
            var offset = 0
            
            // Process matches in reverse to preserve indices
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                var replacement = " "
                
                // Check if it's a decimal entity (capture group 1)
                if match.range(at: 1).location != NSNotFound {
                    let decimalStr = nsString.substring(with: match.range(at: 1))
                    if let code = UInt32(decimalStr), let scalar = UnicodeScalar(code) {
                        replacement = String(Character(scalar))
                    }
                }
                // Check if it's a hex entity (capture group 2)
                else if match.range(at: 2).location != NSNotFound {
                    let hexStr = nsString.substring(with: match.range(at: 2))
                    if let code = UInt32(hexStr, radix: 16), let scalar = UnicodeScalar(code) {
                        replacement = String(Character(scalar))
                    }
                }
                
                let range = Range(match.range, in: decodedText)!
                decodedText.replaceSubrange(range, with: replacement)
            }
            text = decodedText
        }
        
        // Replace newlines with spaces and clean up whitespace
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Limit to 100 characters
        if text.count > 100 {
            return String(text.prefix(100)) + "…"
        }
        
        return text.isEmpty ? "(No content)" : text
    }
    
    // Implement Hashable based on id only
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Email, rhs: Email) -> Bool {
        lhs.id == rhs.id
    }
    
    init(
        id: UUID = UUID(),
        from: String,
        to: [String],
        subject: String,
        body: String,
        date: Date = Date(),
        isRead: Bool = false,
        isStarred: Bool = false,
        folder: MailFolder = .inbox,
        hasAttachments: Bool = false,
        attachments: [EmailAttachment] = []
    ) {
        self.id = id
        self.from = from
        self.to = to
        self.subject = subject
        self.body = body
        self.date = date
        self.isRead = isRead
        self.isStarred = isStarred
        self.folder = folder
        self.attachments = attachments
        self.hasAttachments = hasAttachments || !attachments.isEmpty
    }
}

struct EmailAttachment: Identifiable, Hashable, Codable {
    let id: UUID
    let filename: String
    let mimeType: String
    let size: Int
    let data: Data?
    let isInline: Bool
    
    init(id: UUID = UUID(), filename: String, mimeType: String, size: Int, data: Data?, isInline: Bool) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.data = data
        self.isInline = isInline
    }
}

// MARK: - Sample Data
extension Email {
    static let sampleEmails: [Email] = [
        Email(
            from: "steve@apple.com",
            to: ["me@example.com"],
            subject: "Welcome to the team!",
            body: "Hi there,\n\nWelcome to the team! We're excited to have you on board. Let's schedule a meeting to discuss your first project.\n\nBest regards,\nSteve",
            date: Date().addingTimeInterval(-3600),
            isRead: false,
            hasAttachments: false
        ),
        Email(
            from: "newsletter@tech.com",
            to: ["me@example.com"],
            subject: "Your weekly tech digest",
            body: "Here are the top tech stories from this week:\n\n1. New SwiftUI features\n2. AI advances\n3. Cloud computing trends\n\nRead more...",
            date: Date().addingTimeInterval(-7200),
            isRead: true,
            hasAttachments: true
        ),
        Email(
            from: "support@service.com",
            to: ["me@example.com"],
            subject: "Your subscription renewal",
            body: "Your subscription is up for renewal. Click here to renew and continue enjoying our services.\n\nThank you!",
            date: Date().addingTimeInterval(-86400),
            isRead: false,
            hasAttachments: false
        ),
        Email(
            from: "friend@email.com",
            to: ["me@example.com"],
            subject: "Coffee this weekend?",
            body: "Hey! Would you like to grab coffee this weekend? Let me know what works for you.\n\nCheers!",
            date: Date().addingTimeInterval(-172800),
            isRead: true,
            isStarred: true,
            hasAttachments: false
        ),
        Email(
            from: "team@project.com",
            to: ["me@example.com", "others@project.com"],
            subject: "Project milestone completed",
            body: "Great news everyone! We've completed the first milestone of our project. Attached is the progress report.\n\nKeep up the great work!",
            date: Date().addingTimeInterval(-259200),
            isRead: true,
            hasAttachments: true
        )
    ]
}
