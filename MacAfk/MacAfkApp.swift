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
    
    var body: some Scene {
        WindowGroup {
            ContentView(appModel: appDelegate.appModel)
        }
        .commands {
            // Add standard commands if needed
        }
    }
}
