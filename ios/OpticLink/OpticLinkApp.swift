import SwiftUI
import UIKit
import AVFoundation

@main
struct OpticLinkApp: App {
    init() {
        // Evita que la pantalla del iPhone se bloquee o apague durante el streaming
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Configura la sesión de audio
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoChat, options: [.defaultToSpeaker, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("OpticLink: Error configurando AVAudioSession: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
