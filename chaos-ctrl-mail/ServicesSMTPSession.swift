//
//  SMTPSession.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import Foundation
import Network

actor SMTPSession {
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
                    default:
                        break
                    }
                }
            }
            
            connection?.start(queue: .global())
        }
        
        // Perform SMTP handshake
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
        // Receive greeting
        _ = try await receive()
        
        // Send EHLO
        try await send("EHLO localhost\r\n")
        let ehloResponse = try await receive()
        
        // Check if AUTH is supported
        if ehloResponse.contains("AUTH") {
            // Send AUTH LOGIN
            try await send("AUTH LOGIN\r\n")
            _ = try await receive()
            
            // Send base64 encoded username
            let usernameBase64 = Data(username.utf8).base64EncodedString()
            try await send("\(usernameBase64)\r\n")
            _ = try await receive()
            
            // Send base64 encoded password
            let passwordBase64 = Data(password.utf8).base64EncodedString()
            try await send("\(passwordBase64)\r\n")
            let authResponse = try await receive()
            
            if !authResponse.contains("235") { // 235 = Authentication successful
                throw EmailServiceError.authenticationFailed
            }
        }
    }
    
    // MARK: - Send Email
    
    func sendMessage(from: String, to: [String], subject: String, body: String) async throws {
        guard isConnected else {
            throw EmailServiceError.notConnected
        }
        
        // MAIL FROM
        try await send("MAIL FROM:<\(from)>\r\n")
        let mailFromResponse = try await receive()
        guard mailFromResponse.contains("250") else {
            throw EmailServiceError.serverError("MAIL FROM failed")
        }
        
        // RCPT TO (for each recipient)
        for recipient in to {
            try await send("RCPT TO:<\(recipient)>\r\n")
            let rcptResponse = try await receive()
            guard rcptResponse.contains("250") else {
                throw EmailServiceError.serverError("RCPT TO failed for \(recipient)")
            }
        }
        
        // DATA
        try await send("DATA\r\n")
        let dataResponse = try await receive()
        guard dataResponse.contains("354") else {
            throw EmailServiceError.serverError("DATA command failed")
        }
        
        // Build email message
        let message = buildEmailMessage(from: from, to: to, subject: subject, body: body)
        try await send(message)
        try await send("\r\n.\r\n") // End of data
        
        let endResponse = try await receive()
        guard endResponse.contains("250") else {
            throw EmailServiceError.serverError("Failed to send message")
        }
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
    
    // MARK: - Email Building
    
    private func buildEmailMessage(from: String, to: [String], subject: String, body: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let dateString = dateFormatter.string(from: Date())
        
        var message = ""
        message += "From: \(from)\r\n"
        message += "To: \(to.joined(separator: ", "))\r\n"
        message += "Subject: \(subject)\r\n"
        message += "Date: \(dateString)\r\n"
        message += "Content-Type: text/plain; charset=UTF-8\r\n"
        message += "\r\n"
        message += body
        
        return message
    }
}
