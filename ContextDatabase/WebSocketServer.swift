//
//  WebSocketServer.swift
//  ContextDatabase
//
//  Created by 高橋直希 on 2024/06/26.
//
import Foundation
import Network
import Combine
import CryptoSwift

// ObservableObjectに準拠したWebSocketServerクラス
class WebSocketServer: ObservableObject {
    // WebSocketServerのシングルトンインスタンス
    static let shared = WebSocketServer()

    // 新しい接続を受け入れるためのNWListener
    private var listener: NWListener?
    // UUIDをキーとするアクティブな接続のディクショナリ
    private var connections: [UUID: NWConnection] = [:]
    // 受信したメッセージを保持するためのPublishedプロパティ（UI更新用）
    @Published var messages: [String] = []

    // シングルトンを保証するためのプライベートイニシャライザ
    private init() {}

    // WebSocketサーバーを開始するメソッド
    func start() {
        let port: NWEndpoint.Port = 8765  // サーバーがリッスンするポート
        let params = NWParameters.tcp  // TCPパラメータを使用
        params.allowLocalEndpointReuse = true  // ローカルエンドポイントの再利用を許可

        // 指定されたパラメータとポートでNWListenerを作成
        self.listener = try? NWListener(using: params, on: port)

        // 新しい接続を処理するハンドラを設定
        self.listener?.newConnectionHandler = { [weak self] newConnection in
            self?.setupNewConnection(newConnection)
        }

        // グローバルディスパッチキューでリスナーを開始
        self.listener?.start(queue: .global())
        print("WebSocket Server started on port \(port)")
    }

    // 新しい接続をセットアップするメソッド
    private func setupNewConnection(_ connection: NWConnection) {
        let connectionID = UUID()  // 接続のための一意の識別子を生成
        connections[connectionID] = connection  // 接続をディクショナリに保存

        // 接続の状態更新を処理するハンドラを設定
        connection.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                print("Client connected: \(connectionID)")
                self?.receive(on: connection, id: connectionID)  // データ受信を開始
            case .failed(let error):
                print("Client connection failed: \(error)")
                self?.removeConnection(id: connectionID)  // 接続が失敗した場合は削除
            default:
                break
            }
        }
        // 接続を開始
        connection.start(queue: .global())
    }

    // 接続からデータを受信するメソッド
    private func receive(on connection: NWConnection, id connectionID: UUID) {
        // 指定された最小および最大長でデータを受信
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            if let data = data, !data.isEmpty {
                // データを文字列に変換
                let request = String(data: data, encoding: .utf8) ?? "Received non-text data"
                print("Received: \(request)") // 受信したメッセージをコンソールに表示
                // WebSocketハンドシェイクを処理
                if request.hasPrefix("GET") {
                    self?.handleHandshake(on: connection, request: request)
                } else {
                    // メインスレッドでメッセージを更新
                    DispatchQueue.main.async {
                        self?.messages.append(request)
                    }
                    // 受信したメッセージをすべての接続にブロードキャスト
                    self?.broadcast(message: request)
                }
            }
            if isComplete {
                // 受信が完了した場合、接続をキャンセル
                connection.cancel()
                self?.removeConnection(id: connectionID)
            } else if error == nil {
                // エラーがなければデータ受信を継続
                self?.receive(on: connection, id: connectionID)
            }
        }
    }

    // WebSocketハンドシェイクを処理するメソッド
    private func handleHandshake(on connection: NWConnection, request: String) {
        guard let webSocketKey = request.components(separatedBy: "\r\n")
                .first(where: { $0.hasPrefix("Sec-WebSocket-Key:") })?
                .components(separatedBy: ": ")
                .last else {
            connection.cancel()
            return
        }

        let acceptKey = generateAcceptKey(webSocketKey: webSocketKey)
        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(acceptKey)\r
        \r
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
            self.receive(on: connection, id: UUID())
        }))
    }

    // WebSocketハンドシェイクのAcceptキーを生成するメソッド
    private func generateAcceptKey(webSocketKey: String) -> String {
        let magicString = webSocketKey + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let data = Data(magicString.utf8)
        let hashed = data.sha1()
        return Data(hashed).base64EncodedString()
    }

    // メッセージをすべての接続にブロードキャストするメソッド
    private func broadcast(message: String) {
        let data = message.data(using: .utf8)  // メッセージをデータに変換
        for (_, connection) in connections {
            // 各接続にメッセージを送信
            connection.send(content: data, completion: .contentProcessed({ _ in }))
        }
    }

    // 接続を削除するメソッド
    private func removeConnection(id connectionID: UUID) {
        connections[connectionID]?.cancel()  // 接続をキャンセル
        connections.removeValue(forKey: connectionID)  // ディクショナリから接続を削除
    }

    // WebSocketサーバーを停止するメソッド
    func stop() {
        listener?.cancel()  // リスナーをキャンセル
        for (_, connection) in connections {
            connection.cancel()  // 各接続をキャンセル
        }
        connections.removeAll()  // すべての接続をクリア
    }
}
