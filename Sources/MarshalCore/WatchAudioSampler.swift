import CoreAudio
import Foundation

public enum WatchAudioActivity: Sendable { case active, silent, unavailable }

/// Reads output-activity flags only. No taps, streams, buffers, or audio capture.
public enum WatchAudioSampler {
    public static func activity(pid: Int32, bundleID: String) -> WatchAudioActivity {
        guard #available(macOS 14.2, *) else { return .unavailable }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectHasProperty(system, &address) else { return .unavailable }
        var bytes: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &bytes) == noErr, bytes <= 1_048_576 else { return .unavailable }
        if bytes == 0 { return .silent }
        var objects = [AudioObjectID](repeating: 0, count: Int(bytes) / MemoryLayout<AudioObjectID>.stride)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &bytes, &objects) == noErr else { return .unavailable }
        var failed = false
        for object in objects.prefix(Int(bytes) / MemoryLayout<AudioObjectID>.stride) {
            guard let active = integer(object, kAudioProcessPropertyIsRunningOutput) else { failed = true; continue }
            guard active != 0, let rawPID = integer(object, kAudioProcessPropertyPID) else { continue }
            let candidate = Int32(bitPattern: rawPID)
            if candidate == pid { return .active }
            if let id = bundle(object), id == bundleID || id.hasPrefix(bundleID + ".") { return .active }
            if ProcessAncestry.owningApp(of: candidate)?.pid == pid { return .active }
        }
        return failed ? .unavailable : .silent
    }
    private static func integer(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var bytes = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &bytes, &value) == noErr ? value : nil
    }
    private static func bundle(_ object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var bytes = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &bytes, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
