import Foundation

/// Deterministic, LLM-free vocabulary correction (~0 ms): fixes misheard versions
/// of dictionary terms directly in the text. Built for the raw mode ("Paraket" →
/// "Parakeet"), but applied after the LLM too — the model demonstrably misses
/// vocabulary corrections at times.
enum GlossaryCorrector {

    static func apply(_ text: String, dictionary: [String]) -> (text: String, corrections: [String]) {
        let singles = dictionary.filter { !$0.contains(" ") && $0.count >= 4 }
        guard !singles.isEmpty else { return (text, []) }
        var corrections: [String] = []
        var result = ""
        result.reserveCapacity(text.count)
        var token = ""

        func corrected(_ word: String) -> String {
            let lower = word.lowercased()
            for entry in singles {
                let e = entry.lowercased()
                if lower == e {
                    if word != entry { corrections.append("\(word) → \(entry)") }
                    return entry // canonical casing
                }
                // Correctly spelled base with a short inflection suffix ("EvoNets")
                // — or the entry itself is the longer form ("Kabelrohr" vs
                // "Kabelrohre"): both are legitimate German, leave untouched.
                if lower.hasPrefix(e), lower.count - e.count <= 2 { return word }
                if e.hasPrefix(lower), e.count - lower.count <= 2 { return word }
                // Fuzzy: small edit distance, same first letter, conservative caps.
                let maxDist = e.count >= 10 ? 2 : (e.count >= 5 ? 1 : 0)
                guard maxDist > 0, lower.first == e.first,
                      abs(lower.count - e.count) <= maxDist else { continue }
                if levenshtein(lower, e) <= maxDist {
                    corrections.append("\(word) → \(entry)")
                    return entry
                }
            }
            return word
        }

        for ch in text {
            if ch.isLetter || ch.isNumber {
                token.append(ch)
            } else {
                if !token.isEmpty { result += corrected(token); token = "" }
                result.append(ch)
            }
        }
        if !token.isEmpty { result += corrected(token) }
        return (result, corrections)
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a.unicodeScalars), y = Array(b.unicodeScalars)
        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = Swift.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[y.count]
    }
}
