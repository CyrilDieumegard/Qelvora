import Foundation

struct HardwareProfile: Equatable {
    let physicalMemoryGB: Int

    static var current: HardwareProfile {
        let bytes = ProcessInfo.processInfo.physicalMemory
        let gibibytes = Double(bytes) / 1_073_741_824
        return HardwareProfile(physicalMemoryGB: Int(gibibytes.rounded(.down)))
    }

    var summary: String {
        "\(physicalMemoryGB) GB RAM detected"
    }

    var recommendedTier: LocalModel.Tier {
        if physicalMemoryGB < 16 {
            return .compact
        }

        if physicalMemoryGB <= 32 {
            return .standard
        }

        return .large
    }
}
