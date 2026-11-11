#Requires -Version 7
<#
.SYNOPSIS
Shared helpers for the Windows setup scripts.

.DESCRIPTION
Import with:

    Import-Module (Join-Path $PSScriptRoot 'lib\Common.psm1') -Force

Every step script returns exactly one object built by New-StepResult, and every
external command goes through Invoke-Native so a non-zero exit code is never
silently ignored.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Step result contract ────────────────────────────────────────────────────

$script:StepStatuses = @('Success', 'Skipped', 'Partial', 'Failed', 'RestartRequired')

<#
.SYNOPSIS
Builds the single result object a step script must return.

.PARAMETER Status
Success         The step did its work.
Skipped         Nothing to do (already satisfied, or not applicable).
Partial         Some sub-items worked and some did not. Counts as a failure.
Failed          The step did not do its work. Counts as a failure.
RestartRequired The step worked but needs a reboot before continuing.

.PARAMETER Data
Optional extra values (counts, versions, paths) for the caller.
#>
function New-StepResult {
    # Pure constructor: builds an object, changes no system state.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an in-memory object only.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('Success', 'Skipped', 'Partial', 'Failed', 'RestartRequired')]
        [string]$Status,

        [Parameter(Position = 1)]
        [string]$Message = '',

        [hashtable]$Data = @{}
    )

    [pscustomobject]@{
        PSTypeName = 'Dotconfigs.StepResult'
        Status     = $Status
        Message    = $Message
        Data       = $Data
    }
}

<#
.SYNOPSIS
True when a step result represents a problem the final summary must report.
#>
function Test-StepFailed {
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()]$Result)

    # A step that returned nothing, or something that is not a StepResult, is a
    # bug in the step, so it is treated as a failure rather than assumed fine.
    if ($null -eq $Result) { return $true }
    if ($Result -is [array]) { $Result = $Result[-1] }
    if (-not $Result.PSObject.Properties['Status']) { return $true }
    return $Result.Status -in @('Partial', 'Failed')
}

# ── Console output ──────────────────────────────────────────────────────────

# Write-Host on purpose: these scripts are interactive installers whose success
# stream must carry only the StepResult, so progress text cannot go to output.

<#
.SYNOPSIS
Prints a section header preceded by a blank line.
#>
function Write-StepHeader {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)
    Write-Host ''
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

<#
.SYNOPSIS
Prints low-importance detail (versions, paths, decisions).
#>
function Write-Info {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)
    Write-Host $Text -ForegroundColor Gray
}

<#
.SYNOPSIS
Prints an action that is about to start.
#>
function Write-Action {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)
    Write-Host $Text -ForegroundColor Yellow
}

<#
.SYNOPSIS
Prints a completed action.
#>
function Write-Success {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)
    Write-Host $Text -ForegroundColor Green
}

# ── Logging ─────────────────────────────────────────────────────────────────

<#
.SYNOPSIS
Starts a transcript under ~/.local/state/dotconfigs/logs and prunes old logs.

.OUTPUTS
The path of the new log file.
#>
function Start-DotconfigsLog {
    # A -WhatIf run must still be logged, so this deliberately ignores ShouldProcess.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Logging must also happen during -WhatIf runs.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$LogDirectory = (Join-Path $env:USERPROFILE '.local\state\dotconfigs\logs'),
        [ValidateRange(1, 1000)]
        [int]$Keep = 10,

        # Appended to the file name, e.g. 'elevated' gives 20261111-120000-elevated.log.
        [string]$Suffix
    )

    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    $name = '{0:yyyyMMdd-HHmmss}{1}.log' -f (Get-Date), ($Suffix ? "-$Suffix" : '')
    $logPath = Join-Path $LogDirectory $name
    Start-Transcript -Path $logPath | Out-Null

    Get-ChildItem -Path $LogDirectory -Filter '*.log' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $Keep |
        Remove-Item -Force -ErrorAction SilentlyContinue

    return $logPath
}

# ── Environment checks ──────────────────────────────────────────────────────

<#
.SYNOPSIS
True when the current process runs elevated.
#>
function Test-IsAdministrator {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $principal = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

<#
.SYNOPSIS
True when this process can create symbolic links.

.DESCRIPTION
Symlinks need either elevation or Developer Mode. Developer Mode is read from
AllowDevelopmentWithoutDevLicense; elevation is checked separately.
#>
function Test-CanCreateSymlink {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if (Test-IsAdministrator) { return $true }
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
    $value = Get-ItemProperty -Path $key -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue
    return [bool]($value -and $value.AllowDevelopmentWithoutDevLicense -eq 1)
}

# ── PATH handling ───────────────────────────────────────────────────────────
# [Environment]::SetEnvironmentVariable('Path', ...) expands %VARS% and rewrites
# a REG_EXPAND_SZ value as a flat REG_SZ (https://github.com/dotnet/corefx/issues/36449).
# These helpers go through the registry and keep the value unexpanded.

function Get-PathRegistryKey {
    param([ValidateSet('User', 'Machine')][string]$Scope, [switch]$Writable)

    if ($Scope -eq 'User') {
        return [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', [bool]$Writable)
    }
    return [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
        'SYSTEM\CurrentControlSet\Control\Session Manager\Environment', [bool]$Writable)
}

function ConvertTo-ComparablePath {
    param([string]$Path)
    [Environment]::ExpandEnvironmentVariables($Path.Trim()).TrimEnd('\', '/').ToLowerInvariant()
}

<#
.SYNOPSIS
Rebuilds $env:Path for this process from the Machine and User values.
#>
function Update-SessionPath {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only changes this process environment, which -WhatIf runs also need.')]
    [CmdletBinding()]
    param()

    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

<#
.SYNOPSIS
Returns the unexpanded PATH entries of a scope.
#>
function Get-PathEntry {
    [CmdletBinding()]
    [OutputType([string])]
    param([ValidateSet('User', 'Machine')][string]$Scope = 'User')

    $key = Get-PathRegistryKey -Scope $Scope
    try {
        $raw = [string]$key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    } finally {
        $key.Dispose()
    }
    # Emitted one entry at a time; callers wrap the call in @() for an array.
    $raw -split ';' | Where-Object { $_.Trim() }
}

# Internal. ShouldProcess is decided by the exported callers, so it is not asked
# again here (that would prompt twice under -Confirm).
function Write-PathRegistryValue {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Entries,
        [Parameter(Mandatory)][ValidateSet('User', 'Machine')][string]$Scope
    )

    $key = Get-PathRegistryKey -Scope $Scope -Writable
    try {
        $kind = try { $key.GetValueKind('Path') } catch { [Microsoft.Win32.RegistryValueKind]::ExpandString }
        $key.SetValue('Path', ($Entries -join ';'), $kind)
    } finally {
        $key.Dispose()
    }
    Send-EnvironmentChange
}

<#
.SYNOPSIS
Adds a directory to a PATH scope when it is not already there.

.OUTPUTS
$true when PATH was changed, $false when the entry already existed.
#>
function Add-PathEntry {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('User', 'Machine')][string]$Scope = 'User',
        [switch]$Prepend
    )

    $entries = @(Get-PathEntry -Scope $Scope)
    $wanted = ConvertTo-ComparablePath $Path
    if ($entries | Where-Object { (ConvertTo-ComparablePath $_) -eq $wanted }) {
        return $false
    }

    $entries = @(if ($Prepend) { @($Path) + $entries } else { $entries + $Path })
    if ($PSCmdlet.ShouldProcess("$Scope PATH", "Add $Path")) {
        Write-PathRegistryValue -Entries $entries -Scope $Scope
        Update-SessionPath
        return $true
    }
    return $false
}

<#
.SYNOPSIS
Removes directories from a PATH scope.

.PARAMETER Path
Exact entries to remove (compared case-insensitively, ignoring trailing slashes
and %VAR% expansion), or a scriptblock predicate via -Where.

.OUTPUTS
$true when PATH was changed.
#>
function Remove-PathEntry {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(ParameterSetName = 'Exact', Mandatory)][string]$Path,
        [Parameter(ParameterSetName = 'Predicate', Mandatory)][scriptblock]$Where,
        [ValidateSet('User', 'Machine')][string]$Scope = 'User'
    )

    $entries = @(Get-PathEntry -Scope $Scope)
    # @() around the whole if: assigning an if statement unrolls a one-element
    # array into a scalar, which has no .Count under strict mode.
    $kept = @(if ($PSCmdlet.ParameterSetName -eq 'Exact') {
            $wanted = ConvertTo-ComparablePath $Path
            $entries | Where-Object { (ConvertTo-ComparablePath $_) -ne $wanted }
        } else {
            $entries | Where-Object { -not (& $Where $_) }
        })

    if ($kept.Count -eq $entries.Count) { return $false }
    if ($PSCmdlet.ShouldProcess("$Scope PATH", 'Remove entries')) {
        Write-PathRegistryValue -Entries $kept -Scope $Scope
        Update-SessionPath
        return $true
    }
    return $false
}

<#
.SYNOPSIS
Broadcasts a window message to every top-level window, without hanging on
windows that do not answer.

.PARAMETER Message
WM_SETTINGCHANGE (0x1A) or WM_FONTCHANGE (0x1D).

.PARAMETER Parameter
lParam string, e.g. 'Environment' for WM_SETTINGCHANGE; $null when unused.

.OUTPUTS
$true when the broadcast was delivered.
#>
function Send-BroadcastMessage {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][uint32]$Message,
        [AllowNull()][string]$Parameter
    )

    if (-not ('Dotconfigs.NativeMethods' -as [type])) {
        Add-Type -Namespace Dotconfigs -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }

    $broadcast = [IntPtr]0xffff   # HWND_BROADCAST
    $result = [UIntPtr]::Zero
    # SMTO_ABORTIFHUNG = 0x2, 5 s per window at most.
    $sent = [Dotconfigs.NativeMethods]::SendMessageTimeout(
        $broadcast, $Message, [UIntPtr]::Zero, $Parameter, 0x2, 5000, [ref]$result)
    return $sent -ne [IntPtr]::Zero
}

<#
.SYNOPSIS
Tells running applications that environment variables changed.
#>
function Send-EnvironmentChange {
    [CmdletBinding()]
    param()

    # WM_SETTINGCHANGE with 'Environment'.
    [void](Send-BroadcastMessage -Message 0x1A -Parameter 'Environment')
}

# ── External commands ───────────────────────────────────────────────────────

<#
.SYNOPSIS
Runs an external program and throws when it exits with an unexpected code.

.DESCRIPTION
try/catch does not see native failures and $ErrorActionPreference does not apply
to them, so every external call goes through here.

Pass the program's flags through -Arguments or a splatted array. Flags typed
inline can bind to this function's own parameters by prefix: in
'Invoke-Native foo -q', '-q' becomes -Quiet.

.PARAMETER AllowedExitCodes
Exit codes treated as success (e.g. 3010 for "reboot required").

.PARAMETER Quiet
Capture output without echoing it.

.PARAMETER NoThrow
Return the result even on a bad exit code; the caller inspects ExitCode.

.OUTPUTS
[pscustomobject] with ExitCode, Output (string[]) and Succeeded.
#>
function Invoke-Native {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$FilePath,
        [Parameter(Position = 1, ValueFromRemainingArguments)][string[]]$Arguments = @(),
        [int[]]$AllowedExitCodes = @(0),
        [switch]$Quiet,
        [switch]$NoThrow
    )

    $command = Get-Command $FilePath -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $command) {
        throw "Command not found: $FilePath"
    }

    $output = & $command.Source @Arguments 2>&1 | ForEach-Object {
        $line = "$_"
        if (-not $Quiet) { Write-Host $line }
        $line
    }
    $exitCode = $LASTEXITCODE

    $succeeded = $exitCode -in $AllowedExitCodes
    if (-not $succeeded -and -not $NoThrow) {
        $tail = ($output | Select-Object -Last 15) -join [Environment]::NewLine
        throw "$FilePath exited with $exitCode.$([Environment]::NewLine)$tail"
    }

    [pscustomobject]@{
        ExitCode  = $exitCode
        Output    = @($output)
        Succeeded = $succeeded
    }
}

<#
.SYNOPSIS
Quotes one argument for a Windows command line (CommandLineToArgvW rules).

.DESCRIPTION
Start-Process joins -ArgumentList with spaces and does not quote, so arguments
holding spaces or quotes must be quoted here. Backslashes are only special
before a quote, where they are doubled.
#>
function ConvertTo-CommandLineArgument {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    if ($Value -eq '') { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }

    $builder = [Text.StringBuilder]::new('"')
    $backslashes = 0
    foreach ($char in $Value.ToCharArray()) {
        if ($char -eq '\') {
            $backslashes++
            continue
        }
        if ($char -eq '"') {
            [void]$builder.Append('\', $backslashes * 2 + 1).Append('"')
        } else {
            [void]$builder.Append('\', $backslashes).Append($char)
        }
        $backslashes = 0
    }
    [void]$builder.Append('\', $backslashes * 2).Append('"')
    return $builder.ToString()
}

<#
.SYNOPSIS
Runs winget, retrying when Windows Installer is busy or the source is corrupt.

.DESCRIPTION
winget runs through Start-Process rather than Invoke-Native so it keeps the
console and renders its own progress; only the exit code comes back.

Retried by default:
  1618         ERROR_INSTALL_ALREADY_RUNNING. winget can start the next MSI
               before the previous one released the machine-wide mutex.
  -1978335217  0x8A15000F, source data missing or corrupt. 'source reset' alone
               keeps the corrupt index.db, so the cached state is wiped first.

.PARAMETER Arguments
Arguments for winget. Each is quoted as needed.

.PARAMETER RetryOnAnyExitCode
Retry every non-zero exit. For 'winget import', whose aggregate exit code hides
which package failed and why; a re-run skips what is already installed.

.OUTPUTS
System.Int32. Exit code of the last attempt.
#>
function Invoke-Winget {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [ValidateRange(1, 10)][int]$MaxAttempts = 3,
        [int]$DelaySeconds = 20,
        [switch]$RetryOnAnyExitCode
    )

    $sourceCorrupt = -1978335217
    $retryable = @(1618, $sourceCorrupt)
    $commandLine = ($Arguments | ForEach-Object { ConvertTo-CommandLineArgument $_ }) -join ' '

    $exitCode = 0
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $process = Start-Process -FilePath 'winget' -ArgumentList $commandLine -NoNewWindow -Wait -PassThru
        $exitCode = $process.ExitCode
        if ($exitCode -eq 0) { return 0 }
        if (-not $RetryOnAnyExitCode -and $exitCode -notin $retryable) { return $exitCode }
        if ($attempt -eq $MaxAttempts) { break }

        Write-Action ('winget exited with {0} (0x{0:X8}). Retrying in {1}s (attempt {2} of {3})...' -f
            $exitCode, $DelaySeconds, ($attempt + 1), $MaxAttempts)

        if ($exitCode -eq $sourceCorrupt) {
            Write-Action 'Clearing the winget source cache and resetting sources...'
            Remove-Item -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\State') -Recurse -Force -ErrorAction SilentlyContinue # safe: winget's own cache directory
            Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState') `
                -Filter '*source*' -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue # safe: winget's own source index files
            Start-Process -FilePath 'winget' -ArgumentList 'source reset --force' -NoNewWindow -Wait | Out-Null
        }
        Start-Sleep -Seconds $DelaySeconds
    }
    return $exitCode
}

# ── Downloads and archives ──────────────────────────────────────────────────

<#
.SYNOPSIS
Downloads a file with retries and an optional SHA256 check.

.OUTPUTS
The destination path.
#>
function Invoke-Download {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile,
        [hashtable]$Headers = @{},
        [string]$Sha256,
        [ValidateRange(1, 10)][int]$MaxAttempts = 3,
        [int]$DelaySeconds = 3
    )

    # Merged key by key: '+' on hashtables throws when both define a key. A
    # distinct name: PowerShell variables are case-insensitive, so $headers
    # would be the $Headers parameter itself.
    $requestHeaders = @{ 'User-Agent' = 'dotconfigs-installer/1.0' }
    foreach ($key in $Headers.Keys) { $requestHeaders[$key] = $Headers[$key] }
    $parent = Split-Path $OutFile -Parent
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -Headers $requestHeaders -UseBasicParsing
            if ($Sha256) {
                $actual = (Get-FileHash -Path $OutFile -Algorithm SHA256).Hash
                if ($actual -ne $Sha256) {
                    Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
                    # A mismatch is not transient, so it is not retried.
                    throw [System.IO.InvalidDataException]::new(
                        "Checksum mismatch for $Uri : expected $Sha256, got $actual")
                }
            }
            return $OutFile
        } catch [System.IO.InvalidDataException] {
            throw
        } catch {
            if ($attempt -eq $MaxAttempts) { throw }
            Write-Info "Download failed ($($_.Exception.Message)). Retrying in ${DelaySeconds}s ($($attempt + 1)/$MaxAttempts)..."
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

<#
.SYNOPSIS
Extracts .zip, .tar.gz, .tgz or .tar.xz and throws if nothing was extracted.
#>
function Expand-ArchiveChecked {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    $name = Split-Path $ArchivePath -Leaf

    switch -Regex ($name) {
        '\.zip$'             { Expand-Archive -Path $ArchivePath -DestinationPath $DestinationPath -Force }
        '\.(tar\.gz|tgz)$'   { Invoke-Native -FilePath tar -Arguments @('-xzf', $ArchivePath, '-C', $DestinationPath) -Quiet | Out-Null }
        '\.tar\.xz$'         { Invoke-Native -FilePath tar -Arguments @('-xf', $ArchivePath, '-C', $DestinationPath) -Quiet | Out-Null }
        default              { throw "Unsupported archive format: $name" }
    }

    if (-not (Get-ChildItem -Path $DestinationPath -Force | Select-Object -First 1)) {
        throw "Extracting $name produced no files."
    }
}

<#
.SYNOPSIS
Finds the SHA256 for one file in a checksum list.

.DESCRIPTION
Understands the GNU format ("<hash>  name", "<hash> *name", "./name") and the
BSD format ("SHA256 (name) = <hash>"). The file name must match a whole entry,
so "tool.zip" never picks up the line for "tool.zip.sig".

.PARAMETER Content
Lines of the checksum file.

.PARAMETER FileName
Asset file name to look up.

.OUTPUTS
The lowercase hash, or $null when the list has no entry for the file. Throws
when the list holds two different hashes for the same name.
#>
function Get-ChecksumEntry {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Content,
        [Parameter(Mandatory)][string]$FileName
    )

    $hashes = foreach ($line in $Content) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^(?<hash>[0-9a-fA-F]{64})\s+\*?(?:\./)?(?<name>.+)$' -or
            $trimmed -match '^SHA256\s*\((?:\./)?(?<name>.+)\)\s*=\s*(?<hash>[0-9a-fA-F]{64})$') {
            if ($Matches.name.Trim() -eq $FileName) { $Matches.hash.ToLowerInvariant() }
        }
    }

    $unique = @($hashes | Select-Object -Unique)
    if ($unique.Count -gt 1) {
        throw "Checksum list has $($unique.Count) different hashes for $FileName."
    }
    if ($unique.Count -eq 1) { return $unique[0] }
    return $null
}

# ── GitHub releases ─────────────────────────────────────────────────────────

<#
.SYNOPSIS
Request headers for the GitHub API, with GITHUB_TOKEN when set (5000 instead of
60 requests per hour).
#>
function Get-GitHubHeader {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $headers = @{
        'Accept'     = 'application/vnd.github+json'
        'User-Agent' = 'dotconfigs-installer/1.0'
    }
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }
    return $headers
}

<#
.SYNOPSIS
Fetches a GitHub release: the latest one, or a specific tag.

.DESCRIPTION
A 403 from the rate limiter is rethrown with the reset time and a pointer to
GITHUB_TOKEN instead of the bare HTTP error.
#>
function Get-GitHubRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[\w.-]+/[\w.-]+$')][string]$Repository,
        [string]$Tag
    )

    $path = if ($Tag) { "tags/$([uri]::EscapeDataString($Tag))" } else { 'latest' }
    $uri = "https://api.github.com/repos/$Repository/releases/$path"
    try {
        return Invoke-RestMethod -Uri $uri -Headers (Get-GitHubHeader)
    } catch {
        $response = $_.Exception.PSObject.Properties['Response']?.Value
        if ($response -and [int]$response.StatusCode -eq 403) {
            $reset = $response.Headers | Where-Object Key -eq 'X-RateLimit-Reset' | ForEach-Object { $_.Value } | Select-Object -First 1
            $when = if ($reset) { ' until ' + [DateTimeOffset]::FromUnixTimeSeconds([long]$reset).LocalDateTime } else { '' }
            throw "GitHub API rate limit reached$when for $Repository. Set GITHUB_TOKEN to raise the limit."
        }
        throw
    }
}

<#
.SYNOPSIS
Finds the published SHA256 of a release asset.

.DESCRIPTION
Looks for a per-asset '<name>.sha256' file first, then for a checksum list
(checksums.txt, SHA256SUMS, SHA-256.txt, hashes.sha256 and similar), and
downloads it into WorkDirectory.

.OUTPUTS
The lowercase hash, or $null when the release publishes none for the asset.
#>
function Get-ReleaseAssetHash {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]$Release,
        [Parameter(Mandatory)][string]$AssetName,
        [Parameter(Mandatory)][string]$WorkDirectory
    )

    $assets = @($Release.assets)
    $single = $assets | Where-Object { $_.name -in "$AssetName.sha256", "$AssetName.sha256sum" } | Select-Object -First 1
    $list = $assets | Where-Object { $_.name -match '(?i)^(checksums?|sha-?256-?sums?|sha-?256|hashes)(\.sha256)?(\.txt)?$' } |
        Select-Object -First 1
    $source = $single ?? $list
    if (-not $source) { return $null }

    $path = Invoke-Download -Uri $source.browser_download_url -OutFile (Join-Path $WorkDirectory "checksum-$($source.name)") `
        -Headers (Get-GitHubHeader)
    $content = @(Get-Content -LiteralPath $path)

    if ($source -eq $single) {
        # Either a bare hash or a one-line "<hash>  <name>".
        $token = ($content -join ' ').Trim() -split '\s+' | Select-Object -First 1
        if ($token -match '^[0-9a-fA-F]{64}$') { return $token.ToLowerInvariant() }
        throw "$($source.name) does not contain a SHA256 hash."
    }
    return Get-ChecksumEntry -Content $content -FileName $AssetName
}

# ── Installed version records ───────────────────────────────────────────────
# ~/.local/opt/versions.json, keyed by install name; kept from the original
# Install-GitHubReleases.ps1 format so existing records stay valid.

$script:VersionsFile = Join-Path $env:USERPROFILE '.local\opt\versions.json'

<#
.SYNOPSIS
The recorded install for a name, or $null.
#>
function Get-InstalledVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Path = $script:VersionsFile
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw
    if (-not $raw.Trim()) { return $null }
    $records = $raw | ConvertFrom-Json -AsHashtable
    if ($records.ContainsKey($Name)) { return [pscustomobject]$records[$Name] }
    return $null
}

<#
.SYNOPSIS
Records an install (version, time, asset, checksum) for a name.

.PARAMETER Checksum
'sha256:<hash>' only when the download was verified against a published hash.
An unverified download is recorded with Verified = $false.
#>
function Set-InstalledVersion {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Version,
        [string]$Asset = '',
        [string]$Checksum = '',
        [bool]$Verified = $false,
        # Additional fields kept with the record, e.g. a download fingerprint.
        [hashtable]$Extra = @{},
        [string]$Path = $script:VersionsFile
    )

    if (-not $PSCmdlet.ShouldProcess($Path, "Record $Name $Version")) { return }

    $records = [ordered]@{}
    if (Test-Path -LiteralPath $Path) {
        $raw = Get-Content -LiteralPath $Path -Raw
        if ($raw.Trim()) { $records = $raw | ConvertFrom-Json -AsHashtable -Depth 10 }
    }
    $records[$Name] = [ordered]@{
        version      = $Version
        installed_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        asset        = $Asset
        checksum     = $Checksum
        verified     = $Verified
    }
    foreach ($key in $Extra.Keys) { $records[$Name][$key] = $Extra[$key] }

    New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force | Out-Null
    # Write then rename, so an interrupted run never leaves a truncated file.
    $temp = "$Path.tmp"
    $records | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temp -Encoding utf8NoBOM
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

# ── Safe file operations ────────────────────────────────────────────────────

<#
.SYNOPSIS
Creates a unique temporary working directory.
#>
function New-WorkDirectory {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates a private temp directory, needed even during -WhatIf runs.')]
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$Prefix = 'dotconfigs')

    $path = Join-Path ([IO.Path]::GetTempPath()) ('{0}-{1}' -f $Prefix, [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

<#
.SYNOPSIS
True when the path is a symlink, junction or other reparse point.
#>
function Test-IsLink {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    return [bool]($item -and $item.LinkType)
}

<#
.SYNOPSIS
Removes a link without touching what it points to.

.DESCRIPTION
Remove-Item -Recurse on a junction can delete the target's contents on Windows
PowerShell 5.1, so links are removed through .NET, which only removes the link.
Refuses to act on anything that is not a link.
#>
function Remove-LinkOnly {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (-not $item.LinkType) {
        throw "Refusing to remove '$Path': it is not a link."
    }
    if (-not $PSCmdlet.ShouldProcess($Path, 'Remove link')) { return }

    if ($item.PSIsContainer) {
        [IO.Directory]::Delete($item.FullName, $false)
    } else {
        [IO.File]::Delete($item.FullName)
    }
}

<#
.SYNOPSIS
Moves an existing file, directory or link aside as <name>.bak-<timestamp>.

.OUTPUTS
The backup path, or $null when there was nothing to back up.
#>
function Backup-Path {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path) -and -not (Test-IsLink $Path)) { return $null }

    $backup = '{0}.bak-{1:yyyyMMdd-HHmmss}' -f $Path, (Get-Date)
    if ($PSCmdlet.ShouldProcess($Path, "Move to $backup")) {
        Move-Item -LiteralPath $Path -Destination $backup -Force
        return $backup
    }
    return $null
}

<#
.SYNOPSIS
Creates a symlink or junction at Target pointing to Source.

.DESCRIPTION
An existing correct link is left alone. A link pointing elsewhere is replaced
(removing only the link). A real file or directory is moved aside, never deleted.

.OUTPUTS
'Unchanged', 'Created', 'Replaced' or 'BackedUp'.
#>
function Set-Link {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target,
        [ValidateSet('SymbolicLink', 'Junction')][string]$Type = 'SymbolicLink'
    )

    $outcome = 'Created'
    $existing = Get-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue

    if ($existing) {
        if ($existing.LinkType -and $existing.LinkType -eq $Type -and
            (@($existing.Target) -contains $Source)) {
            return 'Unchanged'
        }
        if ($existing.LinkType) {
            Remove-LinkOnly -Path $Target
            $outcome = 'Replaced'
        } else {
            Backup-Path -Path $Target | Out-Null
            $outcome = 'BackedUp'
        }
    }

    $parent = Split-Path $Target -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if ($PSCmdlet.ShouldProcess($Target, "Link to $Source")) {
        New-Item -ItemType $Type -Path $Target -Target $Source | Out-Null
    }
    return $outcome
}

<#
.SYNOPSIS
Links an executable into a bin directory, falling back to a copy.

.OUTPUTS
'Symlink' or 'Copy', or nothing under -WhatIf.
#>
function New-BinLink {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$BinDirectory,
        [string]$LinkName = (Split-Path $Source -Leaf)
    )

    if (-not $PSCmdlet.ShouldProcess((Join-Path $BinDirectory $LinkName), "Link to $Source")) { return }

    New-Item -ItemType Directory -Path $BinDirectory -Force | Out-Null
    $linkPath = Join-Path $BinDirectory $LinkName

    if (Test-IsLink $linkPath) {
        Remove-LinkOnly -Path $linkPath
    } elseif (Test-Path -LiteralPath $linkPath) {
        Remove-Item -LiteralPath $linkPath -Force
    }

    try {
        New-Item -ItemType SymbolicLink -Path $linkPath -Target $Source | Out-Null
        return 'Symlink'
    } catch {
        # Symlinks need elevation or Developer Mode; a copy keeps the tool on PATH.
        Copy-Item -LiteralPath $Source -Destination $linkPath -Force
        return 'Copy'
    }
}

<#
.SYNOPSIS
Replaces a directory with a prepared one, restoring the old one on failure.

.DESCRIPTION
The old install is renamed aside first, so nothing is lost if the swap fails
(for example when a file in it is locked by a running process). It is deleted
only after the new one is in place.

.PARAMETER Source
Fully prepared directory (already downloaded, verified and extracted).

.PARAMETER Destination
The install directory to create or replace.
#>
function Install-DirectoryAtomic {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Source directory not found: $Source"
    }
    if (-not $PSCmdlet.ShouldProcess($Destination, 'Replace install')) { return }

    New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null

    # Move-Item cannot move a directory across volumes (%TEMP% on another
    # drive), so the source is first copied next to the destination.
    $sourceRoot = [IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $Source).Path)
    $destinationRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Destination))
    if ($sourceRoot -ne $destinationRoot) {
        $sibling = '{0}.staging-{1}' -f $Destination, [guid]::NewGuid().ToString('N').Substring(0, 8)
        Copy-Item -LiteralPath $Source -Destination $sibling -Recurse
        $Source = $sibling
    }

    $backup = $null
    if (Test-Path -LiteralPath $Destination) {
        $backup = '{0}.old-{1}' -f $Destination, [guid]::NewGuid().ToString('N').Substring(0, 8)
        try {
            Move-Item -LiteralPath $Destination -Destination $backup -Force
        } catch {
            if ($sourceRoot -ne $destinationRoot) {
                Remove-Item -LiteralPath $Source -Recurse -Force -ErrorAction SilentlyContinue # safe: the sibling copy made above
            }
            throw "Cannot replace '$Destination' (is a program from it still running?): $($_.Exception.Message)"
        }
    }

    try {
        Move-Item -LiteralPath $Source -Destination $Destination -Force
    } catch {
        if ($backup) {
            Move-Item -LiteralPath $backup -Destination $Destination -Force -ErrorAction SilentlyContinue
        }
        throw
    }

    if ($backup) {
        Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue # safe: the old install this function renamed; PS7 does not follow junctions
        if (Test-Path -LiteralPath $backup) {
            Write-Warning "Could not remove the previous install at $backup; delete it manually."
        }
    }
}

# ── Config files ────────────────────────────────────────────────────────────

<#
.SYNOPSIS
Reads a JSON file that may contain // and /* */ comments and trailing commas.

.DESCRIPTION
ConvertFrom-Json in PowerShell 7 understands comments natively, so no regex
stripping is needed (the old regex broke on '//' inside string values).
#>
function Read-Jsonc {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "File not found: $Path"
    }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 20
}

Export-ModuleMember -Function @(
    'New-StepResult', 'Test-StepFailed',
    'Write-StepHeader', 'Write-Info', 'Write-Action', 'Write-Success',
    'Start-DotconfigsLog',
    'Test-IsAdministrator', 'Test-CanCreateSymlink',
    'Update-SessionPath', 'Get-PathEntry', 'Add-PathEntry', 'Remove-PathEntry',
    'Send-BroadcastMessage', 'Send-EnvironmentChange',
    'Get-GitHubHeader', 'Get-GitHubRelease', 'Get-ReleaseAssetHash',
    'Get-InstalledVersion', 'Set-InstalledVersion',
    'Invoke-Native', 'ConvertTo-CommandLineArgument', 'Invoke-Winget', 'Invoke-Download', 'Expand-ArchiveChecked', 'Get-ChecksumEntry',
    'New-WorkDirectory', 'Test-IsLink', 'Remove-LinkOnly', 'Backup-Path', 'Set-Link', 'New-BinLink',
    'Install-DirectoryAtomic',
    'Read-Jsonc'
)
