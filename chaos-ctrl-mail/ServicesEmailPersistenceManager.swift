//
//  EmailPersistenceManager.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import Foundation

/// Manages persistence of emails to disk for faster app startup
actor EmailPersistenceManager {
    static let shared = EmailPersistenceManager()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        // Store in app's cache directory (can be cleared by user/system)
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cacheDir.appendingPathComponent("EmailCache", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Save emails for a specific account and folder to disk
    func saveEmails(_ emails: [Email], accountId: UUID, folder: MailFolder) async throws {
        let fileName = "\(accountId.uuidString)_\(folder.rawValue).json"
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(emails)
        try data.write(to: fileURL, options: .atomic)
        
        print("EmailPersistence: Saved \(emails.count) emails to \(fileName)")
    }
    
    /// Load cached emails for a specific account and folder from disk
    func loadEmails(accountId: UUID, folder: MailFolder) async -> [Email] {
        let fileName = "\(accountId.uuidString)_\(folder.rawValue).json"
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            print("EmailPersistence: No cache file found for \(fileName)")
            return []
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let emails = try decoder.decode([Email].self, from: data)
            print("EmailPersistence: Loaded \(emails.count) cached emails from \(fileName)")
            return emails
        } catch {
            print("EmailPersistence: Failed to load cached emails from \(fileName): \(error)")
            return []
        }
    }
    
    /// Clear all cached emails for a specific account
    func clearCache(for accountId: UUID) async {
        let filePrefix = accountId.uuidString
        
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            print("EmailPersistence: Failed to list cache directory")
            return
        }
        
        var clearedCount = 0
        for fileURL in files where fileURL.lastPathComponent.hasPrefix(filePrefix) {
            do {
                try fileManager.removeItem(at: fileURL)
                clearedCount += 1
                print("EmailPersistence: Cleared cache file \(fileURL.lastPathComponent)")
            } catch {
                print("EmailPersistence: Failed to clear cache file \(fileURL.lastPathComponent): \(error)")
            }
        }
        
        print("EmailPersistence: Cleared \(clearedCount) cache files for account \(accountId)")
    }
    
    /// Clear all cached emails (for all accounts)
    func clearAllCache() async {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            print("EmailPersistence: Failed to list cache directory")
            return
        }
        
        var clearedCount = 0
        for fileURL in files where fileURL.pathExtension == "json" {
            do {
                try fileManager.removeItem(at: fileURL)
                clearedCount += 1
            } catch {
                print("EmailPersistence: Failed to clear cache file \(fileURL.lastPathComponent): \(error)")
            }
        }
        
        print("EmailPersistence: Cleared all \(clearedCount) cache files")
    }
    
    /// Get cache directory path (for debugging)
    var cacheDirectoryPath: String {
        cacheDirectory.path
    }
}
