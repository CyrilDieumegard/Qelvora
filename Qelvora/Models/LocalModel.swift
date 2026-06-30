import Foundation

struct LocalModel: Identifiable, Hashable, Codable {
    enum Tier: String, Codable {
        case compact
        case standard
        case large
    }

    enum Source: String, Codable {
        case recommended
        case installed
        case custom
    }

    let name: String
    let displayName: String
    let tier: Tier
    let detail: String
    let source: Source

    init(
        name: String,
        displayName: String,
        tier: Tier,
        detail: String,
        source: Source = .recommended
    ) {
        self.name = name
        self.displayName = displayName
        self.tier = tier
        self.detail = detail
        self.source = source
    }

    var id: String {
        name
    }

    var isDownloadable: Bool {
        source == .recommended
    }

    func menuTitle(installedModelNames: Set<String>) -> String {
        installedModelNames.contains(name) ? displayName : "\(displayName) - not installed"
    }
}
