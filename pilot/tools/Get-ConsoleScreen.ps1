#Requires -Version 7
<#
.SYNOPSIS
    Prints what another console window shows, for checking a Zellij client
    in end-to-end tests.
.DESCRIPTION
    Attaches to the console of -ProcessId and reads the visible part of its
    screen buffer, one line of text per row: what a person looking at that
    window sees, floating panes and plugins included (`zellij action
    dump-screen` cannot read plugin panes).

    Run it as its own process (`pwsh -File`): it detaches from the console it
    was started in. For the same reason the rows go to a file, as UTF-8, and
    not to the console.
.PARAMETER ProcessId
    A process attached to the target console.
.PARAMETER OutFile
    Where to write the rows.
.EXAMPLE
    pwsh -File Get-ConsoleScreen.ps1 -ProcessId 1234 -OutFile screen.txt
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$ProcessId,
    [Parameter(Mandatory)][string]$OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public static class ConsoleScreen {
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool FreeConsole();
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool AttachConsole(uint pid);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetConsoleScreenBufferInfo(IntPtr handle, out INFO info);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool ReadConsoleOutputCharacterW(IntPtr handle, [Out] char[] buffer, uint length, COORD start, out uint read);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);

    [StructLayout(LayoutKind.Sequential)] struct COORD { public short X; public short Y; }
    [StructLayout(LayoutKind.Sequential)] struct RECT { public short Left; public short Top; public short Right; public short Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct INFO { public COORD Size; public COORD Cursor; public ushort Attributes; public RECT Window; public COORD MaxSize; }

    /// The visible rows of the console `pid` is attached to.
    public static string[] Read(int pid) {
        FreeConsole();
        if (!AttachConsole((uint)pid)) throw new Win32Exception(Marshal.GetLastWin32Error(), "AttachConsole failed for process " + pid);
        IntPtr output = CreateFileW("CONOUT$", 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        try {
            if (output == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error(), "Opening CONOUT$ failed");
            INFO info;
            if (!GetConsoleScreenBufferInfo(output, out info)) throw new Win32Exception(Marshal.GetLastWin32Error(), "GetConsoleScreenBufferInfo failed");
            int width = info.Window.Right - info.Window.Left + 1;
            var rows = new List<string>();
            var buffer = new char[width];
            for (short y = info.Window.Top; y <= info.Window.Bottom; y++) {
                uint read;
                ReadConsoleOutputCharacterW(output, buffer, (uint)width, new COORD { X = info.Window.Left, Y = y }, out read);
                rows.Add(new string(buffer, 0, (int)read).TrimEnd());
            }
            return rows.ToArray();
        } finally {
            if (output != new IntPtr(-1)) CloseHandle(output);
            FreeConsole();
        }
    }
}
'@

Set-Content -LiteralPath $OutFile -Value ([ConsoleScreen]::Read($ProcessId)) -Encoding utf8NoBOM
