import SwiftUI
import AudioKit
import AVFoundation

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

            Button(action: {
                testOutput()
            }) {
                Label("Test lydoutput", systemImage: "speaker.wave.2.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.orange)
                    .cornerRadius(10)
            }
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
            convertWithAudioKit(inputURL: inputURL, outputURL: outputURL)
        } else {
            statusMessage = "Bruger annullerede gemning."
        }
    }

    func convertWithAudioKit(inputURL: URL, outputURL: URL) {
        guard !isProcessing else {
            statusMessage = "En konvertering er allerede i gang."
            return
        }

        isProcessing = true
        statusMessage = "Konverterer..."

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                print("Læser inputfil: \(inputURL.path)")
                let inputFile = try AVAudioFile(forReading: inputURL)
                let inputFormat = inputFile.processingFormat
                print("Inputfil format: \(inputFormat)")

                let engine = AudioEngine()
                guard let player = AudioPlayer(file: inputFile) else {
                    DispatchQueue.main.async {
                        self.statusMessage = "Fejl: Kunne ikke initialisere AudioPlayer."
                        self.isProcessing = false
                    }
                    return
                }

                print("AudioPlayer initialiseret.")

                let mixer = Mixer(player)
                mixer.volume = 1.0
                mixer.pan = 0.0 // Sørger for mono-output
                engine.output = mixer

                do {
                    try engine.start()
                    print("Motoren er startet.")
                } catch {
                    DispatchQueue.main.async {
                        self.statusMessage = "Fejl: Kunne ikke starte motoren: \(error.localizedDescription)"
                        self.isProcessing = false
                    }
                    return
                }

                player.start(at: nil)
                print("Afspiller kører: \(player.isPlaying)")

                let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 1, interleaved: true)!
                let duration = Double(inputFile.length) / inputFormat.sampleRate
                print("Varighed af inputfil: \(duration) sekunder.")

                let outputFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
                print("Outputfil oprettet: \(outputURL.path)")

                try engine.renderToFile(outputFile, duration: duration)
                print("Render fuldført.")

                player.stop()
                engine.stop()
                print("Motoren stoppet.")

                DispatchQueue.main.async {
                    self.statusMessage = "Konvertering fuldført! Fil gemt som \(outputURL.lastPathComponent)."
                    self.isProcessing = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "Fejl under konvertering: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }

    func testOutput() {
        do {
            let engine = AudioEngine()
            let sineWave = PlaygroundOscillator()
            engine.output = sineWave

            try engine.start()
            print("Motoren startet til testlyd.")
            sineWave.start()
            print("Testlyd spiller.")
            sleep(2)
            sineWave.stop()
            engine.stop()
            print("Testlyd stoppet.")
        } catch {
            print("Fejl under testlyd: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.statusMessage = "Fejl under testlyd: \(error.localizedDescription)"
            }
        }
    }
}
