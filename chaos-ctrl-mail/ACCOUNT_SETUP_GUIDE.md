# Chaos Mail - Account Configuration Guide

## Overview
Chaos Mail is a feature-rich email client for iOS that supports multiple email accounts with IMAP/SMTP protocols.

## Adding an Email Account

### First-Time Setup
When you first launch the app, you'll see a welcome screen. Tap the "Add Account" button to get started.

### Supported Email Providers

#### 1. **Gmail**
- **Automatic Configuration**: ✅ Yes
- **Requirements**: 
  - 2-Step Verification must be enabled
  - App-specific password required
- **Setup Steps**:
  1. Visit [Google App Passwords](https://myaccount.google.com/apppasswords)
  2. Generate a new app password for "Mail"
  3. Use the 16-character password in the app

#### 2. **Outlook/Microsoft 365**
- **Automatic Configuration**: ✅ Yes
- **Requirements**:
  - Microsoft account
  - App password if 2FA is enabled
- **Setup Steps**:
  1. Use your regular Microsoft password
  2. If 2FA is enabled, create app password at account.microsoft.com/security

#### 3. **Yahoo Mail**
- **Automatic Configuration**: ✅ Yes
- **Requirements**: 
  - App-specific password required
- **Setup Steps**:
  1. Go to Yahoo Account Security settings
  2. Generate app password
  3. Use generated password in the app

#### 4. **iCloud Mail**
- **Automatic Configuration**: ✅ Yes
- **Requirements**:
  - 2FA must be enabled
  - App-specific password required
- **Setup Steps**:
  1. Visit [Apple ID](https://appleid.apple.com)
  2. Go to "App-Specific Passwords"
  3. Generate password for "Mail Client"

#### 5. **Custom/Other Providers**
- **Automatic Configuration**: ❌ No (Manual setup required)
- **Requirements**:
  - IMAP and SMTP server details from your email provider
- **Common Ports**:
  - IMAP: 993 (SSL) or 143 (plain)
  - SMTP: 587 (TLS) or 465 (SSL)

## Account Setup Form

### Basic Information
- **Account Name**: A friendly name to identify this account (e.g., "Work", "Personal")
- **Email Address**: Your full email address
- **Provider**: Select from the dropdown list
- **Password**: Your email password or app-specific password

### Advanced Settings
Toggle "Show Advanced Settings" to manually configure:

#### IMAP Settings (Incoming Mail)
- **Server**: IMAP server address (e.g., imap.gmail.com)
- **Port**: Usually 993 for SSL
- **Username**: Usually your email address
- **Password**: Your password or app password
- **Use SSL**: Recommended to keep enabled

#### SMTP Settings (Outgoing Mail)
- **Server**: SMTP server address (e.g., smtp.gmail.com)
- **Port**: Usually 587 for TLS or 465 for SSL
- **Username**: Usually your email address
- **Password**: Same as IMAP password
- **Use SSL**: Recommended to keep enabled

## Managing Accounts

### Viewing All Accounts
1. Tap on your account name at the top of the Mailboxes screen
2. View list of all configured accounts
3. The active account is marked with a checkmark

### Switching Accounts
- Tap any account in the list to make it active
- The app will load emails for the selected account

### Editing an Account
- Swipe left on an account
- Tap "Edit" (blue button)
- Make your changes
- Tap "Save"

### Deleting an Account
- Swipe left on an account
- Tap "Delete" (red button)
- Confirm deletion

## Features

### Email Management
- ✅ View emails by folder (Inbox, Sent, Drafts, Trash, Spam, Archive)
- ✅ Search emails
- ✅ Mark as read/unread
- ✅ Star important emails
- ✅ Move emails between folders
- ✅ Swipe actions for quick access
- ✅ Context menus
- ✅ Unread count badges

### Account Features
- ✅ Multiple account support
- ✅ Quick provider setup (Gmail, Outlook, Yahoo, iCloud)
- ✅ Custom IMAP/SMTP configuration
- ✅ Account switching
- ✅ Persistent storage (accounts saved between app launches)

## Security Notes

⚠️ **Important Security Information**:
- Passwords are currently stored in UserDefaults for demo purposes
- **Production apps should use Keychain for secure password storage**
- Always use app-specific passwords when available
- Enable SSL/TLS whenever possible

## Troubleshooting

### "Cannot Connect to Server"
- Verify server addresses are correct
- Check port numbers
- Ensure SSL setting matches your provider's requirements
- Confirm username and password are correct

### "Authentication Failed"
- Double-check your password
- Use app-specific password if 2FA is enabled
- Verify your email provider allows IMAP/SMTP access

### Gmail Specific Issues
- Ensure "Less secure app access" is OFF (use app passwords instead)
- IMAP must be enabled in Gmail settings
- 2-Step Verification must be enabled to create app passwords

## Next Steps

After configuring your account:
1. Browse your mailboxes
2. Read and organize emails
3. Use swipe gestures for quick actions
4. Search for specific emails
5. Star important messages

## Future Enhancements
- 🔄 Real IMAP/SMTP connectivity (currently uses sample data)
- 📝 Compose and send emails
- 📎 Attachment support
- 🔐 Keychain integration for secure password storage
- 🔔 Push notifications
- 📱 Widget support
- ☁️ Cloud sync

---

**Need Help?** Tap the help icon (?) when adding an account for provider-specific setup instructions.
