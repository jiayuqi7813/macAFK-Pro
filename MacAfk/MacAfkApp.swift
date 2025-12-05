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
        // 菜单栏应用不需要主窗口，所有UI通过AppDelegate管理
        Settings {
            EmptyView()
        }
    }
}
