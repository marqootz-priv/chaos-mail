//
//  Email.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import Foundation

struct Email: Identifiable, Hashable {
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
        hasAttachments: Bool = false
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
        self.hasAttachments = hasAttachments
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
