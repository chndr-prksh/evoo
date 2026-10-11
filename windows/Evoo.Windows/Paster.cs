using System;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;

namespace Evoo.Windows;

/// <summary>Types the text at the cursor of whatever app is in front: clipboard + Ctrl+V, then the clipboard back.</summary>
internal static class Paster
{
    /// <summary>Call on the UI thread (the clipboard needs it).</summary>
    public static async Task PasteAsync(string text)
    {
        // The person has just let go of Ctrl + Win. If either is still down, our Ctrl+V would become Win+V
        // (clipboard history) — wait for them, briefly.
        for (var i = 0; i < 25 && (Native.IsDown(Native.VK_LWIN) || Native.IsDown(Native.VK_RWIN) ||
                                   Native.IsDown(Native.VK_CONTROL) || Native.IsDown(Native.VK_SHIFT) || Native.IsDown(Native.VK_MENU)); i++)
            await Task.Delay(20);

        string? previous = null;
        try { if (Clipboard.ContainsText()) previous = Clipboard.GetText(); } catch { }
        if (!SetClipboard(text)) return;
        Native.Send(Native.Key(Native.VK_CONTROL, false), Native.Key(Native.VK_V, false),
                    Native.Key(Native.VK_V, true), Native.Key(Native.VK_CONTROL, true));
        // Give the app time to read the clipboard before the old content comes back.
        await Task.Delay(350);
        if (previous is not null) SetClipboard(previous);
    }

    private static bool SetClipboard(string text)
    {
        for (var attempt = 0; attempt < 6; attempt++)
        {
            try { Clipboard.SetDataObject(text, true); return true; }
            catch { Thread.Sleep(30); } // another app has the clipboard open; try again
        }
        return false;
    }
}
