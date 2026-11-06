import AppKit

/// Entry point. Marshal is a menu-bar-less "accessory" app: it has no Dock icon
/// and no main window. Everything lives in two floating panels (the robot and
/// the notch widget) plus a small status-bar item as a safety net.
@main
struct MarshalMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--readme-art"), index + 1 < args.count {
            do { try ReadmeArtwork.run(directory: args[index + 1]) }
            catch {
                fputs("Artwork export failed: \(error)\n", stderr)
                exit(EXIT_FAILURE)
            }
            return
        }
        if let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count {
            Snapshot.run(outputDirectory: args[index + 1])
            return
        }

        let delegate = AppDelegate()
        app.delegate = delegate
        // Works both from a .app bundle (LSUIElement) and from `swift run`.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
