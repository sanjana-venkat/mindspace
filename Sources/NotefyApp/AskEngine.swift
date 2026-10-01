import Foundation
import NotefyCore

/// One capture offered to the model as evidence, and offered to you as a chip.
///
/// The index is what the model cites and what the chip shows, so the number you
/// see in the answer is the number you can click.
struct AskSource: Identifiable, Equatable {
    let id = UUID()
    let index: Int
    let noteURL: URL
    let noteTitle: String
    let stepID: UUID?
    let label: String
    let date: Date
    let text: String

    static func == (a: AskSource, b: AskSource) -> Bool { a.id == b.id }
}

/// A question, its answer, and the captures the answer came out of.
struct AskTurn: Identifiable {
    let id = UUID()
    let question: String
    var answer: String = ""
    var sources: [AskSource] = []
    var cited: [Int] = []
    var failure: String?
    var thinking: Bool = true
    /// What it is doing while it thinks: searching, then reading.
    var status: String = "Reading what you saved…"

    /// Only the sources the answer actually leaned on. Listing all twelve under
    /// a two line answer is noise pretending to be rigour.
    var citedSources: [AskSource] {
        let used = Set(cited)
        let hits = sources.filter { used.contains($0.index) }
        return hits.isEmpty ? [] : hits
    }
}

enum AskEngine {
    /// Words worth matching on. Everything here is either grammar or a word
    /// every note contains, so keeping them would rank the whole library.
    private static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "if", "of", "to", "in", "on", "for",
        "with", "about", "from", "by", "at", "as", "is", "are", "was", "were", "be",
        "been", "it", "its", "this", "that", "these", "those", "i", "me", "my",
        "mine", "you", "your", "we", "our", "they", "them", "what", "which", "who",
        "when", "where", "why", "how", "did", "do", "does", "done", "can", "could",
        "would", "should", "have", "has", "had", "save", "saved", "note", "notes",
        "find", "show", "tell", "me", "anything", "something"
    ]

    static func keywords(_ question: String) -> [String] {
        question.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopwords.contains($0) }
    }

    /// Scores a capture against the question. Deliberately simple: a word that
    /// appears is worth something, a word in the title is worth more, and a
    /// recent capture breaks ties. There is no embedding index here, and
    /// pretending otherwise would be worse than being plain about it.
    static func score(text: String, title: String, date: Date, keywords: [String]) -> Double {
        guard !keywords.isEmpty else { return 0 }
        let haystack = text.lowercased()
        let head = title.lowercased()
        var score = 0.0
        for word in keywords {
            if haystack.contains(word) { score += 1 }
            if head.contains(word) { score += 1.5 }
        }
        guard score > 0 else { return 0 }
        // A month old halves it. Recency is a tiebreak, not a ranking.
        let age = max(0, Date().timeIntervalSince(date)) / (60 * 60 * 24 * 30)
        return score * (1.0 / (1.0 + age * 0.5))
    }

    /// Questions about time are the common case and carry almost no keywords.
    /// "What did I save this week" reduces to nothing once the grammar is gone,
    /// which is why it used to come back empty.
    static func timeWindow(in question: String) -> Date? {
        let q = question.lowercased()
        let now = Date()
        if q.contains("today") { return Calendar.current.startOfDay(for: now) }
        if q.contains("yesterday") { return now.addingTimeInterval(-2 * 86_400) }
        if q.contains("this week") || q.contains("past week") || q.contains("last week") {
            return now.addingTimeInterval(-7 * 86_400)
        }
        if q.contains("this month") || q.contains("past month") || q.contains("last month") {
            return now.addingTimeInterval(-31 * 86_400)
        }
        if q.contains("recent") || q.contains("lately") { return now.addingTimeInterval(-14 * 86_400) }
        return nil
    }

    static func label(for step: ExplorationStep) -> String {
        let when = DateFormatter()
        when.dateFormat = "d MMM"
        let stamp = when.string(from: step.timestamp)
        if step.appName == "Your audio" || step.windowTitle == "Voice note" {
            return "your voice note, \(stamp)"
        }
        if step.screenshotPath != nil { return "your screenshot, \(stamp)" }
        if let host = URL(string: step.url ?? "")?.host?.replacingOccurrences(of: "www.", with: ""),
           !host.isEmpty {
            return "\(host), \(stamp)"
        }
        return "\(step.appName), \(stamp)"
    }

    /// Today's date in words, so "this week" and "yesterday" mean something
    /// to a model that has no clock.
    static var today: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM yyyy"
        return f.string(from: Date())
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM yyyy, HH:mm"
        return f.string(from: date)
    }

    static let systemPrompt = """
    You are the person's own memory, answering from material they saved themselves.

    How to answer:
    · Answer the question directly in the first sentence. Work from the numbered \
    sources: summarise, compare, connect and draw the takeaway out of them when \
    that is what is asked. A question like "what was the key takeaway" wants your \
    best synthesis of the sources, not a search for that exact phrase.
    · Stay grounded. Everything you claim must come from the sources. If they \
    genuinely do not cover the question, say so in one sentence and name what is \
    missing. Never fill a gap from general knowledge.
    · Cite with bracketed numbers like [2] or [2, 5] right after the claim they \
    support. Every factual sentence carries at least one. Only cite numbers that exist.
    · Quote their own words when they wrote something well. They will recognise it.
    · Plain prose, second person, no headings, no bullet lists, under 150 words.
    · You are the part of them that remembers, so say "you saved", "you wrote", \
    "you were looking at", "you said".
    """

    /// The librarian: reads an index of every capture and picks the ones that
    /// bear on the question. This is the search, done by reading for meaning
    /// rather than counting shared words.
    static let retrievalPrompt = """
    You pick sources for a question. You are given a question and an index of \
    saved captures, one per line, each starting with its number in brackets, \
    then the note it belongs to, what it is, when it was saved, and an excerpt.

    Choose the captures that help answer the question, judging by meaning, not \
    shared words: synonyms, related topics and paraphrases count. Use the dates \
    when the question is about time ("this week", "yesterday", "recently"). For \
    a broad question ("what did I save", "summarise everything") choose a wide \
    spread. Choose at most 12, most useful first.

    Reply with only a JSON array of the chosen numbers, like [4, 17, 2]. \
    Reply [] if nothing is relevant.
    """

    /// Reads the librarian's reply. Tolerates code fences and stray words, since
    /// a model asked for bare JSON does not always send bare JSON.
    static func pickedIndices(in reply: String) -> [Int] {
        guard let open = reply.firstIndex(of: "["),
              let close = reply[open...].firstIndex(of: "]") else { return [] }
        let inner = reply[reply.index(after: open)..<close]
        var seen = Set<Int>()
        return inner.split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
            .filter { seen.insert($0).inserted }
    }

    /// Pulls the numbers back out of the answer so the chips match the citations.
    /// Handles [2], [2, 3], [2-4] and [2][3]; a bracket holding anything other
    /// than numbers, commas and dashes is prose and is ignored.
    static func citations(in answer: String) -> [Int] {
        var found = Set<Int>()
        var inside = false
        var body = ""
        for ch in answer {
            if ch == "[" { inside = true; body = ""; continue }
            guard inside else { continue }
            if ch == "]" {
                inside = false
                found.formUnion(numbers(inCitation: body))
                continue
            }
            body.append(ch)
        }
        return found.sorted()
    }

    private static func numbers(inCitation body: String) -> [Int] {
        let allowed = CharacterSet(charactersIn: "0123456789,-–; ")
        guard !body.isEmpty, body.unicodeScalars.allSatisfy(allowed.contains) else { return [] }
        var out: [Int] = []
        for piece in body.split(whereSeparator: { $0 == "," || $0 == ";" }) {
            let ends = piece.split(whereSeparator: { $0 == "-" || $0 == "–" })
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if ends.count == 2, ends[0] <= ends[1], ends[1] - ends[0] < 50 {
                out.append(contentsOf: ends[0]...ends[1])
            } else if let n = ends.first {
                out.append(n)
            }
        }
        return out
    }
}
