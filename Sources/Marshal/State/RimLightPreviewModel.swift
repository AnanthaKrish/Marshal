import Combine
import Foundation

/// Local preview state only: never creates sessions, nudges, or saved preferences.
@MainActor
final class RimLightPreviewModel: ObservableObject {
    @Published private(set) var selected: CompletionLightStyle
    @Published private(set) var isPlaying = false
    @Published private(set) var isTryingAll = false
    @Published private(set) var trigger = 0
    private var task: Task<Void, Never>?

    init(selected: CompletionLightStyle) { self.selected = selected }
    deinit { task?.cancel() }

    func play(_ style: CompletionLightStyle? = nil) {
        stop()
        begin(style ?? selected)
        task = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(CompletionLightStyle.previewDuration)) } catch { return }
            self?.isPlaying = false
        }
    }

    func tryAll() {
        stop()
        isTryingAll = true
        task = Task { [weak self] in
            for style in CompletionLightStyle.allCases {
                guard !Task.isCancelled else { return }
                self?.begin(style)
                do { try await Task.sleep(for: .seconds(CompletionLightStyle.previewDuration)) } catch { return }
                self?.isPlaying = false
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            }
            self?.isTryingAll = false
        }
    }

    func stop() {
        task?.cancel(); task = nil
        isPlaying = false
        isTryingAll = false
    }

    private func begin(_ style: CompletionLightStyle) {
        selected = style
        trigger += 1
        isPlaying = true
    }
}
