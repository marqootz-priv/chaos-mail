//
//  EmailListView.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import SwiftUI

struct EmailListView: View {
    @Bindable var mailStore: IntegratedMailStore
    
    var body: some View {
        List {
            if mailStore.isSyncing {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if mailStore.filteredEmails.isEmpty {
                ContentUnavailableView(
                    "No Emails",
                    systemImage: "tray",
                    description: Text("No emails in \(mailStore.selectedFolder.rawValue)")
                )
            } else {
                ForEach(mailStore.filteredEmails) { email in
                    NavigationLink {
                        EmailDetailView(email: email, mailStore: mailStore)
                    } label: {
                        EmailRowView(email: email, mailStore: mailStore)
                    }
                }
            }
        }
        .navigationTitle(mailStore.selectedFolder.rawValue)
        .searchable(text: $mailStore.searchText, prompt: "Search emails")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        try? await mailStore.syncCurrentFolder()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

struct EmailRowView: View {
    let email: Email
    @Bindable var mailStore: IntegratedMailStore
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Unread indicator dot
            if !email.isRead {
                Circle()
                    .fill(.blue)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
            } else {
                // Spacer to align content when read
                Circle()
                    .fill(.clear)
                    .frame(width: 8, height: 8)
            }
            
            // Sender avatar/icon
            CompanyAvatarView(email: email.from, size: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                // Subject and timestamp (first line)
                HStack {
                    Text(email.subject)
                        .fontWeight(email.isRead ? .regular : .semibold)
                        .font(.body)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        if email.hasAttachments {
                            Image(systemName: "paperclip")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        Text(email.date, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Sender (second line)
                Text(email.from)
                    .fontWeight(email.isRead ? .regular : .semibold)
                    .font(.body)
                    .lineLimit(1)
                
                // Preview (2 lines)
                Text(email.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            // Star indicator (moved to right)
            Button {
                mailStore.toggleStarred(email: email)
            } label: {
                Image(systemName: email.isStarred ? "star.fill" : "star")
                    .foregroundStyle(email.isStarred ? .yellow : .clear)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button {
                Task {
                    try? await mailStore.toggleRead(email: email)
                }
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
                        Task {
                            try? await mailStore.moveToFolder(email: email, folder: folder)
                        }
                    } label: {
                        Label(folder.rawValue, systemImage: folder.icon)
                    }
                }
            }
            
            Divider()
            
            Button(role: .destructive) {
                Task {
                    try? await mailStore.deleteEmail(email: email)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task {
                    try? await mailStore.toggleRead(email: email)
                }
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
                Task {
                    try? await mailStore.deleteEmail(email: email)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            
            Button {
                Task {
                    try? await mailStore.moveToFolder(email: email, folder: .archive)
                }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.green)
        }
    }
}

#Preview {
    NavigationStack {
        EmailListView(mailStore: IntegratedMailStore(accountManager: AccountManager()))
    }
}
