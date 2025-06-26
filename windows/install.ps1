function Get-MajorMinorVersion {
    param([string]$version)

    # Strip non-digit/dot characters, e.g., 'v1.11.400' -> '1.11.400'
    $clean = $version -replace '[^\d\.]', ''

    # Split version into parts
    $parts = $clean -split '\.'

    # Return array of integers: major, minor
    return @([int]$parts[0], [int]$parts[1])
}

# Install winget
$shouldInstallWinget = $false
$wingetUrl = ""

# Download latest release information
$tempFile = "$env:TEMP\winget_latest.json"
Invoke-WebRequest -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -OutFile $tempFile -UseBasicParsing

# Parse release information
$latestJson = (Get-Content $tempFile | ConvertFrom-Json)

$latestVersion = $latestJson.tag_name # e.g., v1.11.400
Write-Host "Latest Winget version: $latestVersion"

$latestVersion = Get-MajorMinorVersion $latestVersion

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "Winget not found. Will install."
    $shouldInstallWinget = $true
} else {
    $installedVersion = (winget --version)  # e.g., v1.6.10121
    Write-Host "Currrently installed Winget version: $installedVersion"

    $installedVersion = Get-MajorMinorVersion $installedVersion

    if ($latestVersion[0] -gt $installedVersion[0] -or ($latestVersion[0] -eq $installedVersion[0] -and $latestVersion[1] -gt $installedVersion[1])) {
        Write-Host "New version available. Will reinstall."
        $shouldInstallWinget = $true
    } else {
        Write-Host "Winget is up to date."
    }
}

if ($shouldInstallWinget) {
    $wingetUrl = $latestJson.assets | Where-Object { $_.browser_download_url -like '*.msixbundle' } | Select-Object -ExpandProperty browser_download_url

    if (-not $wingetUrl) {
        Write-Host "Failed to find .msixbundle in release assets."
        Remove-Item -Force $tempFile
        exit 1
    }

    $msixPath = "$env:TEMP\Setup.msix"
    Write-Host "Downloading Winget from: $wingetUrl"
    Invoke-WebRequest -Uri $wingetUrl -OutFile $msixPath -UseBasicParsing

    # Install Winget
    try
    {
        Add-AppxPackage -Path $msixPath
        Write-Host "Winget installed successfully."
    } catch
    {
        Write-Host "Failed to install Winget."
        Remove-Item -Force $msixPath
        Remove-Item -Force $tempFile
        exit 1
    }

    # Update PATH environment variable
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    # Clean up
    Remove-Item -Force $msixPath
}

Remove-Item -Force $tempFile

if (-not(Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git not found. Installing..."
    winget install --exact --id Git.Git --silent

    # Update PATH environment variable
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# Clone the repository
$REPO_URL = "https://github.com/dyskette/.dotconfigs.git"
$DEST_DIR = "$env:USERPROFILE\.dotconfigs"

if (Test-Path "$DEST_DIR")
{
    Write-Host "Repository already exists. Pulling the latest changes..."
    git -C "$DEST_DIR" pull
} else
{
    Write-Host "Cloning repository..."
    git clone "$REPO_URL" "$DEST_DIR"
}

# Run Winget configuration
Set-Location -Path $DEST_DIR -ErrorAction Stop
winget configure --accept-configuration-agreements --file "windows\configuration.dsc.yaml"
