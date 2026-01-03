//
//  EmailDetailView.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import SwiftUI

struct EmailDetailView: View {
    let email: Email
    @Bindable var mailStore: IntegratedMailStore
    @State private var htmlHeight: CGFloat = UIScreen.main.bounds.height * 0.9
    
    
    private func isHTML(_ content: String) -> Bool {
        let htmlTags = ["<html", "<!DOCTYPE", "<body", "<div", "<p", "<br", "<span", "<a href", "<img", "<table", "<h1", "<h2", "<h3", "<ul", "<ol", "<li"]
        let lowerContent = content.lowercased()
        return htmlTags.contains { lowerContent.contains($0.lowercased()) }
    }
    
    @State private var isToExpanded = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header - full width, no padding on sides
                VStack(alignment: .leading, spacing: 16) {
                    // Subject
                    Text(email.subject)
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    HStack(alignment: .top, spacing: 12) {
                        // Avatar
                        CompanyAvatarView(email: email.from, size: 50)
                            .padding(.leading)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            // Sender name
                            Text(email.from)
                                .fontWeight(.semibold)
                                .font(.body)
                            
                            // To field - collapsible
                            if isToExpanded {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        Text("to")
                                            .foregroundStyle(.secondary)
                                        Button {
                                            isToExpanded = false
                                        } label: {
                                            Image(systemName: "chevron.down")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .font(.caption)
                                    
                                    Text(email.to.joined(separator: ", "))
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            } else {
                                Button {
                                    isToExpanded = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("to")
                                            .foregroundStyle(.secondary)
                                        if !email.to.isEmpty {
                                            Text(email.to[0])
                                                .foregroundStyle(.secondary)
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        Spacer()
                        
                        // Timestamp
                        Text(email.date, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.trailing)
                    }
                    .padding(.vertical, 8)
                }
                
                Divider()
                    .padding(.vertical, 8)
                
                // Body - full width, expands to at least screen height, scrolls if longer
                Group {
                    if isHTML(email.body) {
                        HTMLView(htmlContent: email.body) { height in
                            htmlHeight = max(height, UIScreen.main.bounds.height * 0.9)
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: htmlHeight,
                            maxHeight: htmlHeight,
                            alignment: .topLeading
                        )
                    } else {
                        Text(email.body)
                            .textSelection(.enabled)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: UIScreen.main.bounds.height * 0.9,
                                alignment: .topLeading
                            )
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom)
                
                if !email.attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Attachments")
                            .font(.headline)
                            .padding(.horizontal)
                            .padding(.top)
                        
                        ForEach(email.attachments) { attachment in
                            HStack {
                                Image(systemName: attachmentIcon(for: attachment.mimeType))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(attachment.filename)
                                        .font(.body)
                                        .lineLimit(1)
                                    Text(formatSize(attachment.size))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    // TODO: Download or share attachment
                                } label: {
                                    Image(systemName: "arrow.down.circle")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding()
                            .background(.quaternary.opacity(0.5))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom)
                }
            }
        }
        .navigationTitle("Email")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    // Reply
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
                
                Button {
                    // Reply All
                } label: {
                    Label("Reply All", systemImage: "arrowshape.turn.up.left.2")
                }
                
                Button {
                    // Forward
                } label: {
                    Label("Forward", systemImage: "arrowshape.turn.up.right")
                }
                
                Divider()
                
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
                
                Menu {
                    ForEach(MailFolder.allCases.filter { $0 != email.folder }) { folder in
                        Button {
                            Task {
                                try? await mailStore.moveToFolder(email: email, folder: folder)
                            }
                        } label: {
                            Label(folder.rawValue, systemImage: folder.icon)
                        }
                    }
                } label: {
                    Label("Move to...", systemImage: "folder")
                }
                
                Button(role: .destructive) {
                    Task {
                        try? await mailStore.deleteEmail(email: email)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .onAppear {
            if !email.isRead {
                Task {
                    try? await mailStore.toggleRead(email: email)
                }
            }
        }
    }

    private func attachmentIcon(for mimeType: String) -> String {
        let type = mimeType.lowercased()
        if type.contains("pdf") { return "doc.richtext.fill" }
        if type.contains("image") { return "photo.fill" }
        if type.contains("video") { return "video.fill" }
        if type.contains("audio") { return "music.note" }
        if type.contains("zip") || type.contains("compressed") { return "archivebox.fill" }
        return "doc.fill"
    }
    
    private func formatSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

#Preview {
    EmailDetailView(
        email: Email.sampleEmails[0],
        mailStore: IntegratedMailStore(accountManager: AccountManager())
    )
}
