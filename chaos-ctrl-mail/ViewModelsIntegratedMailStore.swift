//
//  IntegratedMailStore.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import Foundation
import Observation

@Observable
class IntegratedMailStore {
    var emails: [Email] = []
    var selectedFolder: MailFolder = .inbox
    var selectedEmail: Email?
    var searchText: String = ""
    
    var emailService: EmailService
    var accountManager: AccountManager
    var oauth2Manager = OAuth2Manager()
    
    var isSyncing: Bool = false
    var lastError: Error?
    var lastSyncDate: Date?
    private var syncTimer: Timer?
    
    init(emailService: EmailService = EmailService(), accountManager: AccountManager) {
        self.emailService = emailService
        self.accountManager = accountManager
    }
    
    deinit {
        stopPeriodicSync()
    }
    
    // MARK: - Cache Management
    
    /// Load cached emails for the current account and folder (instant display)
    func loadCachedEmails() async {
        guard let account = accountManager.selectedAccount else { return }
        
        let startTime = Date()
        let cachedEmails = await EmailPersistenceManager.shared.loadCachedEmails(
            accountId: account.id,
            folder: selectedFolder
        )
        let duration = Date().timeIntervalSince(startTime)
        
        if !cachedEmails.isEmpty {
            emails = cachedEmails.map { $0.toEmail() }
            print("PERF: loadCachedEmails - Loaded \(cachedEmails.count) cached emails in \(String(format: "%.3f", duration))s")
        } else {
            print("PERF: loadCachedEmails - No cached emails found")
        }
    }
    
    /// Check if cache is valid (not stale)
    func isCacheValid() async -> Bool {
        guard let account = accountManager.selectedAccount else { return false }
        return await EmailPersistenceManager.shared.isCacheValid(
            accountId: account.id,
            folder: selectedFolder
        )
    }
    
    /// Save emails to cache with metadata
    private func saveEmailsToCache(_ cachedEmails: [CachedEmail]) async {
        guard let account = accountManager.selectedAccount else { return }
        do {
            try await EmailPersistenceManager.shared.saveCachedEmails(
                cachedEmails,
                accountId: account.id,
                folder: selectedFolder
            )
        } catch {
            print("IntegratedMailStore: Failed to save emails to cache: \(error)")
        }
    }
    
    /// Merge new emails with existing cache (incremental sync)
    private func mergeEmailsToCache(_ newCachedEmails: [CachedEmail]) async {
        guard let account = accountManager.selectedAccount else { return }
        do {
            try await EmailPersistenceManager.shared.mergeCachedEmails(
                newCachedEmails,
                accountId: account.id,
                folder: selectedFolder
            )
        } catch {
            print("IntegratedMailStore: Failed to merge emails to cache: \(error)")
        }
    }
    
    /// Clear all cached emails for the current account (for dev/testing)
    func clearCache() async {
        guard let account = accountManager.selectedAccount else { return }
        await EmailPersistenceManager.shared.clearCache(for: account.id)
        print("IntegratedMailStore: Cleared cache for account \(account.emailAddress)")
    }
    
    // MARK: - Periodic Sync
    
    /// Start periodic background sync (every 5 minutes)
    func startPeriodicSync(interval: TimeInterval = 300) {
        stopPeriodicSync() // Stop any existing timer
        
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.emailService.isConnected else { return }
                // Only sync if cache is stale
                if !(await self.isCacheValid()) {
                    print("PERF: Periodic sync triggered - cache is stale")
                    try? await self.syncCurrentFolder(incremental: true)
                } else {
                    print("PERF: Periodic sync skipped - cache is still valid")
                }
            }
        }
        print("PERF: Started periodic sync (every \(interval)s)")
    }
    
    /// Stop periodic background sync
    func stopPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    // MARK: - Connection
    
    func connectToAccount(_ account: MailAccount) async throws {
        guard let password = account.password else {
            print("ERROR: Password not found in Keychain for account \(account.id.uuidString)")
            print("Account email: \(account.emailAddress), authType: \(account.authType)")
            print("This account may need to be re-added, or the password wasn't saved during setup.")
            throw EmailServiceError.invalidCredentials
        }
        
        // Load cached emails first for instant display
        await loadCachedEmails()
        
        try await emailService.connect(account: account)
        
        // Sync in background (incremental if cache exists, full if not)
        let cacheValid = await isCacheValid()
        try await syncCurrentFolder(incremental: cacheValid, force: false)
        
        // Start periodic background sync
        startPeriodicSync()
    }
    
    func connectWithOAuth2(_ account: MailAccount) async throws {
        // Check if this is an Apple Sign In account (which cannot access IMAP/SMTP)
        if account.imapServer == "apple-signin" || account.emailAddress.contains("@privaterelay.appleid.com") {
            throw EmailServiceError.serverError("Apple Sign In accounts cannot access email via IMAP/SMTP. Please add your iCloud account manually using an app-specific password.")
        }
        
        // Load cached emails first for instant display
        await loadCachedEmails()
        
        // Check if we have a valid token
        if let token = account.oauthToken, !token.isExpired {
            // Use existing token
            try await useOAuth2Token(token, for: account)
        } else if let token = account.oauthToken, let config = OAuth2Manager.OAuth2Config.config(for: account.provider) {
            // Refresh token
            let newToken = try await oauth2Manager.refreshToken(token, config: config)
            try KeychainManager.shared.saveOAuth2Token(newToken, for: account.id)
            try await useOAuth2Token(newToken, for: account)
        } else {
            // Authenticate with OAuth2
            let token = try await oauth2Manager.authenticate(provider: account.provider)
            try KeychainManager.shared.saveOAuth2Token(token, for: account.id)
            try await useOAuth2Token(token, for: account)
        }
        
        // Sync in background (incremental if cache exists, full if not)
        let cacheValid = await isCacheValid()
        try await syncCurrentFolder(incremental: cacheValid, force: false)
        
        // Start periodic background sync
        startPeriodicSync()
    }
    
    private func useOAuth2Token(_ token: OAuth2Token, for account: MailAccount) async throws {
        // Create a modified account with OAuth2 access token
        var modifiedAccount = account
        // Store the access token temporarily for this session
        // In production, you'd pass this to the IMAP/SMTP sessions
        try await emailService.connect(account: modifiedAccount)
    }
    
    func disconnect() async {
        stopPeriodicSync()
        await emailService.disconnect()
    }
    
    // MARK: - Sync
    
    /// Sync current folder with smart caching strategy
    /// - Parameter incremental: If true, only fetch emails since last known UID
    /// - Parameter force: If true, sync even if cache is valid
    func syncCurrentFolder(incremental: Bool = false, force: Bool = false) async throws {
        let startTime = Date()
        print("PERF: syncCurrentFolder - Starting sync for folder: \(selectedFolder.rawValue), incremental: \(incremental), force: \(force)")
        
        guard emailService.isConnected else {
            print("PERF: syncCurrentFolder - Failed: not connected")
            throw EmailServiceError.notConnected
        }
        
        // Check if cache is valid (unless forced)
        if !force {
            let cacheValid = await isCacheValid()
            if cacheValid {
                print("PERF: syncCurrentFolder - Cache is valid, skipping sync")
                return
            }
        }
        
        isSyncing = true
        defer { 
            isSyncing = false
            let duration = Date().timeIntervalSince(startTime)
            print("PERF: syncCurrentFolder - Completed in \(String(format: "%.3f", duration))s, emails count: \(emails.count)")
        }
        
        do {
            guard let account = accountManager.selectedAccount else {
                throw EmailServiceError.notConnected
            }
            
            let fetchStartTime = Date()
            var cachedEmails: [CachedEmail] = []
            
            if incremental {
                // Incremental sync: fetch only new emails since last UID
                let metadata = await EmailPersistenceManager.shared.loadMetadata(
                    accountId: account.id,
                    folder: selectedFolder
                )
                let lastUID = metadata?.highestUID ?? "0"
                
                let results = try await emailService.fetchEmailsSince(
                    uid: lastUID,
                    folder: mapFolderToIMAP(selectedFolder),
                    limit: 50
                )
                
                // Convert to CachedEmail
                cachedEmails = results.map { result in
                    CachedEmail(
                        from: result.email,
                        imapUID: result.uid,
                        flags: result.flags
                    )
                }
                
                // Merge with existing cache
                await mergeEmailsToCache(cachedEmails)
                
                // Reload all cached emails to update UI
                let allCached = await EmailPersistenceManager.shared.loadCachedEmails(
                    accountId: account.id,
                    folder: selectedFolder
                )
                emails = allCached.map { $0.toEmail() }
                
            } else {
                // Full sync: fetch all emails (for initial load or pull-to-refresh)
                let fetchedEmails = try await emailService.fetchEmails(folder: selectedFolder, limit: 50)
                
                // Convert to CachedEmail with UIDs (use sequence numbers as UIDs for now)
                cachedEmails = fetchedEmails.enumerated().map { index, email in
                    CachedEmail(
                        from: email,
                        imapUID: String(index + 1),
                        flags: email.isRead ? ["\\Seen"] : []
                    )
                }
                
                // Save to cache
                await saveEmailsToCache(cachedEmails)
                
                // Update UI
                emails = fetchedEmails
            }
            
            let fetchDuration = Date().timeIntervalSince(fetchStartTime)
            print("PERF: syncCurrentFolder - Fetched \(cachedEmails.count) emails from server in \(String(format: "%.3f", fetchDuration))s")
            
            lastError = nil
            lastSyncDate = Date()
            
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            print("PERF: syncCurrentFolder - Failed after \(String(format: "%.3f", duration))s: \(error)")
            lastError = error
            throw error
        }
    }
    
    /// Map MailFolder to IMAP folder name
    private func mapFolderToIMAP(_ folder: MailFolder) -> String {
        switch folder {
        case .inbox: return "INBOX"
        case .sent: return "Sent"
        case .drafts: return "Drafts"
        case .trash: return "Trash"
        case .spam: return "Spam"
        case .archive: return "Archive"
        }
    }
    
    func syncAllFolders() async throws {
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            let results = try await emailService.syncAllFolders()
            // Merge all emails
            emails = results.values.flatMap { $0 }
            lastError = nil
        } catch {
            lastError = error
            throw error
        }
    }
    
    // MARK: - Filtered Emails
    
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
    
    // MARK: - Email Operations
    
    func toggleRead(email: Email) async throws {
        if email.isRead {
            try await emailService.markAsUnread(email: email)
        } else {
            try await emailService.markAsRead(email: email)
        }
        
        if let index = emails.firstIndex(where: { $0.id == email.id }) {
            emails[index].isRead.toggle()
        }
    }
    
    func toggleStarred(email: Email) {
        // Local only for now - would need IMAP flag support
        if let index = emails.firstIndex(where: { $0.id == email.id }) {
            emails[index].isStarred.toggle()
        }
    }
    
    func moveToFolder(email: Email, folder: MailFolder) async throws {
        try await emailService.moveEmail(email: email, to: folder)
        
        if let index = emails.firstIndex(where: { $0.id == email.id }) {
            emails[index].folder = folder
            if selectedEmail?.id == email.id {
                selectedEmail = nil
            }
        }
    }
    
    func deleteEmail(email: Email) async throws {
        if email.folder == .trash {
            try await emailService.deleteEmail(email: email, permanently: true)
            emails.removeAll { $0.id == email.id }
        } else {
            try await emailService.deleteEmail(email: email, permanently: false)
            if let index = emails.firstIndex(where: { $0.id == email.id }) {
                emails[index].folder = .trash
            }
        }
        
        if selectedEmail?.id == email.id {
            selectedEmail = nil
        }
    }
    
    func sendEmail(to: [String], subject: String, body: String) async throws {
        guard let account = accountManager.selectedAccount else {
            throw EmailServiceError.notConnected
        }
        
        try await emailService.sendEmail(
            to: to,
            subject: subject,
            body: body,
            from: account.emailAddress
        )
        
        // Add to sent folder locally
        let sentEmail = Email(
            from: account.emailAddress,
            to: to,
            subject: subject,
            body: body,
            date: Date(),
            isRead: true,
            folder: .sent
        )
        emails.append(sentEmail)
    }
}
