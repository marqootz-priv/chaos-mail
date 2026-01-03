//
//  IMAPSession.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import Foundation
import Network

actor IMAPSession {
    private let server: String
    private let port: Int
    private let username: String
    private let password: String
    private let useSSL: Bool
    
    private var connection: NWConnection?
    private var isConnected = false
    
    init(server: String, port: Int, username: String, password: String, useSSL: Bool) {
        self.server = server
        self.port = port
        self.username = username
        self.password = password
        self.useSSL = useSSL
    }
    
    // MARK: - Connection Management
    
    func connect() async throws {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(server),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )
        
        let parameters: NWParameters
        if useSSL {
            parameters = NWParameters(tls: .init(), tcp: .init())
        } else {
            parameters = .tcp
        }
        
        connection = NWConnection(to: endpoint, using: parameters)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection?.stateUpdateHandler = { [weak self] state in
                Task { [weak self] in
                    guard let self = self else { return }
                    
                    switch state {
                    case .ready:
                        await self.setConnected(true)
                        continuation.resume()
                    case .failed(let error):
                        await self.setConnected(false)
                        continuation.resume(throwing: error)
                    case .waiting(let error):
                        print("Connection waiting: \(error)")
                    default:
                        break
                    }
                }
            }
            
            connection?.start(queue: .global())
        }
        
        // Authenticate
        try await authenticate()
    }
    
    func disconnect() async {
        connection?.cancel()
        connection = nil
        isConnected = false
    }
    
    private func setConnected(_ value: Bool) {
        isConnected = value
    }
    
    private func authenticate() async throws {
        // Send LOGIN command
        let loginCommand = "A001 LOGIN \(username) \(password)\r\n"
        try await send(loginCommand)
        
        let response = try await receive()
        
        if !response.contains("A001 OK") {
            throw EmailServiceError.authenticationFailed
        }
    }
    
    // MARK: - Fetch Messages
    
    func fetchMessages(from folder: String, limit: Int) async throws -> [Email] {
        // SELECT folder
        try await send("A002 SELECT \(folder)\r\n")
        let selectResponse = try await receive()
        
        guard selectResponse.contains("OK") else {
            throw EmailServiceError.serverError("Failed to select folder")
        }
        
        // SEARCH for recent messages
        try await send("A003 SEARCH ALL\r\n")
        let searchResponse = try await receive()
        
        // Parse message IDs from search response
        let messageIds = parseMessageIds(from: searchResponse)
        let limitedIds = Array(messageIds.suffix(limit))
        
        var emails: [Email] = []
        
        // FETCH messages
        for id in limitedIds {
            do {
                let email = try await fetchMessage(id: id)
                emails.append(email)
            } catch {
                print("Failed to fetch message \(id): \(error)")
            }
        }
        
        return emails
    }
    
    func fetchMessage(id: String) async throws -> Email {
        // FETCH message headers and body
        try await send("A004 FETCH \(id) (FLAGS ENVELOPE BODY[TEXT])\r\n")
        let response = try await receive()
        
        return try parseEmail(from: response, id: id)
    }
    
    // MARK: - Message Operations
    
    func markAsRead(messageId: String) async throws {
        try await send("A005 STORE \(messageId) +FLAGS (\\Seen)\r\n")
        _ = try await receive()
    }
    
    func markAsUnread(messageId: String) async throws {
        try await send("A006 STORE \(messageId) -FLAGS (\\Seen)\r\n")
        _ = try await receive()
    }
    
    func moveMessage(messageId: String, to folder: String) async throws {
        // COPY to destination folder
        try await send("A007 COPY \(messageId) \(folder)\r\n")
        _ = try await receive()
        
        // Mark as deleted in current folder
        try await send("A008 STORE \(messageId) +FLAGS (\\Deleted)\r\n")
        _ = try await receive()
        
        // EXPUNGE to permanently delete
        try await send("A009 EXPUNGE\r\n")
        _ = try await receive()
    }
    
    func deleteMessage(messageId: String) async throws {
        try await send("A010 STORE \(messageId) +FLAGS (\\Deleted)\r\n")
        _ = try await receive()
        
        try await send("A011 EXPUNGE\r\n")
        _ = try await receive()
    }
    
    // MARK: - Network Communication
    
    private func send(_ data: String) async throws {
        guard let connection = connection, isConnected else {
            throw EmailServiceError.notConnected
        }
        
        let content = data.data(using: .utf8)!
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: content, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
    
    private func receive() async throws -> String {
        guard let connection = connection, isConnected else {
            throw EmailServiceError.notConnected
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data {
                    let string = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: string)
                } else {
                    continuation.resume(returning: "")
                }
            }
        }
    }
    
    // MARK: - Parsing Helpers
    
    private func parseMessageIds(from response: String) -> [String] {
        // Parse SEARCH response: "* SEARCH 1 2 3 4 5"
        let components = response.components(separatedBy: " ")
        return components.compactMap { component in
            Int(component.trimmingCharacters(in: .whitespacesAndNewlines)) != nil ? component : nil
        }
    }
    
    private func parseEmail(from response: String, id: String) throws -> Email {
        // Basic parsing - in production, use a proper MIME parser
        let lines = response.components(separatedBy: "\r\n")
        
        var from = ""
        var subject = ""
        var date = Date()
        var body = ""
        var isRead = false
        
        for line in lines {
            if line.hasPrefix("From:") {
                from = line.replacingOccurrences(of: "From:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Subject:") {
                subject = line.replacingOccurrences(of: "Subject:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Date:") {
                let dateString = line.replacingOccurrences(of: "Date:", with: "").trimmingCharacters(in: .whitespaces)
                date = parseDate(dateString) ?? Date()
            } else if line.contains("\\Seen") {
                isRead = true
            }
        }
        
        // Extract body (simplified)
        if let bodyStart = response.range(of: "\r\n\r\n") {
            body = String(response[bodyStart.upperBound...])
        }
        
        return Email(
            id: UUID(),
            from: from,
            to: ["me@example.com"], // Would be parsed from headers
            subject: subject.isEmpty ? "(No Subject)" : subject,
            body: body,
            date: date,
            isRead: isRead,
            isStarred: false,
            folder: .inbox
        )
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: dateString)
    }
}
