//
//  EmailPersistenceManager.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import Foundation

/// Manages persistence of emails to disk with metadata tracking for smart caching
actor EmailPersistenceManager {
    static let shared = EmailPersistenceManager()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let cacheValidityInterval: TimeInterval = 300 // 5 minutes
    
    private init() {
        // Store in app's application support directory (persistent, not cleared by system)
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDirectory = appSupport.appendingPathComponent("EmailCache", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Cache Operations
    
    /// Save cached emails with metadata for a specific account and folder
    func saveCachedEmails(_ cachedEmails: [CachedEmail], accountId: UUID, folder: MailFolder) async throws {
        let folderCache = cacheDirectory.appendingPathComponent("\(accountId.uuidString)_\(folder.rawValue)", isDirectory: true)
        try fileManager.createDirectory(at: folderCache, withIntermediateDirectories: true)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        // Save each email as individual file (for easier incremental updates)
        for cachedEmail in cachedEmails {
            let fileURL = folderCache.appendingPathComponent("\(cachedEmail.imapUID).json")
            let data = try encoder.encode(cachedEmail)
            try data.write(to: fileURL, options: .atomic)
        }
        
        // Save metadata
        let highestUID = cachedEmails.map { Int($0.imapUID) ?? 0 }.max() ?? 0
        let metadata = CacheMetadata(
            folder: folder.rawValue,
            lastSyncDate: Date(),
            highestUID: String(highestUID),
            totalEmails: cachedEmails.count
        )
        
        let metadataURL = folderCache.appendingPathComponent("_metadata.json")
        let metadataData = try encoder.encode(metadata)
        try metadataData.write(to: metadataURL, options: .atomic)
        
        print("EmailPersistence: Saved \(cachedEmails.count) cached emails to \(folder.rawValue), highestUID: \(highestUID)")
    }
    
    /// Load cached emails for a specific account and folder from disk
    func loadCachedEmails(accountId: UUID, folder: MailFolder) async -> [CachedEmail] {
        print("DEBUG: EmailPersistenceManager.loadCachedEmails - START")
        print("DEBUG: EmailPersistenceManager.loadCachedEmails - accountId=\(accountId), folder=\(folder.rawValue)")
        print("DEBUG: EmailPersistenceManager.loadCachedEmails - cacheDirectory=\(cacheDirectory.path)")
        
        let folderCache = cacheDirectory.appendingPathComponent("\(accountId.uuidString)_\(folder.rawValue)", isDirectory: true)
        print("DEBUG: EmailPersistenceManager.loadCachedEmails - folderCache.path=\(folderCache.path)")
        
        guard fileManager.fileExists(atPath: folderCache.path) else {
            print("DEBUG: EmailPersistenceManager.loadCachedEmails - Cache directory does not exist")
            print("EmailPersistence: No cache directory found for \(folder.rawValue)")
            return []
        }
        
        print("DEBUG: EmailPersistenceManager.loadCachedEmails - Cache directory exists")
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let files = try? fileManager.contentsOfDirectory(at: folderCache, includingPropertiesForKeys: nil) else {
            print("DEBUG: EmailPersistenceManager.loadCachedEmails - ERROR: Failed to list cache directory")
            print("EmailPersistence: Failed to list cache directory")
            return []
        }
        
        print("DEBUG: EmailPersistenceManager.loadCachedEmails - Found \(files.count) files in cache directory")
        
        var cachedEmails: [CachedEmail] = []
        var decodeSuccessCount = 0
        var decodeFailureCount = 0
        
        for fileURL in files {
            guard fileURL.pathExtension == "json" && !fileURL.lastPathComponent.contains("_metadata") else {
                print("DEBUG: EmailPersistenceManager.loadCachedEmails - Skipping file: \(fileURL.lastPathComponent)")
                continue
            }
            
            print("DEBUG: EmailPersistenceManager.loadCachedEmails - Processing file: \(fileURL.lastPathComponent)")
            
            if let data = try? Data(contentsOf: fileURL) {
                print("DEBUG: EmailPersistenceManager.loadCachedEmails - File loaded, size=\(data.count) bytes")
                if let cachedEmail = try? decoder.decode(CachedEmail.self, from: data) {
                    cachedEmails.append(cachedEmail)
                    decodeSuccessCount += 1
                    print("DEBUG: EmailPersistenceManager.loadCachedEmails - Successfully decoded email: \(cachedEmail.subject.prefix(50))")
                } else {
                    decodeFailureCount += 1
                    print("DEBUG: EmailPersistenceManager.loadCachedEmails - ERROR: Failed to decode email from file: \(fileURL.lastPathComponent)")
                }
            } else {
                decodeFailureCount += 1
                print("DEBUG: EmailPersistenceManager.loadCachedEmails - ERROR: Failed to read data from file: \(fileURL.lastPathComponent)")
            }
        }
        
        print("DEBUG: EmailPersistenceManager.loadCachedEmails - Decoded \(decodeSuccessCount) emails, failed \(decodeFailureCount)")
        
        // Sort by date (most recent first)
        cachedEmails.sort { $0.date > $1.date }
        
        print("DEBUG: EmailPersistenceManager.loadCachedEmails - Returning \(cachedEmails.count) cached emails")
        print("EmailPersistence: Loaded \(cachedEmails.count) cached emails from \(folder.rawValue)")
        return cachedEmails
    }
    
    /// Load cache metadata
    func loadMetadata(accountId: UUID, folder: MailFolder) async -> CacheMetadata? {
        let folderCache = cacheDirectory.appendingPathComponent("\(accountId.uuidString)_\(folder.rawValue)", isDirectory: true)
        let metadataURL = folderCache.appendingPathComponent("_metadata.json")
        
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return nil
        }
        
        guard let data = try? Data(contentsOf: metadataURL) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try? decoder.decode(CacheMetadata.self, from: data)
    }
    
    /// Check if cache is still valid (not stale)
    func isCacheValid(accountId: UUID, folder: MailFolder) async -> Bool {
        guard let metadata = await loadMetadata(accountId: accountId, folder: folder) else {
            return false
        }
        
        let cacheAge = Date().timeIntervalSince(metadata.lastSyncDate)
        let isValid = cacheAge < cacheValidityInterval
        
        print("EmailPersistence: Cache validity check for \(folder.rawValue): \(isValid ? "VALID" : "STALE") (age: \(String(format: "%.1f", cacheAge))s)")
        return isValid
    }
    
    /// Merge new cached emails with existing cache (for incremental sync)
    func mergeCachedEmails(_ newEmails: [CachedEmail], accountId: UUID, folder: MailFolder) async throws {
        let existing = await loadCachedEmails(accountId: accountId, folder: folder)
        
        // Create a dictionary for quick lookup
        var emailMap: [String: CachedEmail] = [:]
        for email in existing {
            emailMap[email.imapUID] = email
        }
        
        // Update or add new emails
        for newEmail in newEmails {
            emailMap[newEmail.imapUID] = newEmail
        }
        
        // Convert back to array and save
        let merged = Array(emailMap.values)
        try await saveCachedEmails(merged, accountId: accountId, folder: folder)
        
        print("EmailPersistence: Merged \(newEmails.count) new emails, total: \(merged.count)")
    }
    
    // MARK: - Legacy Support (for backward compatibility)
    
    /// Save emails (legacy - converts to CachedEmail)
    func saveEmails(_ emails: [Email], accountId: UUID, folder: MailFolder) async throws {
        let cachedEmails = emails.enumerated().map { index, email in
            CachedEmail(from: email, imapUID: String(index + 1), flags: email.isRead ? ["\\Seen"] : [])
        }
        try await saveCachedEmails(cachedEmails, accountId: accountId, folder: folder)
    }
    
    /// Load emails (legacy - converts from CachedEmail)
    func loadEmails(accountId: UUID, folder: MailFolder) async -> [Email] {
        let cachedEmails = await loadCachedEmails(accountId: accountId, folder: folder)
        return cachedEmails.map { $0.toEmail() }
    }
    
    // MARK: - Cache Management
    
    /// Clear all cached emails for a specific account
    func clearCache(for accountId: UUID) async {
        let filePrefix = "\(accountId.uuidString)_"
        
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            print("EmailPersistence: Failed to list cache directory")
            return
        }
        
        var clearedCount = 0
        for fileURL in files {
            if fileURL.lastPathComponent.hasPrefix(filePrefix) {
                do {
                    try fileManager.removeItem(at: fileURL)
                    clearedCount += 1
                } catch {
                    print("EmailPersistence: Failed to clear cache: \(fileURL.lastPathComponent): \(error)")
                }
            }
        }
        
        print("EmailPersistence: Cleared \(clearedCount) cache items for account \(accountId)")
    }
    
    /// Clear all cached emails (for all accounts)
    func clearAllCache() async {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            print("EmailPersistence: Failed to list cache directory")
            return
        }
        
        var clearedCount = 0
        for fileURL in files {
            do {
                try fileManager.removeItem(at: fileURL)
                clearedCount += 1
            } catch {
                print("EmailPersistence: Failed to clear cache: \(fileURL.lastPathComponent): \(error)")
            }
        }
        
        print("EmailPersistence: Cleared all \(clearedCount) cache items")
    }
    
    /// Get cache directory path (for debugging)
    var cacheDirectoryPath: String {
        cacheDirectory.path
    }
}
