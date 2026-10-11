using System;
using System.Collections.Generic;
using NAudio.Wave;

namespace Evoo.Windows;

/// <summary>Captures the microphone as 16 kHz mono floats — what the speech model expects. Kept in memory only.</summary>
internal sealed class Recorder : IDisposable
{
    /// <summary>0…1 loudness, about 20 times a second, for the pill's bars.</summary>
    public event Action<float>? Level;

    private WaveInEvent? input;
    private readonly List<float> samples = new();
    private readonly object gate = new();

    public bool IsRecording => input is not null;
    public static int DeviceCount => WaveInEvent.DeviceCount;
    /// <summary>One dictation is at most this long (the recording lives in memory).</summary>
    public const int MaxSeconds = 300;

    public void Start()
    {
        if (input is not null) return;
        lock (gate) samples.Clear();
        var wave = new WaveInEvent { WaveFormat = new WaveFormat(16000, 16, 1), BufferMilliseconds = 50 };
        wave.DataAvailable += (_, e) =>
        {
            double sum = 0;
            var n = e.BytesRecorded / 2;
            lock (gate)
            {
                if (samples.Count > MaxSeconds * 16000) return;
                for (var i = 0; i < n; i++)
                {
                    var s = BitConverter.ToInt16(e.Buffer, i * 2) / 32768f;
                    samples.Add(s);
                    sum += s * s;
                }
            }
            if (n > 0)
            {
                var db = 20 * Math.Log10(Math.Max(Math.Sqrt(sum / n), 1e-6));
                Level?.Invoke((float)Math.Clamp((db + 50) / 30, 0, 1));
            }
        };
        wave.StartRecording();
        input = wave;
    }

    /// <summary>Stops and returns everything recorded.</summary>
    public float[] Stop()
    {
        var wave = input;
        input = null;
        if (wave is not null)
        {
            try { wave.StopRecording(); } catch { }
            wave.Dispose();
        }
        lock (gate)
        {
            var all = samples.ToArray();
            samples.Clear();
            return all;
        }
    }

    public void Dispose() => Stop();
}
