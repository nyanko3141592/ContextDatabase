//
//  ContextDatabaseApp.swift
//  ContextDatabase
//
//  Created by 高橋直希 on 2024/06/26.
//

import SwiftUI

@main
struct ContextDatabaseApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    WebSocketServer.shared.start()
                }
        }
    }
}
