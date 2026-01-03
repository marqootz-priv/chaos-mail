//
//  KeychainManager.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {}
    
    // MARK: - Save
    
    func save(_ data: Data, for key: String, account: String) throws {
        // Delete existing item if any
        try? delete(key: key, account: account)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }
    
    func save(_ string: String, for key: String, account: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.conversionFailed
        }
        try save(data, for: key, account: account)
    }
    
    func save<T: Codable>(_ object: T, for key: String, account: String) throws {
        let data = try JSONEncoder().encode(object)
        try save(data, for: key, account: account)
    }
    
    // MARK: - Retrieve
    
    func retrieve(key: String, account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            throw KeychainError.retrieveFailed(status: status)
        }
        
        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }
        
        return data
    }
    
    func retrieveString(key: String, account: String) throws -> String {
        let data = try retrieve(key: key, account: account)
        
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.conversionFailed
        }
        
        return string
    }
    
    func retrieve<T: Codable>(key: String, account: String, type: T.Type) throws -> T {
        let data = try retrieve(key: key, account: account)
        return try JSONDecoder().decode(type, from: data)
    }
    
    // MARK: - Delete
    
    func delete(key: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }
    
    // MARK: - Update
    
    func update(_ data: Data, for key: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key,
            kSecAttrAccount as String: account
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        if status != errSecSuccess {
            // If item doesn't exist, create it
            if status == errSecItemNotFound {
                try save(data, for: key, account: account)
                return
            } else {
                throw KeychainError.updateFailed(status: status)
            }
        }
    }
    
    // MARK: - List All
    
    func listAll() throws -> [[String: Any]] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return []
            }
            throw KeychainError.retrieveFailed(status: status)
        }
        
        guard let items = result as? [[String: Any]] else {
            return []
        }
        
        return items
    }
}

// MARK: - KeychainError

enum KeychainError: LocalizedError {
    case saveFailed(status: OSStatus)
    case retrieveFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case updateFailed(status: OSStatus)
    case invalidData
    case conversionFailed
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to keychain (status: \(status))"
        case .retrieveFailed(let status):
            return "Failed to retrieve from keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete from keychain (status: \(status))"
        case .updateFailed(let status):
            return "Failed to update keychain (status: \(status))"
        case .invalidData:
            return "Invalid data in keychain"
        case .conversionFailed:
            return "Failed to convert data"
        }
    }
}

// MARK: - Convenience Extensions for Mail Accounts

extension KeychainManager {
    // Save account credentials
    func saveAccountPassword(_ password: String, for accountId: UUID) throws {
        try save(password, for: "mail-password", account: accountId.uuidString)
    }
    
    func retrieveAccountPassword(for accountId: UUID) throws -> String {
        try retrieveString(key: "mail-password", account: accountId.uuidString)
    }
    
    func deleteAccountPassword(for accountId: UUID) throws {
        try delete(key: "mail-password", account: accountId.uuidString)
    }
    
    // Save OAuth2 token
    func saveOAuth2Token(_ token: OAuth2Token, for accountId: UUID) throws {
        try save(token, for: "oauth2-token", account: accountId.uuidString)
    }
    
    func retrieveOAuth2Token(for accountId: UUID) throws -> OAuth2Token {
        try retrieve(key: "oauth2-token", account: accountId.uuidString, type: OAuth2Token.self)
    }
    
    func deleteOAuth2Token(for accountId: UUID) throws {
        try delete(key: "oauth2-token", account: accountId.uuidString)
    }
}
