//
//  SidebarView.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import SwiftUI

struct SidebarView: View {
    @Bindable var mailStore: IntegratedMailStore
    @Bindable var accountManager: AccountManager
    @State private var showingQuickSetup = false
    
    var body: some View {
        List {
            // Account selector
            if let selectedAccount = accountManager.selectedAccount {
                Section {
                    NavigationLink {
                        AccountsListView(accountManager: accountManager, mailStore: mailStore)
                    } label: {
                        HStack {
                            Image(systemName: selectedAccount.provider.icon)
                                .foregroundStyle(.blue)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedAccount.name)
                                    .font(.headline)
                                Text(selectedAccount.emailAddress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Quick add account button
                    Button {
                        showingQuickSetup = true
                    } label: {
                        Label("Add Account", systemImage: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }
            } else {
                Section {
                    Button {
                        showingQuickSetup = true
                    } label: {
                        Label("Add Account", systemImage: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            Section("Mailboxes") {
                ForEach(MailFolder.allCases) { folder in
                    NavigationLink {
                        EmailListView(mailStore: mailStore)
                            .onAppear {
                                print("DEBUG: SidebarView.onAppear - Folder: \(folder.rawValue)")
                                print("DEBUG: SidebarView.onAppear - Setting selectedFolder to \(folder.rawValue)")
                                mailStore.selectedFolder = folder
                                print("DEBUG: SidebarView.onAppear - selectedFolder set, current value=\(mailStore.selectedFolder.rawValue)")
                                
                                // Load cached emails immediately (no network call)
                                Task {
                                    print("DEBUG: SidebarView.onAppear - Task started, calling loadCachedEmails")
                                    await mailStore.loadCachedEmails()
                                    print("DEBUG: SidebarView.onAppear - loadCachedEmails completed")
                                    
                                    // Only sync if connected and cache is stale
                                    print("DEBUG: SidebarView.onAppear - Checking connection: isConnected=\(mailStore.emailService.isConnected)")
                                    if mailStore.emailService.isConnected {
                                        print("DEBUG: SidebarView.onAppear - Connected, checking cache validity")
                                        let cacheValid = await mailStore.isCacheValid()
                                        print("DEBUG: SidebarView.onAppear - Cache valid=\(cacheValid)")
                                        if !cacheValid {
                                            print("DEBUG: SidebarView.onAppear - Cache stale, starting sync")
                                            try? await mailStore.syncCurrentFolder(incremental: true, force: false)
                                            print("DEBUG: SidebarView.onAppear - Sync completed")
                                        } else {
                                            print("DEBUG: SidebarView.onAppear - Cache valid, skipping sync")
                                        }
                                    } else {
                                        print("DEBUG: SidebarView.onAppear - Not connected, skipping sync")
                                    }
                                    print("DEBUG: SidebarView.onAppear - Task completed")
                                }
                            }
                    } label: {
                        folderRow(for: folder)
                    }
                }
            }
        }
        .navigationTitle("Mailboxes")
        .sheet(isPresented: $showingQuickSetup) {
            QuickAccountSetupView(accountManager: accountManager)
        }
    }
    
    @ViewBuilder
    private func folderRow(for folder: MailFolder) -> some View {
        let unreadCount = mailStore.unreadCount[folder] ?? 0
        
        HStack {
            Label(folder.rawValue, systemImage: folder.icon)
            Spacer()
            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
            }
        }
    }
}

#Preview {
    NavigationStack {
        SidebarView(mailStore: IntegratedMailStore(accountManager: AccountManager()), accountManager: AccountManager())
    }
}
