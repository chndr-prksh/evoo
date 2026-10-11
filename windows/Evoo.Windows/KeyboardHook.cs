using System;
using System.Runtime.InteropServices;

namespace Evoo.Windows;

/// <summary>
/// Watches the keyboard system-wide for the hold-to-talk gesture: Ctrl + Win held together. (Windows never shows
/// apps the Fn key — the laptop's firmware keeps it.) It only listens: no key is ever swallowed.
/// </summary>
internal sealed class KeyboardHook : IDisposable
{
    public event Action? HoldStarted;
    public event Action? HoldEnded;
    /// <summary>Esc, or another key pressed during the hold (the person meant a shortcut like Ctrl+Win+D).</summary>
    public event Action? Cancelled;

    private IntPtr hook;
    private readonly Native.HookProc proc; // kept alive: Windows calls it for as long as the hook is installed
    private bool ctrl, win, holding;

    public KeyboardHook() { proc = Callback; }

    public bool IsInstalled => hook != IntPtr.Zero;

    /// <summary>Must be called on a thread with a message loop (the UI thread).</summary>
    public bool Install()
    {
        if (hook != IntPtr.Zero) return true;
        hook = Native.SetWindowsHookEx(Native.WH_KEYBOARD_LL, proc, Native.GetModuleHandle(null), 0);
        return hook != IntPtr.Zero;
    }

    private IntPtr Callback(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0)
        {
            var info = Marshal.PtrToStructure<Native.KBDLLHOOKSTRUCT>(lParam);
            // Keys Evoo itself sends (the paste, the Start-menu mask) are not the person's.
            if ((info.flags & Native.LLKHF_INJECTED) == 0)
            {
                var message = wParam.ToInt32();
                var down = message is Native.WM_KEYDOWN or Native.WM_SYSKEYDOWN;
                var up = message is Native.WM_KEYUP or Native.WM_SYSKEYUP;
                var vk = (int)info.vkCode;
                var isCtrl = vk is Native.VK_LCONTROL or Native.VK_RCONTROL or Native.VK_CONTROL;
                var isWin = vk is Native.VK_LWIN or Native.VK_RWIN;
                try { Handle(isCtrl, isWin, vk, down, up); } catch { /* never let an exception escape into the hook */ }
            }
        }
        return Native.CallNextHookEx(hook, code, wParam, lParam);
    }

    private void Handle(bool isCtrl, bool isWin, int vk, bool down, bool up)
    {
        if (isCtrl || isWin)
        {
            if (isCtrl) ctrl = down ? true : up ? false : ctrl;
            if (isWin) win = down ? true : up ? false : win;
            if (!holding && ctrl && win)
            {
                holding = true;
                HoldStarted?.Invoke();
            }
            else if (holding && (!ctrl || !win))
            {
                holding = false;
                HoldEnded?.Invoke();
            }
            return;
        }
        if (holding && down)
        {
            holding = false;
            Cancelled?.Invoke();
        }
    }

    public void Dispose()
    {
        if (hook != IntPtr.Zero) Native.UnhookWindowsHookEx(hook);
        hook = IntPtr.Zero;
    }
}
