#Requires -Version 7
<#
.SYNOPSIS
    Builds the pilot Zellij plugin and installs it where config.kdl loads it.
.DESCRIPTION
    Compiles plugins/pilot for wasm32-wasip1 (adding the target through rustup
    when it is missing) and copies the result to plugins/pilot.wasm, which
    config.kdl loads as file:~/.dotconfigs/zellij/plugins/pilot.wasm. The
    .wasm is a build output and is not committed.

    Running sessions keep the plugin they loaded. Restart a session, or run
    `zellij action start-or-reload-plugin pilot` in it, to pick up a new build.
.PARAMETER Test
    Also run the plugin's unit tests on the host target first.
.EXAMPLE
    ./zellij/plugins/Build-Pilot.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Test
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$crate = Join-Path $PSScriptRoot 'pilot'
$target = 'wasm32-wasip1'
$output = Join-Path $PSScriptRoot 'pilot.wasm'

foreach ($tool in 'cargo', 'rustup') {
    if (-not (Get-Command $tool -CommandType Application -ErrorAction Ignore)) {
        throw "$tool is not on PATH. Install Rust with rustup (winget: Rustlang.Rustup)."
    }
}

if ((rustup target list --installed) -notcontains $target) {
    if ($PSCmdlet.ShouldProcess($target, 'rustup target add')) {
        rustup target add $target
        if ($LASTEXITCODE -ne 0) { throw "rustup target add $target failed ($LASTEXITCODE)." }
    }
}

if ($Test) {
    # The tests only touch pure helpers, so they run natively; the host
    # triple overrides the wasm default in .cargo/config.toml.
    $hostTriple = ((rustc -vV) -match '^host:' -replace '^host:\s*', '')
    cargo test --manifest-path (Join-Path $crate 'Cargo.toml') --target $hostTriple
    if ($LASTEXITCODE -ne 0) { throw "cargo test failed ($LASTEXITCODE)." }
}

if (-not $PSCmdlet.ShouldProcess($output, 'Build pilot')) { return }

cargo build --release --manifest-path (Join-Path $crate 'Cargo.toml') --target $target
if ($LASTEXITCODE -ne 0) { throw "cargo build failed ($LASTEXITCODE)." }

$built = Join-Path $crate "target\$target\release\pilot.wasm"
Copy-Item -LiteralPath $built -Destination $output -Force
Write-Host "pilot.wasm: $([math]::Round((Get-Item $output).Length / 1KB)) KB -> $output"

# Grant the permissions pilot asks for, as answering Zellij's prompt once
# would. pilot runs in the background (load_plugins), and a session started
# with `zellij attach -b` has no client to show that prompt to, so without
# this the plugin stays inert until a session is opened by hand.
#
# Zellij keys the cache by the plugin path with ~ expanded and no file:
# prefix, as it writes it when you answer the prompt yourself:
# C:\Users\me/.dotconfigs/zellij/plugins/pilot.wasm (checked on 0.46.0).
$cache = Join-Path $env:LOCALAPPDATA 'Zellij\cache\permissions.kdl'
$location = "$HOME/.dotconfigs/zellij/plugins/pilot.wasm"
# Keep this list in step with request_permission in pilot/src/main.rs:
# Zellij prompts again when the plugin asks for one that is not cached.
$permissions = 'ReadApplicationState', 'ChangeApplicationState', 'WriteToStdin', 'RunCommands',
    'OpenTerminalsOrPlugins', 'RunActionsAsUser'
$key = $location.Replace('\', '\\')
$node = "`"$key`" {`n" + (($permissions | ForEach-Object { "    $_`n" }) -join '') + "}`n"

$existing = if (Test-Path -LiteralPath $cache) { Get-Content -LiteralPath $cache -Raw } else { '' }
# pilot's entry as it stands, written by this script or by Zellij's prompt
# (one node, its permissions as children, in any order).
$current = [regex]::Match($existing, '(?ms)^"' + [regex]::Escape($key) + '"\s*\{[^}]*\}\s*')
$granted = if ($current.Success) { [regex]::Matches($current.Value, '(?m)^\s+(\w+)\s*$') | ForEach-Object { $_.Groups[1].Value } } else { @() }

if (-not ($permissions | Where-Object { $_ -notin $granted })) {
    Write-Host "Permissions already granted in $cache"
} elseif ($PSCmdlet.ShouldProcess($cache, "Grant pilot $($permissions -join ', ')")) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cache) | Out-Null
    $others = if ($current.Success) { $existing.Remove($current.Index, $current.Length) } else { $existing }
    Set-Content -LiteralPath $cache -Value ($others.TrimEnd() + "`n" + $node).TrimStart() -Encoding utf8NoBOM -NoNewline
    Write-Host "Granted pilot's permissions in $cache"
}
