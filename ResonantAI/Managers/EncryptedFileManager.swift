import Foundation
import CryptoKit
import AVFoundation

final class EncryptedFileManager {
    private let key: SymmetricKey

    init() {
        // In production, store key securely in Keychain!
        self.key = SymmetricKey(size: .bits256)
    }

    /// Returns the URL for the encrypted audio file (.enc) for a given segment ID.
    func encryptedAudioURL(for id: UUID) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("\(id).enc")
    }

    /// Encrypts the file at the given URL and writes the encrypted data to a .enc file.
    /// Does NOT overwrite the original file.
    func encryptFile(at url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let sealed = try! AES.GCM.seal(data, using: key)
        let encURL = url.deletingPathExtension().appendingPathExtension("enc")
        try? sealed.combined?.write(to: encURL)
        // Optionally: remove the original file for security
        // try? FileManager.default.removeItem(at: url)
    }

    /// Decrypts the .enc file and returns the raw data.
    func decryptFile(at url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url),
              let sealedBox = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(sealedBox, using: key)
    }

    /// Converts an m4a file to a true PCM WAV file at the given output URL.
    func convertM4AToWAV(m4aURL: URL, wavURL: URL) throws {
        let asset = AVURLAsset(url: m4aURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw NSError(domain: "Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAssetExportSession"])
        }
        exporter.outputURL = wavURL
        exporter.outputFileType = .wav
        let group = DispatchGroup()
        group.enter()
        exporter.exportAsynchronously {
            group.leave()
        }
        group.wait()
        if exporter.status != .completed {
            throw exporter.error ?? NSError(domain: "Export", code: 2, userInfo: [NSLocalizedDescriptionKey: "Export failed"])
        }
    }

    /// Decrypts an encrypted audio file (.enc) to a temporary WAV file for transcription.
    /// If the input is an m4a file, converts it to a true PCM WAV file.
    /// Falls back to copying the file as-is if decryption fails (for debugging or unencrypted files).
    func decryptedTempURL(for encryptedURL: URL) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        if encryptedURL.pathExtension.lowercased() == "enc" {
            // Decrypt the .enc file
            guard let decryptedData = decryptFile(at: encryptedURL) else {
                throw NSError(domain: "Decryption", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decrypt audio file"])
            }
            // Write decrypted data to temp WAV file
            try decryptedData.write(to: tempURL)
            return tempURL
        } else if let plainData = try? Data(contentsOf: encryptedURL) {
            // Fallback: treat as unencrypted for debugging
            // If the file is m4a, convert to wav
            if encryptedURL.pathExtension.lowercased() == "m4a" {
                let m4aTemp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
                try plainData.write(to: m4aTemp)
                try convertM4AToWAV(m4aURL: m4aTemp, wavURL: tempURL)
                try? FileManager.default.removeItem(at: m4aTemp)
                return tempURL
            } else {
                try plainData.write(to: tempURL)
                return tempURL
            }
        } else {
            throw NSError(domain: "Decryption", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to decrypt or read audio file"])
        }
    }
} 