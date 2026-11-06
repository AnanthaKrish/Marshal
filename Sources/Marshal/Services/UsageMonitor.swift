import Combine
import Foundation
import MarshalCore

@MainActor
final class UsageMonitor {
    private let store: UsageStore
    private let agents: AgentSessionStore
    private let files = UsageFiles()
    private var localTask: Task<Void, Never>?
    private var quotaTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    init(store: UsageStore, agents: AgentSessionStore) { self.store = store; self.agents = agents }
    func start() {
        guard localTask == nil else { return }
        localTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let ids = self.agents.sessions.filter { $0.agent == "codex" }.map(\.session)
                let samples = await self.files.read(sessions: ids)
                guard !Task.isCancelled else { return }
                for sample in samples { self.store.apply(sample) }
                self.store.prune(now: .now)
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
    }
    func stop() {
        localTask?.cancel(); localTask = nil
        timerTask?.cancel(); timerTask = nil
        quotaTask?.cancel(); quotaTask = nil
    }
    func refresh() {
        guard quotaTask == nil else { return }
        store.isRefreshing = true
        quotaTask = Task { [weak self] in
            let worker = Task.detached(priority: .utility) { () -> Result<UsageSample, CodexUsageError> in
                do { return .success(try CodexUsageClient.read()) }
                catch let error as CodexUsageError { return .failure(error) }
                catch { return .failure(.unavailable) }
            }
            let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard let self else { return }
            defer { self.store.isRefreshing = false; self.quotaTask = nil }
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let sample): self.store.apply(sample)
            case .failure(let error): self.store.setMessage(error.message, for: "codex")
            }
        }
    }
}
