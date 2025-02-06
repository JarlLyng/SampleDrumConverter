import XCTest
import AVFoundation
@testable import SampleDrumConverter

final class AudioConversionTests: XCTestCase {
    let testBundle = Bundle(for: AudioConversionTests.self)
    
    func testStereoToMonoConversion() async throws {
        // Setup test files
        guard let inputURL = testBundle.url(forResource: "test_stereo", withExtension: "wav"),
              let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_output.wav") else {
            XCTFail("Could not create test URLs")
            return
        }
        
        // Perform conversion
        try convertAudioFile(inputURL: inputURL, outputURL: outputURL) { _ in }
        
        // Verify output
        guard let outputFile = try? AVAudioFile(forReading: outputURL) else {
            XCTFail("Could not read output file")
            return
        }
        
        // Check that output is mono
        XCTAssertEqual(outputFile.processingFormat.channelCount, 1)
        
        // Check that sample rate is preserved
        let inputFile = try XCTUnwrap(try? AVAudioFile(forReading: inputURL))
        XCTAssertEqual(outputFile.processingFormat.sampleRate, inputFile.processingFormat.sampleRate)
        
        // Cleanup
        try? FileManager.default.removeItem(at: outputURL)
    }
    
    func testErrorHandling() async throws {
        // Test with invalid input file
        let invalidURL = URL(fileURLWithPath: "/invalid/path.wav")
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("error_test.wav")
        
        do {
            try convertAudioFile(inputURL: invalidURL, outputURL: outputURL) { _ in }
            XCTFail("Expected error for invalid input")
        } catch {
            XCTAssertTrue(error is ConversionError)
        }
    }
    
    func testFileSizeValidation() async throws {
        // Create a large test file
        let largeFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("large_test.wav")
        
        // Test validation
        do {
            try validateFile(at: largeFileURL)
            XCTFail("Expected error for large file")
        } catch ConversionError.fileSizeTooLarge {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
} 