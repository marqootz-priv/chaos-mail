//
//  MailStore.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import Foundation
import Observation

@Observable
class MailStore {
    var emails: [Email]
    var selectedFolder: MailFolder = .inbox
    var selectedEmail: Email?
    var searchText: String = ""
    
    init() {
        self.emails = Email.sampleEmails
    }
    
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
    
    func toggleRead(email: Email) {
        if let index = emails.firstIndex(where: { $0.id == email.id }) {
            emails[index].isRead.toggle()
        }
    }
    
    func toggleStarred(email: Email) {
        if let index = emails.firstIndex(where: { $0.id == email.id }) {
            emails[index].isStarred.toggle()
        }
    }
    
    func moveToFolder(email: Email, folder: MailFolder) {
        if let index = emails.firstIndex(where: { $0.id == email.id }) {
            emails[index].folder = folder
            if selectedEmail?.id == email.id {
                selectedEmail = nil
            }
        }
    }
    
    func deleteEmail(email: Email) {
        if email.folder == .trash {
            emails.removeAll { $0.id == email.id }
            if selectedEmail?.id == email.id {
                selectedEmail = nil
            }
        } else {
            moveToFolder(email: email, folder: .trash)
        }
    }
    
    func composeEmail(to: [String], subject: String, body: String) {
        let newEmail = Email(
            from: "me@example.com",
            to: to,
            subject: subject,
            body: body,
            date: Date(),
            isRead: true,
            folder: .sent
        )
        emails.append(newEmail)
    }
}
