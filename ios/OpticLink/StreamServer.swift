import Foundation
import Network

public protocol StreamServerDelegate: AnyObject {
    func didUpdateClientCount(_ count: Int)
    func didReceiveRPCCommand(_ json: [String: Any])
    func didConnectVideoClient()
}

public class StreamServer {
    public weak var delegate: StreamServerDelegate?
    
    private var videoListener: NWListener?
    private var controlListener: NWListener?
    
    private var activeVideoConnections: [NWConnection] = []
    private var activeControlConnections: [NWConnection] = []
    
    private let connectionQueue = DispatchQueue(label: "com.opticlink.server.connections", attributes: .concurrent)
    
    private let videoPort: UInt16 = 8554
    private let controlPort: UInt16 = 8555
    
    public init() {}
    
    public func start() {
        startVideoServer()
        startControlServer()
    }
    
    public func stop() {
        videoListener?.cancel()
        controlListener?.cancel()
        
        connectionQueue.async(flags: .barrier) {
            self.activeVideoConnections.forEach { $0.cancel() }
            self.activeVideoConnections.removeAll()
            self.activeControlConnections.forEach { $0.cancel() }
            self.activeControlConnections.removeAll()
        }
    }
    
    // MARK: - Video Streaming Server (Port 8554)
    private func startVideoServer() {
        do {
            let params = NWParameters.tcp
            let port = NWEndpoint.Port(rawValue: videoPort)!
            videoListener = try NWListener(using: params, on: port)
            
            videoListener?.stateUpdateHandler = { state in
                print("OpticLink: Servidor de video (8554) estado: \(state)")
            }
            
            videoListener?.newConnectionHandler = { [weak self] newConnection in
                self?.handleNewVideoConnection(newConnection)
            }
            
            videoListener?.start(queue: .global(qos: .userInteractive))
        } catch {
            print("OpticLink: Error iniciando servidor de video: \(error)")
        }
    }
    
    private func handleNewVideoConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let conn = connection else { return }
            switch state {
            case .ready:
                self.connectionQueue.async(flags: .barrier) {
                    self.activeVideoConnections.append(conn)
                    DispatchQueue.main.async {
                        self.delegate?.didUpdateClientCount(self.activeVideoConnections.count)
                        self.delegate?.didConnectVideoClient()
                    }
                }
                self.listenForVideoClientDisconnect(conn)
            case .failed, .cancelled:
                self.connectionQueue.async(flags: .barrier) {
                    self.activeVideoConnections.removeAll { $0 === conn }
                    DispatchQueue.main.async {
                        self.delegate?.didUpdateClientCount(self.activeVideoConnections.count)
                    }
                }
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInteractive))
    }
    
    private func listenForVideoClientDisconnect(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self, weak connection] _, _, isComplete, error in
            guard let conn = connection else { return }
            if isComplete || error != nil {
                conn.cancel()
            } else {
                self?.listenForVideoClientDisconnect(conn)
            }
        }
    }
    
    public func broadcastVideoData(_ data: Data) {
        connectionQueue.sync {
            for connection in self.activeVideoConnections {
                connection.send(content: data, contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed({ error in
                    if let err = error {
                        print("OpticLink: Error enviando datos de video: \(err)")
                    }
                }))
            }
        }
    }
    
    // MARK: - Control Server (Port 8555)
    private func startControlServer() {
        do {
            let params = NWParameters.tcp
            let port = NWEndpoint.Port(rawValue: controlPort)!
            controlListener = try NWListener(using: params, on: port)
            
            controlListener?.stateUpdateHandler = { state in
                print("OpticLink: Servidor de control (8555) estado: \(state)")
            }
            
            controlListener?.newConnectionHandler = { [weak self] newConnection in
                self?.handleNewControlConnection(newConnection)
            }
            
            controlListener?.start(queue: .global(qos: .userInitiated))
        } catch {
            print("OpticLink: Error iniciando servidor de control: \(error)")
        }
    }
    
    private func handleNewControlConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let conn = connection else { return }
            switch state {
            case .ready:
                self.connectionQueue.async(flags: .barrier) {
                    self.activeControlConnections.append(conn)
                }
                self.receiveNextRPCMessage(from: conn)
            case .failed, .cancelled:
                self.connectionQueue.async(flags: .barrier) {
                    self.activeControlConnections.removeAll { $0 === conn }
                }
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }
    
    private func receiveNextRPCMessage(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] content, _, isComplete, error in
            guard let self = self, let conn = connection else { return }
            
            if let data = content, !data.isEmpty {
                if let str = String(data: data, encoding: .utf8) {
                    let lines = str.components(separatedBy: "\n")
                    for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if let lineData = line.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                            DispatchQueue.main.async {
                                self.delegate?.didReceiveRPCCommand(json)
                            }
                        }
                    }
                }
            }
            
            if isComplete || error != nil {
                conn.cancel()
            } else {
                self.receiveNextRPCMessage(from: conn)
            }
        }
    }
    
    public func sendControlResponse(_ response: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: response),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        
        let messageData = (jsonString + "\n").data(using: .utf8)!
        connectionQueue.sync {
            for connection in self.activeControlConnections {
                connection.send(content: messageData, contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed({ _ in }))
            }
        }
    }
}
