//
//  AccountManager.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import Foundation
import Observation

@Observable
class AccountManager {
    var accounts: [MailAccount] = []
    var selectedAccount: MailAccount?
    
    init() {
        loadAccounts()
        if accounts.isEmpty {
            // No accounts configured yet
            selectedAccount = nil
        } else {
            selectedAccount = accounts.first
        }
    }
    
    func addAccount(_ account: MailAccount) {
        accounts.append(account)
        if selectedAccount == nil {
            selectedAccount = account
        }
        saveAccounts()
    }
    
    func updateAccount(_ account: MailAccount) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
            if selectedAccount?.id == account.id {
                selectedAccount = account
            }
            saveAccounts()
        }
    }
    
    func deleteAccount(_ account: MailAccount) {
        // Remove account credentials from Keychain
        try? KeychainManager.shared.deleteAccountPassword(for: account.id)
        try? KeychainManager.shared.deleteOAuth2Token(for: account.id)
        
        // Remove account from list
        accounts.removeAll { $0.id == account.id }
        if selectedAccount?.id == account.id {
            selectedAccount = accounts.first
        }
        saveAccounts()
    }
    
    func selectAccount(_ account: MailAccount) {
        selectedAccount = account
    }
    
    // MARK: - Persistence
    
    private func saveAccounts() {
        if let encoded = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(encoded, forKey: "mailAccounts")
        }
    }
    
    private func loadAccounts() {
        if let data = UserDefaults.standard.data(forKey: "mailAccounts"),
           let decoded = try? JSONDecoder().decode([MailAccount].self, from: data) {
            accounts = decoded
        }
    }
}
