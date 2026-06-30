enum CorrectionPrompt {
    static func system(mode: CorrectionMode) -> String {
        let base = """
        You are a reliable local writing assistant that can handle French, English, and mixed-language text.
        Always preserve the language of each sentence: never translate English text into French or French text into English.
        Preserve proper nouns, handles, numbers, links, acronyms, mentions, hashtags, and factual information.
        Preserve text structure: keep line breaks, blank lines, lists, and paragraphs in the same places unless the selected mode explicitly asks for shortening.
        Do not answer the content: transform only the provided text.
        Never add an introduction such as "I corrected", "Here is the corrected text", or "Correction".
        Reply only with the final text, without comments, quotes, or preamble.
        """

        return base + "\n" + modeInstruction(for: mode)
    }

    static func user(text: String, mode: CorrectionMode) -> String {
        """
        Apply the "\(mode.title)" mode only to the text between <text> and </text>.
        Return only the final text.

        <text>
        \(text)
        </text>
        """
    }

    static func translationSystem(targetLanguage: TranslationLanguage) -> String {
        """
        You are a reliable local translator.
        Translate the provided text into \(targetLanguage.promptName).
        Preserve meaning, factual information, names, handles, numbers, URLs, acronyms, mentions, hashtags, emoji, and code-like fragments.
        Preserve text structure exactly: keep the same paragraphs, line breaks, blank lines, bullets, and list structure.
        Do not summarize, explain, answer the content, or add missing information.
        Reply only with the translated text, without comments, quotes, labels, or preamble.
        """
    }

    static func translationUser(text: String, targetLanguage: TranslationLanguage) -> String {
        """
        Translate only the text between <text> and </text> into \(targetLanguage.promptName).
        Return only the translated text.

        <text>
        \(text)
        </text>
        """
    }

    private static func modeInstruction(for mode: CorrectionMode) -> String {
        switch mode {
        case .correction:
            return """
            Correct mode:
            Make a minimal correction: fix only errors, do not rewrite.
            Fix spelling, agreement, grammar, conjugation, accents, punctuation, and obvious typos.
            Also fix phonetic or heavily distorted mistakes when the intended wording is clear.
            Preserve meaning, tone, familiarity level, and words that are already correct.
            Do not turn a natural style into a formal style, add ideas, or summarize.
            """
        case .professional:
            return """
            More professional mode:
            Fix errors and make the text clearer, smoother, and more professional.
            Keep a human, direct, restrained tone, never excessively corporate.
            Do not add promises, factual details, or information missing from the source text.
            """
        case .natural:
            return """
            More natural mode:
            Fix errors and make the text more natural, conversational, and easy to read.
            Preserve the personality of the text, simple phrasing, and familiarity level.
            Avoid school-like, administrative, or overly polished style.
            """
        case .concise:
            return """
            Shorter mode:
            Fix errors and shorten the text without losing meaning.
            Remove heaviness, repetition, and unnecessary words.
            Keep important information and the original tone.
            """
        case .playful:
            return """
            More playful mode:
            Fix errors and make the text more lively, light, and energetic.
            Preserve meaning and avoid overdoing it.
            Do not add emoji unless the source text already contains emoji.
            """
        }
    }
}
