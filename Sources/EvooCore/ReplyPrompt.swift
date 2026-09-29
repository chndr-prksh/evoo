import Foundation

/// 16 GB Macs: "reply saying Thursday works" writes a full reply to the conversation on screen,
/// and "translate to Hindi, see you tomorrow" translates what you say before typing it.
public enum ReplyPrompt {
    /// The intent from "reply saying …", "respond that …", "write a reply telling them …".
    public static func replyIntent(_ dictation: String) -> String? {
        capture(dictation, #"(?:reply|respond|answer|write (?:a |an )?(?:reply|response|answer))(?: back)?(?: to (?:this|them|him|her|it))?(?: (?:saying|that|with|to say|and say|telling (?:them|him|her)|letting (?:them|him|her) know(?: that)?))?[,:]? (.+)"#)?[1]
    }

    /// ("Hindi", "see you tomorrow") from "translate to Hindi, see you tomorrow".
    public static func translation(_ dictation: String) -> (language: String, text: String)? {
        guard let m = capture(dictation, #"(?:translate|say this|write this) (?:to|into|in) ([A-Za-z]+)[,:]? (.+)"#) else { return nil }
        return (m[1], m[2])
    }

    static func capture(_ dictation: String, _ pattern: String) -> [String]? {
        let s = dictation.trimmingCharacters(in: .whitespaces)
        guard let regex = try? NSRegularExpression(pattern: "^(?i)(?:please )?" + pattern + "$"),
              let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0 ..< m.numberOfRanges).map { Range(m.range(at: $0), in: s).map { String(s[$0]) } ?? "" }
    }

    static let system = """
    You write replies for the user. You see what's on their screen (a conversation or email) and what they \
    want to say. Turn it into the natural, complete message they would send: respond directly to the other \
    person, in the user's voice, matching the conversation's language and tone (a friendly sentence or two for \
    chats; greeting and sign-off for emails). Use only the facts they gave — don't invent times, names or \
    promises. Output only the message: no "Reply:" label, no quotes, no explanation.
    """

    public static var prefix: String { "<|im_start|>system\n\(system)<|im_end|>\n" }

    public static func suffix(screen: String, intent: String, thinkBlock: Bool) -> String {
        "<|im_start|>user\nOn screen:\n\(screen)\n\nWhat I want to say: \(intent)<|im_end|>\n<|im_start|>assistant\n"
            + (thinkBlock ? "<think>\n\n</think>\n\n" : "")
    }
}

/// How formal smart cleanup should sound in the app you're typing into.
public enum Tone: String, Sendable {
    case neutral, casual, professional

    public static func forApp(_ bundleID: String?) -> Tone {
        guard let id = bundleID?.lowercased() else { return .neutral }
        let casual = ["whatsapp", "com.apple.mobilesms", "slack", "discord", "telegram", "signal", "messenger"]
        let professional = ["com.apple.mail", "outlook", "superhuman", "spark", "airmail", "mimestream"]
        if casual.contains(where: id.contains) { return .casual }
        if professional.contains(where: id.contains) { return .professional }
        return .neutral
    }

    var instruction: String {
        switch self {
        case .neutral: ""
        case .casual: "This is a chat message: keep it casual and short, keep contractions, don't make it formal."
        case .professional: "This is an email: keep it clear and professional, with complete sentences."
        }
    }
}

/// One-click term lists for the personal dictionary.
public enum VocabularyPacks {
    public static let packs: [(name: String, terms: [String])] = [
        ("Medical", ["acetaminophen", "ibuprofen", "amoxicillin", "metformin", "lisinopril", "atorvastatin",
                     "hypertension", "tachycardia", "bradycardia", "arrhythmia", "dyspnea", "edema", "sepsis",
                     "myocardial", "infarction", "pneumonia", "COPD", "MRI", "CT", "ECG", "EKG", "hemoglobin",
                     "creatinine", "biopsy", "oncology", "cardiology", "neurology", "pediatrics", "anesthesia",
                     "prognosis", "differential", "subcutaneous", "intravenous", "SpO2", "HbA1c"]),
        ("Legal", ["plaintiff", "defendant", "affidavit", "deposition", "subpoena", "indemnification",
                   "indemnify", "arbitration", "jurisdiction", "tort", "estoppel", "habeas", "voir dire",
                   "amicus", "certiorari", "fiduciary", "lien", "escrow", "NDA", "MSA", "SOW", "force majeure",
                   "severability", "counterparty", "novation", "statute", "precedent", "pro bono", "litigation"]),
        ("Finance", ["EBITDA", "ARR", "MRR", "CAGR", "P&L", "COGS", "OPEX", "CAPEX", "amortization",
                     "depreciation", "accrual", "receivables", "payables", "liquidity", "solvency", "dividend",
                     "valuation", "term sheet", "cap table", "SAFE", "tranche", "hedging", "derivatives", "ROI",
                     "IRR", "NPV", "YoY", "QoQ", "burn rate", "runway", "GAAP", "IFRS"]),
        ("Tech", ["Kubernetes", "Docker", "PostgreSQL", "MongoDB", "Redis", "GraphQL", "TypeScript", "JavaScript",
                  "Python", "Swift", "React", "Next.js", "Node.js", "GitHub", "GitLab", "Terraform", "AWS", "GCP",
                  "Azure", "API", "SDK", "CI/CD", "OAuth", "JWT", "JSON", "YAML", "LLM", "RAG", "embeddings",
                  "latency", "microservices", "Figma", "Jira", "Confluence", "Vercel", "Supabase"]),
    ]
}
