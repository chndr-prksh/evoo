using Evoo.Core;
using SherpaOnnx;

namespace Evoo.Speech;

/// <summary>
/// Parakeet TDT 0.6B v3 running on this PC through sherpa-onnx. Nothing leaves the machine: audio goes from the
/// microphone to this model in memory and is thrown away once the text is out.
/// </summary>
public sealed class SpeechEngine : IDisposable
{
    private OfflineRecognizer? recognizer;
    private readonly object gate = new();

    public bool IsLoaded => recognizer is not null;

    /// <summary>Loads the model (a few seconds; it then stays in memory).</summary>
    public void Load()
    {
        lock (gate)
        {
            if (recognizer is not null) return;
            if (!ModelStore.IsReady) throw new InvalidOperationException("The speech model isn't downloaded yet");
            var config = new OfflineRecognizerConfig();
            config.FeatConfig.SampleRate = 16000;
            config.FeatConfig.FeatureDim = 80;
            config.ModelConfig.Transducer.Encoder = ModelStore.PathOf("encoder.int8.onnx");
            config.ModelConfig.Transducer.Decoder = ModelStore.PathOf("decoder.int8.onnx");
            config.ModelConfig.Transducer.Joiner = ModelStore.PathOf("joiner.int8.onnx");
            config.ModelConfig.Tokens = ModelStore.PathOf("tokens.txt");
            config.ModelConfig.ModelType = "nemo_transducer";
            config.ModelConfig.NumThreads = Math.Clamp(Environment.ProcessorCount / 2, 2, 6);
            config.ModelConfig.Provider = "cpu";
            config.ModelConfig.Debug = 0;
            recognizer = new OfflineRecognizer(config);
        }
    }

    /// <summary>Speech → text. Long recordings are cut at quiet moments so each piece stays small.</summary>
    public string Transcribe(float[] samples)
    {
        if (AudioStats.SpeechRange(samples) is not { } range) return "";
        var clip = samples[range.Start..range.End];
        var texts = new List<string>();
        foreach (var piece in Pieces(clip))
        {
            lock (gate)
            {
                var r = recognizer ?? throw new InvalidOperationException("The speech model isn't loaded");
                using var stream = r.CreateStream();
                stream.AcceptWaveform(16000, piece);
                r.Decode(stream);
                texts.Add(stream.Result.Text.Trim());
            }
        }
        return string.Join(' ', texts.Where(t => t.Length > 0)).Trim();
    }

    /// <summary>Pieces of at most ~30 s, cut at the quietest 100 ms of each piece's last 5 s.</summary>
    private static IEnumerable<float[]> Pieces(float[] clip, int rate = 16000)
    {
        var max = 30 * rate;
        var start = 0;
        while (clip.Length - start > max)
        {
            int best = start + max;
            var bestEnergy = double.MaxValue;
            for (var i = start + max - 5 * rate; i + rate / 10 <= start + max; i += rate / 20)
            {
                double e = 0;
                for (var k = i; k < i + rate / 10; k++) e += clip[k] * clip[k];
                if (e < bestEnergy) { bestEnergy = e; best = i + rate / 20; }
            }
            yield return clip[start..best];
            start = best;
        }
        yield return clip[start..];
    }

    public void Dispose()
    {
        lock (gate) { recognizer?.Dispose(); recognizer = null; }
    }
}

/// <summary>Reads a 16-bit PCM mono WAV file as floats, and reports its sample rate.</summary>
public static class Wav
{
    public static (float[] Samples, int SampleRate) Read(string path)
    {
        var b = File.ReadAllBytes(path);
        if (b.Length < 44 || System.Text.Encoding.ASCII.GetString(b, 0, 4) != "RIFF") throw new InvalidDataException("Not a WAV file");
        int rate = 16000, channels = 1, bits = 16;
        for (var at = 12; at + 8 <= b.Length;)
        {
            var id = System.Text.Encoding.ASCII.GetString(b, at, 4);
            var size = BitConverter.ToInt32(b, at + 4);
            if (id == "fmt ")
            {
                channels = BitConverter.ToInt16(b, at + 10);
                rate = BitConverter.ToInt32(b, at + 12);
                bits = BitConverter.ToInt16(b, at + 22);
            }
            else if (id == "data")
            {
                if (bits != 16) throw new InvalidDataException("Only 16-bit WAV is supported");
                var n = Math.Min(size, b.Length - at - 8) / 2 / channels;
                var samples = new float[n];
                for (var i = 0; i < n; i++) samples[i] = BitConverter.ToInt16(b, at + 8 + i * 2 * channels) / 32768f;
                return (samples, rate);
            }
            at += 8 + size + (size & 1);
        }
        throw new InvalidDataException("No audio in the WAV file");
    }
}
