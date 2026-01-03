//
//  EmailDetailView.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import SwiftUI

struct EmailDetailView: View {
    let email: Email
    @Bindable var mailStore: MailStore
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(email.subject)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Button {
                            mailStore.toggleStarred(email: email)
                        } label: {
                            Image(systemName: email.isStarred ? "star.fill" : "star")
                                .foregroundStyle(email.isStarred ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Divider()
                    
                    HStack(alignment: .top) {
                        // Avatar
                        Circle()
                            .fill(.blue.gradient)
                            .frame(width: 40, height: 40)
                            .overlay {
                                Text(String(email.from.prefix(1).uppercased()))
                                    .foregroundStyle(.white)
                                    .fontWeight(.semibold)
                            }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(email.from)
                                .fontWeight(.semibold)
                            
                            HStack(spacing: 4) {
                                Text("to")
                                    .foregroundStyle(.secondary)
                                Text(email.to.joined(separator: ", "))
                            }
                            .font(.caption)
                        }
                        
                        Spacer()
                        
                        Text(email.date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text(email.date, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.quaternary.opacity(0.5))
                .cornerRadius(8)
                
                // Body
                Text(email.body)
                    .textSelection(.enabled)
                    .padding()
                
                if email.hasAttachments {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Attachments")
                            .font(.headline)
                        
                        HStack {
                            Image(systemName: "doc.fill")
                            Text("document.pdf")
                            Spacer()
                            Text("2.3 MB")
                                .foregroundStyle(.secondary)
                            Button {
                                // Download attachment
                            } label: {
                                Image(systemName: "arrow.down.circle")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .background(.quaternary.opacity(0.5))
                        .cornerRadius(8)
                    }
                    .padding()
                }
                
                Spacer()
            }
            .padding()
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
                    mailStore.toggleRead(email: email)
                } label: {
                    Label(
                        email.isRead ? "Mark as Unread" : "Mark as Read",
                        systemImage: email.isRead ? "envelope.badge" : "envelope.open"
                    )
                }
                
                Menu {
                    ForEach(MailFolder.allCases.filter { $0 != email.folder }) { folder in
                        Button {
                            mailStore.moveToFolder(email: email, folder: folder)
                        } label: {
                            Label(folder.rawValue, systemImage: folder.icon)
                        }
                    }
                } label: {
                    Label("Move to...", systemImage: "folder")
                }
                
                Button(role: .destructive) {
                    mailStore.deleteEmail(email: email)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .onAppear {
            if !email.isRead {
                mailStore.toggleRead(email: email)
            }
        }
    }
}

#Preview {
    EmailDetailView(
        email: Email.sampleEmails[0],
        mailStore: MailStore()
    )
}
