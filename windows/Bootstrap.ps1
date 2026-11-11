<#
.SYNOPSIS
Sets up the dotfiles on a fresh Windows install.

.DESCRIPTION
Runs on Windows PowerShell 5.1, which is all a fresh machine has, so this file
must stay 5.1-compatible and ASCII-only (5.1 reads BOM-less files as
Windows-1252). It:

  1. Downloads the repository as a zip into ~/.dotconfigs (no git needed),
     unless that folder already holds it.
  2. Makes sure PowerShell 7 is installed: with winget when it works, otherwise
     from the PowerShell MSI on GitHub, verified against the release's SHA256.
  3. Runs windows/Install-WindowsEnvironment.ps1 in PowerShell 7, as the
     current user. That script asks for elevation itself, once.
  4. Turns ~/.dotconfigs into a git clone once git is installed, so
     'git pull' works from then on.

Paste into PowerShell (no Administrator, no execution policy change needed):

    irm https://raw.githubusercontent.com/dyskette/.dotconfigs/master/windows/Bootstrap.ps1 | iex

'irm | iex' runs this text in your shell's own scope, so everything happens
inside functions: preferences set here do not leak into your session, and
errors throw instead of calling 'exit', which would close the window.

.NOTES
Requirements: Windows 10 2004 (build 19041) or later, an internet connection.
#>

<#
.SYNOPSIS
Rebuilds $env:Path from the Machine and User values.
#>
function Sync-BootstrapPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

<#
.SYNOPSIS
Path of pwsh.exe, or $null when PowerShell 7 is not installed.
#>
function Find-Pwsh {
    $command = Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }

    $default = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    if (Test-Path -LiteralPath $default) { return $default }
    return $null
}

<#
.SYNOPSIS
Architecture name used in PowerShell release asset names: x64, arm64 or x86.
#>
function Get-OSArchitecture {
    # A 32-bit process on 64-bit Windows sees x86 here, with the real value in
    # PROCESSOR_ARCHITEW6432.
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch ($arch) {
        'AMD64' { return 'x64' }
        'ARM64' { return 'arm64' }
        'x86' { return 'x86' }
        default { throw "Unsupported processor architecture: $arch" }
    }
}

<#
.SYNOPSIS
Picks the MSI and the checksum list from a PowerShell GitHub release.

.PARAMETER Release
Release object from the GitHub API.

.PARAMETER Architecture
x64, arm64 or x86.
#>
function Select-PwshMsiAsset {
    param(
        [Parameter(Mandatory = $true)]$Release,
        [Parameter(Mandatory = $true)][string]$Architecture
    )

    $pattern = '^PowerShell-[\d.]+-win-' + [regex]::Escape($Architecture) + '\.msi$'
    $msi = @($Release.assets | Where-Object { $_.name -match $pattern })
    if ($msi.Count -ne 1) {
        throw "Expected one $Architecture MSI in PowerShell $($Release.tag_name), found $($msi.Count)."
    }
    $hashes = @($Release.assets | Where-Object { $_.name -eq 'hashes.sha256' })
    if ($hashes.Count -ne 1) {
        throw "PowerShell $($Release.tag_name) publishes no hashes.sha256; refusing to install an unverified MSI."
    }
    return New-Object PSObject -Property @{ Msi = $msi[0]; Hashes = $hashes[0] }
}

<#
.SYNOPSIS
SHA256 for one file name in a checksum list (GNU or BSD format), or $null.

.DESCRIPTION
5.1 copy of Get-ChecksumEntry in lib/Common.psm1, which needs PowerShell 7.
The name must match a whole entry, so 'a.msi' never matches 'a.msi.sig'.
#>
function Get-HashFromList {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Content,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    foreach ($line in $Content) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^(?<hash>[0-9a-fA-F]{64})\s+\*?(?:\./)?(?<name>.+)$' -or
            $trimmed -match '^SHA256\s*\((?:\./)?(?<name>.+)\)\s*=\s*(?<hash>[0-9a-fA-F]{64})$') {
            if ($Matches['name'].Trim() -eq $FileName) { return $Matches['hash'].ToLowerInvariant() }
        }
    }
    return $null
}

<#
.SYNOPSIS
Installs PowerShell 7 and returns the path of pwsh.exe.

.DESCRIPTION
winget first, since it also keeps PowerShell updated later. If winget is
missing or fails (common on a fresh account before App Installer registers),
the MSI from the latest GitHub release is downloaded, checked against the
release's hashes.sha256 and installed elevated.
#>
function Install-Pwsh {
    param([Parameter(Mandatory = $true)][string]$WorkDirectory)

    if (Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue) {
        Write-Host 'Installing PowerShell 7 with winget...' -ForegroundColor Yellow
        # Start-Process keeps winget's output on the console and out of this
        # function's return value.
        $wingetExit = (Start-Process -FilePath 'winget.exe' -NoNewWindow -Wait -PassThru -ArgumentList (
                'install --exact --id Microsoft.PowerShell --source winget --silent ' +
                '--accept-package-agreements --accept-source-agreements')).ExitCode
        Sync-BootstrapPath
        $pwsh = Find-Pwsh
        if ($pwsh) { return $pwsh }
        Write-Warning "winget exited with $wingetExit and pwsh.exe is still missing. Falling back to the MSI."
    } else {
        Write-Host 'winget is not available yet. Installing PowerShell 7 from its MSI.' -ForegroundColor Yellow
    }

    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -UseBasicParsing
    $assets = Select-PwshMsiAsset -Release $release -Architecture (Get-OSArchitecture)

    $msiPath = Join-Path $WorkDirectory $assets.Msi.name
    $hashesPath = Join-Path $WorkDirectory 'hashes.sha256'
    Write-Host "Downloading $($assets.Msi.name)..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $assets.Msi.browser_download_url -OutFile $msiPath -UseBasicParsing
    Invoke-WebRequest -Uri $assets.Hashes.browser_download_url -OutFile $hashesPath -UseBasicParsing

    $expected = Get-HashFromList -Content @(Get-Content -LiteralPath $hashesPath) -FileName $assets.Msi.name
    if (-not $expected) { throw "hashes.sha256 has no entry for $($assets.Msi.name)." }
    $actual = (Get-FileHash -LiteralPath $msiPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "Checksum mismatch for $($assets.Msi.name): expected $expected, got $actual."
    }
    Write-Host 'Checksum verified. Installing (accept the UAC prompt)...' -ForegroundColor Yellow

    $arguments = '/i "{0}" /passive /norestart ADD_PATH=1' -f $msiPath
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    # 3010: installed, reboot pending. pwsh works before the reboot.
    if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
        throw "The PowerShell MSI exited with $($process.ExitCode)."
    }

    Sync-BootstrapPath
    $pwsh = Find-Pwsh
    if (-not $pwsh) { throw 'PowerShell 7 was installed but pwsh.exe cannot be found.' }
    return $pwsh
}

<#
.SYNOPSIS
Puts the repository at Destination, downloading the zip when it is not there.

.DESCRIPTION
An existing git clone or an earlier extracted copy is used as-is (a clone is
not pulled: it may hold local changes). Any other existing folder is refused
rather than overwritten.

.OUTPUTS
Path of the orchestrator script.
#>
function Get-DotfilesRepository {
    param(
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$ZipUrl,
        [Parameter(Mandatory = $true)][string]$WorkDirectory
    )

    $orchestrator = Join-Path $Destination 'windows\Install-WindowsEnvironment.ps1'
    if (Test-Path -LiteralPath $Destination) {
        if (Test-Path -LiteralPath $orchestrator) {
            $kind = if (Test-Path -LiteralPath (Join-Path $Destination '.git')) { 'git clone (not updated)' } else { 'copy' }
            Write-Host "Using the existing $kind at $Destination." -ForegroundColor Yellow
            return $orchestrator
        }
        throw "$Destination exists but does not contain the dotfiles. Move it aside and run this again."
    }

    $zipPath = Join-Path $WorkDirectory 'dotconfigs.zip'
    Write-Host "Downloading the dotfiles from $ZipUrl..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $ZipUrl -OutFile $zipPath -UseBasicParsing

    # Extracted next to the destination, so the final step is a same-volume
    # rename (Move-Item cannot move a directory across volumes).
    $staging = '{0}.download-{1}' -f $Destination, ([guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        Expand-Archive -LiteralPath $zipPath -DestinationPath $staging -Force
        # GitHub zips everything under one <repo>-<branch> folder.
        $root = @(Get-ChildItem -LiteralPath $staging -Directory)
        if ($root.Count -ne 1 -or -not (Test-Path -LiteralPath (Join-Path $root[0].FullName 'windows\Install-WindowsEnvironment.ps1'))) {
            throw "The downloaded archive does not look like the dotfiles repository."
        }
        Move-Item -LiteralPath $root[0].FullName -Destination $Destination
    } finally {
        if (Test-Path -LiteralPath $staging) {
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue # safe: staging folder created above
        }
    }
    Write-Host "Dotfiles extracted to $Destination." -ForegroundColor Green
    return $orchestrator
}

<#
.SYNOPSIS
Turns an extracted copy into a git clone tracking origin/<Branch>.

.DESCRIPTION
Clones without checkout into a sibling folder and moves only its .git in, then
resets the index to match. Nothing in Destination changes until the clone has
fully succeeded, so a network failure leaves no half-made repository behind.
#>
function ConvertTo-GitClone {
    param(
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$RepositoryUrl,
        [Parameter(Mandatory = $true)][string]$Branch
    )

    if (Test-Path -LiteralPath (Join-Path $Destination '.git')) { return }

    $clone = '{0}.clone-{1}' -f $Destination, ([guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        & git clone --quiet --no-checkout --branch $Branch $RepositoryUrl $clone
        if ($LASTEXITCODE -ne 0) { throw "git clone exited with $LASTEXITCODE." }
        Move-Item -LiteralPath (Join-Path $clone '.git') -Destination (Join-Path $Destination '.git')
    } finally {
        if (Test-Path -LiteralPath $clone) {
            Remove-Item -LiteralPath $clone -Recurse -Force -ErrorAction SilentlyContinue # safe: temporary clone created above
        }
    }

    & git -C $Destination reset --quiet --mixed
    if ($LASTEXITCODE -ne 0) { throw "git reset exited with $LASTEXITCODE." }

    $changed = @(& git -C $Destination status --porcelain)
    if ($changed.Count -gt 0) {
        Write-Warning "$($changed.Count) file(s) differ from origin/$Branch; see 'git -C $Destination status'."
    }
}

<#
.SYNOPSIS
Runs the bootstrap and returns the orchestrator's exit code.

.PARAMETER Destination
Where the repository lives.
#>
function Invoke-Bootstrap {
    param(
        [string]$Destination = (Join-Path $env:USERPROFILE '.dotconfigs'),
        [string]$RepositoryUrl = 'https://github.com/dyskette/.dotconfigs.git',
        [string]$Branch = 'master'
    )

    $ErrorActionPreference = 'Stop'
    # Windows PowerShell 5.1 renders Invoke-WebRequest progress so slowly that
    # it dominates download time.
    $ProgressPreference = 'SilentlyContinue'
    # 5.1 may default to TLS 1.0, which GitHub rejects. Added, not replaced.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    Write-Host '=== Dotfiles bootstrap ===' -ForegroundColor Cyan
    $build = [Environment]::OSVersion.Version.Build
    if ($build -lt 19041) {
        throw "Windows 10 version 2004 (build 19041) or later is required; this is build $build."
    }

    $workDirectory = Join-Path ([IO.Path]::GetTempPath()) ('dotconfigs-bootstrap-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null
    try {
        $zipUrl = ($RepositoryUrl -replace '\.git$', '') + "/archive/refs/heads/$Branch.zip"
        $orchestrator = Get-DotfilesRepository -Destination $Destination -ZipUrl $zipUrl -WorkDirectory $workDirectory

        $pwsh = Find-Pwsh
        if (-not $pwsh) { $pwsh = Install-Pwsh -WorkDirectory $workDirectory }
        Write-Host "Using $pwsh" -ForegroundColor Gray
    } finally {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue # safe: private temp folder created above
    }

    Write-Host 'Handing over to Install-WindowsEnvironment.ps1 in PowerShell 7...' -ForegroundColor Cyan
    # Same console, and nothing leaks into this function's return value.
    $exitCode = (Start-Process -FilePath $pwsh -NoNewWindow -Wait -PassThru `
            -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $orchestrator)).ExitCode

    # Independent of the orchestrator's outcome: git may have been installed
    # even if another step failed.
    Sync-BootstrapPath
    if (Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue) {
        try {
            ConvertTo-GitClone -Destination $Destination -RepositoryUrl $RepositoryUrl -Branch $Branch
        } catch {
            Write-Warning "Could not turn $Destination into a git clone: $($_.Exception.Message)"
            Write-Warning 'Everything else is set up. Run this bootstrap again later to retry.'
        }
    } else {
        Write-Warning "git is not installed yet, so $Destination is not a git clone. Run this bootstrap again once it is."
    }

    $rerun = "pwsh -File `"$orchestrator`""
    switch ($exitCode) {
        0 { Write-Host '=== Bootstrap complete. Open a new terminal. ===' -ForegroundColor Green }
        3010 { Write-Host "=== Restart Windows, then run: $rerun ===" -ForegroundColor Yellow }
        default { Write-Host "=== Setup finished with errors (exit $exitCode). Fix them, then run: $rerun ===" -ForegroundColor Red }
    }
    return $exitCode
}

# Tests dot-source this file with $DotconfigsBootstrapNoRun = $true to load the
# functions without running anything.
if (-not (Get-Variable -Name DotconfigsBootstrapNoRun -ValueOnly -ErrorAction SilentlyContinue)) {
    $bootstrapExitCode = Invoke-Bootstrap
    # Only 'powershell -File Bootstrap.ps1' may exit: under 'irm | iex'
    # $PSCommandPath is empty, and when dot-sourced InvocationName is '.';
    # exiting there would close the user's shell.
    if ($PSCommandPath -and $MyInvocation.InvocationName -ne '.') { exit $bootstrapExitCode }
    $global:LASTEXITCODE = $bootstrapExitCode
}
