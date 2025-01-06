import SwiftUI
import AudioKit
import AVFoundation
import AudioToolbox

struct AudioFile: Identifiable {
    let id = UUID()
    let url: URL
    var status: ConversionStatus = .pending
    var progress: Float = 0.0
    var errorMessage: String?
    
    var format: AudioFileFormat?
    
    enum ConversionStatus {
        case pending
        case converting
        case completed
        case failed
        
        var description: String {
            switch self {
            case .pending: return "Pending"
            case .converting: return "Converting"
            case .completed: return "Completed"
            case .failed: return "Failed"
            }
        }
    }
}

struct AudioFileFormat {
    let channels: Int
    let sampleRate: Double
    let bitDepth: Int
    
    var description: String {
        return "\(channels == 1 ? "Mono" : "Stereo"), \(Int(sampleRate))kHz, \(bitDepth)-bit"
    }
}

struct ContentView: View {
    @State private var audioFiles: [AudioFile] = []
    @State private var isProcessing = false
    @State private var outputFolder: URL?
    @State private var statusMessage: String = "Select files to start."
    
    private let maxFiles = 50
    
    var totalFileSize: Int64 {
        audioFiles.compactMap { try? FileManager.default.attributesOfItem(atPath: $0.url.path)[.size] as? Int64 }
            .reduce(0, +)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("SampleDrumConverter")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top)

            Text(statusMessage)
                .multilineTextAlignment(.center)
                .padding()
                .foregroundColor(statusMessage.contains("Error") ? .red : .green)

            // File list
            List {
                ForEach(audioFiles) { file in
                    FileRowView(file: file)
                }
                .onDelete(perform: removeFiles)
            }
            .frame(height: 200)

            // File size info
            Text("Total size: \(formatFileSize(totalFileSize))")
                .font(.caption)
                .foregroundColor(.secondary)

            // Buttons
            HStack {
                Button(action: selectFiles) {
                    Label("Select Files", systemImage: "folder.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)

                Button(action: selectOutputFolder) {
                    Label("Select Output Folder", systemImage: "folder.badge.plus")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }

            if !audioFiles.isEmpty {
                Button(action: startConversion) {
                    Label("Convert All", systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || outputFolder == nil)

                Button(action: clearFiles) {
                    Label("Clear All", systemImage: "trash")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            Spacer()
        }
        .padding()
        .frame(width: 600, height: 500)
    }

    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func removeFiles(at offsets: IndexSet) {
        audioFiles.remove(atOffsets: offsets)
    }

    private func clearFiles() {
        audioFiles.removeAll()
    }

    func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.wav]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK {
            let newFiles = panel.urls.map { url in
                AudioFile(url: url, format: getAudioFormat(for: url))
            }
            
            // Check for max files limit
            let remainingSlots = maxFiles - audioFiles.count
            if newFiles.count > remainingSlots {
                statusMessage = "Can only add \(remainingSlots) more files. Maximum is \(maxFiles)."
                audioFiles.append(contentsOf: Array(newFiles.prefix(remainingSlots)))
            } else {
                audioFiles.append(contentsOf: newFiles)
            }
        }
    }
    
    func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose Output Folder"
        
        if panel.runModal() == .OK {
            outputFolder = panel.url
            statusMessage = "Output folder selected: \(panel.url?.lastPathComponent ?? "")"
        }
    }
    
    func startConversion() {
        guard outputFolder != nil else {
            statusMessage = "Please select an output folder first"
            return
        }
        
        isProcessing = true
        
        // Find first pending file
        guard let index = audioFiles.firstIndex(where: { $0.status == .pending }) else {
            isProcessing = false
            statusMessage = "No pending files to convert"
            return
        }
        
        // Start conversion for this file
        convertFile(at: index)
    }
    
    private func convertFile(at index: Int) {
        guard index < audioFiles.count else {
            isProcessing = false
            statusMessage = "All conversions completed"
            return
        }
        
        // Update file status
        audioFiles[index].status = .converting
        
        // Get input and output URLs
        let inputURL = audioFiles[index].url
        let outputURL = outputFolder!.appendingPathComponent(inputURL.lastPathComponent)
            .deletingPathExtension()
            .appendingPathExtension("Mono")
            .appendingPathExtension("wav")
        
        // Start conversion in background
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try convertAudioFile(
                    inputURL: inputURL,
                    outputURL: outputURL,
                    updateProgress: { progress in
                        DispatchQueue.main.async {
                            audioFiles[index].progress = progress
                        }
                    }
                )
                
                DispatchQueue.main.async {
                    audioFiles[index].status = .completed
                    // Start next file
                    convertFile(at: index + 1)
                }
            } catch {
                DispatchQueue.main.async {
                    audioFiles[index].status = .failed
                    audioFiles[index].errorMessage = error.localizedDescription
                    // Continue with next file despite error
                    convertFile(at: index + 1)
                }
            }
        }
    }
    
    private func getAudioFormat(for url: URL) -> AudioFileFormat? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        
        return AudioFileFormat(
            channels: Int(format.channelCount),
            sampleRate: format.sampleRate,
            bitDepth: Int(format.streamDescription.pointee.mBitsPerChannel)
        )
    }
}

// FileRowView til at vise individuelle filer
struct FileRowView: View {
    let file: AudioFile
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(file.url.lastPathComponent)
                .font(.headline)
            
            if let format = file.format {
                Text(format.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if file.status == .converting {
                ProgressView(value: file.progress)
                    .progressViewStyle(.linear)
            }
            
            if let error = file.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            HStack {
                switch file.status {
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                case .converting:
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.blue)
                case .pending:
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                }
                
                Text(file.status.description)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

func convertAudioFile(inputURL: URL, outputURL: URL, updateProgress: @escaping (Float) -> Void) throws {
    var inputFile: ExtAudioFileRef?
    var outputFile: ExtAudioFileRef?
    
    // Åbn input fil
    guard ExtAudioFileOpenURL(inputURL as CFURL, &inputFile) == noErr,
          let inputFile = inputFile else {
        throw NSError(domain: "Conversion", code: -1,
                     userInfo: [NSLocalizedDescriptionKey: "Could not open input file"])
    }
    defer { ExtAudioFileDispose(inputFile) }
    
    // Få input format
    var inputFormat = AudioStreamBasicDescription()
    var propSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)
    guard ExtAudioFileGetProperty(inputFile,
                                kExtAudioFileProperty_FileDataFormat,
                                &propSize,
                                &inputFormat) == noErr else {
        throw NSError(domain: "Conversion", code: -1,
                     userInfo: [NSLocalizedDescriptionKey: "Could not get input format"])
    }
    
    // Sæt output format (mono, samme sample rate som input, 16-bit)
    var outputFormat = AudioStreamBasicDescription(
        mSampleRate: inputFormat.mSampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        mBytesPerPacket: 2,
        mFramesPerPacket: 1,
        mBytesPerFrame: 2,
        mChannelsPerFrame: 1,
        mBitsPerChannel: 16,
        mReserved: 0
    )
    
    // Opret output fil
    guard ExtAudioFileCreateWithURL(
        outputURL as CFURL,
        kAudioFileWAVEType,
        &outputFormat,
        nil,
        AudioFileFlags.eraseFile.rawValue,
        &outputFile
    ) == noErr,
    let outputFile = outputFile else {
        throw NSError(domain: "Conversion", code: -1,
                     userInfo: [NSLocalizedDescriptionKey: "Could not create output file"])
    }
    defer { ExtAudioFileDispose(outputFile) }
    
    // Sæt client format på input fil til float for bedre kvalitet
    var clientFormat = AudioStreamBasicDescription(
        mSampleRate: inputFormat.mSampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 4 * inputFormat.mChannelsPerFrame,
        mFramesPerPacket: 1,
        mBytesPerFrame: 4 * inputFormat.mChannelsPerFrame,
        mChannelsPerFrame: inputFormat.mChannelsPerFrame,
        mBitsPerChannel: 32,
        mReserved: 0
    )
    
    guard ExtAudioFileSetProperty(inputFile,
                                kExtAudioFileProperty_ClientDataFormat,
                                UInt32(MemoryLayout<AudioStreamBasicDescription>.stride),
                                &clientFormat) == noErr else {
        throw NSError(domain: "Conversion", code: -1,
                     userInfo: [NSLocalizedDescriptionKey: "Could not set client format"])
    }
    
    // Sæt client format på output fil
    guard ExtAudioFileSetProperty(outputFile,
                                kExtAudioFileProperty_ClientDataFormat,
                                UInt32(MemoryLayout<AudioStreamBasicDescription>.stride),
                                &outputFormat) == noErr else {
        throw NSError(domain: "Conversion", code: -1,
                     userInfo: [NSLocalizedDescriptionKey: "Could not set output client format"])
    }
    
    // Få total antal frames
    var fileLengthFrames: Int64 = 0
    propSize = UInt32(MemoryLayout<Int64>.stride)
    guard ExtAudioFileGetProperty(inputFile,
                                kExtAudioFileProperty_FileLengthFrames,
                                &propSize,
                                &fileLengthFrames) == noErr else {
        throw NSError(domain: "Conversion", code: -1,
                     userInfo: [NSLocalizedDescriptionKey: "Could not get file length"])
    }
    
    // Konverter i chunks
    let bufferSize: UInt32 = 32768
    let channelCount = Int(clientFormat.mChannelsPerFrame)
    let buffer = UnsafeMutablePointer<Float>.allocate(capacity: Int(bufferSize) * channelCount)
    defer { buffer.deallocate() }
    
    // Temporary buffer for mono output
    let monoBuffer = UnsafeMutablePointer<Int16>.allocate(capacity: Int(bufferSize))
    defer { monoBuffer.deallocate() }
    
    var currentFrame: Int64 = 0
    
    while currentFrame < fileLengthFrames {
        var frameCount = bufferSize
        let bytesPerFrame = channelCount * Int(MemoryLayout<Float>.size)
        let totalBytes = Int(bufferSize) * bytesPerFrame
        var inputBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: UInt32(channelCount),
                mDataByteSize: UInt32(totalBytes),
                mData: buffer
            )
        )
        
        // Læs frames
        guard ExtAudioFileRead(inputFile, &frameCount, &inputBufferList) == noErr else {
            throw NSError(domain: "Conversion", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Could not read frames"])
        }
        
        if frameCount == 0 { break }
        
        // Konverter til mono ved at tage gennemsnittet af kanalerne
        let floatBuffer = UnsafeBufferPointer(start: buffer, count: Int(frameCount) * channelCount)
        for frame in 0..<Int(frameCount) {
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += floatBuffer[frame * channelCount + channel]
            }
            // Konverter float til int16 og normaliser
            let avg = sum / Float(channelCount)
            monoBuffer[frame] = Int16(max(-1, min(1, avg)) * 32767.0)
        }
        
        // Skriv mono data
        var outputBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(Int(frameCount) * MemoryLayout<Int16>.stride),
                mData: monoBuffer
            )
        )
        
        guard ExtAudioFileWrite(outputFile, frameCount, &outputBufferList) == noErr else {
            throw NSError(domain: "Conversion", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Could not write frames"])
        }
        
        currentFrame += Int64(frameCount)
        updateProgress(Float(currentFrame) / Float(fileLengthFrames))
    }
}
