import Foundation
import Network
import Combine

public enum GemmaModelStatus: Equatable {
    case notInstalled
    case downloading(progress: Double, bytesWritten: Int64, totalBytes: Int64, speedMBps: Double)
    case ready
    case error(String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

@MainActor
public final class GemmaModelManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    public static let shared = GemmaModelManager()

    public static let modelURLString = "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm"
    public static let modelFilename = "gemma-4-E2B-it.litertlm"
    public static let estimatedSizeGB = 2.62

    @Published public var status: GemmaModelStatus = .notInstalled
    @Published public var wifiOnlyDownload: Bool = true
    @Published public var modelDiskSizeString: String = "0 MB"

    private var downloadTask: URLSessionDownloadTask?
    private var downloadStartTime: Date?
    private var session: URLSession?
    private let pathMonitor = NWPathMonitor()
    private var isConnectedToWifi = true

    public override init() {
        super.init()
        setupNetworkMonitoring()
        checkLocalModelFile()
    }

    private func setupNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnectedToWifi = path.usesInterfaceType(.wifi)
            }
        }
        let queue = DispatchQueue(label: "org.sih2026.foreverfit.networkmonitor")
        pathMonitor.start(queue: queue)
    }

    public var localModelURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsDir = docs.appendingPathComponent("models", isDirectory: true)
        if !FileManager.default.fileExists(atPath: modelsDir.path) {
            try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }
        return modelsDir.appendingPathComponent(Self.modelFilename)
    }

    public func checkLocalModelFile() {
        let path = localModelURL.path
        if FileManager.default.fileExists(atPath: path) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                let sizeGB = Double(size) / (1024 * 1024 * 1024)
                if sizeGB > 0.05 { // Model exists and has substantial content
                    self.status = .ready
                    self.modelDiskSizeString = String(format: "%.2f GB", sizeGB)
                    return
                }
            }
        }
        self.status = .notInstalled
        self.modelDiskSizeString = "0 MB"
    }

    // MARK: - Download Lifecycle

    public func startDownload() throws {
        guard !status.isDownloading else { return }

        // Wi-Fi check (matching Flutter StateError wording)
        if wifiOnlyDownload && !isConnectedToWifi {
            throw StateError(
                message: "Wi-Fi-only download is on and this device isn't on Wi-Fi. Connect to Wi-Fi or turn off 'Wi-Fi only' in Settings to continue."
            )
        }

        guard let url = URL(string: Self.modelURLString) else {
            self.status = .error("Invalid model URL")
            return
        }

        self.status = .downloading(progress: 0.0, bytesWritten: 0, totalBytes: 2_812_000_000, speedMBps: 0.0)
        self.downloadStartTime = Date()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        self.downloadTask = session?.downloadTask(with: url)
        downloadTask?.resume()
    }

    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        self.status = .notInstalled
    }

    public func deleteModel() {
        cancelDownload()
        let path = localModelURL.path
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
        self.status = .notInstalled
        self.modelDiskSizeString = "0 MB"
    }

    // MARK: - URLSessionDownloadDelegate

    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 2_812_000_000
            let progress = min(1.0, Double(totalBytesWritten) / Double(total))
            let elapsed = Date().timeIntervalSince(self.downloadStartTime ?? Date())
            let speed = elapsed > 0 ? (Double(totalBytesWritten) / (1024 * 1024)) / elapsed : 0.0

            self.status = .downloading(
                progress: progress,
                bytesWritten: totalBytesWritten,
                totalBytes: total,
                speedMBps: speed
            )
        }
    }

    public nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsDir = docs.appendingPathComponent("models", isDirectory: true)

        do {
            if !fileManager.fileExists(atPath: modelsDir.path) {
                try fileManager.createDirectory(at: modelsDir, withIntermediateDirectories: true, attributes: nil)
            }
            let destination = modelsDir.appendingPathComponent(GemmaModelManager.modelFilename)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            // Move synchronously while temporary location is guaranteed to exist
            try fileManager.moveItem(at: location, to: destination)

            Task { @MainActor in
                self.checkLocalModelFile()
            }
        } catch {
            Task { @MainActor in
                self.status = .error("Failed to save downloaded model: \(error.localizedDescription)")
            }
        }
    }

    public nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let err = error {
            Task { @MainActor in
                let nsErr = err as NSError
                if nsErr.code != NSURLErrorCancelled {
                    self.status = .error("Download failed: \(err.localizedDescription)")
                }
            }
        }
    }
}

public struct StateError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}
