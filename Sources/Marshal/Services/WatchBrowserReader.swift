import AppKit
import Carbon
import MarshalCore

struct WatchBrowser: Identifiable, Sendable {
    let id: String
    let name: String
    var safari = false
    static let all: [Self] = [
        .init(id: "com.apple.Safari", name: "Safari", safari: true),
        .init(id: "com.google.Chrome", name: "Chrome"),
        .init(id: "com.microsoft.edgemac", name: "Edge"),
        .init(id: "com.brave.Browser", name: "Brave"),
        .init(id: "org.chromium.Chromium", name: "Chromium")
    ]
}

enum WatchBrowserResult: Sendable {
    case host(String?), permissionNeeded, denied, unavailable
}

/// Serialized off the UI thread. Passive reads check consent without prompting.
actor WatchBrowserReader {
    func read(_ browser: WatchBrowser, pid: Int32, ask: Bool = false) -> WatchBrowserResult {
        // Address the already-running process, so a quit can never relaunch a browser.
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        let permission = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(kAECoreSuite),
                                                                AEEventID(kAEGetData), ask)
        if permission == errAEEventNotPermitted { return .denied }
        if permission == errAEEventWouldRequireUserConsent { return .permissionNeeded }
        guard permission == noErr else { return .unavailable }
        if ask { return .host(nil) } // Connection never reads a page in the background.
        let event = Self.urlRequest(browser: browser, target: target)
        let options: NSAppleEventDescriptor.SendOptions = [.waitForReply, .neverInteract,
            .init(rawValue: UInt(kAEDoNotPromptForUserConsent))]
        do {
            let reply = try event.sendEvent(options: options, timeout: 2)
            let error = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value ?? 0
            if error == -1743 || error == -1744 { return .denied }
            if error == -1728 { return .host(nil) } // No front window/current tab.
            guard error == 0 else { return .unavailable }
            return .host(reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue.flatMap(WatchRule.domain))
        } catch {
            return (error as NSError).code == -1743 ? .denied : .unavailable
        }
    }
    static func urlRequest(browser: WatchBrowser, target: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        // Get Data is core/getd. aevt (kCoreEventClass) is for application lifecycle events.
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kAECoreSuite), eventID: AEEventID(kAEGetData),
                                           targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(urlSpecifier(safari: browser.safari), forKeyword: AEKeyword(keyDirectObject))
        return event
    }
    /// Codes verified against the browsers' installed scripting dictionaries.
    static func urlSpecifier(safari: Bool) -> NSAppleEventDescriptor {
        func object(_ desired: OSType, container: NSAppleEventDescriptor, form: OSType,
                    key: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
            let record = NSAppleEventDescriptor.record()
            record.setDescriptor(NSAppleEventDescriptor(typeCode: desired), forKeyword: AEKeyword(keyAEDesiredClass))
            record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
            record.setDescriptor(NSAppleEventDescriptor(enumCode: form), forKeyword: AEKeyword(keyAEKeyForm))
            record.setDescriptor(key, forKeyword: AEKeyword(keyAEKeyData))
            return record.coerce(toDescriptorType: DescType(typeObjectSpecifier))!
        }
        let window = object(0x6377696e, container: .null(), form: OSType(formAbsolutePosition), key: .init(int32: 1))
        let tab = object(OSType(typeProperty), container: window, form: OSType(formPropertyID),
                         key: .init(typeCode: safari ? 0x63546162 : 0x61635461)) // cTab / acTa
        return object(OSType(typeProperty), container: tab, form: OSType(formPropertyID),
                      key: .init(typeCode: safari ? 0x7055524c : 0x55524c20)) // pURL / URL
    }
}
