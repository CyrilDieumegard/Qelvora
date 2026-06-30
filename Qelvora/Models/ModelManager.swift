import Foundation

@MainActor
final class ModelManager: ObservableObject {
    @Published private(set) var hardwareProfile: HardwareProfile
    @Published private(set) var availableModels: [LocalModel]
    @Published private(set) var installedModelNames: Set<String> = []
    @Published private(set) var installedOllamaModelNames: [String] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var downloadingModelName: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var selectedModelName: String

    private let registry: OllamaModelRegistry
    private let userDefaults: UserDefaults
    private let selectedModelKey = "selectedModelName"

    var hardwareSummary: String {
        hardwareProfile.summary
    }

    var selectedModelDisplayName: String {
        availableModels.first { $0.name == selectedModelName }?.displayName ?? selectedModelName
    }

    var missingModels: [LocalModel] {
        availableModels.filter { $0.isDownloadable && !installedModelNames.contains($0.name) }
    }

    init(
        hardwareProfile: HardwareProfile = .current,
        registry: OllamaModelRegistry = OllamaModelRegistry(),
        userDefaults: UserDefaults = .standard
    ) {
        self.hardwareProfile = hardwareProfile
        self.registry = registry
        self.userDefaults = userDefaults
        let storedModelName = userDefaults.string(forKey: selectedModelKey)
        self.selectedModelName = storedModelName
            ?? Self.preferredModelName(for: hardwareProfile)
            ?? Self.models(for: hardwareProfile).first?.name
            ?? "qwen2.5:3b"
        self.availableModels = Self.mergedModels(
            recommendedModels: Self.models(for: hardwareProfile),
            installedModelNames: [],
            selectedModelName: storedModelName
        )

        if !availableModels.contains(where: { $0.name == selectedModelName }),
           let firstModel = availableModels.first {
            selectedModelName = firstModel.name
        }
    }

    func selectModel(named name: String) {
        guard availableModels.contains(where: { $0.name == name }) else {
            return
        }

        selectedModelName = name
        userDefaults.set(name, forKey: selectedModelKey)
    }

    func addCustomModel(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidOllamaModelName(name) else {
            statusMessage = "Enter an Ollama model name such as gemma4:e4b."
            return
        }

        if !availableModels.contains(where: { $0.name == name }) {
            availableModels.append(Self.customModel(named: name, isInstalled: installedModelNames.contains(name)))
            availableModels = Self.sortedModels(availableModels)
        }

        selectModel(named: name)
        statusMessage = installedModelNames.contains(name)
            ? "\(name) is now selected."
            : "\(name) is selected. Pull it in Ollama before correcting text."
    }

    func refreshInstalledModels() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            installedOllamaModelNames = try await registry.installedModels()
            installedModelNames = Set(installedOllamaModelNames)
            availableModels = Self.mergedModels(
                recommendedModels: Self.models(for: hardwareProfile),
                installedModelNames: installedOllamaModelNames,
                selectedModelName: selectedModelName
            )
            chooseInstalledModelIfNeeded()
            statusMessage = installedModelNames.isEmpty
                ? "No Ollama model is installed."
                : "\(installedModelNames.count) Ollama model(s) detected."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func download(model: LocalModel) async {
        downloadingModelName = model.name
        statusMessage = "Downloading \(model.displayName)..."
        defer { downloadingModelName = nil }

        do {
            try await registry.pull(model: model)
            await refreshInstalledModels()
            selectModel(named: model.name)
            statusMessage = "\(model.displayName) is ready."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func chooseInstalledModelIfNeeded() {
        guard !installedModelNames.contains(selectedModelName) else {
            return
        }

        if let firstInstalled = availableModels.first(where: { installedModelNames.contains($0.name) }) {
            selectModel(named: firstInstalled.name)
        }
    }

    nonisolated static func customModel(named name: String, isInstalled: Bool = false) -> LocalModel {
        LocalModel(
            name: name,
            displayName: name,
            tier: .standard,
            detail: isInstalled
                ? "Installed in Ollama. Added automatically from the local model list."
                : "Custom Ollama model. Qelvora will use this exact model name.",
            source: isInstalled ? .installed : .custom
        )
    }

    nonisolated static func isValidOllamaModelName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 120 else {
            return false
        }

        return trimmed.range(of: #"^[A-Za-z0-9][A-Za-z0-9._/-]*(?::[A-Za-z0-9._-]+)?$"#, options: .regularExpression) != nil
    }

    nonisolated static func mergedModels(
        recommendedModels: [LocalModel],
        installedModelNames: [String],
        selectedModelName: String?
    ) -> [LocalModel] {
        var models = recommendedModels
        var knownNames = Set(recommendedModels.map(\.name))

        for name in installedModelNames where isValidOllamaModelName(name) && !knownNames.contains(name) {
            models.append(customModel(named: name, isInstalled: true))
            knownNames.insert(name)
        }

        if let selectedModelName,
           isValidOllamaModelName(selectedModelName),
           !knownNames.contains(selectedModelName) {
            models.append(customModel(named: selectedModelName))
        }

        return sortedModels(models)
    }

    nonisolated static func sortedModels(_ models: [LocalModel]) -> [LocalModel] {
        models.sorted { lhs, rhs in
            if lhs.source != rhs.source {
                return sourceRank(lhs.source) < sourceRank(rhs.source)
            }

            if lhs.tier != rhs.tier {
                return tierRank(lhs.tier) < tierRank(rhs.tier)
            }

            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private nonisolated static func sourceRank(_ source: LocalModel.Source) -> Int {
        switch source {
        case .recommended:
            return 0
        case .installed:
            return 1
        case .custom:
            return 2
        }
    }

    private nonisolated static func tierRank(_ tier: LocalModel.Tier) -> Int {
        switch tier {
        case .compact:
            return 0
        case .standard:
            return 1
        case .large:
            return 2
        }
    }

    nonisolated static func preferredModelName(for hardwareProfile: HardwareProfile) -> String? {
        hardwareProfile.recommendedTier == .compact ? "qwen2.5:3b" : "gemma4:e4b"
    }

    nonisolated static func models(for hardwareProfile: HardwareProfile) -> [LocalModel] {
        let compact = [
            LocalModel(
                name: "qwen2.5:3b",
                displayName: "Qwen 2.5 3B",
                tier: .compact,
                detail: "Fast and suitable for Macs with less than 16 GB of RAM."
            ),
            LocalModel(
                name: "gemma2:2b",
                displayName: "Gemma 2 2B",
                tier: .compact,
                detail: "Very light, useful for validating the full flow."
            )
        ]

        let standard = [
            LocalModel(
                name: "qwen2.5:7b",
                displayName: "Qwen 2.5 7B",
                tier: .standard,
                detail: "Good balance between quality and speed."
            ),
            LocalModel(
                name: "gemma4:e4b",
                displayName: "Gemma 4 4B",
                tier: .standard,
                detail: "Recommended default model for more disciplined correction."
            ),
            LocalModel(
                name: "mistral:7b",
                displayName: "Mistral 7B",
                tier: .standard,
                detail: "Solid general-purpose model for multilingual correction."
            )
        ]

        let large = [
            LocalModel(
                name: "llama3.1:8b",
                displayName: "Llama 3.1 8B",
                tier: .large,
                detail: "More comfortable option for Macs with more than 32 GB of RAM."
            ),
            LocalModel(
                name: "qwen2.5:14b",
                displayName: "Qwen 2.5 14B",
                tier: .large,
                detail: "Better quality margin if the machine can keep up."
            ),
            LocalModel(
                name: "mistral-nemo:12b",
                displayName: "Mistral Nemo 12B",
                tier: .large,
                detail: "Larger variant for very capable Macs."
            )
        ]

        switch hardwareProfile.recommendedTier {
        case .compact:
            return compact
        case .standard:
            return compact + standard
        case .large:
            return compact + standard + large
        }
    }
}
