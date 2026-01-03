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
        // DEBUG: Limit to 1 email for debugging
        let debugLimit = 1
        print("IMAP: Fetching messages from folder: \(folder) (DEBUG: limited to \(debugLimit) email)")
        
        // SELECT folder
        try await send("A002 SELECT \(folder)\r\n")
        let selectResponse = try await receiveUntilComplete()
        print("IMAP SELECT Response: \(selectResponse)")
        
        guard selectResponse.contains("A002 OK") else {
            print("IMAP: Failed to select folder - \(selectResponse)")
            throw EmailServiceError.serverError("Failed to select folder")
        }
        
        // SEARCH for all messages
        try await send("A003 SEARCH ALL\r\n")
        let searchResponse = try await receiveUntilComplete()
        print("IMAP SEARCH Response: \(searchResponse)")
        
        // Parse message IDs from search response
        let messageIds = parseMessageIds(from: searchResponse)
        print("IMAP: Found \(messageIds.count) message IDs")
        
        // DEBUG: Use debugLimit instead of limit
        let limitedIds = Array(messageIds.suffix(debugLimit))
        print("IMAP: Fetching \(limitedIds.count) messages (DEBUG limit: \(debugLimit), original limit: \(limit))")
        
        var emails: [Email] = []
        
        // FETCH messages
        var commandTag = 4
        for id in limitedIds {
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
        
        print("IMAP: Successfully fetched \(emails.count) emails")
        return emails
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
                date = parseIMAPDate(dateStr) ?? Date()
            }
            
            // Extract subject (second quoted string)
            var subjectStart = envelopeContent.startIndex
            if let firstQuote = envelopeContent.range(of: #""([^"]+)""#, options: .regularExpression) {
                subjectStart = firstQuote.upperBound
                if let secondQuote = envelopeContent[subjectStart...].range(of: #""([^"]+)""#, options: .regularExpression) {
                    subject = String(envelopeContent[secondQuote])
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
            
            // Extract from address - find first address list after subject
            // Pattern: (("Name" NIL "user" "domain.com"))
            from = extractFirstEmail(from: envelopeContent)
            
            // Extract to addresses - find the "to" field (5th field after date, subject, from, sender, reply-to)
            to = extractToAddresses(from: envelopeContent)
        }
        
        // Parse body - handle MIME encoding and extract actual content
        body = parseBody(from: bodyResponse)
        print("IMAP: Parsed body length: \(body.count) characters")
        if body.count > 0 {
            print("IMAP: Body preview (first 200 chars): \(String(body.prefix(200)))")
            // Parse MIME structure, decode encoding, and extract text content
            body = parseMIMEBody(body)
            print("IMAP: After MIME parsing, body length: \(body.count) characters")
            if body.count > 0 {
                print("IMAP: Final body preview: \(String(body.prefix(200)))")
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
            folder: .inbox
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
    
    private func parseMIMEBody(_ rawBody: String) -> String {
        var body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if this is a multipart message (has multipart/ in Content-Type header)
        // OR if it has MIME boundary markers (starts with ----)
        let isMultipart = body.lowercased().contains("multipart/") || body.hasPrefix("----")
        
        if isMultipart && body.lowercased().contains("multipart/") {
            // True multipart message - extract the preferred part
            // PRIORITY: HTML first (rich content), then plain text (fallback)
            // Most commercial/marketing emails have HTML with full formatting
            if let htmlPart = extractMIMEPart(body, preferredType: "text/html") {
                print("IMAP: Found text/html part, using HTML content")
                body = processMIMEPart(htmlPart)
            } else if let plainPart = extractMIMEPart(body, preferredType: "text/plain") {
                print("IMAP: No HTML found, falling back to text/plain")
                body = processMIMEPart(plainPart)
            } else {
                // Fallback: try to extract any text part
                print("IMAP: No text/html or text/plain found, trying fallback extraction")
                body = extractAndProcessFirstTextPart(body)
            }
        } else {
            // Single part message (may have boundary marker but is still a single part)
            // Process directly - this will handle boundary markers, headers, and decoding
            body = processMIMEPart(body)
            
            // Double-check: if body still contains quoted-printable sequences, decode again
            if body.contains("=") && body.range(of: #"=[0-9A-F]{2}"#, options: [.regularExpression, .caseInsensitive]) != nil {
                print("IMAP: Body still contains quoted-printable sequences after processing, decoding again")
                body = decodeQuotedPrintable(body)
            }
        }
        
        // Final verification: ensure no MIME artifacts remain
        if body.contains("Content-Type:") || body.contains("Content-Transfer-Encoding:") || body.contains("----==_mimepart_") {
            print("IMAP: WARNING - MIME artifacts still present in body after parsing")
            // Remove them aggressively
            body = body.replacingOccurrences(of: #"Content-Type:[^\r\n]*"#, with: "", options: [.regularExpression, .caseInsensitive])
            body = body.replacingOccurrences(of: #"Content-Transfer-Encoding:[^\r\n]*"#, with: "", options: [.regularExpression, .caseInsensitive])
            body = body.replacingOccurrences(of: #"----==_mimepart_[^\r\n]*"#, with: "", options: [.regularExpression, .caseInsensitive])
        }
        
        // Strip threading metadata:
        // - For HTML: remove quoted sections (gmail_quote, cite blockquotes, reply/forward blocks)
        // - For plain text: remove reply dividers, quoted text markers, timestamps, ticket IDs
        let isHTMLContent = body.lowercased().contains("<html") ||
                            body.lowercased().contains("<!doctype") ||
                            body.lowercased().contains("<body") ||
                            body.lowercased().contains("<div") ||
                            body.lowercased().contains("<table")
        
        if isHTMLContent {
            body = stripThreadingMetadataHTML(body)
        } else {
            body = stripThreadingMetadata(body)
        }
        
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
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
            if let date = formatter.date(from: cleanDate) {
                return date
            }
        }
        
        return nil
    }
}
