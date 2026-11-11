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
        [int]$Keep = 10
    )

    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    $logPath = Join-Path $LogDirectory ('{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
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
Tells running applications that environment variables changed.
#>
function Send-EnvironmentChange {
    [CmdletBinding()]
    param()

    if (-not ('Dotconfigs.NativeMethods' -as [type])) {
        Add-Type -Namespace Dotconfigs -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }

    $broadcast = [IntPtr]0xffff
    $result = [UIntPtr]::Zero
    # WM_SETTINGCHANGE = 0x1A, SMTO_ABORTIFHUNG = 0x2
    [void][Dotconfigs.NativeMethods]::SendMessageTimeout(
        $broadcast, 0x1A, [UIntPtr]::Zero, 'Environment', 0x2, 5000, [ref]$result)
}

# ── External commands ───────────────────────────────────────────────────────

<#
.SYNOPSIS
Runs an external program and throws when it exits with an unexpected code.

.DESCRIPTION
try/catch does not see native failures and $ErrorActionPreference does not apply
to them, so every external call goes through here.

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

    $headers = @{ 'User-Agent' = 'dotconfigs-installer/1.0' } + $Headers
    $parent = Split-Path $OutFile -Parent
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -Headers $headers -UseBasicParsing
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
        '\.(tar\.gz|tgz)$'   { Invoke-Native tar -xzf $ArchivePath -C $DestinationPath -Quiet | Out-Null }
        '\.tar\.xz$'         { Invoke-Native tar -xf $ArchivePath -C $DestinationPath -Quiet | Out-Null }
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

    $backup = $null
    if (Test-Path -LiteralPath $Destination) {
        $backup = '{0}.old-{1}' -f $Destination, [guid]::NewGuid().ToString('N').Substring(0, 8)
        try {
            Move-Item -LiteralPath $Destination -Destination $backup -Force
        } catch {
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
    'Update-SessionPath', 'Get-PathEntry', 'Add-PathEntry', 'Remove-PathEntry', 'Send-EnvironmentChange',
    'Invoke-Native', 'Invoke-Download', 'Expand-ArchiveChecked', 'Get-ChecksumEntry',
    'New-WorkDirectory', 'Test-IsLink', 'Remove-LinkOnly', 'Backup-Path', 'Set-Link', 'New-BinLink',
    'Install-DirectoryAtomic',
    'Read-Jsonc'
)
