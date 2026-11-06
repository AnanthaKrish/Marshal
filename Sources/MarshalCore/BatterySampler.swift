import Foundation
import IOKit.ps

/// Reads the internal battery via IOKit power sources. `level` is nil on
/// machines without a battery.
public enum BatterySampler {
    public static func sample() -> (level: Int?, isCharging: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return (nil, false)
        }
        for source in list {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard info[kIOPSTypeKey as String] as? String == kIOPSInternalBatteryType else { continue }
            return (info[kIOPSCurrentCapacityKey as String] as? Int,
                    info[kIOPSIsChargingKey as String] as? Bool ?? false)
        }
        return (nil, false)
    }
}
