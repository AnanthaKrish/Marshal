import Foundation
import MarshalCore

let usage = """
usage: marshal status --agent <id> --session <id> --state <state> [--title T] [--project P] [--message M]
                        [--app-path <bundle path>] [--app-pid <pid>]
       marshal hook <claude-code|codex>        (reads the hook JSON on stdin)
       marshal setup <claude-code|codex> [--write | --remove]
       marshal usage setup [--write | --remove] (connects Marshal directly to Claude Code)
       marshal usage claude                     (reads Claude status-line JSON on stdin)
       marshal usage codex                      (reads account limits; starts no chat)
       marshal ping
       marshal vitals                          (samples the machine for 2 s, prints Vitals JSON)

"""

func fail() -> Never {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(64)
}

/// Parses `--key value` pairs; any malformed shape is a usage error.
func parseOptions(_ args: ArraySlice<String>) -> [String: String] {
    var options: [String: String] = [:]
    var index = args.startIndex
    while index < args.endIndex {
        let key = args[index]
        guard key.hasPrefix("--"), index + 1 < args.endIndex else { fail() }
        options[String(key.dropFirst(2))] = args[index + 1]
        index += 2
    }
    return options
}

/// Just the event name, read before (and independently of) the full `HookPayload`.
struct HookEventName: Decodable {
    var name: String
    private enum CodingKeys: String, CodingKey { case name = "hook_event_name" }
}

func parseAgent(_ name: String?) -> HookAgent {
    guard let name, let agent = HookAgent(rawValue: name) else { fail() }
    return agent
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { fail() }

switch command {
case "usage":
    guard args.count >= 2 else { fail() }
    switch args[1] {
    case "claude":
        let data = FileHandle.standardInput.readDataToEndOfFile()
        ClaudeUsageReporter.report(data)
    case "setup":
        guard args.count == 3 else { fail() }
        do {
            if args[2] == "--write" {
                let changed = try UsageInstaller.install()
                print(changed ? "Marshal is connected directly to Claude Code for usage reporting." : "Claude usage is already connected.")
            } else if args[2] == "--remove" {
                let changed = try UsageInstaller.remove()
                print(changed ? "Claude usage disconnected; previous status-line settings restored." : "Claude usage was not connected.")
            } else { fail() }
        } catch {
            FileHandle.standardError.write(Data("Could not update Claude usage integration: \(error)\n".utf8)); exit(1)
        }
    case "codex":
        do {
            let sample = try CodexUsageClient.read()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            FileHandle.standardOutput.write(try encoder.encode(sample))
            print()
        } catch {
            let message = (error as? CodexUsageError)?.message ?? "Codex limits unavailable"
            FileHandle.standardError.write(Data("\(message)\n".utf8)); exit(1)
        }
    default: fail()
    }

case "status":
    let options = parseOptions(args.dropFirst())
    guard let agent = options["agent"], let session = options["session"],
          let stateName = options["state"], let state = AgentState(rawValue: stateName) else { fail() }
    var appPid: Int32?
    if let pidText = options["app-pid"] {
        guard let pid = Int32(pidText) else { fail() }
        appPid = pid
    }
    var event = AgentEvent(
        agent: agent, session: session, state: state,
        title: options["title"], project: options["project"], message: options["message"],
        at: .now
    )
    // Either flag replaces detection entirely (the other stays nil); with neither, detect.
    let anyOverride = options["app-path"] != nil || appPid != nil
    let owner = anyOverride ? nil : ProcessAncestry.owningApp()
    event.appPath = options["app-path"] ?? owner?.bundlePath
    event.appPid = appPid ?? owner?.pid
    SocketClient.send(event)

case "hook":
    guard args.count == 2 else { fail() }
    let agent = parseAgent(args[1])
    let input = FileHandle.standardInput.readDataToEndOfFile()
    // Codex expects a JSON reply to Stop, so it must not depend on the rest of the payload
    // decoding or mapping.
    if agent == .codex, (try? JSONDecoder().decode(HookEventName.self, from: input))?.name == "Stop" {
        print("{}")
    }
    guard let payload = try? JSONDecoder().decode(HookPayload.self, from: input),
          var event = HookMapper.map(agent: agent, payload: payload, now: .now) else { break }
    let owner = ProcessAncestry.owningApp()
    event.appPath = owner?.bundlePath
    event.appPid = owner?.pid
    SocketClient.send(event)

case "setup":
    guard args.count >= 2, args.count <= 3 else { fail() }
    let agent = parseAgent(args[1])
    let file = HookInstaller.defaultFile(for: agent)
    let shim = MarshalPaths.shim.path
    switch args.count == 3 ? args[2] : nil {
    case nil:
        print(HookInstaller.fragmentJSON(for: agent, shimPath: shim))
        print("Add this to \(file.path), or run: marshal setup \(agent.rawValue) --write")
    case "--write":
        let existed = FileManager.default.fileExists(atPath: file.path)
        do {
            switch try HookInstaller.write(agent: agent, shimPath: shim, into: file) {
            case .added:
                let backup = existed ? " (backup: \(file.lastPathComponent).marshal-backup-<UTC timestamp>)" : ""
                print("Added hooks to \(file.path)\(backup)")
            case .alreadyPresent:
                print("Hooks already present in \(file.path)")
            }
            if agent == .codex {
                print("Codex asks you to trust new hooks the next time it starts.")
            }
        } catch {
            FileHandle.standardError.write(Data("Could not write \(file.path): \(error)\n".utf8))
            exit(1)
        }
    case "--remove":
        do {
            let result = try HookInstaller.remove(agent: agent, from: file)
            print(result.removed ? "Removed Marshal hooks from \(file.path)" : "No Marshal hooks found in \(file.path)")
            if agent == .codex && result.removed && result.shiftedLaterGroups {
                print("Other hooks moved position; Codex will ask you to trust them again.")
            }
        } catch {
            FileHandle.standardError.write(Data("Could not update \(file.path): \(error)\n".utf8))
            exit(1)
        }
    default:
        fail()
    }

case "ping":
    guard args.count == 1 else { fail() }
    if !SocketClient.ping() {
        print("Marshal is not running")
        exit(1)
    }

case "vitals":
    guard args.count == 1 else { fail() }
    let cpuBefore = CPUSampler.ticks()
    let processesBefore = TopProcessSampler.snapshot()
    let startedAt = Date.now
    Thread.sleep(forTimeInterval: 2)
    let cpuAfter = CPUSampler.ticks()
    let processesAfter = TopProcessSampler.snapshot()
    let interval = Date.now.timeIntervalSince(startedAt)

    var vitals = Vitals()
    if let cpuBefore, let cpuAfter {
        let load = CPUSampler.load(previous: cpuBefore, current: cpuAfter)
        vitals.cpu = load
        vitals.cpuRaw = load
    }
    if let memory = MemorySampler.sample() {
        vitals.memoryUsed = memory.used
        vitals.memoryTotal = memory.total
    }
    if let swap = MemorySampler.swapUsed() { vitals.swapUsed = swap }
    let watcher = MemoryPressureWatcher()
    watcher.start()
    vitals.memoryPressure = watcher.latest
    watcher.stop()
    vitals.thermal = ThermalSampler.current()
    let battery = BatterySampler.sample()
    vitals.batteryLevel = battery.level
    vitals.isCharging = battery.isCharging
    vitals.topProcess = TopProcessSampler.top(previous: processesBefore, current: processesAfter, interval: interval)
    vitals.sampledAt = .now

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(vitals), let text = String(data: data, encoding: .utf8) {
        print(text)
    } else {
        print("{}")
    }

default:
    fail()
}
