import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var inputURL: URL? = nil
    @State private var statusMessage: String = "Vælg en fil for at starte."
    @State private var isProcessing = false

    var body: some View {
        VStack(spacing: 20) {
            Text("SampleDrumConverter")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top)

            Text(statusMessage)
                .multilineTextAlignment(.center)
                .padding()
                .foregroundColor(statusMessage.contains("Fejl") ? .red : .green)

            Button(action: {
                selectInputFile()
            }) {
                Label("Vælg input WAV-fil", systemImage: "folder.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding(.horizontal)

            Button(action: {
                if let inputURL = inputURL {
                    saveConvertedFile(inputURL: inputURL)
                } else {
                    statusMessage = "Ingen fil valgt!"
                }
            }) {
                Label("Konverter til mono, 48kHz, 16-bit WAV", systemImage: "arrow.down.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green)
                    .cornerRadius(10)
            }
            .disabled(inputURL == nil || isProcessing)
            .padding(.horizontal)

            Spacer()
        }
        .padding()
        .frame(width: 400, height: 300)
    }

    func selectInputFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.wav]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            inputURL = panel.url
            statusMessage = "Valgt fil: \(inputURL!.lastPathComponent)"
        }
    }

    func saveConvertedFile(inputURL: URL) {
        let originalFileName = inputURL.deletingPathExtension().lastPathComponent
        let suggestedFileName = "\(originalFileName)Mono.wav"

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = suggestedFileName

        if panel.runModal() == .OK, let outputURL = panel.url {
            convertToMono48kHz16Bit(inputURL: inputURL, outputURL: outputURL)
        } else {
            statusMessage = "Bruger annullerede gemning."
        }
    }

    func convertToMono48kHz16Bit(inputURL: URL, outputURL: URL) {
        if isProcessing {
            statusMessage = "En konvertering er allerede i gang."
            return
        }

        isProcessing = true
        statusMessage = "Konverterer..."

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let inputFile = try AVAudioFile(forReading: inputURL)
                let inputFormat = inputFile.processingFormat

                guard inputFormat.sampleRate == 44100, inputFormat.channelCount == 2 else {
                    DispatchQueue.main.async {
                        self.statusMessage = "Inputfil skal være stereo og 44.1kHz."
                        self.isProcessing = false
                    }
                    return
                }

                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(atPath: outputURL.path)
                }

                let mixerFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 1, interleaved: true)!
                let outputFile = try AVAudioFile(forWriting: outputURL, settings: mixerFormat.settings)

                let engine = AVAudioEngine()
                let player = AVAudioPlayerNode()
                let mixer = AVAudioMixerNode()

                engine.attach(player)
                engine.attach(mixer)
                engine.connect(player, to: mixer, format: inputFormat)
                engine.connect(mixer, to: engine.mainMixerNode, format: mixerFormat)

                mixer.installTap(onBus: 0, bufferSize: 8192, format: mixer.outputFormat(forBus: 0)) { buffer, _ in
                    do {
                        if buffer.frameLength > 0 {
                            try outputFile.write(from: buffer)
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.statusMessage = "Fejl ved skrivning: \(error.localizedDescription)"
                            self.isProcessing = false
                        }
                        engine.stop()
                        mixer.removeTap(onBus: 0)
                        return
                    }
                }

                try engine.start()
                player.scheduleFile(inputFile, at: nil) {
                    DispatchQueue.main.async {
                        self.statusMessage = "Konvertering fuldført! Fil gemt som \(outputURL.lastPathComponent)."
                        self.isProcessing = false
                    }
                    engine.stop()
                    mixer.removeTap(onBus: 0)
                }

                player.play()
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "Fejl: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }
}
