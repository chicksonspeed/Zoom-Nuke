import Foundation

// MARK: - Cleanup Process Manager

/// Owns the subprocess, its pipes, and output streaming.
/// All state mutations run on a private serial queue; callbacks are always
/// delivered on the main queue so callers don't need to dispatch themselves.
final class CleanupProcessManager {
    private let queue = DispatchQueue(label: "zoom.nuke.process", qos: .userInitiated)
    private var process: Process?
    private var outputPipe: Pipe?

    /// Receives each chunk of stdout/stderr text. Called on the main queue.
    var onOutput: ((String) -> Void)?
    /// Called on the main queue when the process exits.
    var onExit: ((Int32) -> Void)?

    func launch(scriptURL: URL, arguments: [String]) {
        queue.async { [weak self] in
            self?._launch(scriptURL: scriptURL, arguments: arguments)
        }
    }

    private func _launch(scriptURL: URL, arguments: [String]) {
        let proc = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["bash", scriptURL.path] + arguments
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.qualityOfService = .userInitiated

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.onOutput?(text) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.onOutput?(text) }
        }

        proc.terminationHandler = { [weak self] p in
            let remaining    = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errRemaining = errPipe.fileHandleForReading.readDataToEndOfFile()
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            let code = p.terminationStatus

            DispatchQueue.main.async {
                if !remaining.isEmpty, let text = String(data: remaining, encoding: .utf8) {
                    self?.onOutput?(text)
                }
                if !errRemaining.isEmpty, let text = String(data: errRemaining, encoding: .utf8) {
                    self?.onOutput?(text)
                }
                self?.onExit?(code)
            }
        }

        do {
            try proc.run()
            self.process = proc
            self.outputPipe = outPipe
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.onOutput?("❌ Failed to start process: \(error.localizedDescription)\n")
                self?.onExit?(-1)
            }
        }
    }

    func terminate() {
        queue.async { [weak self] in self?.process?.terminate() }
    }

    func interrupt() {
        queue.async { [weak self] in
            guard let proc = self?.process, proc.isRunning else { return }
            proc.interrupt()
        }
    }
}

// MARK: - Observable Wrapper

/// Bridges CleanupProcessManager into SwiftUI's @StateObject ownership model.
/// A single instance survives view re-renders.
final class CleanupProcessManagerObservable: ObservableObject {
    private let manager = CleanupProcessManager()

    var onOutput: ((String) -> Void)? {
        get { manager.onOutput }
        set { manager.onOutput = newValue }
    }
    var onExit: ((Int32) -> Void)? {
        get { manager.onExit }
        set { manager.onExit = newValue }
    }

    func launch(scriptURL: URL, arguments: [String]) {
        manager.launch(scriptURL: scriptURL, arguments: arguments)
    }
    func terminate() { manager.terminate() }
    func interrupt()  { manager.interrupt() }
}
