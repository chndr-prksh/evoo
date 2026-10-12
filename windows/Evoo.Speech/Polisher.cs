using System.Diagnostics;
using System.Net;
using System.Net.Http.Json;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text.Json;
using Evoo.Core;

namespace Evoo.Speech;

/// <summary>
/// AI polish on this PC: Qwen3 0.6B (Apache-2.0), the Mac app's small polish model, run by llama.cpp (MIT) — the
/// same release the Mac app uses. llama.cpp ships with Evoo as a small local server that listens only on this
/// computer (127.0.0.1); nothing is sent anywhere. Polish runs after Evoo's rules, only on text with something to
/// fix, and its answer is checked before it replaces the rules' text.
/// </summary>
public sealed class Polisher : IDisposable
{
    public sealed record ModelFile(string Name, long Size, string Sha256);

    public static readonly ModelFile Model = new("Qwen3-0.6B-Q4_K_M.gguf", 396_705_472, "ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a");
    private const string ModelUrl = "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/50968a4468ef4233ed78cd7c3de230dd1d61a56b/Qwen3-0.6B-Q4_K_M.gguf";
    /// <summary>The longest a dictation waits for polish; past that the rules' text goes in as it is.</summary>
    public static readonly TimeSpan Limit = TimeSpan.FromSeconds(4);

    public static string ModelFolder
    {
        get
        {
            var custom = Environment.GetEnvironmentVariable("EVOO_POLISH_DIR");
            var dir = !string.IsNullOrEmpty(custom) ? custom : Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Evoo", "models", "qwen3-0.6b-q4");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string ModelPath => Path.Combine(ModelFolder, Model.Name);
    private static string Marker => Path.Combine(ModelFolder, ".verified");
    public static bool IsModelReady => File.Exists(Marker) && File.Exists(ModelPath) && new FileInfo(ModelPath).Length == Model.Size;

    /// <summary>llama-server.exe, shipped next to Evoo.exe in the "llama" folder (or EVOO_LLAMA_DIR, for tests).</summary>
    public static string ServerPath => Path.Combine(
        Environment.GetEnvironmentVariable("EVOO_LLAMA_DIR") is { Length: > 0 } d ? d : Path.Combine(AppContext.BaseDirectory, "llama"), "llama-server.exe");

    public static bool IsAvailable => File.Exists(ServerPath);

    public static async Task DownloadModelAsync(IProgress<double>? progress = null, CancellationToken cancel = default)
    {
        if (IsModelReady) return;
        using var http = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
        http.DefaultRequestHeaders.UserAgent.ParseAdd("Evoo-Windows");
        var part = ModelPath + ".part";
        long have = File.Exists(part) ? new FileInfo(part).Length : 0;
        if (have > Model.Size) { File.Delete(part); have = 0; }
        if (have < Model.Size)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, ModelUrl);
            if (have > 0) request.Headers.Range = new System.Net.Http.Headers.RangeHeaderValue(have, null);
            using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancel);
            response.EnsureSuccessStatusCode();
            if (have > 0 && response.StatusCode != HttpStatusCode.PartialContent) have = 0;
            await using var input = await response.Content.ReadAsStreamAsync(cancel);
            await using var output = new FileStream(part, have > 0 ? FileMode.Append : FileMode.Create, FileAccess.Write, FileShare.None, 1 << 16);
            var buffer = new byte[1 << 16];
            long got = have;
            int n;
            while ((n = await input.ReadAsync(buffer, cancel)) > 0)
            {
                await output.WriteAsync(buffer.AsMemory(0, n), cancel);
                got += n;
                progress?.Report(Math.Min(0.99, (double)got / Model.Size));
            }
        }
        await using (var stream = File.OpenRead(part))
        {
            var sha = Convert.ToHexString(await SHA256.HashDataAsync(stream, cancel)).ToLowerInvariant();
            if (sha != Model.Sha256)
            {
                stream.Close();
                File.Delete(part);
                throw new InvalidDataException("The polish model didn't verify — please download again");
            }
        }
        File.Move(part, ModelPath, overwrite: true);
        await File.WriteAllTextAsync(Marker, "ok", cancel);
        progress?.Report(1);
    }

    private Process? server;
    private HttpClient? http;
    private readonly SemaphoreSlim gate = new(1, 1);
    private readonly object sync = new();
    private Task? starting;

    public bool IsWarm { get; private set; }
    /// <summary>How long the last warm-up took (starting the model and reading the instructions once).</summary>
    public TimeSpan WarmUpTime { get; private set; }

    /// <summary>Starts the model in the background so the first polish is quick. Safe to call repeatedly.</summary>
    public Task WarmUpAsync()
    {
        lock (sync) return starting ??= Task.Run(StartAsync);
    }

    private async Task StartAsync()
    {
        try
        {
            if (!IsAvailable || !IsModelReady) throw new InvalidOperationException("The polish model isn't installed");
            var watch = Stopwatch.StartNew();
            var port = FreePort();
            var threads = Math.Clamp(Environment.ProcessorCount / 2, 2, 6);
            var info = new ProcessStartInfo(ServerPath)
            {
                // Only this computer can reach it (127.0.0.1); one conversation slot; no web page.
                Arguments = $"--model \"{ModelPath}\" --host 127.0.0.1 --port {port} --ctx-size 4096 --threads {threads} --parallel 1 --no-webui --log-disable",
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = Path.GetDirectoryName(ServerPath)!,
            };
            server = Process.Start(info) ?? throw new InvalidOperationException("Couldn't start the polish model");
            http = new HttpClient { BaseAddress = new Uri($"http://127.0.0.1:{port}"), Timeout = TimeSpan.FromSeconds(120) };
            for (var i = 0; i < 240; i++) // up to a minute for the model to load
            {
                if (server.HasExited) throw new InvalidOperationException("The polish model stopped while starting");
                try { if ((await http.GetAsync("/health")).IsSuccessStatusCode) break; } catch { }
                await Task.Delay(250);
            }
            // Have the model read the instructions once; llama.cpp keeps them, so later calls only pay for the new text.
            await CompleteAsync(RefinePrompt.Prefix, 1, CancellationToken.None);
            WarmUpTime = watch.Elapsed;
            IsWarm = true;
        }
        catch
        {
            Stop();
            lock (sync) starting = null; // allow another try later
            throw;
        }
    }

    private async Task<string?> CompleteAsync(string prompt, int maxTokens, CancellationToken cancel)
    {
        var body = new { prompt, n_predict = maxTokens, temperature = 0, cache_prompt = true, stop = new[] { "<|im_end|>" } };
        using var response = await http!.PostAsJsonAsync("/completion", body, cancel);
        response.EnsureSuccessStatusCode();
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancel));
        return json.RootElement.TryGetProperty("content", out var content) ? content.GetString() : null;
    }

    /// <summary>
    /// The polished text, or `text` unchanged when there's nothing to fix, the model isn't ready, it takes longer
    /// than the limit, or its answer doesn't pass the checks.
    /// </summary>
    public async Task<(string Text, bool Used, TimeSpan Took)> PolishAsync(string text, string? context = null)
    {
        if (!RefinePrompt.NeedsPolish(text)) return (text, false, TimeSpan.Zero);
        if (!IsWarm) { _ = WarmUpAsync().ContinueWith(t => _ = t.Exception, TaskContinuationOptions.OnlyOnFaulted); return (text, false, TimeSpan.Zero); }
        // Still busy with an earlier dictation that ran over the limit: don't queue behind it.
        if (!await gate.WaitAsync(0)) return (text, false, TimeSpan.Zero);
        var watch = Stopwatch.StartNew();
        try
        {
            using var cancel = new CancellationTokenSource(Limit);
            var words = text.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length;
            var answer = await CompleteAsync(RefinePrompt.Prefix + RefinePrompt.Suffix(text, context), RefinePrompt.MaxTokens(words), cancel.Token);
            var accepted = answer is null ? null : RefinePrompt.Accept(answer, text);
            return (accepted ?? text, accepted is not null, watch.Elapsed);
        }
        catch
        {
            return (text, false, watch.Elapsed);
        }
        finally
        {
            gate.Release();
        }
    }

    private static int FreePort()
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        listener.Stop();
        return port;
    }

    private void Stop()
    {
        IsWarm = false;
        try { if (server is { HasExited: false }) server.Kill(entireProcessTree: true); } catch { }
        server?.Dispose();
        server = null;
        http?.Dispose();
        http = null;
    }

    public void Dispose()
    {
        Stop();
        lock (sync) starting = null;
    }
}
