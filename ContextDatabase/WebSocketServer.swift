//
//  WebSocketServer.swift
//  ContextDatabase
//
//  Created by 高橋直希 on 2024/06/26.
//
import Foundation
import Network
import Combine

class WebSocketServer: ObservableObject {
    static let shared = WebSocketServer()

    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    @Published var messages: [String] = []

    private init() {}

    func start() {
        let port: NWEndpoint.Port = 8765
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        self.listener = try? NWListener(using: params, on: port)

        self.listener?.newConnectionHandler = { [weak self] newConnection in
            self?.setupNewConnection(newConnection)
        }

        self.listener?.start(queue: .global())
        print("WebSocket Server started on port \(port)")
    }

    private func setupNewConnection(_ connection: NWConnection) {
        let connectionID = UUID()
        connections[connectionID] = connection

        connection.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                print("Client connected: \(connectionID)")
                self?.receive(on: connection, id: connectionID)
            case .failed(let error):
                print("Client connection failed: \(error)")
                self?.removeConnection(id: connectionID)
            default:
                break
            }
        }
        connection.start(queue: .global())
    }

    private func receive(on connection: NWConnection, id connectionID: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            if let data = data, !data.isEmpty {
                let message = String(data: data, encoding: .utf8) ?? "Received non-text data"
                print("Received: \(message)")
                DispatchQueue.main.async {
                    self?.messages.append(message)
                }
                self?.broadcast(message: message)
            }
            if isComplete {
                connection.cancel()
                self?.removeConnection(id: connectionID)
            } else if error == nil {
                self?.receive(on: connection, id: connectionID)
            }
        }
    }

    private func broadcast(message: String) {
        let data = message.data(using: .utf8)
        for (_, connection) in connections {
            connection.send(content: data, completion: .contentProcessed({ _ in }))
        }
    }

    private func removeConnection(id connectionID: UUID) {
        connections[connectionID]?.cancel()
        connections.removeValue(forKey: connectionID)
    }

    func stop() {
        listener?.cancel()
        for (_, connection) in connections {
            connection.cancel()
        }
        connections.removeAll()
    }
}
