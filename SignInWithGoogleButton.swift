//
//  SignInWithGoogleButton.swift
//  chaos-ctrl-mail
//

import SwiftUI

struct SignInWithGoogleButton: View {
    let action: () -> Void
    var style: GoogleButtonStyle = .light
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 20))
                    .foregroundStyle(style.iconColor)
                
                Text("Sign in with Google")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(style.textColor)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(style.backgroundColor)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(style.borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

enum GoogleButtonStyle {
    case light, dark, neutral
    
    var backgroundColor: Color {
        switch self {
        case .light, .dark: return Color(red: 66/255, green: 133/255, blue: 244/255)
        case .neutral: return .white
        }
    }
    
    var textColor: Color {
        switch self {
        case .light, .dark: return .white
        case .neutral: return Color(red: 0, green: 0, blue: 0, opacity: 0.54)
        }
    }
    
    var iconColor: Color { .white }
    
    var borderColor: Color {
        switch self {
        case .neutral: return Color(red: 0, green: 0, blue: 0, opacity: 0.12)
        default: return .clear
        }
    }
}
