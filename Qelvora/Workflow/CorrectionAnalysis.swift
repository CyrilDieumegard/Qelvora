import Foundation
import NaturalLanguage

struct CorrectionAnalysis: Equatable {
    let wordCount: Int
    let detectedLanguage: DetectedLanguage?
    let correctnessPercentage: Int?
    let correctionCount: Int
    let highlightedSourceRuns: [CorrectionHighlightRun]
    let replacements: [CorrectionReplacement]

    var hasHighlightedErrors: Bool {
        highlightedSourceRuns.contains { $0.isError }
    }

    init(sourceText: String?, correctedText: String) {
        let correctedText = correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.wordCount = Self.wordCount(in: correctedText)
        self.detectedLanguage = DetectedLanguage.detect(in: sourceText ?? correctedText)

        guard let rawSourceText = sourceText else {
            self.correctnessPercentage = nil
            self.correctionCount = 0
            self.highlightedSourceRuns = []
            self.replacements = []
            return
        }

        let sourceText = rawSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            self.correctnessPercentage = nil
            self.correctionCount = 0
            self.highlightedSourceRuns = []
            self.replacements = []
            return
        }

        let sourceTokens = Self.wordTokens(in: sourceText)
        let correctedTokens = Self.wordTokens(in: correctedText)
        let matches = Self.longestCommonSubsequence(
            sourceTokens: sourceTokens,
            correctedTokens: correctedTokens
        )
        let matchedSourceIndexes = Set(matches.map { $0.sourceIndex })
        let changedSourceIndexes = Set(sourceTokens.indices.filter { !matchedSourceIndexes.contains($0) })
        let correctionCount = Self.correctionMagnitude(
            sourceTokens: sourceTokens,
            correctedTokens: correctedTokens,
            matches: matches
        )

        self.correctionCount = correctionCount
        self.correctnessPercentage = Self.correctnessPercentage(
            sourceWordCount: sourceTokens.count,
            correctionCount: correctionCount
        )
        self.highlightedSourceRuns = Self.highlightRuns(
            sourceText: sourceText,
            sourceTokens: sourceTokens,
            changedSourceIndexes: changedSourceIndexes
        )
        self.replacements = Self.replacements(
            sourceTokens: sourceTokens,
            correctedTokens: correctedTokens,
            matches: matches
        )
    }

    static func wordCount(in text: String) -> Int {
        wordTokens(in: text).count
    }

    private static func longestCommonSubsequence(
        sourceTokens: [WordToken],
        correctedTokens: [WordToken]
    ) -> [TokenMatch] {
        guard !sourceTokens.isEmpty, !correctedTokens.isEmpty else {
            return []
        }

        var lengths = Array(
            repeating: Array(repeating: 0, count: correctedTokens.count + 1),
            count: sourceTokens.count + 1
        )

        for sourceIndex in stride(from: sourceTokens.count - 1, through: 0, by: -1) {
            for correctedIndex in stride(from: correctedTokens.count - 1, through: 0, by: -1) {
                if sourceTokens[sourceIndex].normalizedText == correctedTokens[correctedIndex].normalizedText {
                    lengths[sourceIndex][correctedIndex] = lengths[sourceIndex + 1][correctedIndex + 1] + 1
                } else {
                    lengths[sourceIndex][correctedIndex] = max(
                        lengths[sourceIndex + 1][correctedIndex],
                        lengths[sourceIndex][correctedIndex + 1]
                    )
                }
            }
        }

        var matches: [TokenMatch] = []
        var sourceIndex = 0
        var correctedIndex = 0

        while sourceIndex < sourceTokens.count, correctedIndex < correctedTokens.count {
            if sourceTokens[sourceIndex].normalizedText == correctedTokens[correctedIndex].normalizedText {
                matches.append(TokenMatch(sourceIndex: sourceIndex, correctedIndex: correctedIndex))
                sourceIndex += 1
                correctedIndex += 1
            } else if lengths[sourceIndex + 1][correctedIndex] >= lengths[sourceIndex][correctedIndex + 1] {
                sourceIndex += 1
            } else {
                correctedIndex += 1
            }
        }

        return matches
    }

    private static func replacements(
        sourceTokens: [WordToken],
        correctedTokens: [WordToken],
        matches: [TokenMatch]
    ) -> [CorrectionReplacement] {
        var replacements: [CorrectionReplacement] = []
        var previousSourceIndex = 0
        var previousCorrectedIndex = 0
        let boundaries = matches + [
            TokenMatch(sourceIndex: sourceTokens.count, correctedIndex: correctedTokens.count)
        ]

        for boundary in boundaries {
            let sourceGap = sourceTokens[previousSourceIndex..<boundary.sourceIndex]
            let correctedGap = correctedTokens[previousCorrectedIndex..<boundary.correctedIndex]

            if !sourceGap.isEmpty {
                let original = sourceGap.map(\.text).joined(separator: " ")
                let corrected = correctedGap.map(\.text).joined(separator: " ")

                if original.normalizedForCorrectionDiff != corrected.normalizedForCorrectionDiff {
                    replacements.append(
                        CorrectionReplacement(
                            original: original,
                            corrected: corrected.isEmpty ? "..." : corrected
                        )
                    )
                }
            }

            previousSourceIndex = boundary.sourceIndex + 1
            previousCorrectedIndex = boundary.correctedIndex + 1
        }

        return replacements
    }

    private static func correctionMagnitude(
        sourceTokens: [WordToken],
        correctedTokens: [WordToken],
        matches: [TokenMatch]
    ) -> Int {
        var correctionCount = 0
        var previousSourceIndex = 0
        var previousCorrectedIndex = 0
        let boundaries = matches + [
            TokenMatch(sourceIndex: sourceTokens.count, correctedIndex: correctedTokens.count)
        ]

        for boundary in boundaries {
            let sourceGapCount = boundary.sourceIndex - previousSourceIndex
            let correctedGapCount = boundary.correctedIndex - previousCorrectedIndex

            if sourceGapCount > 0 || correctedGapCount > 0 {
                correctionCount += max(sourceGapCount, correctedGapCount)
            }

            previousSourceIndex = boundary.sourceIndex + 1
            previousCorrectedIndex = boundary.correctedIndex + 1
        }

        return correctionCount
    }

    private static func correctnessPercentage(sourceWordCount: Int, correctionCount: Int) -> Int? {
        guard sourceWordCount > 0 else {
            return nil
        }

        let correctWordCount = max(0, sourceWordCount - min(correctionCount, sourceWordCount))
        let percentage = (Double(correctWordCount) / Double(sourceWordCount) * 100).rounded()
        return Int(percentage)
    }

    private static func highlightRuns(
        sourceText: String,
        sourceTokens: [WordToken],
        changedSourceIndexes: Set<Int>
    ) -> [CorrectionHighlightRun] {
        guard !sourceTokens.isEmpty else {
            return [CorrectionHighlightRun(text: sourceText, isError: false)]
        }

        var runs: [CorrectionHighlightRun] = []
        var cursor = sourceText.startIndex

        for (index, token) in sourceTokens.enumerated() {
            if cursor < token.range.lowerBound {
                runs.append(
                    CorrectionHighlightRun(
                        text: String(sourceText[cursor..<token.range.lowerBound]),
                        isError: false
                    )
                )
            }

            runs.append(
                CorrectionHighlightRun(
                    text: token.text,
                    isError: changedSourceIndexes.contains(index)
                )
            )
            cursor = token.range.upperBound
        }

        if cursor < sourceText.endIndex {
            runs.append(
                CorrectionHighlightRun(
                    text: String(sourceText[cursor..<sourceText.endIndex]),
                    isError: false
                )
            )
        }

        return runs.mergingAdjacentRuns()
    }

    private static func wordTokens(in text: String) -> [WordToken] {
        let pattern = #"[\p{L}\p{N}]+(?:[’'\-][\p{L}\p{N}]+)*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else {
                return nil
            }

            let tokenText = String(text[swiftRange])
            return WordToken(
                text: tokenText,
                normalizedText: tokenText.normalizedForCorrectionDiff,
                range: swiftRange
            )
        }
    }
}

struct CorrectionHighlightRun: Equatable {
    let text: String
    let isError: Bool
}

struct CorrectionReplacement: Equatable {
    let original: String
    let corrected: String
}

struct DetectedLanguage: Equatable {
    let code: String
    let name: String
    let flag: String
    let confidence: Double

    var displayLabel: String {
        "\(flag) \(name)"
    }

    static func detect(in text: String) -> DetectedLanguage? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.unicodeScalars.count >= 3 else {
            return nil
        }

        if trimmedText.containsJapaneseScript {
            return DetectedLanguage(code: "JA", name: "Japanese", flag: "🇯🇵", confidence: 1)
        }

        if trimmedText.containsCJKScript {
            return DetectedLanguage(code: "ZH", name: "Chinese", flag: "🇨🇳", confidence: 1)
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmedText)

        guard
            let language = recognizer.dominantLanguage,
            language != .undetermined
        else {
            return nil
        }

        let confidence = recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0
        guard confidence >= 0.35 else {
            return nil
        }

        let rawCode = language.rawValue
        return DetectedLanguage(
            code: Self.shortCode(for: rawCode),
            name: Self.displayName(for: rawCode),
            flag: Self.flag(for: rawCode),
            confidence: confidence
        )
    }

    private static func shortCode(for rawCode: String) -> String {
        rawCode
            .split(separator: "-")
            .first
            .map { String($0).uppercased() } ?? rawCode.uppercased()
    }

    private static func displayName(for rawCode: String) -> String {
        let languageCode = String(rawCode.split(separator: "-").first ?? Substring(rawCode))
        return Locale(identifier: "en").localizedString(forLanguageCode: languageCode) ?? rawCode
    }

    private static func flag(for rawCode: String) -> String {
        switch shortCode(for: rawCode) {
        case "EN":
            return "🇬🇧"
        case "FR":
            return "🇫🇷"
        case "ES":
            return "🇪🇸"
        case "DE":
            return "🇩🇪"
        case "IT":
            return "🇮🇹"
        case "PT":
            return "🇵🇹"
        case "JA":
            return "🇯🇵"
        case "ZH":
            return "🇨🇳"
        default:
            return "🌐"
        }
    }
}

private struct WordToken: Equatable {
    let text: String
    let normalizedText: String
    let range: Range<String.Index>
}

private struct TokenMatch: Equatable {
    let sourceIndex: Int
    let correctedIndex: Int
}

private extension String {
    var normalizedForCorrectionDiff: String {
        lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "‐", with: "-")
            .replacingOccurrences(of: "‑", with: "-")
            .replacingOccurrences(of: "–", with: "-")
    }

    var containsJapaneseScript: Bool {
        unicodeScalars.contains { scalar in
            (0x3040...0x309F).contains(scalar.value) || (0x30A0...0x30FF).contains(scalar.value)
        }
    }

    var containsCJKScript: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }
}

private extension Array where Element == CorrectionHighlightRun {
    func mergingAdjacentRuns() -> [CorrectionHighlightRun] {
        reduce(into: []) { mergedRuns, run in
            guard let lastRun = mergedRuns.last, lastRun.isError == run.isError else {
                mergedRuns.append(run)
                return
            }

            mergedRuns[mergedRuns.count - 1] = CorrectionHighlightRun(
                text: lastRun.text + run.text,
                isError: lastRun.isError
            )
        }
    }
}
