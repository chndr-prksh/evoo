using System.Text.RegularExpressions;

namespace Evoo.Core;

/// <summary>Removes speech-model noise before the rules run — a port of the Mac app's TextCleaner.</summary>
public static class TextCleaner
{
    /// <summary>Phrases speech models are known to make up on silence or noise.</summary>
    private static readonly HashSet<string> Hallucinations = new()
    {
        "thank you", "thank you.", "thanks for watching", "thanks for watching!", "thank you for watching",
        "thank you for watching.", "please subscribe", "subscribe to my channel", "you", "bye", "bye.", ".", "…",
    };

    public static string Clean(string raw)
    {
        var text = Regex.Replace(raw, @"\[[^\]]*\]|\((?:music|inaudible|silence|applause|laughs?)\)|♪+", " ", RegexOptions.IgnoreCase);
        text = Regex.Replace(text, @"\s+", " ").Trim();
        if (Hallucinations.Contains(text.ToLowerInvariant())) return "";
        // "p.m. on the 21st": the sentence goes on — the dot is the abbreviation's, not a full stop.
        text = Regex.Replace(text, @"\b([AaPp])\.\s?([Mm])\.(?=\s+[a-z])", "$1.$2");
        // A speech model sometimes echoes the last word: "Click Send. Send", "T. T. T. T."
        text = Regex.Replace(text, @"\b([\w']+)\.(?:\s+\1\.?)+$", "$1.", RegexOptions.IgnoreCase);
        return text;
    }
}

/// <summary>Decides whether a recording holds speech at all — a port of the Mac app's AudioStats.</summary>
public static class AudioStats
{
    private static float Rms(float[] samples, int from, int to)
    {
        if (to <= from) return 0;
        double sum = 0;
        for (var i = from; i < to; i++) sum += samples[i] * samples[i];
        return (float)Math.Sqrt(sum / (to - from));
    }

    /// <summary>Seconds of the clip that sound like voice (20 ms frames above the threshold).</summary>
    public static double VoicedSeconds(float[] samples, int sampleRate = 16000, float threshold = 0.008f)
    {
        var frame = sampleRate / 50;
        var voiced = 0;
        for (var i = 0; i + frame <= samples.Length; i += frame)
            if (Rms(samples, i, i + frame) >= threshold) voiced++;
        return voiced * 0.02;
    }

    /// <summary>Nothing worth transcribing: quiet, or only a key click (the model would turn that into "Yeah.").</summary>
    public static bool HasNoSpeech(float[] samples, int sampleRate = 16000) => VoicedSeconds(samples, sampleRate) < 0.15;

    /// <summary>The part of the clip that contains speech, padded a little so soft word edges survive.</summary>
    public static (int Start, int End)? SpeechRange(float[] samples, int sampleRate = 16000, float threshold = 0.008f)
    {
        var frame = sampleRate / 50;
        if (samples.Length < frame) return null;
        int first = -1, last = 0;
        for (var i = 0; i + frame <= samples.Length; i += frame)
        {
            if (Rms(samples, i, i + frame) < threshold) continue;
            if (first < 0) first = i;
            last = i + frame;
        }
        if (first < 0) return null;
        return (Math.Max(0, first - (int)(0.15 * sampleRate)), Math.Min(samples.Length, last + (int)(0.25 * sampleRate)));
    }
}

/// <summary>What the speech model heard → what gets typed. The same order as the Mac app.</summary>
public static class EvooPipeline
{
    public static string Process(string raw)
    {
        var cleaned = TextCleaner.Clean(raw);
        if (cleaned.Length == 0) return "";
        var text = DictationRules.Apply(cleaned).Text;
        // "i will", "i'm" → "I will", "I'm" (a speech-model slip).
        return Regex.Replace(text, @"\bi\b(?=['’ ,]|$)", "I");
    }
}
