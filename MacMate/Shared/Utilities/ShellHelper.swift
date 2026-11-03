import Foundation

/// Run a shell command synchronously and return output + exit code.
@discardableResult
public func shell(_ command: String) -> (output: String, exitCode: Int32) {
    let process = Process()
    let pipe = Pipe()

    process.standardOutput = pipe
    process.standardError = pipe
    process.arguments = ["-c", command]
    process.launchPath = "/bin/zsh"
    process.standardInput = nil

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return ("Error: \(error.localizedDescription)", -1)
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    return (output.trimmingCharacters(in: .whitespacesAndNewlines), process.terminationStatus)
}

/// Locate m1ddc binary in common Homebrew paths or via $PATH.
public func findM1DDCPath() -> String? {
    let candidates = [
        "/opt/homebrew/bin/m1ddc",
        "/usr/local/bin/m1ddc",
    ]

    for path in candidates {
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }

    let (output, status) = shell("which m1ddc 2>/dev/null")
    if status == 0 && !output.isEmpty {
        return output
    }

    return nil
}

/// Locate betterdisplaycli binary
public func findBetterDisplayCLIPath() -> String? {
    let candidates = [
        "/opt/homebrew/bin/betterdisplaycli",
        "/usr/local/bin/betterdisplaycli",
    ]

    for path in candidates {
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }

    let (output, status) = shell("which betterdisplaycli 2>/dev/null")
    if status == 0 && !output.isEmpty {
        return output
    }

    return nil
}
