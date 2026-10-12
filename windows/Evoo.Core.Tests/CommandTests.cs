using Evoo.Core;
using Xunit;

namespace Evoo.Core.Tests;

public class CommandTests
{
    private static readonly HashSet<string> Apps = new(StringComparer.OrdinalIgnoreCase) { "Chrome", "Notepad", "Slack", "Outlook" };
    private static VoiceCommand? P(string s) => VoiceCommands.Parse(s, Apps.Contains);
    private static List<string>? Chain(string s) => CommandChain.Parts(s, p => P(p) is not null);

    [Fact]
    public void Keys()
    {
        Assert.Equal(new VoiceCommand.Keys(new KeyCombo("t", Ctrl: true), "New tab"), P("New tab."));
        Assert.Equal(P("new tab"), P("Open a new tab"));
        Assert.Equal(P("close tab"), P("Close the current tab."));
        Assert.Equal(P("paste"), P("paste it here"));
        Assert.Equal(P("copy"), P("Copy that"));
        Assert.Equal(new KeyCombo("t", Ctrl: true, Shift: true), ((VoiceCommand.Keys)P("Press control shift T")!).Combo);
        Assert.Equal(new KeyCombo("space"), ((VoiceCommand.Keys)P("Press space bar.")!).Combo);
        Assert.Equal(new KeyCombo("escape"), ((VoiceCommand.Keys)P("Escape")!).Combo);
    }

    [Fact]
    public void VolumeMediaWindows()
    {
        Assert.Equal(new VoiceCommand.Volume(30), P("Volume, thirty."));
        Assert.Equal(new VoiceCommand.Volume(50), P("Set the volume to fifty percent."));
        Assert.Equal(new VoiceCommand.VolumeStep(false), P("Turn the volume down."));
        Assert.Equal(new VoiceCommand.Mute(true), P("Mute."));
        Assert.Equal(new VoiceCommand.Media(MediaKey.PlayPause), P("Pause the music"));
        Assert.Equal(new VoiceCommand.Window(WindowAction.Left), P("Snap this window to the left"));
        Assert.Equal(new VoiceCommand.Window(WindowAction.Maximize), P("Maximize this window"));
    }

    [Fact]
    public void AppsAndSites()
    {
        Assert.Equal(new VoiceCommand.OpenApp("Chrome"), P("Open Chrome"));
        Assert.Equal(new VoiceCommand.OpenApp("Notepad"), P("Switch to Notepad."));
        Assert.Equal(new VoiceCommand.OpenUrl("https://github.com", "github.com"), P("Open github.com"));
        Assert.Equal(new VoiceCommand.OpenUrl("https://mail.google.com", "Gmail"), P("Go to Gmail"));
        Assert.Equal("https://www.google.com/search?q=flights%20to%20Delhi", ((VoiceCommand.OpenUrl)P("Search Google for flights to Delhi")!).Url);
        Assert.Equal("https://www.youtube.com/results?search_query=lo-fi%20music", ((VoiceCommand.OpenUrl)P("YouTube lo-fi music")!).Url);
        Assert.Null(P("Open the door")); // not an app, not a site
    }

    [Fact]
    public void OrdinarySpeechIsNotACommand()
    {
        foreach (var s in new[] { "I need to copy the report for the team.", "Buy milk and eggs.", "Let's meet tomorrow.", "The volume of sales went up.",
                                  "Can you open the window please?", "I closed the tab already." })
            Assert.Null(P(s));
    }

    [Fact]
    public void Chains()
    {
        Assert.Equal(["Close the tab", "switch to Chrome"], Chain("Close the tab and switch to Chrome."));
        Assert.Equal(["Copy", "open new tab", "paste"], Chain("Copy, then open new tab and then paste."));
        Assert.Equal(["Mute", "open Slack"], Chain("Mute, then open Slack"));
        Assert.Equal(["Copy that", "New tab", "Paste"], Chain("Copy that. New tab. Paste."));
        Assert.Equal("Close the tab → Switch to Chrome", CommandChain.Summary(["Close the tab", "switch to Chrome"]));
        Assert.Null(Chain("Buy milk and eggs."));
        Assert.Null(Chain("Open Chrome")); // one command: handled as a single command
        Assert.Null(Chain("Close the tab and tell me a joke"));
        Assert.Null(Chain("I closed the tab and switched to Chrome."));
    }

    [Fact]
    public void PolishPromptIsTheMacApps()
    {
        // Exported from the Mac app with: evoo-cli prompt-prefix
        var mac = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "polish-prefix.txt")).Replace("\r\n", "\n");
        Assert.Equal(mac, RefinePrompt.Prefix);
    }

    [Fact]
    public void PolishGuards()
    {
        Assert.Equal("Let's meet Monday.", RefinePrompt.Accept("<think>\n\n</think>\n\nLet's meet Monday.<|im_end|>", "let's meet monday"));
        // The model answered instead of cleaning, or lost a "not": keep the rules' text.
        Assert.Null(RefinePrompt.Accept("Photosynthesis is the process by which plants turn light, water and carbon dioxide into sugar and oxygen, using chlorophyll in their leaves to capture energy.", "can you explain photosynthesis"));
        Assert.Null(RefinePrompt.Accept("I'm in the office Friday.", "I'm in the office Monday not Friday"));
        Assert.True(RefinePrompt.NeedsPolish("So basically we could like ship it on Friday I guess."));
        Assert.False(RefinePrompt.NeedsPolish("The design team finished the new screens last night."));
    }
}
