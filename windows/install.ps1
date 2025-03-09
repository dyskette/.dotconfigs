# Install winget
if (-not(Get-Command winget -ErrorAction SilentlyContinue))
{
    Write-Host "Winget not found. Installing..."

    # Download latest release
    $tempFile = "$env:TEMP\winget_latest.json"
    Invoke-WebRequest -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -OutFile $tempFile -UseBasicParsing
    $wingetUrl = (Get-Content $tempFile | ConvertFrom-Json).assets | Where-Object { $_.browser_download_url -like '*.msixbundle' } | Select-Object -ExpandProperty browser_download_url
    Invoke-WebRequest -Uri $wingetUrl -OutFile "Setup.msix" -UseBasicParsing

    # Install Winget
    try
    {
        Add-AppxPackage -Path "Setup.msix"
    } catch
    {
        Write-Host "Failed to install Winget."
        Remove-Item -Force "Setup.msix"
        exit 1
    }

    # Update PATH environment variable
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    # Clean up
    Remove-Item -Force "Setup.msix"
    Remove-Item -Force $tempFile
} else
{
    Write-Host "Winget is already installed."
}

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
