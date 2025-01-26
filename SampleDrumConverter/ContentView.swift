import SwiftUI
import AudioKit
import AVFoundation
import AudioToolbox

struct AudioFile: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    var status: ConversionStatus = .pending
    var progress: Float = 0.0
    var errorMessage: String?
    
    var format: AudioFileFormat?
    
    enum ConversionStatus: Sendable {
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
        
        var icon: String {
            switch self {
            case .pending: return "circle"
            case .converting: return "arrow.triangle.2.circlepath"
            case .completed: return "checkmark.circle.fill"
            case .failed: return "exclamationmark.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .pending: return .secondary
            case .converting: return .blue
            case .completed: return .green
            case .failed: return .red
            }
        }
    }
}

struct AudioFileFormat: Sendable {
    let channels: Int
    let sampleRate: Double
    let bitDepth: Int
    
    var description: String {
        return "\(channels == 1 ? "Mono" : "Stereo"), \(Int(sampleRate))kHz, \(bitDepth)-bit"
    }
}

func validateFile(at url: URL) throws {
    // Check file size
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let fileSize = attributes[.size] as? Int64 ?? 0
    let maxSize: Int64 = 100 * 1024 * 1024 // 100 MB
    
    if fileSize > maxSize {
        throw ConversionError.fileSizeTooLarge
    }
}

func getAudioFormat(for url: URL) -> AudioFileFormat? {
    guard let file = try? AVAudioFile(forReading: url) else { return nil }
    let format = file.processingFormat
    
    return AudioFileFormat(
        channels: Int(format.channelCount),
        sampleRate: format.sampleRate,
        bitDepth: Int(format.streamDescription.pointee.mBitsPerChannel)
    )
}

enum ConversionStep {
    case selectFiles
    case selectOutput
    case convert
    case completed
    
    var title: String {
        switch self {
        case .selectFiles: return "Select Files"
        case .selectOutput: return "Select Output"
        case .convert: return "Convert"
        case .completed: return "Completed"
        }
    }
    
    var icon: String {
        switch self {
        case .selectFiles: return "plus.rectangle.fill"
        case .selectOutput: return "folder.fill"
        case .convert: return "waveform.circle.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }
}

struct ContentView: View {
    @State private var currentStep = ConversionStep.selectFiles
    @State private var audioFiles: [AudioFile] = []
    @State private var isProcessing = false
    @State private var outputFolder: URL?
    @State private var customStatusMessage: String?
    
    private let maxFiles = 50
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    
    private var statusMessage: String {
        if let custom = customStatusMessage {
            return custom
        }
        if isProcessing {
            let completed = audioFiles.filter { $0.status == .completed }.count
            let total = audioFiles.count
            return "Converting... (\(completed)/\(total) completed)"
        }
        if audioFiles.isEmpty {
            return "Click 'Add WAV Files' button to get started"
        }
        if outputFolder == nil {
            return "Select output folder to start conversion"
        }
        let pending = audioFiles.filter { $0.status == .pending }.count
        if pending > 0 {
            return "Ready to convert \(pending) files"
        }
        let failed = audioFiles.filter { $0.status == .failed }.count
        if failed > 0 {
            return "\(failed) files failed to convert"
        }
        return "All files converted successfully"
    }
    
    var totalFileSize: Int64 {
        audioFiles.compactMap { try? FileManager.default.attributesOfItem(atPath: $0.url.path)[.size] as? Int64 }
            .reduce(0, +)
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Progress indicators
                HStack(spacing: 15) {
                    ForEach([ConversionStep.selectFiles, .selectOutput, .convert, .completed], id: \.self) { step in
                        Circle()
                            .fill(currentStep == step ? Color.white : Color.gray)
                            .frame(width: 10, height: 10)
                            .animation(.easeInOut(duration: 0.3), value: currentStep)
                    }
                }
                .padding(.top)
                
                // Current step content
                switch currentStep {
                case .selectFiles:
                    SelectFilesView(
                        audioFiles: $audioFiles,
                        onNext: { withAnimation(.easeInOut) { currentStep = .selectOutput } }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
                case .selectOutput:
                    SelectOutputView(
                        outputFolder: $outputFolder,
                        onBack: { withAnimation(.easeInOut) { currentStep = .selectFiles } },
                        onNext: { withAnimation(.easeInOut) { currentStep = .convert } }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
                case .convert:
                    ConvertView(
                        audioFiles: $audioFiles,
                        currentStep: $currentStep,
                        outputFolder: outputFolder,
                        onBack: { withAnimation(.easeInOut) { currentStep = .selectOutput } }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
                case .completed:
                    CompletionView(
                        audioFiles: audioFiles,
                        outputFolder: outputFolder,
                        onStartOver: { 
                            withAnimation(.easeInOut) { 
                                currentStep = .selectFiles
                                audioFiles.removeAll()
                            }
                        }
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .foregroundColor(.white)
            .animation(.easeInOut, value: currentStep)
        }
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
            let newFiles = panel.urls.compactMap { url -> AudioFile? in
                do {
                    try validateFile(at: url)
                    return AudioFile(url: url, format: getAudioFormat(for: url))
                } catch {
                    setStatusMessage("Skipped file \(url.lastPathComponent): \(error.localizedDescription)")
                    return nil
                }
            }
            
            // Check for max files limit
            let remainingSlots = maxFiles - audioFiles.count
            if newFiles.count > remainingSlots {
                setStatusMessage("Can only add \(remainingSlots) more files. Maximum is \(maxFiles).")
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
            setStatusMessage("Output folder selected: \(panel.url?.lastPathComponent ?? "")")
        }
    }
    
    func startConversion() {
        guard outputFolder != nil else {
            setStatusMessage("Please select an output folder first")
            return
        }
        
        isProcessing = true
        
        // Find first pending file
        guard let index = audioFiles.firstIndex(where: { $0.status == .pending }) else {
            isProcessing = false
            setStatusMessage("No pending files to convert")
            return
        }
        
        // Start conversion for this file
        convertFile(at: index)
    }
    
    private func convertFile(at index: Int) {
        guard index < audioFiles.count else {
            isProcessing = false
            setStatusMessage("All conversions completed")
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
    
    private func setStatusMessage(_ message: String) {
        customStatusMessage = message
    }

    @MainActor
    private func addFile(from url: URL) {
        let newFile = AudioFile(url: url, format: getAudioFormat(for: url))
        if audioFiles.count < maxFiles {
            audioFiles.append(newFile)
        } else {
            setStatusMessage("Maximum number of files (\(maxFiles)) reached")
        }
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[\(Date())] \(message)")
        #endif
    }
}

// FileRowView til at vise individuelle filer
struct FileRowView: View {
    let file: AudioFile
    var onRetry: (() -> Void)?
    var onReveal: (() -> Void)?
    var onRemove: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.status.icon)
                .foregroundColor(file.status.color)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(file.url.lastPathComponent)
                    .font(.system(.body))
                if let format = file.format {
                    Text(format.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if file.status == .converting {
                ProgressView(value: file.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 100)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if file.status == .failed {
                Button(action: { onRetry?() }) {
                    Label("Retry Conversion", systemImage: "arrow.clockwise")
                }
            }
            if file.status == .completed {
                Button(action: { onReveal?() }) {
                    Label("Show in Finder", systemImage: "folder")
                }
            }
            Divider()
            Button(role: .destructive, action: { onRemove?() }) {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

func convertAudioFile(inputURL: URL, outputURL: URL, updateProgress: @escaping (Float) -> Void) throws {
    // Validate file first
    try validateFile(at: inputURL)
    
    var inputFile: ExtAudioFileRef?
    var outputFile: ExtAudioFileRef?
    
    // Open input file
    guard ExtAudioFileOpenURL(inputURL as CFURL, &inputFile) == noErr,
          let inputFile = inputFile else {
        throw ConversionError.inputFileOpenFailed
    }
    defer { ExtAudioFileDispose(inputFile) }
    
    // Get input format
    var inputFormat = AudioStreamBasicDescription()
    var propSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)
    guard ExtAudioFileGetProperty(inputFile,
                                kExtAudioFileProperty_FileDataFormat,
                                &propSize,
                                &inputFormat) == noErr else {
        throw NSError(domain: "Conversion", code: -1,
                     userInfo: [NSLocalizedDescriptionKey: "Could not get input format"])
    }
    
    // Set output format (mono, same sample rate as input, 16-bit)
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
    
    // Create output file
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
    
    // Set client format on input file to float for better quality
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
    
    // Set client format on output file
    guard ExtAudioFileSetProperty(outputFile,
                                kExtAudioFileProperty_ClientDataFormat,
                                UInt32(MemoryLayout<AudioStreamBasicDescription>.stride),
                                &outputFormat) == noErr else {
        throw NSError(domain: "Conversion", code: -1,
                     userInfo: [NSLocalizedDescriptionKey: "Could not set output client format"])
    }
    
    // Get total number of frames
    var fileLengthFrames: Int64 = 0
    propSize = UInt32(MemoryLayout<Int64>.stride)
    guard ExtAudioFileGetProperty(inputFile,
                                kExtAudioFileProperty_FileLengthFrames,
                                &propSize,
                                &fileLengthFrames) == noErr else {
        throw NSError(domain: "Conversion", code: -1,
                     userInfo: [NSLocalizedDescriptionKey: "Could not get file length"])
    }
    
    // Convert in chunks
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
        
        // Read frames
        guard ExtAudioFileRead(inputFile, &frameCount, &inputBufferList) == noErr else {
            throw NSError(domain: "Conversion", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Could not read frames"])
        }
        
        if frameCount == 0 { break }
        
        // Convert to mono by averaging the channels
        let floatBuffer = UnsafeBufferPointer(start: buffer, count: Int(frameCount) * channelCount)
        for frame in 0..<Int(frameCount) {
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += floatBuffer[frame * channelCount + channel]
            }
            // Convert float to int16 and normalize
            let avg = sum / Float(channelCount)
            monoBuffer[frame] = Int16(max(-1, min(1, avg)) * 32767.0)
        }
        
        // Write mono data
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

enum ConversionError: LocalizedError {
    case inputFileOpenFailed
    case outputFileCreateFailed
    case inputFormatReadFailed
    case clientFormatSetFailed
    case fileLengthReadFailed
    case readFramesFailed
    case writeFramesFailed
    case fileSizeTooLarge
    
    var errorDescription: String? {
        switch self {
        case .inputFileOpenFailed:
            return "Could not open input file. Please ensure it's a valid WAV file."
        case .outputFileCreateFailed:
            return "Could not create output file. Please check disk space and permissions."
        case .inputFormatReadFailed:
            return "Could not read input file format. File may be corrupted."
        case .clientFormatSetFailed:
            return "Could not set audio processing format. Please try again."
        case .fileLengthReadFailed:
            return "Could not determine file length. File may be corrupted."
        case .readFramesFailed:
            return "Error reading audio data. File may be corrupted."
        case .writeFramesFailed:
            return "Error writing audio data. Please check disk space."
        case .fileSizeTooLarge:
            return "File size exceeds maximum limit of 100 MB."
        }
    }
}

struct SelectFilesView: View {
    @Binding var audioFiles: [AudioFile]
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            // Title
            Text("Select WAV Files")
                .font(.title)
                .fontWeight(.bold)
            
            // Icon and drop zone
            VStack(spacing: 20) {
                Image(systemName: "plus.rectangle.fill")
                    .font(.system(size: 40, weight: .ultraLight))
                
                Text("Click to select WAV files\nor drag files here")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: 200)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            .onTapGesture(perform: selectFiles)
            
            // Selected files list
            if !audioFiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected Files:")
                        .fontWeight(.medium)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(audioFiles) { file in
                                HStack {
                                    Text(file.url.lastPathComponent)
                                    Spacer()
                                    if let format = file.format {
                                        Text(format.description)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
            }
            
            // Next button
            Button(action: onNext) {
                Text("Next")
                    .fontWeight(.medium)
                    .frame(width: 100)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .disabled(audioFiles.isEmpty)
            
            Spacer()
        }
        .padding()
    }
    
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.wav]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK {
            let newFiles = panel.urls.compactMap { url -> AudioFile? in
                do {
                    try validateFile(at: url)
                    return AudioFile(url: url, format: getAudioFormat(for: url))
                } catch {
                    // Show error in UI
                    return nil
                }
            }
            audioFiles.append(contentsOf: newFiles)
        }
    }
}

struct SelectOutputView: View {
    @Binding var outputFolder: URL?
    let onBack: () -> Void
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            // Title
            Text("Select Output Folder")
                .font(.title)
                .fontWeight(.bold)
            
            // Icon and select area
            VStack(spacing: 20) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 40, weight: .ultraLight))
                
                if let folder = outputFolder {
                    VStack(spacing: 8) {
                        Text("Selected Folder:")
                            .fontWeight(.medium)
                        Text(folder.lastPathComponent)
                            .foregroundColor(.gray)
                    }
                } else {
                    Text("Click to select output folder")
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 200)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            .onTapGesture(perform: selectOutputFolder)
            
            // Navigation buttons
            HStack(spacing: 20) {
                Button(action: onBack) {
                    Text("Back")
                        .fontWeight(.medium)
                        .frame(width: 100)
                }
                .buttonStyle(.bordered)
                
                Button(action: onNext) {
                    Text("Next")
                        .fontWeight(.medium)
                        .frame(width: 100)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .disabled(outputFolder == nil)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose Output Folder"
        
        if panel.runModal() == .OK {
            outputFolder = panel.url
        }
    }
}

struct ConvertView: View {
    @Binding var audioFiles: [AudioFile]
    @Binding var currentStep: ConversionStep
    let outputFolder: URL?
    let onBack: () -> Void
    @State private var isConverting = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 30) {
            // Title
            Text("Convert Files")
                .font(.title)
                .fontWeight(.bold)
            
            // Status and progress
            VStack(spacing: 20) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 40, weight: .ultraLight))
                
                if isConverting {
                    let completed = audioFiles.filter { $0.status == .completed }.count
                    VStack(spacing: 8) {
                        Text("Converting files...")
                            .fontWeight(.medium)
                        Text("\(completed) of \(audioFiles.count) completed")
                            .foregroundColor(.gray)
                        
                        // Show current file progress
                        if let converting = audioFiles.first(where: { $0.status == .converting }) {
                            VStack(spacing: 4) {
                                Text(converting.url.lastPathComponent)
                                    .foregroundColor(.gray)
                                ProgressView(value: converting.progress)
                                    .progressViewStyle(.linear)
                                    .frame(width: 200)
                            }
                            .padding(.top)
                        }
                    }
                } else {
                    Text("Ready to convert \(audioFiles.count) files")
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 200)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            
            // Buttons
            if isConverting {
                Button(action: { /* Show in Finder */ }) {
                    Text("Show in Finder")
                        .fontWeight(.medium)
                        .frame(width: 150)
                }
                .buttonStyle(.bordered)
            } else {
                HStack(spacing: 20) {
                    Button(action: onBack) {
                        Text("Back")
                            .fontWeight(.medium)
                            .frame(width: 100)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: startConversion) {
                        Text("Start")
                            .fontWeight(.medium)
                            .frame(width: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func startConversion() {
        guard let outputFolder = outputFolder else { return }
        isConverting = true
        
        // Start conversion for first pending file
        Task {
            await convertNextFile(outputFolder: outputFolder)
        }
    }
    
    private func convertNextFile(outputFolder: URL) async {
        // Find first pending file
        guard let index = audioFiles.firstIndex(where: { $0.status == .pending }) else {
            isConverting = false
            // Add this line to transition to completion view
            currentStep = .completed  // Vi skal passe denne værdi gennem som binding
            return
        }
        
        // Update file status
        await MainActor.run {
            audioFiles[index].status = .converting
        }
        
        // Get input and output URLs
        let inputURL = audioFiles[index].url
        let outputURL = outputFolder.appendingPathComponent(inputURL.lastPathComponent)
            .deletingPathExtension()
            .appendingPathExtension("Mono")
            .appendingPathExtension("wav")
        
        do {
            try await convertFile(at: index, from: inputURL, to: outputURL)
            
            await MainActor.run {
                audioFiles[index].status = .completed
                // Continue with next file
                Task {
                    await convertNextFile(outputFolder: outputFolder)
                }
            }
        } catch {
            await MainActor.run {
                audioFiles[index].status = .failed
                audioFiles[index].errorMessage = error.localizedDescription
                errorMessage = "Error converting \(inputURL.lastPathComponent): \(error.localizedDescription)"
                
                // Continue with next file despite error
                Task {
                    await convertNextFile(outputFolder: outputFolder)
                }
            }
        }
    }
    
    private func convertFile(at index: Int, from inputURL: URL, to outputURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try convertAudioFile(
                    inputURL: inputURL,
                    outputURL: outputURL,
                    updateProgress: { progress in
                        Task { @MainActor in
                            audioFiles[index].progress = progress
                        }
                    }
                )
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func showInFinder() {
        guard let outputFolder = outputFolder else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: outputFolder.path)
    }
}

struct CompletionView: View {
    let audioFiles: [AudioFile]
    let outputFolder: URL?
    let onStartOver: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50, weight: .ultraLight))
            
            // Stats
            VStack(spacing: 10) {
                Text("Conversion Complete!")
                    .font(.title)
                    .fontWeight(.bold)
                
                let successful = audioFiles.filter { $0.status == .completed }.count
                let failed = audioFiles.filter { $0.status == .failed }.count
                
                Text("\(successful) files converted successfully")
                    .foregroundColor(.gray)
                
                if failed > 0 {
                    Text("\(failed) files failed")
                        .foregroundColor(.red)
                }
            }
            
            // Action buttons
            VStack(spacing: 15) {
                Button(action: {
                    guard let outputFolder = outputFolder else { return }
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: outputFolder.path)
                }) {
                    Label("Show in Finder", systemImage: "folder")
                        .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                
                Button(action: onStartOver) {
                    Label("Convert More Files", systemImage: "arrow.clockwise")
                        .frame(width: 200)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top)
            
            Spacer()
        }
        .padding()
    }
}
