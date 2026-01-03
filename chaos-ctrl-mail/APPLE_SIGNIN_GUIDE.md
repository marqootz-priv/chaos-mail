# Sign in with Apple Implementation Guide

## Overview

The email client now includes **Sign in with Apple** as the primary authentication method, following Apple's Human Interface Guidelines and using the AuthenticationServices framework.

## Implementation

### Components Created

#### 1. **AppleSignInManager.swift**
Observable manager class that handles Apple Sign In flow:
- `ASAuthorizationAppleIDProvider` integration
- `ASAuthorizationControllerDelegate` implementation
- Credential state checking
- Error handling
- Support for Hide My Email

#### 2. **SignInWithAppleButton.swift**
SwiftUI wrapper for `ASAuthorizationAppleIDButton`:
- Native `UIViewRepresentable` implementation
- Multiple button types (Sign In, Continue, Sign Up)
- Multiple styles (Black, White, White Outline)
- Follows Apple's HIG specifications

#### 3. **Updated QuickAccountSetupView.swift**
Integration of Sign in with Apple:
- **Primary authentication method** (appears first)
- Manual email entry as secondary option
- Seamless user experience
- Hide My Email support

## User Experience

### Sign in with Apple Flow

```
User opens app
    ↓
Sees "Add Your Email" screen
    ↓
Taps "Sign in with Apple" button (Primary)
    ↓
Face ID / Touch ID authentication
    ↓
Apple ID sheet appears
    ↓
User confirms email (or uses Hide My Email)
    ↓
Account created automatically
    ↓
User taken to mailbox
```

### Hide My Email Support

When users choose Hide My Email:
- Private relay email: `abc123@privaterelay.appleid.com`
- Real email protected
- Privacy indicator shown
- Full functionality maintained

## Technical Details

### ASAuthorizationAppleIDButton

The native button follows Apple's specifications:
```swift
SignInWithAppleButton.signIn(
    onRequest: {
        // Button tapped
    },
    onCompletion: { result in
        // Handle result
    }
)
```

**Button Types:**
- `.signIn` - "Sign in with Apple"
- `.continue` - "Continue with Apple"
- `.signUp` - "Sign up with Apple"

**Button Styles:**
- `.black` - Black background, white text (default)
- `.white` - White background, black text
- `.whiteOutline` - White background, black border

### Credential Handling

```swift
// Extract credential
guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
    return
}

// User information
let userEmail = credential.email ?? "\(credential.user)@privaterelay.appleid.com"
let fullName = credential.fullName

// Identity token for backend
let identityToken = credential.identityToken

// Authorization code for token exchange
let authorizationCode = credential.authorizationCode

// Real user detection
let realUserStatus = credential.realUserStatus
```

### Keychain Storage

Apple credentials stored securely:
```swift
// Store identity token as OAuth2 token
let token = OAuth2Token(
    accessToken: identityTokenString,
    refreshToken: nil,
    expiresIn: nil,
    tokenType: "Apple",
    scope: nil
)

KeychainManager.shared.saveOAuth2Token(token, for: accountId)
```

## Required Setup

### 1. Enable Sign in with Apple Capability

In Xcode:
1. Select your target
2. Go to "Signing & Capabilities"
3. Click "+ Capability"
4. Add "Sign in with Apple"

### 2. Configure App ID

In Apple Developer Portal:
1. Go to Certificates, Identifiers & Profiles
2. Select your App ID
3. Enable "Sign in with Apple"
4. Save configuration

### 3. Add Entitlements

Xcode automatically adds:
```xml
<key>com.apple.developer.applesignin</key>
<array>
    <string>Default</string>
</array>
```

### 4. Backend Integration (Optional)

For backend validation:
```swift
// Send identity token to your server
let identityToken = String(data: credential.identityToken, encoding: .utf8)

// Server validates token with Apple
POST https://appleid.apple.com/auth/token
```

## Privacy & Security

### Data Collection

Sign in with Apple provides:
- ✅ **User identifier** (unique, stable)
- ✅ **Email** (real or private relay)
- ✅ **Full name** (first time only)
- ✅ **Real user indicator**
- ❌ **No tracking**
- ❌ **No analytics**
- ❌ **No ads**

### Hide My Email

When enabled:
- Relay email: `abc123@privaterelay.appleid.com`
- Emails forwarded to real address
- User's real email protected
- Can disable relay anytime

### Security Features

1. **Face ID / Touch ID** - Biometric authentication
2. **Two-Factor Authentication** - Built-in 2FA
3. **Token-based** - No password exchange
4. **Time-limited tokens** - Automatic expiry
5. **Revocable** - User can revoke anytime

## Error Handling

### ASAuthorizationError Codes

```swift
switch authError.code {
case .canceled:
    // User canceled - don't show error
case .failed:
    // Authorization failed
case .invalidResponse:
    // Invalid response from Apple
case .notHandled:
    // Request not handled
case .unknown:
    // Unknown error
}
```

### User-Facing Messages

- ✅ **Success**: "Signed in with Apple"
- ℹ️ **Hide My Email**: "Signed in with Apple (Hide My Email enabled)"
- ❌ **Canceled**: No message (silent)
- ❌ **Failed**: "Sign in failed: [reason]"

## UI/UX Guidelines

### Button Placement

Following Apple's HIG:
1. ✅ **Primary position** - Above other sign-in options
2. ✅ **Minimum height** - 44pt (50pt in our implementation)
3. ✅ **Corners** - 8pt rounded
4. ✅ **Padding** - Adequate spacing

### Button States

- **Default**: Black background, Apple logo, white text
- **Pressed**: Slightly darker
- **Disabled**: Grayed out (N/A for Sign in with Apple)

### Accessibility

- ✅ VoiceOver support
- ✅ Dynamic Type
- ✅ High contrast
- ✅ Reduced motion
- ✅ Voice Control

## Testing

### Test Scenarios

1. **First-time sign in**
   - User authenticates
   - Provides email and name
   - Account created

2. **Returning user**
   - User authenticates
   - No email/name prompt
   - Account recognized

3. **Hide My Email**
   - User enables privacy
   - Private relay email used
   - Full functionality

4. **User cancellation**
   - User taps cancel
   - Returns to sign-in screen
   - No error shown

5. **Network error**
   - Connection fails
   - Error message shown
   - Retry available

### Sandbox Testing

Use Sandbox Apple IDs:
1. Settings → Sign in with Apple ID → Sandbox Accounts
2. Create test accounts
3. Test all flows

## Backend Integration

### Verify Identity Token

```swift
// Client sends identity token
let token = credential.identityToken

// Server validates with Apple
POST https://appleid.apple.com/auth/token
Content-Type: application/x-www-form-urlencoded

client_id=YOUR_CLIENT_ID
client_secret=YOUR_CLIENT_SECRET
code=IDENTITY_TOKEN
grant_type=authorization_code
```

### Response

```json
{
  "access_token": "...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "...",
  "id_token": "..."
}
```

### Verify ID Token

Decode JWT and verify:
- `iss`: https://appleid.apple.com
- `aud`: Your client ID
- `exp`: Not expired
- `sub`: User identifier

## Credential State

### Check if User is Still Authenticated

```swift
let state = try await appleSignInManager.checkCredentialState(
    for: userIdentifier
)

switch state {
case .authorized:
    // User is still signed in
case .revoked:
    // User revoked access
case .notFound:
    // Credential not found
}
```

### Handle Revocation

When user revokes:
1. Delete local account
2. Clear stored tokens
3. Return to sign-in screen

## Migration from Email/Password

For existing users:
1. **Option 1**: Link Apple ID to existing account
2. **Option 2**: Create new account with Apple ID
3. **Option 3**: Merge accounts based on email

## Best Practices

### Do's ✅

- ✅ Use as primary sign-in method
- ✅ Follow Apple's button guidelines
- ✅ Support Hide My Email
- ✅ Check credential state on app launch
- ✅ Handle errors gracefully
- ✅ Provide alternative sign-in methods

### Don'ts ❌

- ❌ Customize Apple button appearance
- ❌ Require additional registration steps
- ❌ Share user data without consent
- ❌ Use for anything other than authentication
- ❌ Remove after adding other social logins
- ❌ Hide or de-emphasize the button

## Compliance

### App Store Requirements

If your app uses third-party sign-in:
- **Must** offer Sign in with Apple
- **Must** be equally prominent
- **Must** be above or equal to other options
- Applies to: Google, Facebook, Twitter, LinkedIn, etc.

### Privacy Manifest

Declare data usage:
```json
{
  "NSPrivacyTracking": false,
  "NSPrivacyCollectedDataTypes": [
    {
      "NSPrivacyCollectedDataType": "Email",
      "NSPrivacyCollectedDataTypeLinked": true,
      "NSPrivacyCollectedDataTypePurpose": "App Functionality"
    }
  ]
}
```

## Troubleshooting

### Button Not Showing

1. Check capability is enabled
2. Verify entitlements file
3. Clean build folder
4. Restart Xcode

### Authentication Fails

1. Check App ID configuration
2. Verify bundle ID matches
3. Check network connection
4. Review error logs

### Hide My Email Not Working

1. Verify user has Hide My Email enabled
2. Check iCloud+ subscription
3. Ensure iOS 15+

## Future Enhancements

### Phase 2
- [ ] Passkey integration
- [ ] Family Sharing support
- [ ] Cross-device authentication
- [ ] Biometric re-authentication

### Phase 3
- [ ] Backend user management
- [ ] Account linking
- [ ] Social profile sync
- [ ] Multi-device sign out

## Resources

- [Apple Sign In Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple)
- [AuthenticationServices Framework](https://developer.apple.com/documentation/authenticationservices)
- [Sign in with Apple REST API](https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_rest_api)
- [Hide My Email](https://support.apple.com/en-us/HT210425)

---

**Sign in with Apple is now the primary authentication method, providing the best privacy and user experience!** 🍎✨
