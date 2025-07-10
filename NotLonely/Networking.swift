import Foundation
import Starscream

protocol NetworkingDelegate: AnyObject {
    func networkingDidConnect()
    func networkingDidDisconnect()
    func networkingDidReceiveMessage(message: String)
}

class Networking: WebSocketDelegate {

    private var socket: WebSocket?
    weak var delegate: NetworkingDelegate?

    init(url: URL) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        socket = WebSocket(request: request)
        socket?.delegate = self
    }

    func connect() {
        socket?.connect()
    }

    func disconnect() {
        socket?.disconnect()
    }

    func send(data: Data) {
        socket?.write(data: data)
    }

    func send(string: String) {
        socket?.write(string: string)
    }

    // MARK: - WebSocketDelegate
    
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected(let headers):
            delegate?.networkingDidConnect()
            print("websocket is connected: \(headers)")
        case .disconnected(let reason, let code):
            delegate?.networkingDidDisconnect()
            print("websocket is disconnected: \(reason) with code: \(code)")
        case .text(let string):
            delegate?.networkingDidReceiveMessage(message: string)
            print("Received text: \(string)")
        case .binary(let data):
            print("Received data: \(data.count)")
        case .ping(_):
            break
        case .pong(_):
            break
        case .viabilityChanged(_):
            break
        case .reconnectSuggested(_):
            break
        case .cancelled:
            delegate?.networkingDidDisconnect()
        case .error(let error):
            delegate?.networkingDidDisconnect()
            print("websocket encountered an error: \(error?.localizedDescription ?? "unknown error")")
        case .peerClosed:
            delegate?.networkingDidDisconnect()
            break
        }
    }
} 
