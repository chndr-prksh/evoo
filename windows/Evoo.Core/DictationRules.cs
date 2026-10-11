using System.Text.RegularExpressions;

namespace Evoo.Core;

/// <summary>
/// Deterministic dictation cleanup — a port of the Mac app's Sources/EvooCore/DictationRules.swift, kept in step
/// with it by the shared cases in Evoo.Core.Tests/rules.tsv (exported from the Mac app's tests):
///  • filler words:     "um so we should ship"               → "so we should ship"
///  • stutters:         "we could we could push it"          → "we could push it"
///  • self-corrections: "let's meet tomorrow, no, day after tomorrow" → "let's meet day after tomorrow"
/// </summary>
public static class DictationRules
{
    public readonly record struct Result(string Text, bool Unresolved);

    public static Result Apply(string input)
    {
        var tokens = Regex.Split(RemoveCommaFillers(NormalizeMeridiem(input)), @"\s+")
            .Where(s => s.Length > 0).Select(s => new Token(s)).ToList();
        tokens = RemoveFillers(tokens);
        tokens = RemoveStutters(tokens);
        tokens = CollapseValueCorrections(tokens);
        tokens = CollapseEchoNegations(tokens);
        tokens = CollapseRestatements(tokens);
        var unresolved = false;
        tokens = ApplyCorrections(tokens, ref unresolved);
        return new Result(Render(tokens), unresolved);
    }

    // ── Tokens

    public sealed class Token(string raw)
    {
        public string Raw = raw;
        /// <summary>Lowercased letters/digits only — used for matching.</summary>
        public string Norm => Normalize(Raw);
        public bool EndsClause => Raw.Length > 0 && ",;:".Contains(Raw[^1]);
        public bool EndsSentence => Raw.Length > 0 && ".?!".Contains(Raw[^1]);
        /// <summary>The word without trailing punctuation, keeping the original casing.</summary>
        public string Bare => Raw.TrimEnd(',', ';', ':', '.', '?', '!');
        public string TrailingPunctuation => Raw[Bare.Length..];
        public Token Copy() => new(Raw);

        public static string Normalize(string s) =>
            new string(s.ToLowerInvariant().Where(c => char.IsLetterOrDigit(c) || c == ':').ToArray()).Trim(':');
    }

    private static string LowerFirst(string s) => s.Length == 0 ? s : char.ToLowerInvariant(s[0]) + s[1..];
    private static string Capitalized(string s) => s.Length > 0 && char.IsLower(s[0]) ? char.ToUpperInvariant(s[0]) + s[1..] : s;
    private static bool StartsUpper(string s) => s.Length > 0 && char.IsUpper(s[0]);

    // ── Fillers & stutters

    private const string Fillers = "(?:like|you know|basically|so yeah|so basically|kind of|sort of|literally|okay so)";

    /// <summary>Spoken fillers the speech model sets off with commas: "…to, like, give…", "You know, we…".</summary>
    public static string RemoveCommaFillers(string text)
    {
        const RegexOptions I = RegexOptions.IgnoreCase;
        var o = Regex.Replace(text, @",\s*(?:you know|so basically|basically|so yeah|okay so),\s*", ", ", I);
        o = Regex.Replace(o, @",\s*" + Fillers + @",\s*", " ", I);
        o = Regex.Replace(o, @"(^|[.!?]\s+)you know,?\s+((?:we|i|they|he|she|there|so|my|our)\b)",
            m => m.Groups[1].Value + Capitalized(m.Groups[2].Value), I);
        o = Regex.Replace(o, @",\s*you know(?=[.!?]|$)", "", I);
        // "…to like give you…" → "…to give you…" ("I'd like to" keeps its "like").
        o = Regex.Replace(o, @"\bto like (\w+)", m => Verbs.IsVerb(m.Groups[1].Value) ? "to " + m.Groups[1].Value : m.Value, I);
        // Sentence start: "Like, engineering…" → "Engineering…"
        o = Regex.Replace(o, @"(^|[.!?]\s+)" + Fillers + @",?\s+(\w)", m =>
            m.Value.Contains(',') || m.Value.ToLowerInvariant().Contains("so ")
                ? m.Groups[1].Value + m.Groups[2].Value.ToUpperInvariant() : m.Value, I);
        return o;
    }

    private static HashSet<string> Set(string words) => new(words.Split(' ', StringSplitOptions.RemoveEmptyEntries));

    /// <summary>Small words a comma never really follows ("to, Wednesday").</summary>
    private static readonly HashSet<string> GlueWords = Set("to the a an and of on in at for from with is was are be my your our their his her by");
    private static readonly HashSet<string> FillerWords = Set("um umm uh uhh uhm erm er hmm mm mhm ah");

    private static List<Token> RemoveFillers(List<Token> tokens)
    {
        var o = new List<Token>();
        for (var i = 0; i < tokens.Count; i++)
        {
            var t = tokens[i];
            // "Um, so, uh, I think…": a "so" wedged between fillers is a filler too.
            var isFiller = FillerWords.Contains(t.Norm) || (t.Norm == "so" && t.Raw.EndsWith(',') &&
                ((i > 0 && FillerWords.Contains(tokens[i - 1].Norm)) || (i + 1 < tokens.Count && FillerWords.Contains(tokens[i + 1].Norm))));
            if (!isFiller) { o.Add(t); continue; }
            // "to, um, Wednesday" → "to Wednesday": the comma only framed the filler.
            if (t.EndsClause && o.Count > 0 && o[^1].EndsClause && GlueWords.Contains(o[^1].Norm)) o[^1].Raw = o[^1].Bare;
            // Keep sentence-ending punctuation the filler carried ("… ship it, um." → "… ship it.").
            if (t.EndsSentence && o.Count > 0) o[^1].Raw = o[^1].Bare + t.TrailingPunctuation;
        }
        return o;
    }

    /// <summary>Real one- and two-letter words, so only broken-off starts are dropped.</summary>
    private static readonly HashSet<string> ShortWords = Set("a i an am as at be by do go he hi if in is it me my no of oh ok on or so to up us we ah ha yo");
    /// <summary>Common three-letter words, never treated as broken-off starts ("the theory", "car carpet").</summary>
    private static readonly HashSet<string> CommonThreeLetter = Set(
        "the and for you are but not all any can had her was one our out day get has him his how man new now old see two way who " +
        "did its let put say she too use car cat dog big bad yes yet got may run sit top red far few own off end why ask men per " +
        "art pay buy fun job law map sun war air age key low set try");
    /// <summary>Words that are legitimately doubled in normal speech ("I know that that is…", "had had").</summary>
    private static readonly HashSet<string> LegitDoubles = Set("that had is very really bye no ha");

    private static List<Token> RemoveStutters(List<Token> tokens)
    {
        // Broken-off word starts: "like m make it" → "like make it", "your dis dictionary" → "your dictionary".
        var t = new List<Token>();
        for (var i = 0; i < tokens.Count; i++)
        {
            var tok = tokens[i];
            if (i + 1 >= tokens.Count || tok.EndsClause || tok.EndsSentence) { t.Add(tok); continue; }
            string w = tok.Norm, next = tokens[i + 1].Norm;
            if (w.Length == 0 || !w.All(char.IsLetter) || next.Length == 0 || next[0] != w[0]) { t.Add(tok); continue; }
            var head = next.Length >= w.Length ? next[..w.Length] : next;
            var mismatches = head.Zip(w).Count(p => p.First != p.Second);
            var fragment = (w.Length <= 2 && next.StartsWith(w, StringComparison.Ordinal) && !ShortWords.Contains(w) && next.Length > w.Length) ||
                (w.Length == 3 && mismatches <= 1 && !CommonThreeLetter.Contains(w) && next.Length >= 6);
            if (!fragment) t.Add(tok);
        }
        t = RemoveRestarts(t);
        var changed = true;
        while (changed)
        {
            changed = false;
            for (var n = 4; n >= 1 && !changed; n--)
            {
                if (t.Count < 2 * n) continue;
                for (var i = 0; i <= t.Count - 2 * n; i++)
                {
                    var a = t.GetRange(i, n).Select(x => x.Norm).ToList();
                    var b = t.GetRange(i + n, n).Select(x => x.Norm).ToList();
                    if (!a.SequenceEqual(b) || a.Contains("") || (n == 1 && LegitDoubles.Contains(a[0]))) continue;
                    // Keep the second copy — it carries the punctuation that follows. If the speech model put a
                    // sentence break inside the stutter ("we could. We could"), undo the capital it added.
                    var wasLowercase = t[i].Raw.Length > 0 && char.IsLower(t[i].Raw[0]);
                    t.RemoveRange(i, n);
                    if (wasLowercase && (i == 0 || !t[i - 1].EndsSentence)) t[i].Raw = LowerFirst(t[i].Raw);
                    changed = true;
                    break;
                }
            }
        }
        return t;
    }

    /// <summary>Openers people restart with ("if it sounds… if it's unusual", "when we… when we're done").</summary>
    private static readonly HashSet<string> RestartOpeners = Set("if when i we you it so and but because the this that they he she there what can");

    /// <summary>A phrase started, abandoned, and started again: "if it sounds if it's unusual" → "if it's unusual".</summary>
    private static List<Token> RemoveRestarts(List<Token> input)
    {
        var t = new List<Token>(input);
        var i = 0;
        while (i + 3 < t.Count)
        {
            string a = t[i].Norm, b = t[i + 1].Norm;
            if (!RestartOpeners.Contains(a)) { i++; continue; }
            var restarted = false;
            for (var j = i + 2; j <= Math.Min(i + 5, t.Count - 2); j++)
            {
                if (t[j].Norm != a || t[j + 1].Norm == b || !t[j + 1].Norm.StartsWith(b, StringComparison.Ordinal) || b.Length < 2) continue;
                // Nothing between the two starts may end a clause — that would be two real phrases.
                if (t.GetRange(i, j - i).Any(x => x.EndsClause || x.EndsSentence)) break;
                t.RemoveRange(i, j - i);
                restarted = true;
                break;
            }
            if (!restarted) i++;
        }
        return t;
    }

    // ── a.m. / p.m.

    /// <summary>"4 p.m." → "4 PM" so the dots aren't mistaken for sentence ends ("at 4 p.m. 5 p.m.").</summary>
    private static string NormalizeMeridiem(string text)
    {
        // The lookahead for a capital must stay case-sensitive; only the letters a/p/m are matched loosely.
        var o = Regex.Replace(text, @"\b([aApP])\.\s?[mM]\.(?=\s*$|\s+[A-Z])", "$1M.");
        o = Regex.Replace(o, @"\b([aApP])\.\s?[mM]\.?", "$1M");
        return o.Replace("aM", "AM").Replace("pM", "PM");
    }

    // ── Value corrections

    private static readonly HashSet<string> ReplacingCues = Set("no sorry actually wait rather correction make meant nahi");
    private static readonly HashSet<string> CueFiller = new(ReplacingCues.Concat(Set("not i mean it that or oh")));

    /// <summary>Multi-word dates: "day after tomorrow", "next week", "this Friday", "the weekend".</summary>
    private static readonly string[][] DatePhrases =
    [
        ["day", "after", "tomorrow"], ["day", "before", "yesterday"], ["the", "day", "after"], ["the", "week", "after"],
        ["the", "week", "after", "next"], ["next", "week"], ["this", "week"], ["next", "month"], ["this", "month"],
        ["next", "year"], ["this", "weekend"], ["next", "weekend"], ["the", "weekend"], ["tomorrow", "morning"],
        ["tomorrow", "evening"], ["tomorrow", "night"], ["tonight"], ["this", "evening"], ["this", "morning"],
    ];
    private static readonly HashSet<string> WeekdayPrefixes = Set("next this coming last");
    private static readonly HashSet<string> DateWords = Set("day week weekend month year morning evening night");

    /// <summary>Words that are only capitalized at the start of a sentence.</summary>
    private static readonly HashSet<string> MidSentenceWords = new(GlueWords.Concat(Set(
        "a an the this that my your our their his her next last day week month year morning evening night noon around about after before maybe probably sometime early late later sooner")));

    private static bool LosesCapitalMidSentence(Token t)
    {
        var kind = WordKindOf(t.Norm);
        return StartsUpper(t.Raw) && (MidSentenceWords.Contains(t.Norm) || kind == WordKind.Number || kind == WordKind.RelativeDay);
    }

    /// <summary>
    /// Chains of times/numbers or days joined by correction words; the last value that survives wins.
    ///   "at 4, not 4 PM, 5 PM" → "at 5 PM";  "on Monday, sorry, Tuesday" → "on Tuesday";  "at 5, not 4" → unchanged
    /// </summary>
    private static List<Token> CollapseValueCorrections(List<Token> input)
    {
        var t = new List<Token>(input);
        var i = 0;
        while (i < t.Count)
        {
            var first = ValueGroup(t, i);
            if (first is null) { i++; continue; }
            var f = first.Value;
            (int Start, int End) kept = f, last = f;
            bool corrected = false, awaitingRestatement = false;
            var j = f.End;
            while (j < t.Count)
            {
                // The words between two values must all be correction words (or nothing but a comma).
                var k = j;
                while (k < t.Count && CueFiller.Contains(t[k].Norm)) k++;
                var gap = t.GetRange(j, k - j).Select(x => x.Norm).ToList();
                var next = ValueGroup(t, k);
                if (next is null || GroupClass(t, next.Value) != GroupClass(t, f)) break;
                var replaces = gap.Any(ReplacingCues.Contains) || gap.Contains("mean");
                var negates = gap.Contains("not");
                var commaOnly = gap.Count == 0 && t[last.End - 1].EndsClause;
                if (negates && !replaces) awaitingRestatement = true; // "not 4 PM" — that value is rejected
                else if (replaces || (gap.Count == 0 && awaitingRestatement) || (commaOnly && corrected))
                {
                    kept = next.Value;
                    corrected = true;
                    awaitingRestatement = false;
                }
                else break;
                last = next.Value;
                j = next.Value.End;
            }
            if (!corrected) { i = f.End; continue; }
            var replacement = t.GetRange(kept.Start, kept.End - kept.Start).Select(x => x.Copy()).ToList();
            var tail = t[last.End - 1].TrailingPunctuation;
            if (replacement.Count > 0)
                replacement[^1].Raw = replacement[^1].Bare + (tail.Any(c => ".?!".Contains(c)) ? tail[^1].ToString() : "");
            // "…tomorrow. No. Day after tomorrow.": the kept value sits mid-sentence, so it loses a capital the
            // speech model gave it for starting a "sentence" (weekdays and months keep theirs).
            if (f.Start > 0 && !t[f.Start - 1].EndsSentence && replacement.Count > 0 && LosesCapitalMidSentence(replacement[0]))
                replacement[0].Raw = LowerFirst(replacement[0].Raw);
            t.RemoveRange(f.Start, last.End - f.Start);
            t.InsertRange(f.Start, replacement);
            i = f.Start + replacement.Count;
        }
        return t;
    }

    /// <summary>A run of tokens forming one value: "4 PM", "3:30", "five thirty", "Tuesday", "day after tomorrow".</summary>
    private static (int Start, int End)? ValueGroup(List<Token> t, int i)
    {
        if (i >= t.Count) return null;
        var phrase = DatePhrases.Where(p => Matches(p, t, i)).OrderByDescending(p => p.Length).FirstOrDefault();
        if (phrase is not null) return (i, i + phrase.Length);
        if (WeekdayPrefixes.Contains(t[i].Norm) && i + 1 < t.Count && WordKindOf(t[i + 1].Norm) == WordKind.Weekday && !t[i].EndsClause)
            return (i, i + 2); // "next Monday"
        var cls = ValueClass(t[i]);
        if (cls is null) return null;
        // "am"/"pm" only belong to a time that came before them; alone they're words ("I am sorry I am late").
        if (t[i].Norm is "am" or "pm") return null;
        var end = i + 1;
        // A group ends at punctuation or after AM/PM ("4 PM 5 PM" is two times).
        while (end < t.Count && !t[end - 1].EndsClause && !t[end - 1].EndsSentence &&
               t[end - 1].Norm != "am" && t[end - 1].Norm != "pm" && ValueClass(t[end]) == cls) end++;
        return (i, end);
    }

    private static int? GroupClass(List<Token> t, (int Start, int End) g)
    {
        var count = g.End - g.Start;
        if (count > 1 && Enumerable.Range(g.Start, count).Any(x => ValueClass(t[x]) == 1 || DateWords.Contains(t[x].Norm))) return 1;
        return ValueClass(t[g.Start]);
    }

    /// <summary>"…play tomorrow, not tomorrow, day after tomorrow" / "send it to John, not John, Mike".</summary>
    private static List<Token> CollapseEchoNegations(List<Token> input)
    {
        var t = new List<Token>(input);
        var i = 1;
        while (i < t.Count)
        {
            // "to be or not to be", "whether or not", "like it or not" aren't corrections.
            if (t[i].Norm != "not" || t[i - 1].EndsSentence || t[i - 1].Norm == "or") { i++; continue; }
            var echoed = 0;
            for (var k = Math.Min(3, i); k >= 1; k--)
            {
                if (i + k >= t.Count) continue;
                var before = t.GetRange(i - k, k).Select(x => x.Norm);
                var after = t.GetRange(i + 1, k).Select(x => x.Norm);
                if (before.SequenceEqual(after)) { echoed = k; break; }
            }
            var start = i - echoed;
            // Partial echo: "2 laptops, not 2, 3 laptops" repeats only the first word of what's taken back.
            if (echoed == 0 && i + 1 < t.Count && t[i - 1].Raw.EndsWith(','))
            {
                for (var j = i - 1; j >= Math.Max(0, i - 3); j--)
                    if (t[j].Norm == t[i + 1].Norm) { echoed = 1; start = j; break; }
            }
            var restStart = i + 1 + echoed;
            // Needs a replacement after the echo, in the same sentence: "not tomorrow, <day after tomorrow>".
            if (echoed <= 0 || restStart >= t.Count || t[restStart - 1].EndsSentence) { i++; continue; }
            t.RemoveRange(start, restStart - start);
            if (start > 0) t[start - 1].Raw = t[start - 1].Bare; // drop a comma left dangling
            i = start + 1;
        }
        return t;
    }

    private static readonly HashSet<string> Intensifiers = Set("very really so super extremely quite too pretty totally absolutely completely much way");
    /// <summary>Words that may sit between a word and its restatement: "bad, not no bad, very bad".</summary>
    private static readonly HashSet<string> RestatementFillers = new(Intensifiers.Concat(Set("not no i mean sorry actually like or rather")));
    /// <summary>"I'm sorry I'm late", "we know we can": a repeated subject is ordinary speech, not a restatement.</summary>
    private static readonly HashSet<string> Subjects = Set("i im ive ill id we were weve well you youre youve he hes she shes they theyre theyve it its that thats this there theres " +
        "am are be been have has had do does did will would can could should shall may might must"); // "I am sorry I am late"

    /// <summary>A word said again with a sharper modifier replaces the first attempt: "still bad, very bad" → "still very bad".</summary>
    private static List<Token> CollapseRestatements(List<Token> input)
    {
        var t = new List<Token>(input);
        var changed = true;
        while (changed)
        {
            changed = false;
            for (var i = 0; i < t.Count; i++)
            {
                var w = t[i].Norm;
                if (w.Length == 0 || FunctionWords.Contains(w) || RestatementFillers.Contains(w) || Subjects.Contains(w) || t[i].EndsSentence) continue;
                // The same word again within 5 words, with only fillers in between.
                var j = -1;
                for (var x = i + 1; x < Math.Min(t.Count, i + 6); x++) if (t[x].Norm == w) { j = x; break; }
                if (j <= i + 1) continue;
                var between = t.GetRange(i + 1, j - i - 1);
                if (!between.All(x => RestatementFillers.Contains(x.Norm))) continue;
                // Keep the modifiers directly before the restated word ("very"), drop the rest.
                var keepFrom = j;
                while (keepFrom > i + 1 && Intensifiers.Contains(t[keepFrom - 1].Norm) && !t[keepFrom - 1].EndsClause) keepFrom--;
                if (!(keepFrom < j || between.Any(x => !Intensifiers.Contains(x.Norm)))) continue;
                t.RemoveRange(i, keepFrom - i);
                changed = true;
                break;
            }
        }
        return t;
    }

    private static int? ValueClass(Token token) => WordKindOf(token.Norm) switch
    {
        WordKind.Number => 0,
        WordKind.Weekday or WordKind.RelativeDay or WordKind.Month => 1,
        _ => token.Norm == "oclock" ? 0 : null,
    };

    // ── Self-corrections

    /// <summary>Words that can make up a correction cue, e.g. "no", "no sorry", "actually make that", "I mean".</summary>
    private static readonly HashSet<string> CueWords = Set("no sorry wait actually nahi nahin matlab");
    private static readonly string[][] CuePhrases =
    [
        ["i", "mean"], ["make", "that"], ["make", "it"], ["or", "rather"], ["scratch", "that"], ["correction"],
        ["mera", "matlab"], ["im", "sorry"], ["i", "am", "sorry"],
    ];
    /// <summary>Cue words that also occur in normal speech; they only count when set off by punctuation or combined.</summary>
    private static readonly HashSet<string> WeakCues = new() { "no", "sorry", "wait", "actually", "make that", "make it", "correction", "im sorry", "i am sorry" };

    private readonly record struct Cue(int Start, int End, bool IsScratch);
    /// <summary>Truncate: drop everything from At and continue with the repair (Unit words after the old value are kept). Swap: replace one word in place.</summary>
    private readonly record struct Plan(bool IsSwap, int At, List<string>? Unit = null);

    private static int LastSentenceEnd(List<Token> t, int before)
    {
        for (var i = before - 1; i >= 0; i--) if (t[i].EndsSentence) return i;
        return -1;
    }

    private static List<Token> ApplyCorrections(List<Token> input, ref bool unresolved)
    {
        var tokens = new List<Token>(input);
        var searchFrom = 0;
        while (FindCue(tokens, searchFrom) is { } cue)
        {
            var sentenceStart = LastSentenceEnd(tokens, cue.Start) + 1;
            // The speech model often ends the sentence at the hesitation: "at 3:30. Actually make it 4." —
            // the cue opens a new sentence, so the correction applies to the previous one.
            if (sentenceStart == cue.Start && sentenceStart > 0 && !cue.IsScratch)
                sentenceStart = LastSentenceEnd(tokens, sentenceStart - 1) + 1;
            var prefix = tokens.GetRange(sentenceStart, cue.Start - sentenceStart);
            var repairEnd = tokens.Count;
            for (var x = cue.End; x < tokens.Count; x++) if (tokens[x].EndsSentence) { repairEnd = x + 1; break; }
            var repair = tokens.GetRange(cue.End, repairEnd - cue.End);

            if (cue.IsScratch)
            {
                // "scratch that" deletes what came before it in the sentence, or the previous sentence.
                var start = sentenceStart;
                if (prefix.Count == 0 && sentenceStart > 0) start = LastSentenceEnd(tokens, sentenceStart - 1) + 1;
                tokens.RemoveRange(start, cue.End - start);
                searchFrom = start;
                continue;
            }
            Plan? plan = prefix.Count > 0 && repair.Count > 0 ? MakePlan(prefix, repair) : null;
            if (plan is null)
            {
                unresolved = true;
                searchFrom = cue.End;
                continue;
            }
            List<Token> fixedTokens;
            var p = plan.Value;
            if (!p.IsSwap)
            {
                var body = repair.Select(x => x.Copy()).ToList();
                if (p.Unit is { Count: > 0 } && body.Count > 0)
                {
                    // "5." + ["boxes"] → "5 boxes."
                    var end = body[^1].TrailingPunctuation;
                    body[^1].Raw = body[^1].Bare;
                    body.AddRange(p.Unit.Select(u => new Token(u)));
                    body[^1].Raw += end;
                }
                fixedTokens = prefix.GetRange(0, p.At).Select(x => x.Copy()).Concat(body).ToList();
                if (p.At == 0 && fixedTokens.Count > 0) fixedTokens[0].Raw = Capitalized(fixedTokens[0].Raw);
                if (p.At > 0) fixedTokens[p.At - 1].Raw = fixedTokens[p.At - 1].Bare; // drop the comma that led into the cue
                // The speech model may have started a new sentence at the cue ("…tomorrow. No. Day after
                // tomorrow."): mid-sentence now, an ordinary word loses that capital (names keep theirs).
                if (p.At > 0 && p.At < fixedTokens.Count && LosesCapitalMidSentence(fixedTokens[p.At]))
                    fixedTokens[p.At].Raw = LowerFirst(fixedTokens[p.At].Raw);
            }
            else
            {
                fixedTokens = prefix.Select(x => x.Copy()).ToList();
                var tail = fixedTokens[p.At].TrailingPunctuation;
                fixedTokens.RemoveAt(p.At);
                fixedTokens.InsertRange(p.At, repair.Select(x => new Token(x.Bare)));
                fixedTokens[p.At + repair.Count - 1].Raw += tail;
                // The sentence's end moves from the repair to the (unchanged) prefix.
                fixedTokens[^1].Raw = fixedTokens[^1].Bare + repair[^1].TrailingPunctuation;
            }
            tokens.RemoveRange(sentenceStart, repairEnd - sentenceStart);
            tokens.InsertRange(sentenceStart, fixedTokens);
            searchFrom = sentenceStart;
        }
        return tokens;
    }

    private static Cue? FindCue(List<Token> t, int from)
    {
        var i = from;
        while (i < t.Count)
        {
            var j = i;
            var parts = new List<string>();
            // Greedily consume consecutive cue words/phrases: "no, sorry, I mean".
            while (j < t.Count)
            {
                var phrase = CuePhrases.FirstOrDefault(p => Matches(p, t, j));
                if (phrase is not null) { parts.Add(string.Join(' ', phrase)); j += phrase.Length; }
                else if (CueWords.Contains(t[j].Norm)) { parts.Add(t[j].Norm); j++; }
                else break;
                if (t[j - 1].EndsSentence) break;
            }
            if (parts.Count == 0) { i++; continue; }
            var isScratch = parts.Contains("scratch that");
            var setOff = (i > 0 && (t[i - 1].EndsClause || t[i - 1].EndsSentence)) || t[j - 1].EndsClause;
            var strong = parts.Count > 1 || parts.Any(x => !WeakCues.Contains(x));
            if (i > 0 && (isScratch || strong || setOff)) return new Cue(i, j, isScratch);
            i = j;
        }
        return null;
    }

    private static bool Matches(string[] phrase, List<Token> t, int i)
    {
        if (i + phrase.Length > t.Count) return false;
        for (var k = 0; k < phrase.Length; k++)
        {
            if (t[i + k].Norm != phrase[k]) return false;
            if (k < phrase.Length - 1 && t[i + k].EndsSentence) return false;
        }
        return true;
    }

    private static readonly HashSet<string> Determiners = Set("a an the this that my your our their his her next last");
    private static readonly HashSet<string> FunctionWords = Set("him her it them me you us the a an to of in on at for and or is was");
    /// <summary>A sentence that stops on one of these was abandoned mid-thought ("I think we should, actually…").</summary>
    private static readonly HashSet<string> DanglingEnds = Set("should could would will can might must to the a an and but or so gonna wanna we i just");

    private static Plan? MakePlan(List<Token> prefix, List<Token> repair)
    {
        var head = repair[0].Norm;
        // 1. The repair restarts from a word already said: "to Rahul, sorry, to Priya".
        var at = prefix.FindLastIndex(x => x.Norm == head);
        if (at >= 0) return new Plan(false, at);
        // 1b. The repair restarts a word that came out wrong: "Multi-tab, I'm sorry, multi command…".
        if (head.Length >= 4)
        {
            at = prefix.FindLastIndex(x => x.Norm.StartsWith(head, StringComparison.Ordinal) ||
                                           (head.StartsWith(x.Norm, StringComparison.Ordinal) && x.Norm.Length >= 4));
            if (at >= 0) return new Plan(false, at);
        }
        // 2. Same kind of value: numbers/times, weekdays, months, relative days.
        var kind = WordKindOf(head);
        if (kind is not null)
        {
            var end = prefix.Count;
            while (end > 0 && WordKindOf(prefix[end - 1].Norm) != kind) end--;
            if (end > 0)
            {
                var start = end - 1;
                while (start > 0 && WordKindOf(prefix[start - 1].Norm) == kind) start--;
                // A bare new value keeps the old value's unit: "3 boxes, actually 5" → "5 boxes".
                var bareValue = repair.All(x => WordKindOf(x.Norm) == kind);
                var unit = bareValue ? prefix.Skip(end).Select(x => x.Bare).Where(x => x.Length > 0).ToList() : [];
                return new Plan(false, start, unit.Count <= 2 ? unit : []);
            }
        }
        // 3. Restart from an article: "a 7 out of 10, actually an 8", "next week, no, the week after".
        if (Determiners.Contains(head))
        {
            at = prefix.FindLastIndex(x => Determiners.Contains(x.Norm));
            if (at >= 0) return new Plan(false, at);
        }
        // 4. A new action replaces the old one: "Email him, no, call him" → "Call him".
        if (StartsWithVerb(repair) && StartsWithVerb(prefix)) return new Plan(false, 0);
        // 5. The first attempt was abandoned mid-phrase: "I think we should, actually let's ship it".
        if (DanglingEnds.Contains(prefix[^1].Norm)) return new Plan(false, 0);
        // 6. A name replaces a name: "CC Tom on the email, I mean Tim", "Call John, sorry, Mike".
        if (repair.Count <= 2 && repair.All(x => StartsUpper(x.Bare)))
        {
            for (var x = prefix.Count - 1; x >= 1; x--)
                if (StartsUpper(prefix[x].Bare) && prefix[x].Norm != "i" && WordKindOf(prefix[x].Norm) is null) return new Plan(true, x);
        }
        // 7. The repair ends on a content word already said: "meet tomorrow, no, day after tomorrow".
        var lastWord = repair[^1].Norm;
        if (!FunctionWords.Contains(lastWord))
        {
            at = prefix.FindLastIndex(x => x.Norm == lastWord);
            if (at >= 0) return new Plan(false, at);
        }
        // 8. A one-word repair replaces the last word: "Buy apples, no, oranges". Never a pronoun.
        if (repair.Count == 1 && prefix.Count > 1 && !FunctionWords.Contains(head)) return new Plan(false, prefix.Count - 1);
        return null;
    }

    /// <summary>Whether the phrase opens with a verb (the Mac app asks Apple's tagger; here: a list of common verbs).</summary>
    private static bool StartsWithVerb(List<Token> tokens) =>
        tokens.Count > 0 && !FunctionWords.Contains(tokens[0].Norm) && Verbs.IsVerb(tokens[0].Norm);

    public enum WordKind { Number, Weekday, Month, RelativeDay }

    private static readonly HashSet<string> NumberWords = Set(
        "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen " +
        "twenty thirty forty fifty sixty seventy eighty ninety hundred thousand million half quarter noon midnight");
    private static readonly HashSet<string> Weekdays = Set("monday tuesday wednesday thursday friday saturday sunday");
    private static readonly HashSet<string> Months = Set("january february march april may june july august september october november december");
    private static readonly HashSet<string> RelativeDays = Set("today tomorrow tonight yesterday kal parso aaj");

    public static WordKind? WordKindOf(string w)
    {
        if ((w.Length > 0 && char.IsDigit(w[0])) || NumberWords.Contains(w) || w is "am" or "pm") return WordKind.Number;
        if (Weekdays.Contains(w)) return WordKind.Weekday;
        if (Months.Contains(w)) return WordKind.Month;
        if (RelativeDays.Contains(w)) return WordKind.RelativeDay;
        return null;
    }

    // ── Rendering

    private static string Render(List<Token> tokens)
    {
        var words = tokens.Select(x => x.Raw).ToList();
        // Re-capitalize after sentence ends and at the start.
        for (var i = 0; i < words.Count; i++)
            if (i == 0 || tokens[i - 1].EndsSentence) words[i] = Capitalized(words[i]);
        return string.Join(' ', words);
    }
}
