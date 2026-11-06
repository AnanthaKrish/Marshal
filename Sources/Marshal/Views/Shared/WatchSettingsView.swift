import AppKit
import MarshalCore
import SwiftUI
import UniformTypeIdentifiers

struct WatchSettingsView: View {
    @ObservedObject var watch: WatchStore
    var close: (() -> Void)? = nil
    @State private var newSite = ""
    @State private var error: String?
    @State private var browserID = WatchBrowser.all[0].id

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("A breather between episodes.").font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("Pookie keeps an eye on your watch time.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 3) {
                    Toggle("Watch-time reminders", isOn: Binding(get: { watch.settings.enabled }, set: { value in
                        watch.configure { $0.enabled = value }
                    })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    Text(watch.settings.enabled ? "On" : "Off").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            Toggle("Count only while the app has audio activity", isOn: Binding(get: { watch.settings.requiresAudio }, set: { value in
                watch.configure { $0.requiresAudio = value }
            })).font(.system(size: 12))
            Toggle("Count while I'm using another app", isOn: Binding(get: { watch.settings.countInBackground }, set: { value in
                watch.configure { $0.countInBackground = value }
            })).font(.system(size: 12))
            Text("Time updates every 5 seconds. Counting beside another app always needs audio and checks the selected tab in connected browsers. Another tab can supply audio; muted video may be missed. Audio detection needs macOS 14.2 or later.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack(spacing: 8) {
                Picker("Browser", selection: $browserID) {
                    ForEach(WatchBrowser.all) { Text($0.name).tag($0.id) }
                }.frame(maxWidth: 230)
                Button(watch.connectingBrowser == browserID ? "Connecting…" : "Connect") { watch.connectBrowser?(browserID) }
                    .disabled(watch.connectingBrowser != nil)
                if watch.settings.browsers.contains(browserID) {
                    Button("Disconnect") {
                        watch.configure { $0.browsers.remove(browserID) }
                        watch.browserStatus[browserID] = nil
                    }
                }
            }.controlSize(.small)
            Text(watch.browserStatus[browserID] ?? (watch.settings.browsers.contains(browserID) ? "Connected" : "Open your browser, then connect. macOS will ask for Automation access."))
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Sites & apps").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("First / firmer reminder").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(watch.settings.rules) { rule in ruleRow(rule) }
                }
            }.frame(height: 210)
            HStack(spacing: 7) {
                TextField("Add a site, e.g. youtube.com", text: $newSite).textFieldStyle(.roundedBorder)
                    .onSubmit(addSite)
                Button("Add site", action: addSite).disabled(newSite.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Add app…", action: addApp)
            }.controlSize(.small)
            if let error { Text(error).font(.system(size: 10)).foregroundStyle(.red) }
            Divider()
            HStack(spacing: 9) {
                Text("Try it now").font(.system(size: 11, weight: .medium))
                Button("30m yawn") { watch.preview(firm: false) }
                Button("45m nudge") { watch.preview(firm: true) }
                if watch.previewLevel != nil { Button("Stop") { watch.stopPreview() } }
                Spacer(minLength: 0)
                if let close { Button("Done", action: close).keyboardShortcut("w", modifiers: .command) }
            }.controlSize(.small)
            Text("Previews last 8 seconds and respect quiet mode. During focus, the first reminder is firmer. Settings stay on this Mac; no viewing history is saved.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20).frame(width: 440).background(.background)
        .onAppear {
            if let connected = WatchBrowser.all.first(where: { watch.settings.browsers.contains($0.id) }) {
                browserID = connected.id
            }
        }
    }
    private func ruleRow(_ rule: WatchRule) -> some View {
        HStack(spacing: 7) {
            Toggle(isOn: Binding(get: { rule.enabled }, set: { value in edit(rule.id) { $0.enabled = value } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text(rule.kind == .site ? rule.target : "App").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading)
            Stepper(value: Binding(get: { rule.gentleMinutes }, set: { value in edit(rule.id) {
                $0.gentleMinutes = value; $0.firmMinutes = max($0.firmMinutes, value + 1)
            }}), in: 1...240, step: 5) { Text("\(rule.gentleMinutes)m").monospacedDigit() }
                .frame(width: 80).help("First reminder")
            Stepper(value: Binding(get: { rule.firmMinutes }, set: { value in edit(rule.id) { $0.firmMinutes = value } }),
                    in: rule.gentleMinutes + 1...360, step: 5) { Text("\(rule.firmMinutes)m").monospacedDigit() }
                .frame(width: 80).help("Firmer reminder")
            Button { watch.configure { $0.rules.removeAll { $0.id == rule.id } } } label: {
                Image(systemName: "minus.circle").foregroundStyle(.secondary)
            }.buttonStyle(.plain).accessibilityLabel("Remove \(rule.name)")
        }
        .font(.system(size: 10)).controlSize(.mini)
        .padding(8).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
    private func edit(_ id: String, _ change: (inout WatchRule) -> Void) {
        watch.configure { settings in
            if let index = settings.rules.firstIndex(where: { $0.id == id }) { change(&settings.rules[index]) }
        }
    }
    private func addSite() {
        guard let host = WatchRule.domain(newSite) else { error = "Enter a valid website address."; return }
        add(WatchRule(kind: .site, target: host, name: String(host.prefix(60))))
    }
    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        if WatchBrowser.all.contains(where: { $0.id == id }) {
            error = "Connect this browser above and add the sites you want to watch."; return
        }
        add(WatchRule(kind: .app, target: id, name: String(url.deletingPathExtension().lastPathComponent.prefix(60))))
    }
    private func add(_ rule: WatchRule) {
        guard !watch.settings.rules.contains(where: { $0.id == rule.id }) else { error = "That site or app is already listed."; return }
        guard watch.configure({ $0.rules.append(rule) }) else { error = "You can watch up to 40 sites and apps."; return }
        newSite = ""; error = nil
    }
}
