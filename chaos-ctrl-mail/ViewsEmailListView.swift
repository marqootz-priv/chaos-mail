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
            if mailStore.filteredEmails.isEmpty {
                if mailStore.isSyncing {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ContentUnavailableView(
                        "No Emails",
                        systemImage: "tray",
                        description: Text("No emails in \(mailStore.selectedFolder.rawValue)")
                    )
                }
            } else {
                ForEach(mailStore.conversationThreads) { conversation in
                    NavigationLink {
                        ConversationDetailView(conversation: conversation, mailStore: mailStore)
                    } label: {
                        ConversationRowView(conversation: conversation)
                    }
                }
            }
        }
        .navigationTitle(mailStore.selectedFolder.rawValue)
        .searchable(text: $mailStore.searchText, prompt: "Search emails")
        .onAppear {
            let startTime = Date()
            let emailCount = mailStore.filteredEmails.count
            print("PERF: EmailListView - Started rendering list view for folder: \(mailStore.selectedFolder.rawValue), emails: \(emailCount)")
            DispatchQueue.main.async {
                let duration = Date().timeIntervalSince(startTime)
                print("PERF: EmailListView - Rendered list in \(String(format: "%.3f", duration))s")
            }
        }
        .refreshable {
            // Pull-to-refresh: force immediate sync
            print("PERF: EmailListView - Pull-to-refresh triggered")
            try? await mailStore.syncCurrentFolder(incremental: false, force: true)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        // Manual refresh: force immediate sync
                        print("PERF: EmailListView - Manual refresh triggered")
                        try? await mailStore.syncCurrentFolder(incremental: false, force: true)
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

struct ConversationRowView: View {
    let conversation: ConversationThread
    
    private var latestMessage: ConversationMessage { conversation.messages.last! }
    private var latestEmail: Email { latestMessage.fullEmail }
    private var hasAttachments: Bool { conversation.messages.contains { $0.fullEmail.hasAttachments } }
    private var attachmentSummary: String? {
        let attachments = conversation.messages.flatMap { $0.fullEmail.attachments }
        guard !attachments.isEmpty else { return nil }
        let count = attachments.count
        let total = attachments.reduce(0) { $0 + $1.size }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        let sizeText = formatter.string(fromByteCount: Int64(total))
        return count > 1 ? "\(count) • \(sizeText)" : sizeText
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Unread indicator
            if conversation.isUnread {
                Circle()
                    .fill(.blue)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
            } else {
                Circle()
                    .fill(.clear)
                    .frame(width: 8, height: 8)
            }
            
            CompanyAvatarView(email: latestEmail.from, size: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.subject)
                        .fontWeight(conversation.isUnread ? .semibold : .regular)
                        .font(.body)
                        .lineLimit(1)
                    Spacer()
                    HStack(spacing: 4) {
                        if hasAttachments {
                            Image(systemName: "paperclip")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let summary = attachmentSummary {
                                Text(summary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(conversation.updatedAt, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if conversation.isUnread {
                            Text("\(conversation.messages.filter { !$0.isRead }.count)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
                
                HStack(spacing: 6) {
                    Text(latestMessage.displayName)
                        .fontWeight(conversation.isUnread ? .semibold : .regular)
                        .font(.body)
                        .lineLimit(1)
                    if conversation.participantEmails.count > 1 {
                        Text("+\(conversation.participantEmails.count - 1) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text(latestMessage.extractedBody.isEmpty ? latestEmail.preview : latestMessage.extractedBody)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }
}

struct ConversationDetailView: View {
    let conversation: ConversationThread
    @Bindable var mailStore: IntegratedMailStore
    
    var body: some View {
        List {
            ForEach(conversation.messages) { message in
                NavigationLink {
                    EmailDetailView(email: message.fullEmail, mailStore: mailStore)
                } label: {
                    MessageRowView(message: message)
                }
            }
        }
        .navigationTitle(conversation.subject)
    }
}

struct MessageRowView: View {
    let message: ConversationMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CompanyAvatarView(email: message.from, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(message.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(message.extractedBody.isEmpty ? message.fullEmail.preview : message.extractedBody)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 6)
    }
}

struct ConversationDetailView: View {
    let conversation: Conversation
    @Bindable var mailStore: IntegratedMailStore
    
    var body: some View {
        List {
            ForEach(conversation.emails) { email in
                NavigationLink {
                    EmailDetailView(email: email, mailStore: mailStore)
                } label: {
                    EmailRowView(email: email, mailStore: mailStore)
                }
            }
        }
        .navigationTitle(conversation.subject)
    }
}


struct EmailRowView: View {
    let email: Email
    @Bindable var mailStore: IntegratedMailStore
    
    private var attachmentSummary: String? {
        guard email.hasAttachments else { return nil }
        let total = email.attachments.reduce(0) { $0 + $1.size }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        let sizeText = formatter.string(fromByteCount: Int64(total))
        let count = email.attachments.count
        return count > 1 ? "\(count) • \(sizeText)" : sizeText
    }
    
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
                            if let summary = attachmentSummary {
                                Text(summary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
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
