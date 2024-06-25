//
//  ContentView.swift
//  ContextDatabase
//
//  Created by 高橋直希 on 2024/06/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var webSocketServer = WebSocketServer.shared

    var body: some View {
        VStack {
            Text("WebSocket Server is running")
                .padding()
            List(webSocketServer.messages, id: \.self) { message in
                Text(message)
            }
        }
    }
}

#Preview {
    ContentView()
}
