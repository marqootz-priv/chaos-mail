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
                        print("IMAP Connection waiting: \(error)")
                    default:
                        break
                    }
                }
            }
            
            connection?.start(queue: .global())
        }
        
        print("IMAP: Connected to \(server):\(port)")
        
        // Read server greeting
        let greeting = try await receiveUntilComplete()
        print("IMAP Greeting: \(greeting)")
        
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
        // Trim username and password to remove any leading/trailing whitespace
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Send LOGIN command - make sure no trailing spaces
        let loginCommand = "A001 LOGIN \(trimmedUsername) \(trimmedPassword)\r\n"
        print("IMAP: Sending LOGIN command (username length: \(trimmedUsername.count), password length: \(trimmedPassword.count))")
        try await send(loginCommand)
        
        let response = try await receiveUntilComplete()
        print("IMAP LOGIN Response: \(response)")
        
        // Check for successful authentication
        // IMAP responses can be: "A001 OK LOGIN completed" or "A001 NO ..." or "A001 BAD ..."
        if response.contains("A001 OK") {
            print("IMAP: Authentication successful")
        } else if response.contains("A001 NO") || response.contains("A001 BAD") {
            print("IMAP: Authentication failed - \(response)")
            throw EmailServiceError.authenticationFailed
        } else {
            print("IMAP: Unexpected response format - \(response)")
            throw EmailServiceError.authenticationFailed
        }
    }
    
    // MARK: - Fetch Messages
    
    func fetchMessages(from folder: String, limit: Int) async throws -> [Email] {
        print("IMAP: Fetching messages from folder: \(folder) (limit: \(limit))")
        
        // SELECT folder
        try await send("A002 SELECT \(folder)\r\n")
        let selectResponse = try await receiveUntilComplete()
        print("IMAP SELECT Response: \(selectResponse)")
        
        guard selectResponse.contains("A002 OK") else {
            print("IMAP: Failed to select folder - \(selectResponse)")
            throw EmailServiceError.serverError("Failed to select folder")
        }
        
        // SEARCH for all messages (returns message sequence numbers in ascending order, higher = newer)
        try await send("A003 SEARCH ALL\r\n")
        let searchResponse = try await receiveUntilComplete()
        print("IMAP SEARCH Response: \(searchResponse)")
        
        // Parse message IDs from search response
        let messageIds = parseMessageIds(from: searchResponse)
        print("IMAP: Found \(messageIds.count) message IDs")
        
        // To get the most recent emails by date, we need to:
        // 1. Fetch more messages than we need (to ensure we get the most recent by date)
        // 2. Sort them by date
        // 3. Take the top N
        // Fetch the last 20 messages (or all if less than 20) to ensure we get the most recent by date
        let fetchCount = min(20, messageIds.count)
        let idsToFetch = Array(messageIds.suffix(fetchCount))
        print("IMAP: Fetching \(idsToFetch.count) messages to find the \(limit) most recent by date")
        
        var emails: [Email] = []
        
        // FETCH messages
        var commandTag = 4
        for id in idsToFetch {
            do {
                print("IMAP: Fetching message \(id)")
                let email = try await fetchMessage(id: id, commandTag: commandTag)
                emails.append(email)
                print("IMAP: Successfully fetched message \(id)")
                commandTag += 2 // Increment by 2 since we use 2 commands per message
            } catch {
                print("IMAP: Failed to fetch message \(id): \(error)")
            }
        }
        
        // Sort by date (most recent first) and take the top N
        emails.sort { $0.date > $1.date }
        let mostRecent = Array(emails.prefix(limit))
        
        print("IMAP: Successfully fetched \(mostRecent.count) most recent emails (from \(emails.count) fetched)")
        return mostRecent
    }
    
    func fetchMessage(id: String, commandTag: Int) async throws -> Email {
        // First fetch ENVELOPE for headers
        try await send("A\(String(format: "%03d", commandTag)) FETCH \(id) (FLAGS ENVELOPE)\r\n")
        let envelopeResponse = try await receiveUntilComplete()
        print("IMAP ENVELOPE Response for \(id): \(String(envelopeResponse.prefix(300)))...")
        
        // Then fetch body - use BODY[] to get full MIME (HTML + attachments), not just BODY[TEXT]
        try await send("A\(String(format: "%03d", commandTag + 1)) FETCH \(id) (BODY[])\r\n")
        let bodyResponse = try await receiveUntilComplete()
        print("IMAP BODY Response for \(id): \(String(bodyResponse.prefix(300)))...")
        
        return try parseEmail(envelopeResponse: envelopeResponse, bodyResponse: bodyResponse, id: id)
    }
    
    /// Fetch emails with UID greater than the specified UID (incremental sync)
    /// Returns emails with their UID for caching
    func fetchEmailsSince(uid: String, folder: String, limit: Int = 50) async throws -> [(email: Email, uid: String, flags: [String])] {
        print("IMAP: Fetching emails since UID \(uid) from folder: \(folder)")
        
        // SELECT folder
        try await send("A002 SELECT \(folder)\r\n")
        let selectResponse = try await receiveUntilComplete()
        
        guard selectResponse.contains("A002 OK") else {
            throw EmailServiceError.serverError("Failed to select folder")
        }
        
        // Use UID SEARCH to get UIDs (not sequence numbers)
        try await send("A003 UID SEARCH ALL\r\n")
        let searchResponse = try await receiveUntilComplete()
        
        // Parse UIDs from search response (UID SEARCH returns UIDs, not sequence numbers)
        let uids = parseMessageIds(from: searchResponse)
        print("IMAP: Found \(uids.count) total UIDs in folder")
        
        // Filter to only UIDs greater than our last known UID
        let lastUID = Int(uid) ?? 0
        let newUIDs = uids.filter { (Int($0) ?? 0) > lastUID }
        print("IMAP: Found \(newUIDs.count) new UIDs since \(uid)")
        
        // Limit to prevent fetching too many
        let uidsToFetch = Array(newUIDs.prefix(limit))
        
        var results: [(email: Email, uid: String, flags: [String])] = []
        var commandTag = 4
        
        for uidString in uidsToFetch {
            do {
                // Fetch using UID (not sequence number)
                try await send("A\(String(format: "%03d", commandTag)) UID FETCH \(uidString) (FLAGS ENVELOPE)\r\n")
                let envelopeResponse = try await receiveUntilComplete()
                
                try await send("A\(String(format: "%03d", commandTag + 1)) UID FETCH \(uidString) (BODY[])\r\n")
                let bodyResponse = try await receiveUntilComplete()
                
                let email = try parseEmail(envelopeResponse: envelopeResponse, bodyResponse: bodyResponse, id: uidString)
                
                // Extract flags from envelope response
                let flags = extractFlags(from: envelopeResponse)
                
                results.append((email: email, uid: uidString, flags: flags))
                commandTag += 2
            } catch {
                print("IMAP: Failed to fetch UID \(uidString): \(error)")
            }
        }
        
        // Sort by date (most recent first)
        results.sort { $0.email.date > $1.email.date }
        
        print("IMAP: Successfully fetched \(results.count) new emails since UID \(uid)")
        return results
    }
    
    /// Extract IMAP flags from FETCH response
    private func extractFlags(from response: String) -> [String] {
        var flags: [String] = []
        
        // Look for FLAGS section: FLAGS (\Seen \Flagged ...)
        let flagsPattern = #"FLAGS\s*\(([^)]+)\)"#
        if let regex = try? NSRegularExpression(pattern: flagsPattern, options: []),
           let match = regex.firstMatch(in: response, options: [], range: NSRange(location: 0, length: response.utf16.count)) {
            let flagsString = (response as NSString).substring(with: match.range(at: 1))
            flags = flagsString.components(separatedBy: .whitespaces)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        
        return flags
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
    
    // Receive until we get a complete IMAP response
    private func receiveUntilComplete() async throws -> String {
        var buffer = ""
        var attempts = 0
        let maxAttempts = 50
        
        while attempts < maxAttempts {
            let chunk = try await receive()
            if chunk.isEmpty {
                // No more data, return what we have
                if !buffer.isEmpty {
                    return buffer
                }
                // Wait a bit and try again
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                attempts += 1
                continue
            }
            
            buffer += chunk
            
            // Check if we have a complete response
            // IMAP responses end with \r\n, and tagged responses end with "TAG OK/NO/BAD"
            let lines = buffer.components(separatedBy: "\r\n")
            
            // Check for any tagged response (A001 OK, A002 OK, A003 OK, etc.)
            for line in lines {
                if line.range(of: #"^A\d+\s+(OK|NO|BAD)"#, options: .regularExpression) != nil {
                    return buffer
                }
            }
            
            // Check for server greeting (* OK)
            if buffer.contains("* OK") && lines.count >= 1 {
                // Make sure we have the complete greeting line
                if lines.filter({ $0.hasPrefix("* OK") }).count > 0 {
                    return buffer
                }
            }
            
            attempts += 1
        }
        
        return buffer
    }
    
    // MARK: - Parsing Helpers
    
    private func parseMessageIds(from response: String) -> [String] {
        // Parse SEARCH response: "* SEARCH 1 2 3 4 5"
        let components = response.components(separatedBy: " ")
        return components.compactMap { component in
            Int(component.trimmingCharacters(in: .whitespacesAndNewlines)) != nil ? component : nil
        }
    }
    
    private func parseEmail(envelopeResponse: String, bodyResponse: String, id: String) throws -> Email {
        var from = ""
        var subject = ""
        var date = Date()
        var body = ""
        var attachments: [EmailAttachment] = []
        var isRead = false
        var to: [String] = []
        
        // Check for read flag - FLAGS appear before ENVELOPE in the response
        // Format: * N FETCH (FLAGS (\Seen) ENVELOPE ...) or * N FETCH (FLAGS (\Seen \Flagged) ENVELOPE ...)
        // Email is read if \Seen flag is present
        // Use regex to find FLAGS section more reliably
        let flagsPattern = #"FLAGS\s*\(([^)]+)\)"#
        if let flagsMatch = envelopeResponse.range(of: flagsPattern, options: .regularExpression) {
            let flagsSection = String(envelopeResponse[flagsMatch])
            if flagsSection.contains("\\Seen") {
                isRead = true
                print("IMAP: Email \(id) is marked as READ (\\Seen flag found in FLAGS section)")
            } else {
                print("IMAP: Email \(id) is UNREAD (\\Seen flag NOT found in FLAGS section: \(flagsSection))")
            }
        } else {
            // Fallback: just check if \Seen appears anywhere (less reliable but should work)
            if envelopeResponse.contains("\\Seen") {
                isRead = true
                print("IMAP: Email \(id) is marked as READ (\\Seen flag found - fallback check)")
            } else {
                print("IMAP: Email \(id) is UNREAD (\\Seen flag NOT found - fallback check)")
            }
        }
        
        // Parse ENVELOPE using regex - simpler and more reliable
        // Format: ENVELOPE ("date" "subject" (from_addr_list) (sender) (reply-to) (to_addr_list) ...)
        if let envelopeRange = envelopeResponse.range(of: "ENVELOPE (") {
            let envelopeContent = String(envelopeResponse[envelopeRange.upperBound...])
            
            // Extract date (first quoted string)
            if let dateMatch = envelopeContent.range(of: #""([^"]+)""#, options: .regularExpression) {
                let dateStr = String(envelopeContent[dateMatch])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                print("IMAP: Parsing date string: '\(dateStr)'")
                if let parsedDate = parseIMAPDate(dateStr) {
                    date = parsedDate
                    print("IMAP: Parsed date: \(date) (ISO8601: \(ISO8601DateFormatter().string(from: date)))")
                } else {
                    print("IMAP: Failed to parse date, using current date")
                    date = Date()
                }
            }
            
            // Extract subject (second quoted string)
            var subjectStart = envelopeContent.startIndex
            var afterSubjectIndex = envelopeContent.endIndex
            if let firstQuote = envelopeContent.range(of: #""([^"]+)""#, options: .regularExpression) {
                subjectStart = firstQuote.upperBound
                if let secondQuote = envelopeContent[subjectStart...].range(of: #""([^"]+)""#, options: .regularExpression) {
                    subject = String(envelopeContent[secondQuote])
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    // Decode RFC 2047 encoded subjects (e.g., =?UTF-8?B?...?= or =?UTF-8?Q?...?=)
                    subject = decodeRFC2047(subject)
                    // Mark position after subject for from address extraction
                    afterSubjectIndex = secondQuote.upperBound
                }
            }
            
            // Extract from address - find first address list AFTER subject
            // Pattern: (("Name" NIL "user" "domain.com"))
            // Only search in content after the subject field to avoid matching date/subject
            let contentAfterSubject = afterSubjectIndex < envelopeContent.endIndex 
                ? String(envelopeContent[afterSubjectIndex...]) 
                : envelopeContent
            from = extractFirstEmail(from: contentAfterSubject)
            print("IMAP: Extracted 'from' address: '\(from)' (searched after subject field)")
            
            // Extract to addresses - find the "to" field (5th field after date, subject, from, sender, reply-to)
            to = extractToAddresses(from: envelopeContent)
        }
        
        // Parse body - handle MIME encoding and extract actual content + attachments
        body = parseBody(from: bodyResponse)
        print("IMAP: Parsed body length: \(body.count) characters")
        var parsedAttachments: [EmailAttachment] = []
        if body.count > 0 {
            print("IMAP: Body preview (first 500 chars): \(String(body.prefix(500)))")
            // Parse MIME structure, decode encoding, and extract text content + attachments
            let parsed = parseMIMEBody(body)
            body = parsed.body
            parsedAttachments = parsed.attachments
            print("IMAP: After MIME parsing, body length: \(body.count) characters, attachments: \(parsedAttachments.count)")
            if body.count > 0 {
                print("IMAP: Final body preview: \(String(body.prefix(200)))")
            } else {
                print("IMAP: WARNING - Body became empty after MIME parsing!")
                print("IMAP: Original body length was: \(parseBody(from: bodyResponse).count)")
            }
        } else {
            print("IMAP: WARNING - Body is empty, bodyResponse length: \(bodyResponse.count)")
            print("IMAP: Body response preview: \(String(bodyResponse.prefix(500)))")
        }
        
        return Email(
            id: UUID(),
            from: from.isEmpty ? "Unknown" : from,
            to: to.isEmpty ? ["me@example.com"] : to,
            subject: subject.isEmpty ? "(No Subject)" : subject,
            body: body,
            date: date,
            isRead: isRead,
            isStarred: false,
            folder: .inbox,
            hasAttachments: !parsedAttachments.isEmpty,
            attachments: parsedAttachments
        )
    }
    
    private func extractFirstEmail(from content: String) -> String {
        // Find pattern: ("user" "domain.com") within address lists
        // Look for quoted strings that look like email parts
        let pattern = #""([^"@]+)"\s+"([^"]+\.[^"]+)""#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = content as NSString
            if let match = regex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: nsString.length)) {
                if match.numberOfRanges >= 3 {
                    let user = nsString.substring(with: match.range(at: 1))
                    let domain = nsString.substring(with: match.range(at: 2))
                    return "\(user)@\(domain)"
                }
            }
        }
        return ""
    }
    
    private func extractToAddresses(from content: String) -> [String] {
        var addresses: [String] = []
        // Extract all email addresses from the content
        // Pattern: ("user" "domain.com")
        let pattern = #""([^"@]+)"\s+"([^"]+\.[^"]+)""#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = content as NSString
            let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                if match.numberOfRanges >= 3 {
                    let user = nsString.substring(with: match.range(at: 1))
                    let domain = nsString.substring(with: match.range(at: 2))
                    addresses.append("\(user)@\(domain)")
                }
            }
        }
        // Return all addresses except the first one (which is the "from" address)
        return Array(addresses.dropFirst())
    }
    
    private func parseBody(from response: String) -> String {
        // BODY[TEXT] response format: * N FETCH (BODY[TEXT] {1234}\r\nbody content\r\n) A005 OK
        // The body content comes after the size marker {number}\r\n
        
        // Try to find the body content between } and the closing )
        if let braceStart = response.range(of: "{") {
            if let braceEnd = response.range(of: "}", range: braceStart.upperBound..<response.endIndex) {
                // Body starts after }\r\n
                let afterBrace = response[braceEnd.upperBound...]
                
                // Skip \r\n if present
                var bodyStart = afterBrace.startIndex
                if afterBrace.hasPrefix("\r\n") {
                    bodyStart = afterBrace.index(afterBrace.startIndex, offsetBy: 2)
                } else if afterBrace.hasPrefix("\n") {
                    bodyStart = afterBrace.index(after: afterBrace.startIndex)
                }
                
                // Find where the body ends - look for ) followed by command tag or \r\n
                // The body ends before the closing ) and command response
                var bodyEnd = afterBrace.endIndex
                
                // Look for patterns that indicate end of body: )\r\nA or ) A
                if let closeParen = afterBrace[bodyStart...].lastIndex(of: ")") {
                    // Check if there's a command tag after (like A005)
                    let afterParen = afterBrace.index(after: closeParen)
                    if afterParen < afterBrace.endIndex {
                        let nextChars = String(afterBrace[afterParen...]).prefix(10)
                        if nextChars.contains("A") && nextChars.range(of: #"A\d+"#, options: .regularExpression) != nil {
                            bodyEnd = closeParen
                        }
                    }
                }
                
                var bodyContent = String(afterBrace[bodyStart..<bodyEnd])
                
                // Remove trailing ) if present
                bodyContent = bodyContent.trimmingCharacters(in: .whitespacesAndNewlines)
                if bodyContent.hasSuffix(")") {
                    bodyContent = String(bodyContent.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                return bodyContent
            }
        }
        
        return ""
    }
    
    private func parseMIMEBody(_ rawBody: String) -> (body: String, attachments: [EmailAttachment]) {
        let trimmedRaw = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // BODY[] from IMAP includes full RFC 822 message: email headers + blank line + MIME body
        // The boundary is typically in a Content-Type header in the MIME body section (after the blank line)
        
        // Step 1: Split email headers from MIME body at first blank line
        let (emailHeaders, mimeBody) = splitAtFirstBlankLine(trimmedRaw)
        print("IMAP: parseMIMEBody - emailHeaders length: \(emailHeaders.count), mimeBody length: \(mimeBody.count)")
        if mimeBody.count > 0 {
            print("IMAP: parseMIMEBody - mimeBody preview (first 300 chars): \(String(mimeBody.prefix(300)))")
        }
        
        // Step 2: Extract boundary - search in emailHeaders first, then mimeBody
        // The Content-Type header with boundary can be in either place
        var boundary = ""
        
        // First try emailHeaders (where Content-Type: multipart/...; boundary=... often is)
        if !emailHeaders.isEmpty {
            boundary = extractHeaderParameter(emailHeaders, header: "Content-Type", param: "boundary") ?? ""
            if !boundary.isEmpty {
                print("IMAP: parseMIMEBody - found boundary in emailHeaders: '\(boundary)'")
            }
        }
        
        // If not found, try mimeBody (first few lines where Content-Type might be)
        if boundary.isEmpty {
            let firstLines = mimeBody.components(separatedBy: .newlines).prefix(20).joined(separator: "\n")
            boundary = extractHeaderParameter(firstLines, header: "Content-Type", param: "boundary") ?? ""
            if !boundary.isEmpty {
                print("IMAP: parseMIMEBody - found boundary in mimeBody: '\(boundary)'")
            }
        }
        
        // If still not found, try regex fallback on the full content
        if boundary.isEmpty {
            let searchContent = !emailHeaders.isEmpty ? emailHeaders + "\n\n" + mimeBody : trimmedRaw
            let boundaryPattern = #"boundary\s*=\s*"([^"]+)"|boundary\s*=\s*([^\s\r\n;]+)"#
            if let regex = try? NSRegularExpression(pattern: boundaryPattern, options: [.caseInsensitive]) {
                let nsString = searchContent as NSString
                let range = NSRange(location: 0, length: min(nsString.length, 10000)) // Search first 10KB
                if let match = regex.firstMatch(in: searchContent, options: [], range: range) {
                    // Try capture group 1 (quoted) first, then group 2 (unquoted)
                    if match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound {
                        let boundaryRange = match.range(at: 1)
                        boundary = nsString.substring(with: boundaryRange)
                    } else if match.numberOfRanges > 2 && match.range(at: 2).location != NSNotFound {
                        let boundaryRange = match.range(at: 2)
                        boundary = nsString.substring(with: boundaryRange)
                    }
                    if !boundary.isEmpty {
                        print("IMAP: parseMIMEBody - found boundary via regex fallback: '\(boundary)'")
                    }
                }
            }
        }
        
        // Step 3: Parse MIME parts - use mimeBody (content after email headers)
        let bodyContent = !emailHeaders.isEmpty ? mimeBody : trimmedRaw
        print("IMAP: parseMIMEBody - calling parseMIMEParts with boundary='\(boundary)', bodyContent length=\(bodyContent.count)")
        let (body, isHTML, attachments) = parseMIMEParts(bodyContent, boundary: boundary)
        print("IMAP: parseMIMEBody - parseMIMEParts returned body length=\(body.count), isHTML=\(isHTML), attachments=\(attachments.count)")
        
        // Step 4: Strip threading metadata
        let finalBody: String
        if isHTML {
            finalBody = stripThreadingMetadataHTML(body)
        } else {
            finalBody = stripThreadingMetadata(body)
        }
        
        // Step 5: Final safety check - decode any remaining quoted-printable artifacts
        let cleanedBody: String
        if finalBody.range(of: #"=[0-9A-F]{2}"#, options: [.regularExpression, .caseInsensitive]) != nil {
            cleanedBody = decodeQuotedPrintable(finalBody)
        } else {
            cleanedBody = finalBody
        }
        
        return (cleanedBody.trimmingCharacters(in: .whitespacesAndNewlines), attachments)
    }
    
    private func splitAtFirstBlankLine(_ content: String) -> (headers: String, body: String) {
        // Find first occurrence of \r\n\r\n or \n\n
        if let range = content.range(of: "\r\n\r\n") {
            let headers = String(content[..<range.lowerBound])
            let body = String(content[range.upperBound...])
            return (headers, body)
        } else if let range = content.range(of: "\n\n") {
            let headers = String(content[..<range.lowerBound])
            let body = String(content[range.upperBound...])
            return (headers, body)
        }
        // No blank line found - assume entire content is body (single-part message)
        return ("", content)
    }

    private func parseMIMEParts(_ mimeBody: String, boundary: String) -> (body: String, isHTML: Bool, attachments: [EmailAttachment]) {
        var htmlBody = ""
        var plainBody = ""
        var attachments: [EmailAttachment] = []
        
        // If no boundary, treat as single-part message
        if boundary.isEmpty {
            print("IMAP: parseMIMEParts - no boundary found, treating as single-part")
            // Single part - use processMIMEPart to handle headers and decoding
            let processed = processMIMEPart(mimeBody)
            let isHTML = processed.lowercased().contains("<html") ||
                        processed.lowercased().contains("<!doctype") ||
                        processed.lowercased().contains("<body")
            print("IMAP: parseMIMEParts - single-part, processed length: \(processed.count)")
            return (processed, isHTML, attachments)
        }
        
        // Split by boundary markers
        let separator = "--\(boundary)"
        var parts = mimeBody.components(separatedBy: separator)
        
        // Remove empty parts and clean up
        parts = parts.map { part in
            var cleaned = part.trimmingCharacters(in: .whitespacesAndNewlines)
            // Remove leading/trailing newlines and boundary markers
            if cleaned.hasPrefix("--") {
                cleaned = String(cleaned.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return cleaned
        }.filter { !$0.isEmpty && $0 != "--" }
        
        print("IMAP: parseMIMEParts - split into \(parts.count) parts with boundary '\(boundary)'")
        
        for (index, part) in parts.enumerated() {
            // Skip closing boundary marker
            if part.trimmingCharacters(in: .whitespacesAndNewlines) == "--" {
                continue
            }
            
            // Split headers from content at first blank line
            // Note: parts may start with a blank line (from the boundary separator)
            var partToParse = part
            // Remove leading blank lines
            while partToParse.hasPrefix("\r\n") || partToParse.hasPrefix("\n") {
                partToParse = String(partToParse.dropFirst(partToParse.hasPrefix("\r\n") ? 2 : 1))
            }
            
            guard let headerEndRange = partToParse.range(of: "\r\n\r\n") ?? partToParse.range(of: "\n\n") else {
                print("IMAP: parseMIMEParts - part \(index) has no header/content separator, skipping (length: \(partToParse.count))")
                if partToParse.count > 0 {
                    print("IMAP: parseMIMEParts - part \(index) preview: \(String(partToParse.prefix(200)))")
                }
                continue
            }
            
            let partHeaders = String(partToParse[..<headerEndRange.lowerBound])
            var partContent = String(partToParse[headerEndRange.upperBound...])
            
            // CRITICAL: For nested multipart, we need to preserve ALL content until the OUTER boundary
            // For regular parts, we stop at the next boundary marker
            // But for nested multipart, the content includes nested boundaries, so we need to
            // find where this part ends by looking for the NEXT part's start (which would be after this part ends)
            // Actually, partContent should already be correctly extracted by the split - it contains
            // everything from after the headers until the next separator split
            // So we don't need to trim at boundaries here - the split already did that
            partContent = partContent.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Extract headers
            print("IMAP: parseMIMEParts - part \(index) headers preview (first 200 chars): \(String(partHeaders.prefix(200)))")
            let contentType = extractHeader(partHeaders, name: "Content-Type")
            let contentDisposition = extractHeader(partHeaders, name: "Content-Disposition")
            let encoding = extractHeader(partHeaders, name: "Content-Transfer-Encoding")
            let filename = extractHeaderParameter(partHeaders, header: "Content-Disposition", param: "filename")
                ?? extractHeaderParameter(partHeaders, header: "Content-Type", param: "name")
            
            let contentTypeLower = contentType.lowercased()
            let dispositionLower = contentDisposition.lowercased()
            
            print("IMAP: parseMIMEParts - part \(index): Content-Type=\(contentTypeLower.prefix(50)), Disposition=\(dispositionLower), Content length=\(partContent.count)")
            
            // Handle nested multipart messages
            if contentTypeLower.contains("multipart/") {
                // This is a nested multipart - recursively parse it
                let nestedBoundary = extractHeaderParameter(partHeaders, header: "Content-Type", param: "boundary") ?? ""
                if !nestedBoundary.isEmpty {
                    print("IMAP: parseMIMEParts - part \(index) is nested multipart with boundary '\(nestedBoundary)', parsing recursively")
                    print("IMAP: parseMIMEParts - nested partContent length: \(partContent.count), preview: \(String(partContent.prefix(500)))")
                    let (nestedBody, nestedIsHTML, nestedAttachments) = parseMIMEParts(partContent, boundary: nestedBoundary)
                    print("IMAP: parseMIMEParts - nested parse returned: body length=\(nestedBody.count), isHTML=\(nestedIsHTML), attachments=\(nestedAttachments.count)")
                    // For nested multipart, we should merge HTML and plain text, preferring HTML
                    if nestedIsHTML {
                        htmlBody = nestedBody
                    } else if htmlBody.isEmpty {
                        // Only use plain text if we don't already have HTML
                        plainBody = nestedBody
                    }
                    attachments.append(contentsOf: nestedAttachments)
                } else {
                    print("IMAP: parseMIMEParts - part \(index) is multipart but no boundary found, skipping")
                }
                continue
            }
            
            // Categorize this part
            let isAttachment = dispositionLower.contains("attachment") ||
                              (dispositionLower.contains("inline") && filename != nil)
            
            if isAttachment {
                // ATTACHMENT - decode to Data and add to attachments array
                // DO NOT include in body
                let decodedData = decodeAttachmentData(partContent, encoding: encoding)
                let decodedFilename = filename.flatMap { decodeRFC2047($0) } ?? "attachment"
                let attachment = EmailAttachment(
                    filename: decodedFilename,
                    mimeType: contentTypeLower.isEmpty ? "application/octet-stream" : contentTypeLower,
                    size: decodedData.count,
                    data: decodedData.isEmpty ? nil : decodedData,
                    isInline: dispositionLower.contains("inline")
                )
                attachments.append(attachment)
                print("IMAP: parseMIMEParts - part \(index) added as attachment: \(decodedFilename)")
            } else if contentTypeLower.contains("text/html") {
                // HTML BODY - decode and store
                htmlBody = decodeTextContent(partContent, encoding: encoding)
                print("IMAP: parseMIMEParts - part \(index) added as HTML body, length: \(htmlBody.count)")
            } else if contentTypeLower.contains("text/plain") {
                // PLAIN TEXT BODY - decode and store
                plainBody = decodeTextContent(partContent, encoding: encoding)
                print("IMAP: parseMIMEParts - part \(index) added as plain text body, length: \(plainBody.count)")
            } else {
                print("IMAP: parseMIMEParts - part \(index) ignored (not text/html, text/plain, or attachment)")
            }
        }
        
        // Prefer HTML over plain text (like Apple Mail)
        let finalBody = !htmlBody.isEmpty ? htmlBody : plainBody
        let isHTML = !htmlBody.isEmpty
        
        return (finalBody, isHTML, attachments)
    }
    
    private func decodeTextContent(_ content: String, encoding: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        switch encoding.lowercased() {
        case "quoted-printable":
            return decodeQuotedPrintable(trimmed)
        case "base64":
            if let data = Data(base64Encoded: trimmed),
               let decoded = String(data: data, encoding: .utf8) {
                return decoded
            }
            return trimmed
        default:
            return trimmed
        }
    }
    
    private func decodeAttachmentData(_ content: String, encoding: String) -> Data {
        let cleaned = content
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch encoding.lowercased() {
        case "base64":
            return Data(base64Encoded: cleaned) ?? Data()
        case "quoted-printable":
            let decoded = decodeQuotedPrintable(content)
            return decoded.data(using: .utf8) ?? Data()
        default:
            // For 7bit, 8bit, binary - convert to Data directly
            return cleaned.data(using: .utf8) ?? Data()
        }
    }
    
    private func decodeRFC2047(_ encoded: String) -> String {
        let pattern = #"=\?([^?]+)\?([QBqb])\?([^?]+)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return encoded
        }
        
        var result = encoded
        let matches = regex.matches(in: encoded, range: NSRange(encoded.startIndex..., in: encoded))
        for match in matches.reversed() {
            guard match.numberOfRanges == 4,
                  let fullRange = Range(match.range(at: 0), in: encoded),
                  let encodingRange = Range(match.range(at: 2), in: encoded),
                  let dataRange = Range(match.range(at: 3), in: encoded) else { continue }
            
            let encType = String(encoded[encodingRange]).uppercased()
            let dataStr = String(encoded[dataRange])
            var decodedPart = ""
            if encType == "Q" {
                decodedPart = dataStr.replacingOccurrences(of: "_", with: " ")
                decodedPart = decodeQuotedPrintable(decodedPart)
            } else if encType == "B" {
                if let d = Data(base64Encoded: dataStr), let s = String(data: d, encoding: .utf8) {
                    decodedPart = s
                }
            }
            result.replaceSubrange(fullRange, with: decodedPart)
        }
        return result
    }
    
    private func extractHeader(_ headers: String, name: String) -> String {
        let lines = headers.components(separatedBy: .newlines)
        var headerLineIndex = -1
        
        // Find the line that starts with the header name
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix(name.lowercased() + ":") {
                headerLineIndex = index
                break
            }
        }
        
        if headerLineIndex >= 0 {
            // Extract the value from the header line (everything after the colon)
            let headerLine = lines[headerLineIndex]
            if let colonRange = headerLine.range(of: ":") {
                var value = String(headerLine[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                
                // Collect continuation lines (lines starting with space/tab)
                for i in (headerLineIndex + 1)..<lines.count {
                    let line = lines[i]
                    if line.hasPrefix(" ") || line.hasPrefix("\t") {
                        value += " " + line.trimmingCharacters(in: .whitespaces)
                    } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                        // Non-empty line that doesn't start with space/tab - end of header
                        break
                    }
                }
                
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return ""
    }
    
    private func extractHeaderParameter(_ headers: String, header: String, param: String) -> String? {
        // Escape special regex characters in header and param names
        let escapedHeader = NSRegularExpression.escapedPattern(for: header)
        let escapedParam = NSRegularExpression.escapedPattern(for: param)
        let pattern = "(?is)\(escapedHeader)[^;]*;\\s*\(escapedParam)\\s*=\\s*\"?([^\";\\r\\n]+)\"?"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: headers, range: NSRange(headers.startIndex..., in: headers)),
           match.numberOfRanges >= 2,
           let range = Range(match.range(at: 1), in: headers) {
            return String(headers[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
    
    private func stripThreadingMetadata(_ body: String) -> String {
        var lines = body.components(separatedBy: .newlines)
        var cleanedLines: [String] = []
        var skipFirstNonEmpty = true  // Skip first non-empty line if it looks like metadata
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines at the start
            if trimmed.isEmpty && cleanedLines.isEmpty {
                continue
            }
            
            // Skip reply divider markers
            if trimmed.contains("##- Please type your reply above this line") ||
               trimmed.contains("-----Original Message-----") ||
               (trimmed.contains("On ") && trimmed.contains("wrote:")) {
                continue
            }
            
            // Skip quoted text lines (lines starting with >)
            if line.starts(with: ">") {
                continue
            }
            
            // Skip excessive separator lines (long lines of dashes or equals)
            if (trimmed.hasPrefix("---") || trimmed.hasPrefix("===")) && trimmed.count > 20 {
                continue
            }
            
            // Skip first non-empty line if it looks like a timestamp/metadata line
            // Pattern: Name, Month Day, Year, Time Timezone (e.g., "Deepak Y., Jul 27, 2024, 8:06 AM PDT")
            if skipFirstNonEmpty && !trimmed.isEmpty {
                // Check for timestamp patterns: contains comma, year (20xx), and time (has colon)
                if trimmed.contains(", 20") && trimmed.contains(":") {
                    // Also check for month names or date patterns
                    let monthPattern = #"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2}"#
                    if trimmed.range(of: monthPattern, options: [.regularExpression, .caseInsensitive]) != nil {
                        skipFirstNonEmpty = false
                        continue  // Skip this timestamp line
                    }
                }
                skipFirstNonEmpty = false
            }
            
            cleanedLines.append(line)
        }
        
        var cleaned = cleanedLines.joined(separator: "\n")
        
        // Remove support ticket IDs like [2DXRRD-1N5LV]
        cleaned = cleaned.replacingOccurrences(
            of: #"\[[A-Z0-9\-]+\]"#,
            with: "",
            options: .regularExpression
        )
        
        // Remove timestamp patterns that might appear elsewhere (more aggressive)
        // Pattern: Name, Month Day, Year, Time Timezone
        let timestampPattern = #"^[A-Za-z\s\.]+,\s+[A-Z][a-z]+\s+\d{1,2},\s+\d{4},\s+\d{1,2}:\d{2}\s+[A-Z]{2,3}\s+[A-Z]{2,4}"#
        cleaned = cleaned.replacingOccurrences(
            of: timestampPattern,
            with: "",
            options: [.regularExpression, .anchored]
        )
        
        // Remove excessive blank lines (more than 2 consecutive newlines)
        cleaned = cleaned.replacingOccurrences(of: #"\n\n\n+"#, with: "\n\n", options: .regularExpression)
        
        // Remove leading blank lines
        while cleaned.hasPrefix("\n") || cleaned.hasPrefix("\r") {
            cleaned = String(cleaned.dropFirst())
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripThreadingMetadataHTML(_ html: String) -> String {
        var cleaned = html
        
        // Keep HTML content intact to avoid data loss; only remove small attribution/dividers
        // Remove Gmail attribution lines
        cleaned = cleaned.replacingOccurrences(of: #"(?is)<div[^>]*gmail_attr[^>]*>.*?</div>"#, with: "", options: [.regularExpression])
        
        // Remove common reply dividers that might be in HTML form
        cleaned = cleaned.replacingOccurrences(of: #"##- Please type your reply above this line -##"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"-----Original Message-----"#, with: "", options: .regularExpression)
        
        // Do NOT truncate HTML; preserve full content
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func processMIMEPart(_ part: String) -> String {
        var content = part.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Step 1: Detect Content-Transfer-Encoding from headers (before we strip them)
        var encoding = "7bit"
        if let encodingMatch = content.range(of: #"Content-Transfer-Encoding:\s*([^\r\n]+)"#, options: [.regularExpression, .caseInsensitive]) {
            let encodingLine = String(content[encodingMatch])
            if encodingLine.lowercased().contains("base64") {
                encoding = "base64"
            } else if encodingLine.lowercased().contains("quoted-printable") {
                encoding = "quoted-printable"
            }
        } else {
            // No headers found - check if content looks like quoted-printable
            // Quoted-printable uses =XX patterns (like =3D for =, =0D for \r, etc.)
            if content.range(of: #"=[0-9A-F]{2}"#, options: [.regularExpression, .caseInsensitive]) != nil {
                encoding = "quoted-printable"
            }
        }
        
        // Step 2: Parse lines and identify structure
        let lines = content.components(separatedBy: .newlines)
        var bodyStartIndex = -1
        var foundHeaders = false
        var foundBlankAfterHeaders = false
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip MIME boundary markers (lines starting with --)
            if trimmed.hasPrefix("--") {
                continue
            }
            
            // Check if this is a header line (contains ":" or is a continuation with space/tab)
            let isHeaderLine = trimmed.contains(":") || (!trimmed.isEmpty && (line.hasPrefix(" ") || line.hasPrefix("\t")))
            
            if isHeaderLine {
                foundHeaders = true
                foundBlankAfterHeaders = false
                continue
            }
            
            // If we found headers and hit a blank line, the next non-empty line is the body
            if foundHeaders && trimmed.isEmpty {
                foundBlankAfterHeaders = true
                continue
            }
            
            // If we've seen headers and a blank line, the next non-empty line is body content
            if foundHeaders && foundBlankAfterHeaders && !trimmed.isEmpty {
                bodyStartIndex = index
                break
            }
            
            // If we hit content without seeing headers, this might be the body already
            if !foundHeaders && !trimmed.isEmpty && !isHeaderLine {
                // Check if this looks like actual content (not a boundary or header)
                if !trimmed.hasPrefix("--") && !trimmed.contains("Content-Type") && !trimmed.contains("Content-Transfer-Encoding") {
                    bodyStartIndex = index
                    break
                }
            }
        }
        
        // Step 3: Extract body content
        if bodyStartIndex >= 0 && bodyStartIndex < lines.count {
            content = lines[bodyStartIndex...].joined(separator: "\n")
        } else if foundHeaders && foundBlankAfterHeaders {
            // Headers found but no body start - take everything after the blank line
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty && index + 1 < lines.count {
                    content = lines[(index + 1)...].joined(separator: "\n")
                    break
                }
            }
        } else {
            // Fallback: aggressively filter out MIME artifacts
            let filteredLines = lines.filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Remove boundary markers, headers, and header continuations
                return !trimmed.hasPrefix("--") && 
                       !trimmed.contains("Content-Type:") && 
                       !trimmed.contains("Content-Transfer-Encoding:") &&
                       !trimmed.contains("charset=") &&
                       !trimmed.contains("boundary=") &&
                       !(line.hasPrefix(" ") && (line.contains("charset=") || line.contains("boundary=")))
            }
            content = filteredLines.joined(separator: "\n")
        }
        
        // Step 4: Remove any remaining boundary markers
        content = removeMIMEBoundaries(content)
        
        // Step 5: Decode based on encoding
        switch encoding {
        case "base64":
            content = decodeBase64(content)
        case "quoted-printable":
            content = decodeQuotedPrintable(content)
        default:
            break
        }
        
        // Step 6: Final cleanup - remove any MIME artifacts that slipped through
        let headerPatterns = [
            #"Content-Type:\s*[^\r\n]+"#,
            #"Content-Transfer-Encoding:\s*[^\r\n]+"#,
            #"charset\s*=\s*[^\s;]+"#,
            #"boundary\s*=\s*[^\s;]+"#,
            #"----==_mimepart_[^\r\n]+"#  // MIME boundary markers
        ]
        
        for pattern in headerPatterns {
            content = content.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        
        // Clean up excessive whitespace
        content = content.replacingOccurrences(of: #"\n\s*\n\s*\n+"#, with: "\n\n", options: .regularExpression)
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractMIMEPart(_ body: String, preferredType: String) -> String? {
        let escapedType = preferredType.replacingOccurrences(of: "/", with: "\\/")
        // Look for Content-Type: text/plain or text/html, followed by headers and then body content
        // Pattern: Content-Type: text/xxx + headers + blank line + content (until next boundary or end)
        let pattern = #"Content-Type:\s*"# + escapedType + #"[^\r\n]*(?:\r?\n[^\r\n]+)*\r?\n\r?\n([\s\S]*?)(?=\r?\n--[^\r\n]+|$)"#
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let nsString = body as NSString
            if let match = regex.firstMatch(in: body, options: [], range: NSRange(location: 0, length: nsString.length)) {
                // Return the full match which includes headers and content
                return nsString.substring(with: match.range)
            }
        }
        
        return nil
    }
    
    private func extractAndProcessFirstTextPart(_ body: String) -> String {
        // Fallback: try to find any Content-Type: text/* part
        if let textPart = extractMIMEPart(body, preferredType: "text/plain") ?? extractMIMEPart(body, preferredType: "text/html") {
            return processMIMEPart(textPart)
        }
        
        // Last resort: try to process the body directly
        return processMIMEPart(body)
    }
    
    private func decodeQuotedPrintable(_ encoded: String) -> String {
        // First, remove soft line breaks (= at end of line, followed by \r\n)
        var decoded = encoded.replacingOccurrences(of: #"=\r?\n"#, with: "", options: .regularExpression)
        
        // Convert string to UTF-8 bytes first (treating as ASCII-compatible)
        guard let inputBytes = decoded.data(using: .utf8) else {
            return encoded
        }
        
        var outputBytes: [UInt8] = []
        var i = 0
        
        func isHexDigit(_ byte: UInt8) -> Bool {
            return (byte >= 48 && byte <= 57) || // 0-9
                   (byte >= 65 && byte <= 70) || // A-F
                   (byte >= 97 && byte <= 102)   // a-f
        }
        
        while i < inputBytes.count {
            if inputBytes[i] == UInt8(ascii: "=") && i + 2 < inputBytes.count {
                // Check if next two bytes are hex digits
                let hex1 = inputBytes[i + 1]
                let hex2 = inputBytes[i + 2]
                
                if isHexDigit(hex1) && isHexDigit(hex2) {
                    // Convert hex bytes to string for parsing
                    let hexChars = [Character(UnicodeScalar(hex1)), Character(UnicodeScalar(hex2))]
                    let hexString = String(hexChars)
                    if let byteValue = UInt8(hexString, radix: 16) {
                        outputBytes.append(byteValue)
                        i += 3
                        continue
                    }
                }
            }
            
            // Regular byte - copy as-is
            outputBytes.append(inputBytes[i])
            i += 1
        }
        
        // Convert decoded bytes back to UTF-8 string
        if let decodedString = String(data: Data(outputBytes), encoding: .utf8) {
            return decodedString
        }
        
        // Fallback: return original if conversion fails
        return encoded
    }
    
    private func removeMIMEBoundaries(_ body: String) -> String {
        var text = body
        // Remove MIME boundary lines (lines starting with --)
        let lines = text.components(separatedBy: .newlines)
        text = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip lines that are boundary markers (start with --) or are empty
            return !trimmed.hasPrefix("--") && !trimmed.isEmpty
        }.joined(separator: "\n")
        return text
    }
    
    private func decodeBase64(_ encoded: String) -> String {
        // Remove whitespace and newlines from base64 string
        let clean = encoded.components(separatedBy: .whitespacesAndNewlines).joined()
        if let data = Data(base64Encoded: clean) {
            return String(data: data, encoding: .utf8) ?? encoded
        }
        return encoded
    }
    
    private func stripHTMLTags(_ html: String) -> String {
        // Simple HTML tag stripper - remove HTML tags and decode entities
        var text = html
        
        // Remove HTML tags (including multi-line tags)
        text = text.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: [.regularExpression, .caseInsensitive])
        
        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&#160;", with: " ")
        
        // Clean up extra whitespace and newlines
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n\s*\n"#, with: "\n\n", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return text
    }
    
    private func parseIMAPDate(_ dateString: String) -> Date? {
        var cleanDate = dateString.trimmingCharacters(in: .whitespaces)
        
        // Remove timezone name in parentheses if present: "Tue, 30 Dec 2025 12:15:48 +0000 (GMT)"
        if let parenRange = cleanDate.range(of: " (", options: .backwards) {
            cleanDate = String(cleanDate[..<parenRange.lowerBound])
        }
        
        let formatters = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss",
            "dd MMM yyyy HH:mm:ss"
        ]
        
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            // Set timezone to UTC for consistent parsing (Z format specifier handles offsets)
            // When format includes Z, the timezone offset in the string is used
            // When format doesn't include Z, assume UTC
            if !format.contains("Z") {
                formatter.timeZone = TimeZone(identifier: "UTC")
            }
            if let date = formatter.date(from: cleanDate) {
                return date
            }
        }
        
        return nil
    }
}
