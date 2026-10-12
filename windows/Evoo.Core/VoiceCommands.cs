using System.Text.RegularExpressions;

namespace Evoo.Core;

/// <summary>A key press with its modifiers, e.g. Ctrl+Shift+T.</summary>
public sealed record KeyCombo(string Key, bool Ctrl = false, bool Shift = false, bool Alt = false, bool Win = false);

public enum MediaKey { PlayPause, Next, Previous }
public enum WindowAction { Maximize, Minimize, Left, Right }

/// <summary>What a spoken command asks for. The Windows app carries it out (see CommandRunner).</summary>
public abstract record VoiceCommand
{
    public sealed record Keys(KeyCombo Combo, string Name) : VoiceCommand;
    public sealed record Volume(int Percent) : VoiceCommand;
    public sealed record VolumeStep(bool Up) : VoiceCommand;
    public sealed record Mute(bool On) : VoiceCommand;
    public sealed record Media(MediaKey Key) : VoiceCommand;
    public sealed record Window(WindowAction Action) : VoiceCommand;
    public sealed record OpenApp(string Name) : VoiceCommand;
    public sealed record OpenUrl(string Url, string Label) : VoiceCommand;
}

/// <summary>
/// Voice commands for Windows — the same idea, and mostly the same phrases, as the Mac app's MacCommands and
/// AppCommands. Only a dictation that is entirely a command counts; anything else is typed as text.
/// </summary>
public static class VoiceCommands
{
    /// <param name="isApp">Whether a spoken name is an app on this PC ("Chrome", "Notepad"). Without it, "open X" only works for websites.</param>
    public static VoiceCommand? Parse(string dictation, Func<string, bool>? isApp = null)
    {
        var s = dictation.Trim().Trim('.', '!', '?', ',').Trim();
        if (s.Length == 0 || s.Length > 200) return null;
        var n = CommandForm(s);
        n = Regex.Replace(n, "^(?:please |hey evoo )", "");

        // Named keys, in the many ways people say them: "close the tab", "open a new tab", "paste it here".
        var bare = Regex.Replace(n, @"\b(?:the|this|that|my|current|a|an) ", "");
        var core = Regex.Replace(Regex.Replace(bare, @"^(?:open|create|make|start|do|just|now|and|then) (?:up )?", ""),
            @"(?: (?:it|that|this|here|now|again|please|for me))+$", "");
        foreach (var form in new[] { n, bare, core })
            if (NamedKeys.TryGetValue(form, out var named)) return new VoiceCommand.Keys(named.Combo, named.Name);

        // "press control shift T", "hit escape"
        var m = Regex.Match(n, @"^(?:press|hit|tap|push) (?:the |on )?(.+?)(?: key| button)?$");
        if (m.Success && Combo(m.Groups[1].Value) is { } combo) return new VoiceCommand.Keys(combo, m.Groups[1].Value);
        if (LoneKeys.TryGetValue(n, out var lone)) return new VoiceCommand.Keys(new KeyCombo(lone), n);

        // Volume and media
        m = Regex.Match(n, @"^(?:(?:set|turn|change|put|make|bring|reduce|increase|lower|raise|adjust) (?:the |my )?)?(?:volume|sound)(?: level)?(?: (?:to|at|of|up to|down to))? (\d{1,3})(?: ?%| percent)?$");
        if (m.Success) return new VoiceCommand.Volume(Math.Min(100, int.Parse(m.Groups[1].Value)));
        if (Regex.IsMatch(n, @"^(?:(?:turn (?:the )?)?volume up|louder|turn it up)$")) return new VoiceCommand.VolumeStep(true);
        if (Regex.IsMatch(n, @"^(?:(?:turn (?:the )?)?volume down|quieter|softer|turn it down)$")) return new VoiceCommand.VolumeStep(false);
        if (Regex.IsMatch(n, @"^(?:mute|mude|moot)(?: (?:the )?(?:sound|volume|pc|computer|audio))?$")) return new VoiceCommand.Mute(true);
        if (Regex.IsMatch(n, @"^unmute(?: (?:the )?(?:sound|volume|pc|computer|audio))?$")) return new VoiceCommand.Mute(false);
        if (Regex.IsMatch(n, @"^(?:(?:play|pause|resume)(?: (?:the )?(?:music|song|video|media))?|play pause)$")) return new VoiceCommand.Media(MediaKey.PlayPause);
        if (Regex.IsMatch(n, @"^(?:(?:next|skip)(?: (?:the )?)?(?:song|track)|skip (?:this|it))$")) return new VoiceCommand.Media(MediaKey.Next);
        if (Regex.IsMatch(n, @"^(?:previous (?:song|track)|(?:go )?back a (?:song|track))$")) return new VoiceCommand.Media(MediaKey.Previous);

        // Windows: "maximize this window", "snap this to the left"
        m = Regex.Match(n, @"^(?:move|snap|put) (?:this|the|this window|the window|it) (?:to )?(?:the )?(left|right)(?: (?:half|side))?$");
        if (m.Success) return new VoiceCommand.Window(m.Groups[1].Value == "left" ? WindowAction.Left : WindowAction.Right);
        if (Regex.IsMatch(n, @"^(?:maximi[sz]e|make (?:this|it) bigger)(?: (?:this|the) window| this| it)?$")) return new VoiceCommand.Window(WindowAction.Maximize);
        if (Regex.IsMatch(n, @"^minimi[sz]e(?: (?:this|the) window| this| it)?$")) return new VoiceCommand.Window(WindowAction.Minimize);

        // Searches: "search Google for flights to Delhi", "google best laptops", "youtube lo-fi music"
        m = Regex.Match(s, @"^(?:please )?(?:search|look up|find|look for)(?: on| in)? (.+?) for (.+)$", RegexOptions.IgnoreCase);
        if (m.Success && Site(m.Groups[1].Value) is { Search: not null } a) return Search(a, m.Groups[2].Value);
        m = Regex.Match(s, @"^(?:please )?(?:search|look up|find|look for)(?: for)? (.+) (?:on|in|using) (.+)$", RegexOptions.IgnoreCase);
        if (m.Success && Site(m.Groups[2].Value) is { Search: not null } b) return Search(b, m.Groups[1].Value);
        m = Regex.Match(s, @"^(?:please )?(google|youtube) (.+)$", RegexOptions.IgnoreCase);
        if (m.Success && Site(m.Groups[1].Value) is { Search: not null } c) return Search(c, m.Groups[2].Value);

        // "open github.com", "go to Gmail", "open Chrome", "switch to Notepad"
        m = Regex.Match(s, @"^(?:please )?(?:open|launch|start|switch to|go to|bring up|show me|pull up|visit) (?:the |my )?(.+?)(?: app| application| website)?$", RegexOptions.IgnoreCase);
        if (m.Success)
        {
            var target = m.Groups[1].Value.Trim();
            var domain = target.ToLowerInvariant().Replace(" dot ", ".").Replace(" ", "");
            if (Regex.IsMatch(domain, @"^[a-z0-9-]+(\.[a-z0-9-]+)*\.(com|org|net|io|ai|app|dev|co|in|edu|gov|so|me|tv)(/\S*)?$"))
                return new VoiceCommand.OpenUrl("https://" + domain, domain);
            // An installed app wins over a website of the same name ("open Outlook", "open WhatsApp").
            if (isApp?.Invoke(target) == true) return new VoiceCommand.OpenApp(target);
            if (Site(target) is { } site) return new VoiceCommand.OpenUrl(site.Url, site.Name);
        }
        return null;
    }

    private sealed record SiteInfo(string Name, string Url, string? Search);

    private static VoiceCommand Search(SiteInfo site, string query) =>
        new VoiceCommand.OpenUrl(site.Search!.Replace("{query}", Uri.EscapeDataString(query.Trim())), $"{site.Name}: {query.Trim()}");

    /// <summary>Websites that work without installing anything.</summary>
    private static readonly (string Name, string[] Aliases, string Url, string? Search)[] Sites =
    [
        ("Google", [], "https://www.google.com", "https://www.google.com/search?q={query}"),
        ("YouTube", ["you tube"], "https://www.youtube.com", "https://www.youtube.com/results?search_query={query}"),
        ("ChatGPT", ["chat gpt"], "https://chatgpt.com", "https://chatgpt.com/?q={query}"),
        ("Claude", [], "https://claude.ai", "https://claude.ai/new?q={query}"),
        ("Perplexity", [], "https://www.perplexity.ai", "https://www.perplexity.ai/search?q={query}"),
        ("Gmail", ["google mail"], "https://mail.google.com", "https://mail.google.com/mail/u/0/#search/{query}"),
        ("Google Calendar", [], "https://calendar.google.com", null),
        ("Google Drive", ["drive"], "https://drive.google.com", "https://drive.google.com/drive/search?q={query}"),
        ("Google Docs", ["docs"], "https://docs.google.com", null),
        ("Google Maps", ["maps"], "https://maps.google.com", "https://www.google.com/maps/search/{query}"),
        ("GitHub", ["git hub"], "https://github.com", "https://github.com/search?q={query}"),
        ("LinkedIn", ["linked in"], "https://www.linkedin.com", "https://www.linkedin.com/search/results/all/?keywords={query}"),
        ("Wikipedia", [], "https://www.wikipedia.org", "https://en.wikipedia.org/w/index.php?search={query}"),
        ("Amazon", [], "https://www.amazon.com", "https://www.amazon.com/s?k={query}"),
        ("Reddit", [], "https://www.reddit.com", "https://www.reddit.com/search/?q={query}"),
        ("WhatsApp", ["whats app"], "https://web.whatsapp.com", null),
        ("Netflix", [], "https://www.netflix.com", null),
    ];

    private static string Plain(string s) => new(s.ToLowerInvariant().Where(char.IsLetterOrDigit).ToArray());

    private static SiteInfo? Site(string spoken)
    {
        var p = Plain(spoken);
        foreach (var site in Sites)
            if (Plain(site.Name) == p || site.Aliases.Any(al => Plain(al) == p)) return new SiteInfo(site.Name, site.Url, site.Search);
        return null;
    }

    /// <summary>"Volume, thirty." → "volume 30", "space bar" → "spacebar": a forgiving form for matching.</summary>
    public static string CommandForm(string text)
    {
        var t = Regex.Replace(text.ToLowerInvariant(), @"[,;:!?.\-]", " ").Replace("per cent", "percent");
        t = Regex.Replace(t, @"\bspace ?bar\b", "spacebar");
        var words = new Queue<string>(t.Split(' ', StringSplitOptions.RemoveEmptyEntries));
        var o = new List<string>();
        while (words.Count > 0)
        {
            var w = words.Dequeue();
            if (w == "hundred" || ((w == "a" || w == "one") && words.Count > 0 && words.Peek() == "hundred"))
            {
                if (w != "hundred") words.Dequeue();
                o.Add("100");
            }
            else if (Tens.TryGetValue(w, out var ten))
            {
                if (words.Count > 0 && Units.TryGetValue(words.Peek(), out var u) && u < 10) { words.Dequeue(); o.Add((ten + u).ToString()); }
                else o.Add(ten.ToString());
            }
            else if (Units.TryGetValue(w, out var unit) && o.Count > 0 && o[^1] is "volume" or "to" or "at" or "sound" or "of" or "level")
                o.Add(unit.ToString());
            else o.Add(w);
        }
        return string.Join(' ', o);
    }

    private static readonly Dictionary<string, int> Units = new()
    {
        ["zero"] = 0, ["one"] = 1, ["two"] = 2, ["three"] = 3, ["four"] = 4, ["five"] = 5, ["six"] = 6, ["seven"] = 7, ["eight"] = 8,
        ["nine"] = 9, ["ten"] = 10, ["eleven"] = 11, ["twelve"] = 12, ["thirteen"] = 13, ["fourteen"] = 14, ["fifteen"] = 15,
        ["sixteen"] = 16, ["seventeen"] = 17, ["eighteen"] = 18, ["nineteen"] = 19,
    };
    private static readonly Dictionary<string, int> Tens = new()
    {
        ["twenty"] = 20, ["thirty"] = 30, ["forty"] = 40, ["fifty"] = 50, ["sixty"] = 60, ["seventy"] = 70, ["eighty"] = 80, ["ninety"] = 90,
    };

    private static (KeyCombo Combo, string Name) K(string key, string name, bool ctrl = true, bool shift = false, bool alt = false) =>
        (new KeyCombo(key, ctrl, shift, alt), name);

    /// <summary>Things people say for common shortcuts, with the Windows keys behind them.</summary>
    private static readonly Dictionary<string, (KeyCombo Combo, string Name)> NamedKeys = new()
    {
        ["new tab"] = K("t", "New tab"), ["close tab"] = K("w", "Close tab"),
        ["reopen tab"] = K("t", "Reopen tab", shift: true), ["reopen closed tab"] = K("t", "Reopen tab", shift: true),
        ["reopen last tab"] = K("t", "Reopen tab", shift: true),
        ["next tab"] = K("tab", "Next tab"), ["previous tab"] = K("tab", "Previous tab", shift: true),
        ["new window"] = K("n", "New window"), ["close window"] = K("f4", "Close window", ctrl: false, alt: true),
        ["refresh"] = K("r", "Refresh"), ["reload"] = K("r", "Refresh"), ["refresh page"] = K("r", "Refresh"), ["reload page"] = K("r", "Refresh"),
        ["select all"] = K("a", "Select all"), ["select everything"] = K("a", "Select all"),
        ["copy"] = K("c", "Copy"), ["cut"] = K("x", "Cut"), ["paste"] = K("v", "Paste"),
        ["undo"] = K("z", "Undo"), ["redo"] = K("y", "Redo"),
        ["save"] = K("s", "Save"), ["save file"] = K("s", "Save"), ["find"] = K("f", "Find"), ["find on page"] = K("f", "Find"),
        ["print"] = K("p", "Print"), ["bold"] = K("b", "Bold"), ["italic"] = K("i", "Italic"), ["underline"] = K("u", "Underline"),
        ["go back"] = K("left", "Back", ctrl: false, alt: true), ["go forward"] = K("right", "Forward", ctrl: false, alt: true),
        ["zoom in"] = K("=", "Zoom in"), ["zoom out"] = K("-", "Zoom out"),
        ["scroll down"] = K("pagedown", "Scroll down", ctrl: false), ["scroll up"] = K("pageup", "Scroll up", ctrl: false),
        ["page down"] = K("pagedown", "Page down", ctrl: false), ["page up"] = K("pageup", "Page up", ctrl: false),
        ["scroll to top"] = K("home", "Top"), ["scroll to bottom"] = K("end", "Bottom"),
        ["go to top"] = K("home", "Top"), ["go to bottom"] = K("end", "Bottom"),
        ["next field"] = K("tab", "Next field", ctrl: false), ["previous field"] = K("tab", "Previous field", ctrl: false, shift: true),
        ["delete last word"] = K("backspace", "Delete word"), ["delete word"] = K("backspace", "Delete word"),
        ["switch window"] = K("tab", "Switch window", ctrl: false, alt: true), ["switch app"] = K("tab", "Switch window", ctrl: false, alt: true),
        ["show desktop"] = (new KeyCombo("d", Win: true), "Show desktop"),
        ["lock screen"] = (new KeyCombo("l", Win: true), "Lock"), ["lock pc"] = (new KeyCombo("l", Win: true), "Lock"),
        ["take screenshot"] = (new KeyCombo("s", Shift: true, Win: true), "Screenshot"), ["screenshot"] = (new KeyCombo("s", Shift: true, Win: true), "Screenshot"),
        ["open file explorer"] = (new KeyCombo("e", Win: true), "File Explorer"),
    };

    /// <summary>Keys that can be said on their own.</summary>
    private static readonly Dictionary<string, string> LoneKeys = new()
    {
        ["spacebar"] = "space", ["escape"] = "escape", ["backspace"] = "backspace",
    };

    private static readonly Dictionary<string, string> KeyNames = new()
    {
        ["enter"] = "enter", ["return"] = "enter", ["escape"] = "escape", ["esc"] = "escape", ["tab"] = "tab", ["space"] = "space",
        ["spacebar"] = "space", ["backspace"] = "backspace", ["delete"] = "delete", ["up"] = "up", ["down"] = "down", ["left"] = "left",
        ["right"] = "right", ["home"] = "home", ["end"] = "end", ["pageup"] = "pageup", ["pagedown"] = "pagedown",
    };

    /// <summary>"control shift t" → Ctrl+Shift+T; null when it isn't a key combination.</summary>
    public static KeyCombo? Combo(string spoken)
    {
        var words = spoken.ToLowerInvariant().Replace("page up", "pageup").Replace("page down", "pagedown").Replace("plus", " ")
            .Split(' ', StringSplitOptions.RemoveEmptyEntries);
        bool ctrl = false, shift = false, alt = false, win = false;
        string? key = null;
        foreach (var w in words)
        {
            if (w is "control" or "ctrl") ctrl = true;
            else if (w == "shift") shift = true;
            else if (w is "alt" or "option") alt = true;
            else if (w is "windows" or "win") win = true;
            else if (key is null && KeyNames.TryGetValue(w, out var named)) key = named;
            else if (key is null && Regex.IsMatch(w, "^(?:[a-z0-9]|f(?:[1-9]|1[0-2]))$")) key = w;
            else return null;
        }
        return key is null ? null : new KeyCombo(key, ctrl, shift, alt, win);
    }
}

/// <summary>
/// Several commands in one breath: "close the tab and switch to Chrome", "copy that, new tab, then paste".
/// A dictation only counts as a chain when every piece is a command by itself — so ordinary sentences with "and"
/// in them ("buy milk and eggs") are never split. Same rule as the Mac app's CommandChain.
/// </summary>
public static class CommandChain
{
    public const int MaxSteps = 6;

    public static List<string>? Parts(string dictation, Func<string, bool> isCommand)
    {
        var text = dictation.Trim();
        if (text.Length == 0 || text.Length > 300) return null;
        var pieces = Regex.Replace(text, @"\s*[,;.]?\s+(?:and then|and after that|after that|and also|and|then|next)\s+|\s*[,;.]\s+", "\u001F", RegexOptions.IgnoreCase)
            .Split('\u001F').Select(p => p.Trim().Trim('.', ',', ';', '!', '?').Trim()).Where(p => p.Length > 0).ToList();
        return pieces.Count >= 2 && pieces.Count <= MaxSteps && pieces.All(isCommand) ? pieces : null;
    }

    public static string Summary(IEnumerable<string> parts) =>
        string.Join(" → ", parts.Select(p => p.Length == 0 ? p : char.ToUpperInvariant(p[0]) + p[1..]));
}
