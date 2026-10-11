using Evoo.Core;
using Xunit;
using Xunit.Abstractions;

namespace Evoo.Core.Tests;

/// <summary>The Windows rules must give the same answers as the Mac app's, on the Mac app's own test cases.</summary>
public class RulesContractTests(ITestOutputHelper output)
{
    [Fact]
    public void MatchesTheMacApp()
    {
        // Exported from the Mac app's tests by scripts/export-rule-cases.py.
        var cases = File.ReadAllLines(Path.Combine(AppContext.BaseDirectory, "rules.tsv"))
            .Where(l => l.Length > 0 && !l.StartsWith('#')).Select(l => l.Split('\t')).Where(f => f.Length == 2).ToList();
        Assert.True(cases.Count >= 50, $"rules.tsv is missing or short: {cases.Count} cases");
        var failures = new List<string>();
        foreach (var f in cases)
        {
            var got = DictationRules.Apply(f[0]).Text;
            if (got != f[1]) failures.Add($"said:     {f[0]}\n  expected: {f[1]}\n  got:      {got}");
        }
        output.WriteLine($"rules contract: {cases.Count - failures.Count}/{cases.Count} match the Mac app");
        Assert.True(failures.Count == 0, $"{failures.Count} of {cases.Count} cases differ from the Mac app:\n" + string.Join("\n", failures));
    }

    [Fact]
    public void PipelineBasics()
    {
        Assert.Equal("", EvooPipeline.Process("[BLANK_AUDIO]"));
        Assert.Equal("I think we should ship it on Friday.", EvooPipeline.Process("Um, so, uh, I think we should, we should ship it on Friday."));
        Assert.Equal("I will call you, and I'm on my way.", EvooPipeline.Process("i will call you, and i'm on my way."));
        Assert.Equal("Multi command not working.", EvooPipeline.Process("Multi-tab I'm sorry, multi command not working."));
        Assert.Equal("I'm sorry I'm late for the call.", EvooPipeline.Process("I'm sorry I'm late for the call."));
    }

    [Fact]
    public void SilenceIsNotSpeech()
    {
        Assert.True(AudioStats.HasNoSpeech(new float[16000]));
        var tone = Enumerable.Range(0, 16000).Select(i => 0.2f * MathF.Sin(i * 0.05f)).ToArray();
        Assert.False(AudioStats.HasNoSpeech(tone));
        Assert.NotNull(AudioStats.SpeechRange(tone));
        Assert.Null(AudioStats.SpeechRange(new float[16000]));
    }
}
