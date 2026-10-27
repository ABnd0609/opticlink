import Foundation
import AVFoundation

public enum CameraLens: String, CaseIterable {
    case ultraWide = "ultra_wide"
    case wide = "wide"
    case telephoto = "telephoto"
    case front = "front"
}

public protocol CameraManagerDelegate: AnyObject {
    func didCaptureSampleBuffer(_ sampleBuffer: CMSampleBuffer)
}

public class CameraManager: NSObject {
    public weak var delegate: CameraManagerDelegate?
    
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.opticlink.camera.session")
    private let videoOutputQueue = DispatchQueue(label: "com.opticlink.camera.output")
    
    private var currentDevice: AVCaptureDevice?
    private var currentInput: AVCaptureDeviceInput?
    private let videoDataOutput = AVCaptureVideoDataOutput()
    
    public private(set) var activeLens: CameraLens = .wide
    
    public override init() {
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .hd1920x1080
            
            self.configureDevice(for: .wide)
            
            self.videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
            self.videoDataOutput.setSampleBufferDelegate(self, queue: self.videoOutputQueue)
            
            if self.captureSession.canAddOutput(self.videoDataOutput) {
                self.captureSession.addOutput(self.videoDataOutput)
            }
            
            if let connection = self.videoDataOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .landscapeRight
                }
            }
            
            self.captureSession.commitConfiguration()
        }
    }
    
    public func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }
    
    public func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }
    
    // MARK: - Lens Configuration
    public func switchLens(_ lens: CameraLens) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            self.configureDevice(for: lens)
            
            // Garantizar que la orientación se mantenga constante al alternar lentes
            if let connection = self.videoDataOutput.connection(with: .video), connection.isVideoOrientationSupported {
                connection.videoOrientation = .landscapeRight
            }
            self.captureSession.commitConfiguration()
        }
    }
    
    private func configureDevice(for lens: CameraLens) {
        if let currentInput = self.currentInput {
            captureSession.removeInput(currentInput)
        }
        
        let deviceType: AVCaptureDevice.DeviceType
        var position: AVCaptureDevice.Position = .back
        
        switch lens {
        case .ultraWide:
            deviceType = .builtInUltraWideCamera
        case .wide:
            deviceType = .builtInWideAngleCamera
        case .telephoto:
            deviceType = .builtInTelephotoCamera
        case .front:
            deviceType = .builtInTrueDepthCamera
            position = .front
        }
        
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [deviceType, .builtInWideAngleCamera],
            mediaType: .video,
            position: position
        )
        
        guard let device = discovery.devices.first else { return }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                self.currentInput = input
                self.currentDevice = device
                self.activeLens = lens
            }
        } catch {
            print("OpticLink: Error al configurar entrada de cámara: \(error)")
        }
    }
    
    // MARK: - Enfoque Manual y Automático (Validación Defensiva)
    public func setFocus(mode: String, position: Float? = nil) {
        sessionQueue.async { [weak self] in
            guard let device = self?.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                if mode == "manual", let pos = position, device.isFocusModeSupported(.locked) {
                    let clamped = max(0.0, min(1.0, pos))
                    device.setFocusModeLocked(lensPosition: clamped, completionHandler: nil)
                } else if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                device.unlockForConfiguration()
            } catch {
                print("OpticLink: Error configurando enfoque: \(error)")
            }
        }
    }
    
    // MARK: - Exposición e ISO Manual (Validación Defensiva - Hallazgo 5)
    public func setExposure(mode: String, iso: Float? = nil, durationSeconds: Double? = nil) {
        sessionQueue.async { [weak self] in
            guard let device = self?.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                if mode == "manual", device.isExposureModeSupported(.custom) {
                    let targetIso = iso ?? device.iso
                    let clampedIso = max(device.activeFormat.minISO, min(device.activeFormat.maxISO, targetIso))
                    
                    let minDurationSec = Double(device.activeFormat.minExposureDuration.seconds)
                    let maxDurationSec = Double(device.activeFormat.maxExposureDuration.seconds)
                    let targetDuration = durationSeconds ?? Double(device.exposureDuration.seconds)
                    let clampedDurationSec = max(minDurationSec, min(maxDurationSec, targetDuration))
                    
                    let timescale: CMTimeScale = 1000000
                    let duration = CMTime(seconds: clampedDurationSec, preferredTimescale: timescale)
                    
                    device.setExposureModeCustom(duration: duration, iso: clampedIso, completionHandler: nil)
                } else if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {
                print("OpticLink: Error configurando exposición defensiva: \(error)")
            }
        }
    }
    
    // MARK: - Balance de Blancos
    public func setWhiteBalance(mode: String, temperature: Float? = nil, tint: Float? = nil) {
        sessionQueue.async { [weak self] in
            guard let device = self?.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                if mode == "manual", let temp = temperature, device.isWhiteBalanceModeSupported(.locked) {
                    let targetTemp = max(2000.0, min(10000.0, temp))
                    let targetTint = max(-150.0, min(150.0, tint ?? 0.0))
                    let tempAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: targetTemp, tint: targetTint)
                    var gains = device.deviceWhiteBalanceGains(for: tempAndTint)
                    gains.redGain = max(1.0, min(device.maxWhiteBalanceGain, gains.redGain))
                    gains.greenGain = max(1.0, min(device.maxWhiteBalanceGain, gains.greenGain))
                    gains.blueGain = max(1.0, min(device.maxWhiteBalanceGain, gains.blueGain))
                    device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
                } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                device.unlockForConfiguration()
            } catch {
                print("OpticLink: Error configurando balance de blancos: \(error)")
            }
        }
    }
    
    // MARK: - Antorcha / Luz de Relleno
    public func setTorch(level: Float) {
        sessionQueue.async { [weak self] in
            guard let device = self?.currentDevice, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                if level > 0.01 {
                    let safeLevel = max(0.01, min(1.0, level))
                    try device.setTorchModeOn(level: safeLevel)
                } else {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
            } catch {
                print("OpticLink: Error configurando linterna: \(error)")
            }
        }
    }
    
    // MARK: - Zoom Digital / Óptico
    public func setZoom(factor: Float) {
        sessionQueue.async { [weak self] in
            guard let device = self?.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                let target = CGFloat(max(1.0, min(Float(device.activeFormat.videoMaxZoomFactor), factor)))
                device.videoZoomFactor = target
                device.unlockForConfiguration()
            } catch {
                print("OpticLink: Error configurando zoom: \(error)")
            }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        delegate?.didCaptureSampleBuffer(sampleBuffer)
    }
}
