import AVFoundation
import Foundation

public enum SoundFileValidationError: Error, Equatable {
    case unsupportedExtension(String)
    case fileMissing
    case unreadableDuration
    case durationTooLong(Double)
}

public enum SoundFileValidator {
    public static let maxDuration: Double = 2.0
    public static let supportedExtensions: Set<String> = ["mp3", "wav", "aiff", "aif", "m4a"]

    public static func isSupportedExtension(_ pathExtension: String) -> Bool {
        supportedExtensions.contains(pathExtension.lowercased())
    }

    public static func validate(url: URL) async throws {
        let ext = url.pathExtension.lowercased()
        guard isSupportedExtension(ext) else {
            throw SoundFileValidationError.unsupportedExtension(ext)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SoundFileValidationError.fileMissing
        }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite else {
            throw SoundFileValidationError.unreadableDuration
        }
        guard seconds <= maxDuration else {
            throw SoundFileValidationError.durationTooLong(seconds)
        }
    }
}
