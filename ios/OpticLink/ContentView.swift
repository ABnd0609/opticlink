import SwiftUI
import Foundation
import AVFoundation
import Darwin

struct ContentView: View {
    @StateObject private var controller = AppCoordinator()
    @State private var isEcoMode: Bool = false
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if isEcoMode {
                // Modo Eco / Pantalla negra para evitar sobrecalentamiento OLED y ahorrar batería
                VStack(spacing: 16) {
                    Image(systemName: "bolt.badge.checkmark.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    Text("OpticLink Transmitiendo (Modo Eco)")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Toca la pantalla para ver el panel de control.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        isEcoMode = false
                    }
                }
            } else {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("OpticLink Pro")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("Cámara Secundaria para Linux")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Circle()
                            .fill(controller.clientCount > 0 ? Color.green : Color.orange)
                            .frame(width: 12, height: 12)
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    
                    // Status Box
                    VStack(spacing: 12) {
                        HStack {
                            Label("IP Local:", systemImage: "network")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Spacer()
                            Text(controller.localIPAddress)
                                .font(.system(.subheadline, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundColor(.cyan)
                        }
                        Divider().background(Color.gray.opacity(0.3))
                        HStack {
                            Label("Clientes Conectados:", systemImage: "display.2")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(controller.clientCount)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(controller.clientCount > 0 ? .green : .white)
                        }
                        Divider().background(Color.gray.opacity(0.3))
                        HStack {
                            Label("Estado Térmico:", systemImage: "thermometer.medium")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Spacer()
                            Text(controller.thermalStatus)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(controller.thermalStatusColor)
                        }
                    }
                    .padding()
                    .background(Color(white: 0.12))
                    .cornerRadius(14)
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Quick Controls
                    HStack(spacing: 16) {
                        Button(action: {
                            controller.toggleTorch()
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: controller.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(controller.isTorchOn ? .yellow : .white)
                                Text("Luz")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(white: 0.15))
                            .cornerRadius(12)
                        }
                        
                        Button(action: {
                            withAnimation {
                                isEcoMode = true
                            }
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: "leaf.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.green)
                                Text("Modo Eco")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(white: 0.15))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    
                    Text("Controla todos los parámetros avanzados (ISO, Enfoque, Balance) desde el panel de Linux.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }
            }
        }
        .onAppear {
            controller.start()
        }
    }
}

class AppCoordinator: ObservableObject, CameraManagerDelegate, VideoEncoderDelegate, StreamServerDelegate {
    @Published var localIPAddress: String = "Obteniendo IP..."
    @Published var clientCount: Int = 0
    @Published var activeLensName: String = "Gran Angular (1x)"
    @Published var isTorchOn: Bool = false
    @Published var thermalStatus: String = "Óptimo"
    @Published var thermalStatusColor: Color = .green
    
    private let cameraManager = CameraManager()
    private let encoder = VideoEncoder()
    private let server = StreamServer()
    
    func start() {
        cameraManager.delegate = self
        encoder.delegate = self
        server.delegate = self
        
        cameraManager.startSession()
        server.start()
        updateLocalIP()
        setupThermalObserver()
    }
    
    private func setupThermalObserver() {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkThermalState()
        }
        checkThermalState()
    }
    
    private func checkThermalState() {
        let state = ProcessInfo.processInfo.thermalState
        switch state {
        case .nominal:
            thermalStatus = "Óptimo"
            thermalStatusColor = .green
        case .fair:
            thermalStatus = "Templado"
            thermalStatusColor = .yellow
        case .serious:
            thermalStatus = "Caliente (Protección Activa)"
            thermalStatusColor = .orange
        case .critical:
            thermalStatus = "Crítico"
            thermalStatusColor = .red
        @unknown default:
            thermalStatus = "Normal"
            thermalStatusColor = .gray
        }
    }
    
    func didCaptureSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        encoder.encode(sampleBuffer: sampleBuffer)
    }
    
    func didEncodeH264Data(_ data: Data, isKeyFrame: Bool) {
        server.broadcastVideoData(data)
    }
    
    func didUpdateClientCount(_ count: Int) {
        self.clientCount = count
    }
    
    func didReceiveRPCCommand(_ json: [String: Any]) {
        guard let param = json["parameter"] as? String else { return }
        
        switch param {
        case "focus":
            let mode = json["mode"] as? String ?? "continuous_auto"
            let val = (json["value"] as? NSNumber)?.floatValue
            cameraManager.setFocus(mode: mode, position: val)
            
        case "exposure":
            let mode = json["mode"] as? String ?? "continuous_auto"
            let iso = (json["iso"] as? NSNumber)?.floatValue
            let duration = (json["duration_seconds"] as? NSNumber)?.doubleValue
            cameraManager.setExposure(mode: mode, iso: iso, durationSeconds: duration)
            
        case "white_balance":
            let mode = json["mode"] as? String ?? "continuous_auto"
            let temp = (json["temperature_kelvin"] as? NSNumber)?.floatValue
            let tint = (json["tint"] as? NSNumber)?.floatValue
            cameraManager.setWhiteBalance(mode: mode, temperature: temp, tint: tint)
            
        case "lens":
            if let lensStr = json["lens"] as? String, let lens = CameraLens(rawValue: lensStr) {
                cameraManager.switchLens(lens)
                DispatchQueue.main.async {
                    self.activeLensName = lensStr
                }
            }
            
        case "torch":
            let level = (json["level"] as? NSNumber)?.floatValue ?? 0.0
            cameraManager.setTorch(level: level)
            DispatchQueue.main.async {
                self.isTorchOn = level > 0.01
            }
            
        case "zoom":
            if let factor = (json["factor"] as? NSNumber)?.floatValue {
                cameraManager.setZoom(factor: factor)
            }
            
        default:
            break
        }
    }
    
    func toggleTorch() {
        isTorchOn.toggle()
        cameraManager.setTorch(level: isTorchOn ? 1.0 : 0.0)
    }
    
    private func updateLocalIP() {
        var address: String = "No conectada"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        self.localIPAddress = address
    }
}
