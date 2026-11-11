#Requires -Version 7
<#
.SYNOPSIS
Installs the uv, cargo and go tools listed in language-tools.jsonc.

.DESCRIPTION
Each toolchain must already be on PATH (winget installs uv, rustup and Go).
A missing toolchain fails its tools rather than being skipped, since it means
an earlier step did not do its job.

cargo builds against the MSVC target. Crates using bindgen need libclang.dll,
and clang needs the MSVC and Windows SDK headers in INCLUDE; LLVM puts neither
on PATH. Both are set for the cargo calls only and restored afterwards.

.PARAMETER ManifestPath
Defaults to language-tools.jsonc next to this script.

.OUTPUTS
Dotconfigs.StepResult: Success when every tool installed, Partial when some
failed, Failed when none installed, Skipped when the manifest lists nothing.
#>
[CmdletBinding()]
param(
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'language-tools.jsonc')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib\Common.psm1')

$toolchains = [ordered]@{
    # --upgrade: an installed tool is otherwise left at its version.
    uv    = { param($name) 'tool', 'install', '--upgrade', $name }
    cargo = { param($name) 'install', '--locked', $name }
    go    = { param($name) 'install', $name }
}

<#
.SYNOPSIS
LLVM's bin directory when it holds libclang.dll, from the installer's registry key.
#>
function Get-LlvmBinPath {
    # GetValue returns $null for a missing value; reading a missing property
    # off Get-ItemProperty throws under strict mode.
    $root = (Get-Item -Path 'HKLM:\SOFTWARE\LLVM\LLVM' -ErrorAction SilentlyContinue)?.GetValue('')
    if (-not $root) { $root = Join-Path $env:ProgramFiles 'LLVM' }
    $bin = Join-Path $root 'bin'
    if (Test-Path -LiteralPath (Join-Path $bin 'libclang.dll')) { return $bin }
    return $null
}

<#
.SYNOPSIS
MSVC and Windows SDK include directories for clang, or nothing when absent.
#>
function Get-MsvcIncludePath {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { return }

    # -requires the C++ toolset: an install without it has no link.exe either.
    $vsPath = (Invoke-Native -FilePath $vswhere -Quiet -Arguments @(
            '-latest', '-products', '*',
            '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
            '-property', 'installationPath')).Output | Where-Object { $_ } | Select-Object -First 1
    if (-not $vsPath) {
        Write-Warning 'No Visual Studio with the C++ toolset (VC.Tools.x86.x64): the Rust msvc target has no link.exe.'
        return
    }

    $msvc = Get-ChildItem (Join-Path $vsPath 'VC\Tools\MSVC') -Directory -ErrorAction SilentlyContinue |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if ($msvc) { Join-Path $msvc.FullName 'include' }

    $kitsRoot = (Get-Item 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots' -ErrorAction SilentlyContinue)?.GetValue('KitsRoot10')
    if ($kitsRoot -and (Test-Path -LiteralPath (Join-Path $kitsRoot 'Include'))) {
        $sdk = Get-ChildItem (Join-Path $kitsRoot 'Include') -Directory |
            Where-Object { $_.Name -as [version] } |
            Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
        if ($sdk) { 'ucrt', 'shared', 'um' | ForEach-Object { Join-Path $sdk.FullName $_ } }
    }
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    return New-StepResult Failed "Manifest not found: $ManifestPath"
}
$manifest = Read-Jsonc $ManifestPath

$installed = [Collections.Generic.List[string]]::new()
$failed = [Collections.Generic.List[string]]::new()

foreach ($toolchain in $toolchains.Keys) {
    if (-not $manifest.PSObject.Properties[$toolchain]) { continue }
    $tools = @($manifest.$toolchain | Where-Object { $_ })
    if ($tools.Count -eq 0) { continue }

    if (-not (Get-Command $toolchain -ErrorAction SilentlyContinue)) {
        Write-Warning "$toolchain is not on PATH; cannot install $($tools -join ', ')."
        $tools | ForEach-Object { $failed.Add("$_ ($toolchain not on PATH)") }
        continue
    }

    $saved = @{ Path = $env:Path; LIBCLANG_PATH = $env:LIBCLANG_PATH; INCLUDE = $env:INCLUDE }
    try {
        if ($toolchain -eq 'cargo') {
            $llvmBin = Get-LlvmBinPath
            if ($llvmBin) {
                $env:LIBCLANG_PATH = $llvmBin
                $env:Path = "$llvmBin;$env:Path"
            }
            if (-not $env:INCLUDE) {
                $include = @(Get-MsvcIncludePath)
                if ($include) { $env:INCLUDE = $include -join ';' }
            }
        }

        foreach ($tool in $tools) {
            Write-Action "$toolchain`: installing $tool..."
            $result = Invoke-Native -FilePath $toolchain -Arguments (& $toolchains[$toolchain] $tool) -NoThrow
            if ($result.Succeeded) {
                $installed.Add($tool)
            } else {
                $hint = if ($toolchain -eq 'cargo') { "; 'link.exe not found' means the Visual Studio C++ workload is missing" } else { '' }
                Write-Warning "$toolchain exited with $($result.ExitCode) for $tool$hint."
                $failed.Add("$tool (exit $($result.ExitCode))")
            }
        }
    } finally {
        # Process scope only; a $null value removes a variable that did not exist before.
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    }
}

$data = @{ Installed = $installed.ToArray(); Failed = $failed.ToArray() }
if ($installed.Count -eq 0 -and $failed.Count -eq 0) {
    return New-StepResult Skipped 'No tools listed.' -Data $data
}
if ($failed.Count -eq 0) {
    return New-StepResult Success "Installed or updated: $($installed -join ', ')." -Data $data
}
$status = if ($installed.Count -gt 0) { 'Partial' } else { 'Failed' }
return New-StepResult $status "Failed: $($failed -join ', ')." -Data $data
