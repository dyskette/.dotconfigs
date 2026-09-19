#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Automated Windows development environment setup

.DESCRIPTION
    Orchestrates the full installation and configuration of a Windows development
    environment: package installation via winget, dotfile linking, font installation,
    editor extensions, and system settings.

.NOTES
    Requirements:
    - Windows 10 version 2004+ (Build 19041+) or Windows 11
    - Administrator privileges
    - Internet connection
#>

param(
    [Parameter(HelpMessage="Skip WSL installation")]
    [switch]$SkipWSL,

    [Parameter(HelpMessage="Skip package installation")]
    [switch]$SkipPackages,

    [Parameter(HelpMessage="Skip dotfile configuration")]
    [switch]$SkipConfiguration,

    [Parameter(HelpMessage="Skip editor extension installation")]
    [switch]$SkipExtensions,

    [Parameter(HelpMessage="Skip JetBrains Mono Nerd Font installation")]
    [switch]$SkipFont,

    [Parameter(HelpMessage="Skip Node.js LTS setup via fnm")]
    [switch]$SkipNodeSetup,

    [Parameter(HelpMessage="Skip Windows registry settings")]
    [switch]$SkipWindowsSettings,

    [Parameter(HelpMessage="Skip GitHub release package installation")]
    [switch]$SkipGitHubPackages
)

# ── Admin elevation ─────────────────────────────────────────────────────────

if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Administrator privileges required. Attempting to elevate..." -ForegroundColor Yellow

    $argString = ""
    if ($PSBoundParameters.Count -gt 0) {
        $argString = ($PSBoundParameters.GetEnumerator() | ForEach-Object {
            if ($_.Value -eq $true) { "-$($_.Key)" }
            elseif ($_.Value -ne $false) { "-$($_.Key) '$($_.Value)'" }
        }) -join " "
    }

    try {
        $processArgs = @{
            FilePath     = "PowerShell"
            ArgumentList = @("-ExecutionPolicy", "Bypass", "-NoExit", "-File", "`"$($MyInvocation.MyCommand.Path)`"") + ($argString -split " " | Where-Object { $_ })
            Verb         = "RunAs"
            Wait         = $true
        }
        Start-Process @processArgs
        Write-Host "Script execution completed in elevated session." -ForegroundColor Green
        exit 0
    } catch {
        Write-Error "Failed to elevate to Administrator privileges: $_"
        Write-Warning "Please right-click PowerShell and select 'Run as Administrator', then run this script again."
        exit 1
    }
}

# ── Windows version check ──────────────────────────────────────────────────

$windowsVersion = [System.Environment]::OSVersion.Version
if ($windowsVersion.Build -lt 19041) {
    Write-Error "This script requires Windows 10 version 2004 (Build 19041) or higher."
    Write-Host "Current build: $($windowsVersion.Build)" -ForegroundColor Yellow
    exit 1
}
Write-Host "Windows version check passed: Build $($windowsVersion.Build)" -ForegroundColor Green

# ── Helpers ─────────────────────────────────────────────────────────────────

# Non-fatal failures collected across the run so the final summary can report
# them instead of the script claiming success over a broken environment.
$script:Failures = [System.Collections.Generic.List[string]]::new()

<#
.SYNOPSIS
    Records a non-fatal step failure and warns immediately.

.PARAMETER Step
    Short name of the failing step, used as the summary label.

.PARAMETER Detail
    Diagnostic text: exit code, log path, or remediation hint.
#>
function Add-Failure {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][string]$Detail
    )

    $script:Failures.Add("${Step}: $Detail")
    Write-Warning "${Step}: $Detail"
}

<#
.SYNOPSIS
    Invokes winget, retrying while Windows Installer is busy.

.DESCRIPTION
    Windows Installer serializes MSI transactions machine-wide through the
    _MSIExecute mutex. When winget misreads an installer exit code it can start
    the next package before the previous MSI released that mutex, which surfaces
    as exit code 1618 (ERROR_INSTALL_ALREADY_RUNNING) and skips the package.
    Re-running is safe: packages already present are detected and skipped.

.PARAMETER Arguments
    Argument list forwarded verbatim to winget.

.PARAMETER MaxAttempts
    Total number of invocations before giving up.

.PARAMETER DelaySeconds
    Pause between attempts, to let a pending MSI transaction drain.

.OUTPUTS
    System.Int32. Exit code of the last winget invocation.
#>
function Invoke-WingetWithRetry {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 20
    )

    # Start-Process joins -ArgumentList with spaces without quoting, so any argument
    # holding a path with spaces has to be quoted before it is handed over.
    $quotedArgs = $Arguments | ForEach-Object {
        if ($_ -match '\s' -and $_ -notmatch '^".*"$') { "`"$_`"" } else { $_ }
    }

    $exitCode = 0
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        # Start-Process rather than a direct call: the child inherits the console,
        # so winget keeps its progress rendering and its output stays out of this
        # function's success stream, which must carry only the exit code.
        $process = Start-Process -FilePath "winget" -ArgumentList $quotedArgs -NoNewWindow -Wait -PassThru
        $exitCode = $process.ExitCode
        if ($exitCode -eq 0) { return 0 }

        if ($attempt -lt $MaxAttempts) {
            Write-Host "winget exited with $exitCode. Retrying in ${DelaySeconds}s (attempt $($attempt + 1) of $MaxAttempts)..." -ForegroundColor Yellow
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    return $exitCode
}

function Invoke-Step {
    param(
        [string]$ScriptName,
        [hashtable]$Parameters = @{},
        [string]$Description
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    if (-not (Test-Path $scriptPath)) {
        Add-Failure -Step $Description -Detail "Script not found: $ScriptName"
        return @{ status = "error"; message = "Script not found" }
    }

    try {
        Write-Host "$Description..." -ForegroundColor Yellow
        $result = & $scriptPath @Parameters
        if ($result -and $result.status -eq "error") {
            Add-Failure -Step $Description -Detail $result.message
        } elseif ($result -and $result.status) {
            Write-Host "$Description completed: $($result.message)" -ForegroundColor Green
        } else {
            Write-Host "$Description completed." -ForegroundColor Green
        }
        return $result
    } catch {
        Add-Failure -Step $Description -Detail $_.Exception.Message
        return @{ status = "error"; message = $_.Exception.Message }
    }
}

function Update-SessionPath {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# ── 1. WSL ──────────────────────────────────────────────────────────────────

if (-not $SkipWSL) {
    $wslResult = Invoke-Step -ScriptName "Install-WSL.ps1" -Parameters @{ ForceRestart = $true } -Description "Setting up WSL with Ubuntu 24.04"
    if ($wslResult.restart_required) {
        Write-Host "WSL installation requires a restart. Please run this script again after restart." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "Skipping WSL installation." -ForegroundColor Yellow
}

# ── 2. Package installation ────────────────────────────────────────────────

if (-not $SkipPackages) {
    Write-Host ""
    Write-Host "=== Package Installation ===" -ForegroundColor Cyan

    # Bootstrap winget
    $pmResult = Invoke-Step -ScriptName "Setup-PackageManagers.ps1" -Description "Setting up winget"
    if ($pmResult.status -ne "success") {
        Write-Error "CRITICAL: Winget setup failed. Cannot proceed."
        exit 1
    }

    Update-SessionPath

    # Install packages from manifest
    $packagesJson = Join-Path $PSScriptRoot "packages.jsonc"
    if (Test-Path $packagesJson) {
        Write-Host "Installing packages via winget import..." -ForegroundColor Yellow
        $importExit = Invoke-WingetWithRetry -Arguments @(
            "import", "-i", $packagesJson,
            "--accept-package-agreements", "--accept-source-agreements", "--ignore-unavailable"
        )
        if ($importExit -eq 0) {
            Write-Host "Winget import completed." -ForegroundColor Green
        } else {
            $diagDir = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir"
            Add-Failure -Step "winget import" -Detail "One or more packages failed (exit $importExit). Installer logs: $diagDir"
        }
    } else {
        Write-Warning "packages.jsonc not found at: $packagesJson"
    }

    # Install or amend Visual Studio 2026 Enterprise with the workloads in vsconfig.
    #
    # The bootstrapper's `install` verb refuses with exit code 1 when the product is
    # already present ("Visual Studio Enterprise 2026 ya se ha instalado") and bails
    # *before* reading --config, silently leaving the declared workloads uninstalled.
    # An existing installation must therefore be amended with the VS Installer's
    # `modify` verb, which is idempotent and adds only the missing components.
    $vsconfig = Join-Path (Split-Path $PSScriptRoot -Parent) "vs\vsconfig.jsonc"
    if (Test-Path $vsconfig) {
        $vsInstallerDir = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer"
        $vswhere = Join-Path $vsInstallerDir "vswhere.exe"

        $vsPath = $null
        if (Test-Path $vswhere) {
            # -version pins the match to 18.x: this manifest declares .NET 10, which
            # only exists in the VS 2026 catalog, so it must never be pushed at a
            # leftover 17.x installation.
            $vsPath = & $vswhere -latest -products Microsoft.VisualStudio.Product.Enterprise `
                -version "[18.0,19.0)" -property installationPath | Select-Object -First 1
        }

        # The installer parses --config as strict JSON, so the commented .jsonc is
        # normalized to a plain .vsconfig before being handed over.
        $vsComponents = @()
        try {
            $vsComponents = (Get-Content $vsconfig -Raw | ConvertFrom-Json -ErrorAction Stop).components
        } catch {
            Write-Warning "Could not parse $vsconfig : $($_.Exception.Message). Passing it to the installer as-is."
        }

        $vsConfigArg = $vsconfig
        if ($vsComponents) {
            $vsConfigArg = Join-Path ([System.IO.Path]::GetTempPath()) "dotconfigs.vsconfig"
            [ordered]@{ version = "1.0"; components = @($vsComponents) } |
                ConvertTo-Json -Depth 3 | Set-Content $vsConfigArg -Encoding utf8
        }

        # Skip the installer entirely when every declared component is already
        # present: vswhere -requires matches only installations that have all of them.
        $vsSkip = $false
        if ($vsPath -and $vsComponents) {
            $satisfied = & $vswhere -latest -products Microsoft.VisualStudio.Product.Enterprise `
                -version "[18.0,19.0)" -requires @($vsComponents) -property installationPath |
                Select-Object -First 1
            if ($satisfied) {
                Write-Host "Visual Studio already has all components from vsconfig. Skipping." -ForegroundColor Green
                $vsSkip = $true
            }
        }

        if ($vsSkip) {
            $vsExit = 0
        } elseif ($vsPath) {
            Write-Host "Applying vsconfig to existing Visual Studio 2026 Enterprise at $vsPath..." -ForegroundColor Yellow
            Write-Host "This downloads several GB and can take a while; the installer shows its own progress window." -ForegroundColor Yellow

            # setup.exe is a Windows-subsystem binary, so the call operator does not
            # block on it and would leave $LASTEXITCODE holding the previous command's
            # value. Start-Process -Wait is required to serialize against the cargo
            # step below, which needs the MSVC toolset this installs. Note that the
            # `modify` verb rejects --wait (that flag belongs to the bootstrapper).
            # Start-Process joins -ArgumentList with spaces without quoting, so paths
            # containing spaces ("C:\Program Files\...") must carry their own quotes
            # or the installer receives them as several arguments.
            $vsArgs = @(
                "modify",
                "--installPath", "`"$vsPath`"",
                "--config", "`"$vsConfigArg`"",
                "--passive", "--norestart"
            )
            $vsProcess = Start-Process -FilePath (Join-Path $vsInstallerDir "setup.exe") `
                -ArgumentList $vsArgs -Wait -PassThru
            $vsExit = $vsProcess.ExitCode
        } else {
            Write-Host "Installing Visual Studio 2026 Enterprise..." -ForegroundColor Yellow
            winget install --exact --id Microsoft.VisualStudio.Enterprise --silent --accept-package-agreements --accept-source-agreements --override "--wait --passive --norestart --config `"$vsConfigArg`""
            $vsExit = $LASTEXITCODE
        }

        if ($vsExit -eq 0) {
            Write-Host "Visual Studio installation completed." -ForegroundColor Green
        } elseif ($vsExit -eq 3010) {
            # 3010 = ERROR_SUCCESS_REBOOT_REQUIRED: components applied, reboot pending.
            Write-Host "Visual Studio installation completed; a restart is required to finish." -ForegroundColor Yellow
        } else {
            Add-Failure -Step "Visual Studio" -Detail "Setup exited with $vsExit. Installer logs: $env:TEMP\dd_installer_*.log"
        }
    } else {
        Write-Warning "vsconfig.jsonc not found at: $vsconfig"
    }

    Update-SessionPath

    # Install tools via uv/cargo/go
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        Write-Host "Installing uv-based tools..." -ForegroundColor Yellow
        uv tool install poetry
        if ($LASTEXITCODE -eq 0) {
            Write-Host "uv-based tools installed." -ForegroundColor Green
        } else {
            Add-Failure -Step "uv tool install poetry" -Detail "uv exited with $LASTEXITCODE."
        }
    } else {
        Write-Warning "uv not found in PATH. Skipping uv-based tool installation."
    }

    if (Get-Command cargo -ErrorAction SilentlyContinue) {
        Write-Host "Installing Cargo-based tools..." -ForegroundColor Yellow

        # bindgen needs libclang.dll and clang needs MSVC/Windows SDK headers.
        # LLVM doesn't add itself to PATH, and clang targeting MSVC needs the
        # INCLUDE env var so it can find stdio.h etc. from the VC toolchain.
        $llvmBin = "C:\Program Files\LLVM\bin"
        if (Test-Path $llvmBin) {
            $env:LIBCLANG_PATH = $llvmBin
            $env:Path = "$llvmBin;$env:Path"
        }

        # Set INCLUDE for clang to find MSVC and Windows SDK headers.
        # vswhere reports the VS installation path even when the C++ workload is
        # absent, so the toolset directory itself has to be probed: without it
        # there is no link.exe either and every msvc-target build will fail.
        if (-not $env:INCLUDE) {
            $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
            if (Test-Path $vswhere) {
                $vsPath = & $vswhere -latest -property installationPath | Select-Object -First 1
                $msvcRoot = if ($vsPath) { Join-Path $vsPath "VC\Tools\MSVC" }
                $msvcDir = $null
                if ($msvcRoot -and (Test-Path $msvcRoot)) {
                    $msvcDir = Get-ChildItem $msvcRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
                } else {
                    Write-Warning "MSVC toolset not found at '$msvcRoot'. The Rust msvc target needs the VC.Tools.x86.x64 component; link.exe will be missing and native builds will fail."
                }
                $sdkVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots" -Name KitsRoot10 -ErrorAction SilentlyContinue).KitsRoot10
                $sdkInc = $null
                if ($sdkVersion -and (Test-Path "${sdkVersion}Include")) {
                    $sdkInc = Get-ChildItem "${sdkVersion}Include" -Directory | Sort-Object Name -Descending | Select-Object -First 1
                }
                $includePaths = @()
                if ($msvcDir) { $includePaths += "$($msvcDir.FullName)\include" }
                if ($sdkInc) {
                    $includePaths += "$($sdkInc.FullName)\ucrt"
                    $includePaths += "$($sdkInc.FullName)\shared"
                    $includePaths += "$($sdkInc.FullName)\um"
                }
                if ($includePaths.Count -gt 0) {
                    $env:INCLUDE = $includePaths -join ";"
                }
            }
        }

        cargo install --locked tree-sitter-cli
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Cargo-based tools installed." -ForegroundColor Green
        } else {
            Add-Failure -Step "cargo install tree-sitter-cli" -Detail "cargo exited with $LASTEXITCODE. A 'linker link.exe not found' error means the Visual Studio C++ workload is missing."
        }
    } else {
        Write-Warning "Cargo not found in PATH. Skipping Cargo-based tool installation."
    }

    if (Get-Command go -ErrorAction SilentlyContinue) {
        Write-Host "Installing Go-based tools..." -ForegroundColor Yellow
        go install github.com/mhersson/mpls@latest
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Go-based tools installed." -ForegroundColor Green
        } else {
            Add-Failure -Step "go install mpls" -Detail "go exited with $LASTEXITCODE."
        }
    } else {
        Write-Warning "Go not found in PATH. Skipping Go-based tool installation."
    }
} else {
    Write-Host "Skipping package installation." -ForegroundColor Yellow
}

# ── 2.5. GitHub release packages ──────────────────────────────────────────

if (-not $SkipPackages -and -not $SkipGitHubPackages) {
    Write-Host ""
    Write-Host "=== GitHub Release Packages ===" -ForegroundColor Cyan
    Invoke-Step -ScriptName "Install-GitHubReleases.ps1" -Description "Installing GitHub release packages"
} else {
    Write-Host "Skipping GitHub release packages." -ForegroundColor Yellow
}

# ── 3. Dotfile configuration ───────────────────────────────────────────────

if (-not $SkipConfiguration) {
    Write-Host ""
    Write-Host "=== Dotfile Configuration ===" -ForegroundColor Cyan
    Invoke-Step -ScriptName "Configure-Dotfiles.ps1" -Description "Configuring dotfiles"
} else {
    Write-Host "Skipping dotfile configuration." -ForegroundColor Yellow
}

# ── 4. Font installation ───────────────────────────────────────────────────

if (-not $SkipFont) {
    Write-Host ""
    Invoke-Step -ScriptName "Install-JetBrainsFont.ps1" -Description "Installing JetBrains Mono Nerd Font"
} else {
    Write-Host "Skipping font installation." -ForegroundColor Yellow
}

# ── 5. Windows settings ────────────────────────────────────────────────────

if (-not $SkipWindowsSettings) {
    Write-Host ""
    Invoke-Step -ScriptName "Configure-WindowsSettings.ps1" -Description "Configuring Windows settings"
} else {
    Write-Host "Skipping Windows settings." -ForegroundColor Yellow
}

# ── 6. Editor extensions ───────────────────────────────────────────────────

if (-not $SkipExtensions) {
    Write-Host ""
    Invoke-Step -ScriptName "Install-Extensions.ps1" -Description "Installing editor extensions"
} else {
    Write-Host "Skipping editor extensions." -ForegroundColor Yellow
}

# ── 7. Node.js setup ───────────────────────────────────────────────────────

if (-not $SkipNodeSetup) {
    Write-Host ""
    Invoke-Step -ScriptName "Setup-NodeLTS.ps1" -Description "Setting up Node.js LTS via fnm"
} else {
    Write-Host "Skipping Node.js setup." -ForegroundColor Yellow
}

# ── Done ────────────────────────────────────────────────────────────────────

Write-Host ""
if ($script:Failures.Count -gt 0) {
    Write-Host "=== INSTALLATION COMPLETED WITH ERRORS ===" -ForegroundColor Red
    Write-Host "$($script:Failures.Count) step(s) failed:" -ForegroundColor Red
    foreach ($failure in $script:Failures) {
        Write-Host "  - $failure" -ForegroundColor Red
    }
    Write-Host "Everything else was configured. Re-run this script after resolving the above." -ForegroundColor Yellow
    exit 1
}

Write-Host "=== INSTALLATION COMPLETE ===" -ForegroundColor Green
Write-Host "Your Windows development environment has been configured." -ForegroundColor White
Write-Host "You may need to restart your shell to use newly installed tools." -ForegroundColor Yellow
