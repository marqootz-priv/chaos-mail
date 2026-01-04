//
//  MailFolder.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import Foundation

enum MailFolder: String, CaseIterable, Identifiable, Codable {
    case inbox = "Inbox"
    case sent = "Sent"
    case drafts = "Drafts"
    case trash = "Trash"
    case spam = "Spam"
    case archive = "Archive"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .inbox: return "tray.and.arrow.down.fill"
        case .sent: return "paperplane.fill"
        case .drafts: return "doc.text.fill"
        case .trash: return "trash.fill"
        case .spam: return "exclamationmark.octagon.fill"
        case .archive: return "archivebox.fill"
        }
    }
}
