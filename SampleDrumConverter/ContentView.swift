import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var inputURL: URL? = nil
    @State private var statusMessage: String = "Vælg en fil for at starte."

    var body: some View {
        VStack(spacing: 20) {
            Text(statusMessage)
                .multilineTextAlignment(.center)
                .padding()
            
            Button("Vælg input WAV-fil") {
                selectInputFile()
            }
            
            Button("Konverter til mono, 48kHz, 16-bit WAV") {
                if let inputURL = inputURL {
                    convertToMono48kHz16Bit(inputURL: inputURL)
                } else {
                    statusMessage = "Ingen fil valgt!"
                }
            }
            .disabled(inputURL == nil)
            
            Spacer()
        }
        .padding()
        .frame(width: 400, height: 200)
    }

    func selectInputFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.wav] // macOS 12+ bruger allowedContentTypes
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            inputURL = panel.url
            statusMessage = "Valgt fil: \(inputURL!.lastPathComponent)"
        }
    }

    func convertToMono48kHz16Bit(inputURL: URL) {
        // Bestem output-filnavn
        let outputPath = inputURL.deletingPathExtension().appendingPathExtension("converted.wav")
        let outputURL = outputPath
        
        do {
            // Indlæs inputfilen
            let inputFile = try AVAudioFile(forReading: inputURL)
            let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 1, interleaved: true)!
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputFormat.settings)
            
            // Opret en audio-engine og tilføj en mixer for konvertering til mono
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)
            
            let mixer = AVAudioMixerNode()
            mixer.outputVolume = 1.0
            engine.attach(mixer)
            
            // Tilslut player -> mixer -> output
            engine.connect(player, to: mixer, format: inputFile.processingFormat)
            engine.connect(mixer, to: engine.mainMixerNode, format: outputFormat)
            
            // Start engine
            try engine.start()
            
            // Afspil inputfilen
            player.scheduleFile(inputFile, at: nil) {
                player.stop()
                engine.stop()
                outputFile.close()
            }
            player.play()
            
            // Læs fra mixer og skriv til outputfilen
            mixer.installTap(onBus: 0, bufferSize: 4096, format: mixer.outputFormat(forBus: 0)) { buffer, _ in
                do {
                    try outputFile.write(from: buffer)
                } catch {
                    self.statusMessage = "Fejl ved skrivning: \(error.localizedDescription)"
                }
            }
            
            // Vent på konverteringen er færdig
            DispatchQueue.global().async {
                while player.isPlaying {
                    usleep(10000)
                }
                DispatchQueue.main.async {
                    self.statusMessage = "Konvertering fuldført! Fil gemt som \(outputURL.lastPathComponent)."
                }
            }
            
        } catch {
            self.statusMessage = "Fejl: \(error.localizedDescription)"
        }
    }
}
