import Foundation

/// Marshal receives Claude's status-line payload directly. An existing status
/// line is optional compatibility: it is never a source for Marshal's readings.
public enum ClaudeUsageReporter {
    public static func report(_ data: Data,
                              cacheDirectory: URL = UsageCache.directory,
                              savedStatusLine: URL = UsageInstaller.savedFile,
                              output: FileHandle = .standardOutput) {
        let sample = UsageParsing.claude(data)
        // Save independently, before running any optional existing command.
        if let sample { try? UsageCache.write(sample, directory: cacheDirectory) }
        if let original = UsageInstaller.originalCommand(saved: savedStatusLine) {
            StatusLineForwarder.run(command: original, input: data, output: output)
        } else if let context = sample?.context {
            try? output.write(contentsOf: Data("Context \(Int(context.usedPercent.rounded()))%\n".utf8))
        }
    }
}
