import XCTest
@testable import Qelvora

final class ModelManagerTests: XCTestCase {
    func testCompactModelShortlistForSmallMemoryMacs() {
        let models = ModelManager.models(for: HardwareProfile(physicalMemoryGB: 8))
            .map(\.name)

        XCTAssertEqual(models, ["gemma4:e4b", "qwen2.5:3b", "gemma2:2b"])
    }

    func testStandardModelShortlistForSixteenToThirtyTwoGBMacs() {
        let models = ModelManager.models(for: HardwareProfile(physicalMemoryGB: 16))
            .map(\.name)

        XCTAssertEqual(models, ["gemma4:e4b", "qwen2.5:3b", "gemma2:2b", "qwen2.5:7b", "mistral:7b"])
    }

    func testGemma4IsPreferredForAllMacs() {
        XCTAssertEqual(
            ModelManager.preferredModelName(for: HardwareProfile(physicalMemoryGB: 8)),
            "gemma4:e4b"
        )

        XCTAssertEqual(
            ModelManager.preferredModelName(for: HardwareProfile(physicalMemoryGB: 16)),
            "gemma4:e4b"
        )
    }

    func testLargeModelShortlistForMoreThanThirtyTwoGBMacs() {
        let models = ModelManager.models(for: HardwareProfile(physicalMemoryGB: 64))
            .map(\.name)

        XCTAssertTrue(models.contains("qwen2.5:14b"))
        XCTAssertTrue(models.contains("mistral-nemo:12b"))
    }

    func testInstalledOllamaModelsAreMergedWithRecommendations() {
        let models = ModelManager.mergedModels(
            recommendedModels: ModelManager.models(for: HardwareProfile(physicalMemoryGB: 16)),
            installedModelNames: ["deepseek-r1:8b", "qwen2.5:7b"],
            selectedModelName: nil
        )

        XCTAssertTrue(models.contains { $0.name == "deepseek-r1:8b" && $0.source == .installed })
        XCTAssertEqual(models.filter { $0.name == "qwen2.5:7b" }.count, 1)
    }

    func testStoredCustomModelIsPreservedWhenNotInstalledYet() {
        let models = ModelManager.mergedModels(
            recommendedModels: ModelManager.models(for: HardwareProfile(physicalMemoryGB: 16)),
            installedModelNames: [],
            selectedModelName: "custom-model:latest"
        )

        XCTAssertTrue(models.contains { $0.name == "custom-model:latest" && $0.source == .custom })
    }

    func testRejectsInvalidCustomModelNames() {
        XCTAssertFalse(ModelManager.isValidOllamaModelName(""))
        XCTAssertFalse(ModelManager.isValidOllamaModelName("model name with spaces"))
        XCTAssertTrue(ModelManager.isValidOllamaModelName("gemma4:e4b"))
        XCTAssertTrue(ModelManager.isValidOllamaModelName("registry.example/team/model:latest"))
    }
}
