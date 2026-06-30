import XCTest
@testable import Qelvora

final class CorrectionAnalysisTests: XCTestCase {
    func testCountsWordsFromCorrectedText() {
        let analysis = CorrectionAnalysis(
            sourceText: "je repousse le moment d'ecrire",
            correctedText: "Je repousse le moment d'écrire."
        )

        XCTAssertEqual(analysis.wordCount, 5)
    }

    func testHighlightsChangedSourceWords() {
        let analysis = CorrectionAnalysis(
            sourceText: "on pourrait afficher les erreurs souligner",
            correctedText: "On pourrait afficher les erreurs soulignées"
        )

        XCTAssertEqual(analysis.correctionCount, 1)
        XCTAssertEqual(analysis.correctnessPercentage, 83)
        XCTAssertTrue(
            analysis.highlightedSourceRuns.contains {
                $0.text == "souligner" && $0.isError
            }
        )
    }

    func testDoesNotHighlightUnchangedWords() {
        let analysis = CorrectionAnalysis(
            sourceText: "Je suis aussi sec qu'un champ de blé.",
            correctedText: "Je suis aussi sec qu'un champ de blé."
        )

        XCTAssertEqual(analysis.correctionCount, 0)
        XCTAssertEqual(analysis.correctnessPercentage, 100)
        XCTAssertFalse(analysis.hasHighlightedErrors)
    }

    func testKeepsAccentCorrectionsVisible() {
        let analysis = CorrectionAnalysis(
            sourceText: "Je connais ca par coeur",
            correctedText: "Je connais ça par cœur"
        )

        XCTAssertEqual(analysis.correctionCount, 2)
        XCTAssertEqual(analysis.correctnessPercentage, 60)
        XCTAssertTrue(
            analysis.highlightedSourceRuns.contains {
                $0.text == "ca" && $0.isError
            }
        )
        XCTAssertTrue(
            analysis.highlightedSourceRuns.contains {
                $0.text == "coeur" && $0.isError
            }
        )
    }

    func testCountsInsertedGrammarCorrectionsInScore() {
        let analysis = CorrectionAnalysis(
            sourceText: "je sais pas",
            correctedText: "Je ne sais pas"
        )

        XCTAssertEqual(analysis.correctionCount, 1)
        XCTAssertEqual(analysis.correctnessPercentage, 67)
        XCTAssertFalse(analysis.hasHighlightedErrors)
    }
}
