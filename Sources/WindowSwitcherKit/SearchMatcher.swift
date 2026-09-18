import Foundation

/// How well a query matches a window's title or app name. Higher scores are better matches.
struct SearchMatch: Equatable, Sendable {
    let score: Int
    /// Matched character positions in the original text, as offsets, merged into runs.
    let ranges: [Range<Int>]
}

/// Case- and diacritic-insensitive matching in tiers, so that typing "saf" ranks Safari above "unsafe.txt" and a
/// two-letter acronym still finds "Activity Monitor". The tiers, best first: whole text, text prefix, word prefix,
/// substring, acronym (word starts in order), scattered letters in order.
enum SearchMatcher {
    private static let tierExact = 1000
    private static let tierPrefix = 800
    private static let tierWordPrefix = 600
    private static let tierSubstring = 400
    private static let tierAcronym = 200
    private static let tierScattered = 100

    private struct Folded {
        /// Folded characters with whitespace removed.
        var chars: [Character] = []
        /// Offset in the original text for each folded character.
        var origin: [Int] = []
        /// True where a word begins (after a space or punctuation, or at a lower-to-upper case change).
        var wordStart: [Bool] = []
    }

    private static func fold(_ text: String) -> Folded {
        var result = Folded()
        var previous: Character?
        for (offset, ch) in text.enumerated() {
            if ch.isWhitespace { previous = ch; continue }
            let folded = String(ch).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let boundary: Bool
            if let previous {
                boundary = previous.isWhitespace || previous.isPunctuation || previous.isSymbol
                    || (previous.isLowercase && ch.isUppercase) || (previous.isNumber != ch.isNumber)
            } else {
                boundary = true
            }
            var first = true
            for f in folded {
                result.chars.append(f)
                result.origin.append(offset)
                result.wordStart.append(first && boundary)
                first = false
            }
            previous = ch
        }
        return result
    }

    static func match(query: String, in text: String) -> SearchMatch? {
        let q = fold(query).chars
        guard !q.isEmpty else { return nil }
        let t = fold(text)
        guard !t.chars.isEmpty else { return nil }
        let n = t.chars.count
        // Shorter texts win ties within a tier: the query covers more of them.
        let lengthPenalty = min(n, 60)

        if q == t.chars {
            return SearchMatch(score: tierExact - lengthPenalty, ranges: ranges(Array(0..<n), t))
        }
        if q.count < n, Array(t.chars.prefix(q.count)) == q {
            return SearchMatch(score: tierPrefix - lengthPenalty, ranges: ranges(Array(0..<q.count), t))
        }
        for start in 1..<n where t.wordStart[start] && start + q.count <= n {
            if Array(t.chars[start..<(start + q.count)]) == q {
                return SearchMatch(score: tierWordPrefix - lengthPenalty, ranges: ranges(Array(start..<(start + q.count)), t))
            }
        }
        if let start = substring(q, in: t.chars) {
            return SearchMatch(score: tierSubstring - lengthPenalty - start, ranges: ranges(Array(start..<(start + q.count)), t))
        }
        if let hits = acronym(q, in: t) {
            return SearchMatch(score: tierAcronym - lengthPenalty, ranges: ranges(hits, t))
        }
        if let hits = scattered(q, in: t.chars) {
            let spread = (hits.last ?? 0) - (hits.first ?? 0) - (q.count - 1)
            return SearchMatch(score: max(1, tierScattered - min(spread, 60) - lengthPenalty / 4), ranges: ranges(hits, t))
        }
        return nil
    }

    private static func substring(_ q: [Character], in t: [Character]) -> Int? {
        guard q.count <= t.count else { return nil }
        for start in 0...(t.count - q.count) where t[start] == q[0] {
            if Array(t[start..<(start + q.count)]) == q { return start }
        }
        return nil
    }

    /// Every query character lands on a word start, in order.
    private static func acronym(_ q: [Character], in t: Folded) -> [Int]? {
        var hits: [Int] = []
        var from = 0
        for ch in q {
            var found: Int?
            var i = from
            while i < t.chars.count {
                if t.wordStart[i], t.chars[i] == ch { found = i; break }
                i += 1
            }
            guard let found else { return nil }
            hits.append(found)
            from = found + 1
        }
        return hits
    }

    /// Query characters appear in order anywhere; each is matched at its earliest position.
    private static func scattered(_ q: [Character], in t: [Character]) -> [Int]? {
        var hits: [Int] = []
        var from = 0
        for ch in q {
            guard let index = t[from...].firstIndex(of: ch) else { return nil }
            hits.append(index)
            from = index + 1
        }
        return hits
    }

    /// Folded positions back to original offsets, merged into contiguous runs.
    private static func ranges(_ positions: [Int], _ t: Folded) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for p in positions {
            let o = t.origin[p]
            if let last = result.last, last.upperBound == o {
                result[result.count - 1] = last.lowerBound..<(o + 1)
            } else if let last = result.last, last.contains(o) {
                continue
            } else {
                result.append(o..<(o + 1))
            }
        }
        return result
    }
}
