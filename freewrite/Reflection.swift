//
//  Reflection.swift
//  Considered
//
//  Tools for developing a piece: questions you ask yourself, and optional AI
//  lenses that examine your reasoning without doing the thinking for you.
//

import Foundation

struct QuestionGroup: Identifiable {
    let id: String
    let title: String
    let questions: [String]
}

enum DevelopQuestions {
    /// Clicking a question adds it to the piece as a section heading to write under.
    static let groups: [QuestionGroup] = [
        QuestionGroup(id: "clarify", title: "Clarify", questions: [
            "What am I actually trying to say?",
            "What prompted this thought?",
            "What do I mean by the key words I'm using?"
        ]),
        QuestionGroup(id: "examine", title: "Examine", questions: [
            "What am I assuming?",
            "What is the strongest objection?",
            "What would change my mind?",
            "Where does this contradict itself?"
        ]),
        QuestionGroup(id: "study", title: "Study a text", questions: [
            "What does the text say?",
            "What does it mean?",
            "What does it show about God, and about people?",
            "How does it apply to me?"
        ]),
        QuestionGroup(id: "conclude", title: "Conclude", questions: [
            "What is still unanswered?",
            "What do I now believe?",
            "How has my thinking changed?"
        ])
    ]
}

enum ReflectionLens: String, CaseIterable, Identifiable {
    case examine
    case clarify
    case challenge
    case talk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .examine: return "Examine my reasoning"
        case .clarify: return "Find what I'm saying"
        case .challenge: return "Challenge my conclusion"
        case .talk: return "Talk it through"
        }
    }

    var subtitle: String {
        switch self {
        case .examine: return "Assumptions, gaps, contradictions, open questions."
        case .clarify: return "My central claim and a structure, in my own words."
        case .challenge: return "The strongest case against what I've concluded."
        case .talk: return "A warm, honest conversation about what I wrote."
        }
    }

    private static let ground = """
    Below is a piece of my own writing. I'm using it to work out what I think. \
    Please don't rewrite it, don't summarise it back to me at length, and don't replace my thinking with yours. \
    Quote my exact words when you point at something. Be direct, specific, and brief where you can.
    """

    var prompt: String {
        switch self {
        case .examine:
            return """
            \(Self.ground)

            Help me examine my reasoning:
            1. In one or two sentences, state the claim I seem to be making.
            2. List the assumptions I'm relying on, including the ones I haven't said out loud.
            3. Point out gaps, leaps, contradictions, or places where I'm vague.
            4. Ask me the three to five questions that would most move my thinking forward.

            My writing:
            """
        case .clarify:
            return """
            \(Self.ground)

            Help me find what I'm actually trying to say:
            1. What seems to be the one central idea underneath everything here?
            2. Which parts serve that idea, and which parts are a different idea that deserves its own piece?
            3. Suggest an order for my existing points that would make the reasoning easier to follow. Use my ideas and my voice; don't add new arguments.

            My writing:
            """
        case .challenge:
            return """
            \(Self.ground)

            I've reached a conclusion here. Steelman the strongest, most charitable objection to it, the one a thoughtful person who disagrees would actually make. \
            Then tell me which part of my reasoning that objection puts the most pressure on, and what I would need to show to answer it. \
            Don't tell me whether I'm right.

            My writing:
            """
        case .talk:
            return """
            Below is something I wrote to think through what's on my mind. Talk it through with me like a thoughtful friend who knows me well. \
            Don't therapise me and don't repeat my thoughts back under headings. Help me notice connections I can't see, \
            validate what's true, and push back where I'm fooling myself. Then ask me what I think now.

            What I wrote:
            """
        }
    }
}

enum AIDestination {
    case claude
    case chatGPT

    var name: String {
        switch self {
        case .claude: return "Claude"
        case .chatGPT: return "ChatGPT"
        }
    }

    var baseURL: String {
        switch self {
        case .claude: return "https://claude.ai/new?q="
        case .chatGPT: return "https://chatgpt.com/?q="
        }
    }

    /// Query-safe encoding: urlQueryAllowed still lets "&", "+", "=" and "#" through, which would cut the prompt short.
    static let queryAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=?#")
        return set
    }()

    func url(for fullPrompt: String) -> URL? {
        guard let encoded = fullPrompt.addingPercentEncoding(withAllowedCharacters: AIDestination.queryAllowed) else {
            return nil
        }
        return URL(string: baseURL + encoded)
    }

    /// Long URLs fail in some browsers; past this the writer copies the prompt instead.
    static let maximumURLLength = 6000
}
