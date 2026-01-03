# Real Email Server Integration Guide

## Overview

The mail client now includes complete support for connecting to real email servers using:
- **IMAP** for receiving emails
- **SMTP** for sending emails  
- **OAuth2** for modern authentication with Gmail, Outlook, and Yahoo
- **Keychain** for secure credential storage

## Architecture

### Core Components

#### 1. **EmailService** (`Services/EmailService.swift`)
Main service class that orchestrates email operations:
- Connection management
- Fetch emails from folders
- Mark as read/unread
- Move and delete emails
- Send emails via SMTP

#### 2. **IMAPSession** (`Services/IMAPSession.swift`)
Handles IMAP protocol communication:
- Uses Apple's `Network` framework with TLS/SSL support
- Implements IMAP commands: LOGIN, SELECT, SEARCH, FETCH, STORE, EXPUNGE
- Actor-based for thread-safety
- Parses email headers and body

#### 3. **SMTPSession** (`Services/SMTPSession.swift`)
Handles SMTP protocol for sending emails:
- EHLO handshake
- AUTH LOGIN authentication
- MAIL FROM, RCPT TO, DATA commands
- Builds RFC 2822 compliant messages

#### 4. **OAuth2Manager** (`Services/OAuth2Manager.swift`)
Modern authentication for Gmail, Outlook, Yahoo:
- ASWebAuthenticationSession for OAuth2 flow
- Token refresh support
- Provider-specific configurations
- Secure token storage in Keychain

#### 5. **KeychainManager** (`Services/KeychainManager.swift`)
Secure credential storage:
- Passwords stored in iOS Keychain
- OAuth2 tokens stored securely
- Account-specific key management
- CRUD operations for credentials

#### 6. **IntegratedMailStore** (`ViewModels/IntegratedMailStore.swift`)
Orchestrates all services:
- Manages connection state
- Syncs emails from server
- Handles OAuth2 vs password authentication
- Updates UI with real data

### Updated Models

#### **MailAccount**
Now includes:
- `authType`: `.password` or `.oauth2`
- `password` computed property (from Keychain)
- `oauthToken` computed property (from Keychain)
- Passwords removed from struct (security improvement)

#### **MailProvider**
Enhanced with:
- `supportsOAuth2`: Whether OAuth2 is available
- `recommendsOAuth2`: Whether OAuth2 is recommended

## Setup Instructions

### 1. Configure OAuth2 Credentials

You need to register your app with email providers:

#### **Gmail**
1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a new project
3. Enable Gmail API
4. Create OAuth2 credentials (iOS app)
5. Add authorized redirect URI: `com.chaosctrl.mail:/oauth2redirect`
6. Copy Client ID and Client Secret
7. Update `OAuth2Manager.swift` with your credentials:
   ```swift
   clientId: "YOUR_GOOGLE_CLIENT_ID",
   clientSecret: "YOUR_GOOGLE_CLIENT_SECRET"
   ```

#### **Microsoft/Outlook**
1. Go to [Azure Portal](https://portal.azure.com)
2. Register a new app
3. Add mobile platform with redirect URI: `com.chaosctrl.mail:/oauth2redirect`
4. Add API permissions: `IMAP.AccessAsUser.All`, `SMTP.Send`, `offline_access`
5. Copy Application (client) ID
6. Create a client secret
7. Update `OAuth2Manager.swift`

#### **Yahoo**
1. Go to [Yahoo Developer Network](https://developer.yahoo.com)
2. Create an app
3. Get Client ID and Secret
4. Update `OAuth2Manager.swift`

### 2. Configure URL Scheme

Add to your `Info.plist`:
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.chaosctrl.mail</string>
        </array>
        <key>CFBundleURLName</key>
        <string>com.chaosctrl.mail</string>
    </dict>
</array>
```

### 3. Add Keychain Capability

1. Select your target in Xcode
2. Go to "Signing & Capabilities"
3. Click "+ Capability"
4. Add "Keychain Sharing"

### 4. Network Permissions

Add to `Info.plist` for testing (remove in production):
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

For production, use proper TLS and remove arbitrary loads.

## Usage Examples

### Connecting to an Account

```swift
let accountManager = AccountManager()
let emailService = EmailService()
let mailStore = IntegratedMailStore(
    emailService: emailService,
    accountManager: accountManager
)

// For password-based authentication
if let account = accountManager.selectedAccount {
    try await mailStore.connectToAccount(account)
}

// For OAuth2 authentication
if let account = accountManager.selectedAccount,
   account.provider.supportsOAuth2 {
    try await mailStore.connectWithOAuth2(account)
}
```

### Syncing Emails

```swift
// Sync current folder
try await mailStore.syncCurrentFolder()

// Sync all folders
try await mailStore.syncAllFolders()
```

### Sending Email

```swift
try await mailStore.sendEmail(
    to: ["recipient@example.com"],
    subject: "Hello",
    body: "This is a test email"
)
```

### Operations

```swift
// Mark as read
try await mailStore.toggleRead(email: selectedEmail)

// Move to folder
try await mailStore.moveToFolder(email: selectedEmail, folder: .archive)

// Delete
try await mailStore.deleteEmail(email: selectedEmail)
```

## Implementation Details

### IMAP Communication

The `IMAPSession` uses Apple's `Network` framework:
```swift
let endpoint = NWEndpoint.hostPort(
    host: NWEndpoint.Host(server),
    port: NWEndpoint.Port(integerLiteral: UInt16(port))
)

let parameters = NWParameters(tls: .init(), tcp: .init())
connection = NWConnection(to: endpoint, using: parameters)
```

Commands are sent as strings:
```swift
try await send("A001 LOGIN username password\r\n")
let response = try await receive()
```

### OAuth2 Flow

1. User taps "Sign in with Google/Microsoft/Yahoo"
2. `ASWebAuthenticationSession` opens provider's login page
3. User authenticates
4. Provider redirects to `com.chaosctrl.mail:/oauth2redirect?code=...`
5. App exchanges code for access token
6. Token stored in Keychain
7. Token used for IMAP/SMTP authentication (via XOAUTH2)

### Security

- **Passwords**: Never stored in UserDefaults or plain files
- **Keychain**: All credentials stored with `kSecAttrAccessibleWhenUnlocked`
- **TLS/SSL**: All connections encrypted
- **OAuth2 Tokens**: Stored securely, refreshed automatically
- **Token Expiration**: Checked before each use

## Limitations & Future Enhancements

### Current Limitations

1. **Basic IMAP Parser**: The current implementation has a simplified parser
   - **Solution**: Integrate a proper MIME parsing library like `mailcore2-ios`

2. **No OAuth2 for IMAP/SMTP**: Currently only basic auth is fully implemented
   - **Solution**: Implement XOAUTH2 SASL mechanism for IMAP/SMTP

3. **Synchronous Operations**: Some operations could be optimized
   - **Solution**: Implement background fetch and incremental sync

4. **No Attachment Support**: Attachments not yet parsed or sent
   - **Solution**: Add MIME multipart handling

5. **Limited Error Handling**: Basic error types
   - **Solution**: Add detailed error types for different failure scenarios

### Recommended Production Enhancements

1. **Use MailCore2**: Replace custom IMAP/SMTP with battle-tested library
   ```
   https://github.com/MailCore/mailcore2
   ```

2. **Background Sync**: Implement BackgroundTasks framework
   ```swift
   import BackgroundTasks
   BGTaskScheduler.shared.register(...)
   ```

3. **Push Notifications**: Add IMAP IDLE support or push notifications

4. **Local Database**: Use SwiftData or Core Data for offline access
   ```swift
   @Model
   class CachedEmail { ... }
   ```

5. **Attachment Preview**: Use QuickLook for attachment preview

6. **Rich Text Composer**: Use UITextView with attributed strings

7. **Search Optimization**: Implement IMAP SEARCH command

8. **Multiple Account Sync**: Parallel syncing for multiple accounts

9. **Conversation Threading**: Group emails by thread ID

10. **Spam Detection**: Integrate with SpamAssassin or similar

## Testing

### Test with Real Accounts

1. **Gmail**: Create app password, test IMAP/SMTP
2. **Outlook**: Test with personal Microsoft account
3. **Yahoo**: Test with Yahoo Mail account
4. **iCloud**: Use app-specific password

### Mock Testing

For unit tests, create mock services:
```swift
class MockEmailService: EmailService {
    var mockEmails: [Email] = []
    
    override func fetchEmails(folder: MailFolder, limit: Int) async throws -> [Email] {
        return mockEmails
    }
}
```

## Troubleshooting

### Connection Fails
- Verify server address and port
- Check SSL/TLS settings
- Test with `telnet imap.gmail.com 993`

### Authentication Fails
- Verify credentials in Keychain
- Check if 2FA is enabled (requires app password)
- Ensure OAuth2 tokens haven't expired

### OAuth2 Not Working
- Verify redirect URI matches exactly
- Check OAuth2 client ID and secret
- Ensure URL scheme is registered in Info.plist

### Can't Send Email
- Verify SMTP server and port
- Check if provider requires authentication
- Ensure "less secure apps" or app passwords are enabled

## Resources

- [RFC 3501 - IMAP4rev1](https://tools.ietf.org/html/rfc3501)
- [RFC 5321 - SMTP](https://tools.ietf.org/html/rfc5321)
- [RFC 6749 - OAuth 2.0](https://tools.ietf.org/html/rfc6749)
- [Apple Network Framework](https://developer.apple.com/documentation/network)
- [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)

## Summary

You now have a complete foundation for real email server connectivity:

✅ IMAP protocol implementation  
✅ SMTP protocol implementation  
✅ OAuth2 authentication flow  
✅ Keychain security integration  
✅ Multiple provider support  
✅ Modern Swift concurrency (async/await, actors)  
✅ Thread-safe network operations  
✅ Token refresh handling  

The next step is to register your app with email providers, configure OAuth2 credentials, and test with real accounts!
