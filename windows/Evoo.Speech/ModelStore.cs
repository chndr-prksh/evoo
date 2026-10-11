using System.Security.Cryptography;

namespace Evoo.Speech;

/// <summary>
/// The speech model: NVIDIA Parakeet TDT 0.6B v3 (CC-BY-4.0), the model the Mac app uses, in the 8-bit ONNX build
/// the sherpa-onnx project publishes. Downloaded once (about 670 MB), resumable, and checked against pinned
/// SHA-256s before it is ever loaded.
/// </summary>
public static class ModelStore
{
    public sealed record ModelFile(string Name, long Size, string Sha256);

    private const string Revision = "2bda32ec70b097a55adaa07d9a7173915b43cc78";
    private const string Base = "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/" + Revision + "/";

    public static readonly ModelFile[] Files =
    [
        new("encoder.int8.onnx", 652_184_281, "acfc2b4456377e15d04f0243af540b7fe7c992f8d898d751cf134c3a55fd2247"),
        new("decoder.int8.onnx", 11_845_275, "179e50c43d1a9de79c8a24149a2f9bac6eb5981823f2a2ed88d655b24248db4e"),
        new("joiner.int8.onnx", 6_355_277, "3164c13fc2821009440d20fcb5fdc78bff28b4db2f8d0f0b329101719c0948b3"),
        new("tokens.txt", 93_939, "d58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d"),
    ];

    public static long TotalBytes => Files.Sum(f => f.Size);

    /// <summary>%LOCALAPPDATA%\Evoo\models\parakeet-v3-int8 (or EVOO_MODEL_DIR, for tests).</summary>
    public static string Folder
    {
        get
        {
            var custom = Environment.GetEnvironmentVariable("EVOO_MODEL_DIR");
            var dir = !string.IsNullOrEmpty(custom) ? custom : Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Evoo", "models", "parakeet-v3-int8");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string PathOf(string name) => Path.Combine(Folder, name);
    private static string Marker => PathOf(".verified-" + Revision);

    public static bool IsReady =>
        File.Exists(Marker) && Files.All(f => File.Exists(PathOf(f.Name)) && new FileInfo(PathOf(f.Name)).Length == f.Size);

    /// <summary>Downloads whatever is missing (continuing a partial file), verifies each file, then marks the model usable.</summary>
    public static async Task DownloadAsync(IProgress<double>? progress = null, CancellationToken cancel = default)
    {
        using var http = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
        http.DefaultRequestHeaders.UserAgent.ParseAdd("Evoo-Windows");
        long done = Files.Where(f => File.Exists(PathOf(f.Name)) && new FileInfo(PathOf(f.Name)).Length == f.Size).Sum(f => f.Size);
        foreach (var f in Files)
        {
            var final = PathOf(f.Name);
            if (File.Exists(final) && new FileInfo(final).Length == f.Size) continue;
            var part = final + ".part";
            long have = File.Exists(part) ? new FileInfo(part).Length : 0;
            if (have > f.Size) { File.Delete(part); have = 0; }
            if (have < f.Size)
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, Base + f.Name);
                if (have > 0) request.Headers.Range = new System.Net.Http.Headers.RangeHeaderValue(have, null);
                using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancel);
                response.EnsureSuccessStatusCode();
                // A server that ignores the range sends the whole file: start over.
                if (have > 0 && response.StatusCode != System.Net.HttpStatusCode.PartialContent) have = 0;
                await using var input = await response.Content.ReadAsStreamAsync(cancel);
                await using var output = new FileStream(part, have > 0 ? FileMode.Append : FileMode.Create, FileAccess.Write, FileShare.None, 1 << 16);
                var buffer = new byte[1 << 16];
                long got = have;
                int n;
                while ((n = await input.ReadAsync(buffer, cancel)) > 0)
                {
                    await output.WriteAsync(buffer.AsMemory(0, n), cancel);
                    got += n;
                    progress?.Report(Math.Min(0.99, (double)(done + got) / TotalBytes));
                }
            }
            if (!string.Equals(await Sha256Async(part, cancel), f.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                File.Delete(part);
                throw new InvalidDataException($"{f.Name} didn't verify — please download again");
            }
            File.Move(part, final, overwrite: true);
            done += f.Size;
        }
        await File.WriteAllTextAsync(Marker, "ok", cancel);
        progress?.Report(1);
    }

    private static async Task<string> Sha256Async(string path, CancellationToken cancel)
    {
        await using var stream = File.OpenRead(path);
        return Convert.ToHexString(await SHA256.HashDataAsync(stream, cancel)).ToLowerInvariant();
    }
}
