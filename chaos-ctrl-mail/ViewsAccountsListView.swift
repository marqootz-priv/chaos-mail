//
//  AccountsListView.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import SwiftUI

struct AccountsListView: View {
    @Bindable var accountManager: AccountManager
    var mailStore: IntegratedMailStore?
    @State private var showingAddAccount = false
    @State private var accountToEdit: MailAccount?
    @State private var accountToDelete: MailAccount?
    @State private var showDeleteConfirmation = false
    @State private var showClearCacheConfirmation = false
    
    var body: some View {
        List {
            if accountManager.accounts.isEmpty {
                ContentUnavailableView(
                    "No Accounts",
                    systemImage: "envelope.badge",
                    description: Text("Add an email account to get started")
                )
            } else {
                Section("Accounts") {
                    ForEach(accountManager.accounts) { account in
                        AccountRowView(
                            account: account,
                            isSelected: accountManager.selectedAccount?.id == account.id
                        )
                        .onTapGesture {
                            accountManager.selectAccount(account)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                accountToDelete = account
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            
                            Button {
                                accountToEdit = account
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Dev: Clear cache button (only show if mailStore is available)
                if mailStore != nil {
                    Button {
                        showClearCacheConfirmation = true
                    } label: {
                        Label("Clear Cache", systemImage: "trash.circle")
                    }
                }
                
                Button {
                    showingAddAccount = true
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            AccountSetupView(accountManager: accountManager)
        }
        .sheet(item: $accountToEdit) { account in
            AccountSetupView(accountManager: accountManager, editingAccount: account)
        }
        .alert("Delete Account", isPresented: $showDeleteConfirmation, presenting: accountToDelete) { account in
            Button("Cancel", role: .cancel) {
                accountToDelete = nil
            }
            Button("Delete", role: .destructive) {
                accountManager.deleteAccount(account)
                accountToDelete = nil
            }
        } message: { account in
            Text("Are you sure you want to delete '\(account.name)'? This will remove all account data and credentials.")
        }
        .alert("Clear Email Cache", isPresented: $showClearCacheConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                Task {
                    await mailStore?.clearCache()
                }
            }
        } message: {
            Text("This will clear all cached emails for the current account. Emails will be re-fetched from the server on next sync.")
        }
    }
}

struct AccountRowView: View {
    let account: MailAccount
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.provider.icon)
                .font(.title2)
                .foregroundStyle(isSelected ? .blue : .secondary)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.headline)
                
                Text(account.emailAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 4) {
                    Image(systemName: account.isActive ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(account.isActive ? .green : .red)
                    
                    Text(account.isActive ? "Active" : "Inactive")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text(account.provider.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        AccountsListView(accountManager: AccountManager(), mailStore: nil)
    }
}
