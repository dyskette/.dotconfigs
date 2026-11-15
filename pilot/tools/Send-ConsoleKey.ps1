#Requires -Version 7
<#
.SYNOPSIS
    Types keys into another console window's input buffer, for driving a
    Zellij client in end-to-end tests.
.DESCRIPTION
    Attaches to the console of -ProcessId (a process running in a conhost
    window, such as a test's `zellij` client) and writes key events straight
    into its input buffer with WriteConsoleInput.

    Unlike SendKeys this needs no focus and cannot reach any other window:
    the keys go to that one console whatever the user is doing meanwhile.

    Run it as its own process (`pwsh -File`): it detaches from the console it
    was started in.
.PARAMETER ProcessId
    A process attached to the target console.
.PARAMETER Key
    Keys in order, as separate arguments or comma-separated. Each is a name
    (enter, esc, backspace, up, down, tab), a chord (alt+s, ctrl+d,
    shift+g), or `text:<characters>` to type literally.
.PARAMETER DelayMilliseconds
    Pause after each key, so the program can react as it would to a person.
.EXAMPLE
    pwsh -File Send-ConsoleKey.ps1 -ProcessId 1234 -Key alt+s, text:cer, esc, j, enter
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$ProcessId,
    [Parameter(Mandatory, ValueFromRemainingArguments)][string[]]$Key,
    [int]$DelayMilliseconds = 150
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class ConsoleKeys {
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool FreeConsole();
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool AttachConsole(uint pid);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool WriteConsoleInputW(IntPtr handle, INPUT_RECORD[] buffer, uint length, out uint written);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern short VkKeyScanW(char c);
    [DllImport("user32.dll")] static extern uint MapVirtualKeyW(uint code, uint type);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct KEY_EVENT_RECORD {
        [MarshalAs(UnmanagedType.Bool)] public bool KeyDown;
        public ushort RepeatCount;
        public ushort VirtualKeyCode;
        public ushort VirtualScanCode;
        public char UnicodeChar;
        public uint ControlKeyState;
    }

    [StructLayout(LayoutKind.Explicit, CharSet = CharSet.Unicode)]
    struct INPUT_RECORD {
        [FieldOffset(0)] public ushort EventType;
        [FieldOffset(4)] public KEY_EVENT_RECORD KeyEvent;
    }

    static IntPtr input = IntPtr.Zero;

    public static void Attach(int pid) {
        FreeConsole();
        if (!AttachConsole((uint)pid)) throw new Win32Exception(Marshal.GetLastWin32Error(), "AttachConsole failed for process " + pid);
        // GENERIC_READ | GENERIC_WRITE, shared, OPEN_EXISTING
        input = CreateFileW("CONIN$", 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (input == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error(), "Opening CONIN$ failed");
    }

    public static void Detach() {
        if (input != IntPtr.Zero) CloseHandle(input);
        FreeConsole();
    }

    /// One key press and release. state: 0x2 left Alt, 0x8 left Ctrl, 0x10 Shift.
    public static void Send(ushort virtualKey, char character, uint state) {
        var records = new INPUT_RECORD[2];
        for (int i = 0; i < 2; i++) {
            records[i].EventType = 1; // KEY_EVENT
            records[i].KeyEvent.KeyDown = i == 0;
            records[i].KeyEvent.RepeatCount = 1;
            records[i].KeyEvent.VirtualKeyCode = virtualKey;
            records[i].KeyEvent.VirtualScanCode = (ushort)MapVirtualKeyW(virtualKey, 0);
            records[i].KeyEvent.UnicodeChar = character;
            records[i].KeyEvent.ControlKeyState = state;
        }
        uint written;
        if (!WriteConsoleInputW(input, records, 2, out written)) throw new Win32Exception(Marshal.GetLastWin32Error(), "WriteConsoleInput failed");
    }

    /// The virtual key and shift state that type a character on this layout.
    public static short Scan(char c) { return VkKeyScanW(c); }
}
'@

$named = @{
    enter = 0x0D, [char]13; esc = 0x1B, [char]27; backspace = 0x08, [char]8; tab = 0x09, [char]9
    up = 0x26, [char]0; down = 0x28, [char]0; left = 0x25, [char]0; right = 0x27, [char]0; space = 0x20, [char]32
}
$modifiers = @{ alt = 0x2; ctrl = 0x8; shift = 0x10 }

<#
.SYNOPSIS
    Send one character as the key that types it, with extra modifier state.
#>
function Send-Character {
    param([char]$Character, [uint32]$State = 0)

    $scan = [ConsoleKeys]::Scan($Character)
    if ($scan -eq -1) { throw "No key types '$Character' on this keyboard layout." }
    $virtualKey = [uint16]($scan -band 0xFF)
    if ($scan -band 0x100) { $State = $State -bor $modifiers.shift }
    # With Ctrl held the console reports the control character (Ctrl+d is 0x04).
    $reported = if ($State -band $modifiers.ctrl) { [char]([int]$Character -band 0x1F) } else { $Character }
    [ConsoleKeys]::Send($virtualKey, $reported, $State)
}

[ConsoleKeys]::Attach($ProcessId)
try {
    foreach ($entry in $Key -split ',' | Where-Object { $_ }) {
        if ($entry.StartsWith('text:')) {
            foreach ($character in $entry.Substring(5).ToCharArray()) {
                Send-Character $character
                Start-Sleep -Milliseconds 30
            }
        } else {
            $parts = $entry.ToLowerInvariant() -split '\+'
            $state = [uint32]0
            foreach ($modifier in $parts | Select-Object -SkipLast 1) {
                if (-not $modifiers.ContainsKey($modifier)) { throw "Unknown modifier '$modifier' in '$entry'." }
                $state = $state -bor $modifiers[$modifier]
            }
            $name = $parts[-1]
            if ($named.ContainsKey($name)) {
                [ConsoleKeys]::Send([uint16]$named[$name][0], $named[$name][1], $state)
            } elseif ($name.Length -eq 1) {
                $character = if ($state -band $modifiers.shift) { [char]::ToUpperInvariant($name[0]) } else { $name[0] }
                Send-Character $character ($state -band 0xFFFFFFEF)
            } else {
                throw "Unknown key '$entry'. Use a name, a chord such as alt+s, or text:<characters>."
            }
        }
        Start-Sleep -Milliseconds $DelayMilliseconds
    }
} finally {
    [ConsoleKeys]::Detach()
}
