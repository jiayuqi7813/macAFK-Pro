//
//  MacAfkApp.swift
//  MacAfk
//
//  Created by Sn1waR on 11/21/25.
//

import SwiftUI

@main
struct MacAfkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var languageManager = LanguageManager.shared
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("menu.preferences".localized) {
                    appDelegate.showPreferences()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
