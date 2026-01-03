//
//  EmailListView.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import SwiftUI

struct EmailListView: View {
    @Bindable var mailStore: MailStore
    
    var body: some View {
        List {
            ForEach(mailStore.filteredEmails) { email in
                NavigationLink {
                    EmailDetailView(email: email, mailStore: mailStore)
                } label: {
                    EmailRowView(email: email, mailStore: mailStore)
                }
            }
        }
        .navigationTitle(mailStore.selectedFolder.rawValue)
        .searchable(text: $mailStore.searchText, prompt: "Search emails")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // Compose new email
                } label: {
                    Label("Compose", systemImage: "square.and.pencil")
                }
            }
        }
    }
}

struct EmailRowView: View {
    let email: Email
    @Bindable var mailStore: MailStore
    
    var body: some View {
        HStack(spacing: 12) {
            // Star indicator
            Button {
                mailStore.toggleStarred(email: email)
            } label: {
                Image(systemName: email.isStarred ? "star.fill" : "star")
                    .foregroundStyle(email.isStarred ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(email.from)
                        .fontWeight(email.isRead ? .regular : .semibold)
                    
                    Spacer()
                    
                    if email.hasAttachments {
                        Image(systemName: "paperclip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(email.date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(email.subject)
                    .fontWeight(email.isRead ? .regular : .semibold)
                    .lineLimit(1)
                
                Text(email.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            if !email.isRead {
                Circle()
                    .fill(.blue)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                mailStore.toggleRead(email: email)
            } label: {
                Label(
                    email.isRead ? "Mark as Unread" : "Mark as Read",
                    systemImage: email.isRead ? "envelope.badge" : "envelope.open"
                )
            }
            
            Button {
                mailStore.toggleStarred(email: email)
            } label: {
                Label(
                    email.isStarred ? "Unstar" : "Star",
                    systemImage: email.isStarred ? "star.slash" : "star"
                )
            }
            
            Divider()
            
            Menu("Move to...") {
                ForEach(MailFolder.allCases.filter { $0 != email.folder }) { folder in
                    Button {
                        mailStore.moveToFolder(email: email, folder: folder)
                    } label: {
                        Label(folder.rawValue, systemImage: folder.icon)
                    }
                }
            }
            
            Divider()
            
            Button(role: .destructive) {
                mailStore.deleteEmail(email: email)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                mailStore.toggleRead(email: email)
            } label: {
                Label(
                    email.isRead ? "Unread" : "Read",
                    systemImage: email.isRead ? "envelope.badge" : "envelope.open"
                )
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                mailStore.deleteEmail(email: email)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            
            Button {
                mailStore.moveToFolder(email: email, folder: .archive)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.green)
        }
    }
}

#Preview {
    NavigationStack {
        EmailListView(mailStore: MailStore())
    }
}
