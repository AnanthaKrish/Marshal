import Foundation

/// Writes the two-line shell shim that agent hooks call. Rewritten at every
/// launch so it always points at the CLI binary next to the running app.
public enum ShimInstaller {
    public static func script(binaryPath: String) -> String {
        """
        #!/bin/sh
        # Written by Marshal at launch. Points at the marshal CLI next to the running app.
        BIN="\(binaryPath)"
        [ -x "$BIN" ] && exec "$BIN" "$@"
        exit 0

        """
    }

    public static func install(binaryPath: String, at file: URL = MarshalPaths.shim) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(script(binaryPath: binaryPath).utf8).write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    }
}
