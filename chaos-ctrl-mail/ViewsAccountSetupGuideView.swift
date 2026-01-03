//
//  AccountSetupGuideView.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import SwiftUI

struct AccountSetupGuideView: View {
    let provider: MailProvider
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Provider Icon and Title
                    HStack {
                        Image(systemName: provider.icon)
                            .font(.largeTitle)
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading) {
                            Text("Setting up \(provider.rawValue)")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Follow these steps to configure your account")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    
                    // Provider-specific instructions
                    VStack(alignment: .leading, spacing: 16) {
                        switch provider {
                        case .gmail:
                            gmailInstructions
                        case .outlook:
                            outlookInstructions
                        case .yahoo:
                            yahooInstructions
                        case .icloud:
                            icloudInstructions
                        case .custom:
                            customInstructions
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Setup Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var gmailInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepView(
                number: 1,
                title: "Enable IMAP",
                description: "Go to Gmail Settings → Forwarding and POP/IMAP → Enable IMAP"
            )
            
            StepView(
                number: 2,
                title: "Create App Password",
                description: "Visit myaccount.google.com/apppasswords and create a new app password for 'Mail'"
            )
            
            StepView(
                number: 3,
                title: "Use App Password",
                description: "Use the 16-character app password instead of your regular password when setting up the account"
            )
            
            InfoBox(
                icon: "info.circle.fill",
                text: "Gmail requires 2-Step Verification to be enabled before you can create app passwords."
            )
        }
    }
    
    private var outlookInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepView(
                number: 1,
                title: "Allow IMAP Access",
                description: "Outlook.com accounts have IMAP enabled by default"
            )
            
            StepView(
                number: 2,
                title: "Use Your Microsoft Password",
                description: "You can use your regular Microsoft account password"
            )
            
            StepView(
                number: 3,
                title: "Two-Factor Authentication",
                description: "If 2FA is enabled, you may need to create an app password from account.microsoft.com/security"
            )
        }
    }
    
    private var yahooInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepView(
                number: 1,
                title: "Generate App Password",
                description: "Go to Account Security settings in Yahoo Mail"
            )
            
            StepView(
                number: 2,
                title: "Create New Password",
                description: "Select 'Generate app password' and choose 'Other App', name it 'Mail Client'"
            )
            
            StepView(
                number: 3,
                title: "Copy the Password",
                description: "Use the generated password (not your regular Yahoo password) when adding the account"
            )
        }
    }
    
    private var icloudInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepView(
                number: 1,
                title: "Create App-Specific Password",
                description: "Visit appleid.apple.com and go to 'App-Specific Passwords'"
            )
            
            StepView(
                number: 2,
                title: "Generate Password",
                description: "Click '+' to generate a new password, name it 'Mail Client'"
            )
            
            StepView(
                number: 3,
                title: "Use App Password",
                description: "Use the generated password instead of your Apple ID password"
            )
            
            InfoBox(
                icon: "exclamationmark.triangle.fill",
                text: "Two-factor authentication must be enabled for your Apple ID to use app-specific passwords."
            )
        }
    }
    
    private var customInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepView(
                number: 1,
                title: "Get Server Information",
                description: "Contact your email provider for IMAP and SMTP server details"
            )
            
            StepView(
                number: 2,
                title: "Common Ports",
                description: "IMAP usually uses port 993 (SSL) or 143. SMTP uses 587 (TLS) or 465 (SSL)"
            )
            
            StepView(
                number: 3,
                title: "Enable Advanced Settings",
                description: "Toggle 'Show Advanced Settings' in the account setup to manually enter server details"
            )
        }
    }
}

struct StepView: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(.blue)
                    .frame(width: 32, height: 32)
                
                Text("\(number)")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct InfoBox: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
            
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    AccountSetupGuideView(provider: .gmail)
}
