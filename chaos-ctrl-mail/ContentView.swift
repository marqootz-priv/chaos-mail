//
//  ContentView.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import SwiftUI

struct ContentView: View {
    @State private var accountManager = AccountManager()
    @State private var mailStore: IntegratedMailStore
    @State private var showingQuickSetup = false
    
    init() {
        let accountManager = AccountManager()
        _accountManager = State(initialValue: accountManager)
        _mailStore = State(initialValue: IntegratedMailStore(accountManager: accountManager))
    }
    
    var body: some View {
        NavigationStack {
            if accountManager.accounts.isEmpty {
                // Show beautiful welcome screen
                WelcomeView(accountManager: accountManager, showingQuickSetup: $showingQuickSetup)
            } else {
                SidebarView(mailStore: mailStore, accountManager: accountManager)
                    .onAppear {
                        Task {
                            await connectToSelectedAccount()
                        }
                    }
                    .onChange(of: accountManager.selectedAccount?.id) {
                        Task {
                            await connectToSelectedAccount()
                        }
                    }
            }
        }
        .sheet(isPresented: $showingQuickSetup) {
            QuickAccountSetupView(accountManager: accountManager)
        }
    }
    
    private func connectToSelectedAccount() async {
        guard let account = accountManager.selectedAccount else {
            print("No account selected")
            return
        }
        
        print("Attempting to connect to account: \(account.emailAddress), authType: \(account.authType)")
        
        do {
            if account.authType == .oauth2 {
                print("Using OAuth2 connection")
                try await mailStore.connectWithOAuth2(account)
            } else {
                print("Using password connection")
                // Check if password exists
                if account.password == nil {
                    print("ERROR: Password is nil for account \(account.id)")
                    print("Account details: email=\(account.emailAddress), id=\(account.id.uuidString)")
                } else {
                    print("Password found, attempting connection")
                }
                try await mailStore.connectToAccount(account)
            }
            print("Successfully connected to account")
        } catch {
            print("Failed to connect to account: \(error)")
            if let emailError = error as? EmailServiceError {
                print("EmailServiceError: \(emailError.localizedDescription)")
            }
        }
    }
}

struct WelcomeView: View {
    @Bindable var accountManager: AccountManager
    @Binding var showingQuickSetup: Bool
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [.blue.opacity(0.15), .purple.opacity(0.15), .pink.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // App icon and branding
                VStack(spacing: 20) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 100))
                        .foregroundStyle(.blue.gradient)
                        .shadow(color: .blue.opacity(0.3), radius: 20)
                    
                    Text("Chaos Mail")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text("Your powerful email client")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Features list
                VStack(spacing: 16) {
                    FeatureRow(icon: "bolt.fill", title: "Lightning Fast", color: .yellow)
                    FeatureRow(icon: "lock.shield.fill", title: "Secure & Private", color: .green)
                    FeatureRow(icon: "wand.and.stars", title: "Auto-Setup", color: .purple)
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 16) {
                    Button {
                        showingQuickSetup = true
                    } label: {
                        HStack {
                            Image(systemName: "envelope.badge.fill")
                            Text("Add Your Email")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue.gradient)
                        .foregroundStyle(.white)
                        .cornerRadius(16)
                        .shadow(color: .blue.opacity(0.3), radius: 10)
                    }
                    
                    Text("Setup takes less than 30 seconds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 40)
            
            Text(title)
                .font(.headline)
            
            Spacer()
        }
        .padding()
        .background(.ultraThickMaterial)
        .cornerRadius(12)
    }
}

#Preview {
    ContentView()
}
