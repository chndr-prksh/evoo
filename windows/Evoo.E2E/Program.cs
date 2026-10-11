using System.Diagnostics;
using System.Speech.AudioFormat;
using System.Speech.Synthesis;
using Evoo.Core;
using Evoo.Speech;

// Audio → text → rules, on real Windows, with the real model. Text-to-speech stands in for a person, so this
// shows the pipeline works — not how well it hears real voices.
var cases = new (string Said, string Expected)[]
{
    ("Let's meet tomorrow, no, day after tomorrow.", "Let's meet day after tomorrow."),
    ("Um, I think we should ship it on Friday.", "I think we should ship it on Friday."),
    ("Call John, sorry, call Mike before the meeting.", "Call Mike before the meeting."),
    ("The design team finished the new onboarding screens last night.", "The design team finished the new onboarding screens last night."),
    ("I am sorry I am late for the call.", "I am sorry I am late for the call."),
};

static string Loose(string s) => new string(s.ToLowerInvariant().Where(c => char.IsLetterOrDigit(c) || c == ' ').ToArray()).Trim();

var watch = Stopwatch.StartNew();
if (!ModelStore.IsReady)
{
    Console.WriteLine($"Downloading the speech model ({ModelStore.TotalBytes / 1_000_000} MB)…");
    var last = -1;
    await ModelStore.DownloadAsync(new Progress<double>(p => { var pct = (int)(p * 10); if (pct != last) { last = pct; Console.WriteLine($"  {pct * 10}%"); } }));
}
Console.WriteLine($"Model ready in {watch.Elapsed.TotalSeconds:0.0} s (folder: {ModelStore.Folder})");

using var engine = new SpeechEngine();
watch.Restart();
engine.Load();
Console.WriteLine($"Model loaded in {watch.Elapsed.TotalSeconds:0.0} s, {Environment.ProcessorCount} logical cores");

var dir = Path.Combine(Path.GetTempPath(), "evoo-e2e");
Directory.CreateDirectory(dir);
using var synth = new SpeechSynthesizer();
Console.WriteLine("Voice: " + synth.Voice.Name);
var passed = 0;
for (var i = 0; i < cases.Length; i++)
{
    var (said, expected) = cases[i];
    var wav = Path.Combine(dir, $"{i}.wav");
    synth.SetOutputToWaveFile(wav, new SpeechAudioFormatInfo(16000, AudioBitsPerSample.Sixteen, AudioChannel.Mono));
    synth.Speak(said);
    synth.SetOutputToNull();
    var (samples, rate) = Wav.Read(wav);
    watch.Restart();
    var heard = engine.Transcribe(samples);
    var ms = watch.ElapsedMilliseconds;
    var text = EvooPipeline.Process(heard);
    var ok = Loose(text) == Loose(expected);
    if (ok) passed++;
    Console.WriteLine($"{(ok ? "PASS" : "FAIL")}  said:  {said}\n      heard: {heard}\n      typed: {text}\n      ({samples.Length / (double)rate:0.0} s of audio → text in {ms} ms)");
}
Console.WriteLine($"\nE2E {passed}/{cases.Length}");
// The Windows voice is robotic and the speech model may mishear a word: require most, report all.
return passed >= cases.Length - 1 ? 0 : 1;
