@{
    # Setup steps run by Install-WindowsEnvironment.ps1, in this order.
    #
    # Name         Used by -Skip / -Only and in the summary.
    # Script       Path relative to this folder. Must return one StepResult.
    # Description  Shown as the step header.
    # Admin        Needs elevation. Consecutive Admin steps share one UAC prompt,
    #              which is why they are listed first.
    # Critical     A failure stops the run (later steps depend on it).
    # OptIn        Skipped unless selected with -Only or an include switch.
    # Tags         Groups for -Skip / -Only, e.g. -Skip packages.
    # Parameters   Passed to the script by name. Machine-specific values live
    #              here rather than in the scripts.
    Steps = @(
        # ── Elevated ───────────────────────────────────────────────────────
        @{
            Name        = 'WslFeatures'
            Script      = 'Install-WSL.ps1'
            Description = 'Enabling the WSL Windows features'
            Admin       = $true
            OptIn       = $true
            Tags        = @('wsl')
            # Enabling the features needs a reboot before a distro can install,
            # so this step reports RestartRequired and the run stops there.
            Parameters  = @{ FeaturesOnly = $true }
        }
        @{
            Name        = 'WslDistro'
            Script      = 'Install-WSL.ps1'
            Description = 'Installing Ubuntu 24.04 in WSL'
            Admin       = $true
            OptIn       = $true
            Tags        = @('wsl')
        }
        @{
            Name        = 'PackageManagers'
            Script      = 'Setup-PackageManagers.ps1'
            Description = 'Setting up winget'
            Admin       = $true
            Critical    = $true
            Tags        = @('packages')
        }
        @{
            Name        = 'WingetPackages'
            Script      = 'Install-WingetPackages.ps1'
            Description = 'Installing winget packages from packages.jsonc'
            Admin       = $true
            Tags        = @('packages')
        }
        @{
            Name        = 'Psql'
            Script      = 'Install-Psql.ps1'
            Description = 'Installing the PostgreSQL command line tools (psql)'
            Admin       = $true
            Tags        = @('packages')
            Parameters  = @{ Version = 18 }
        }
        @{
            Name        = 'VisualStudio'
            Script      = 'Install-VisualStudio.ps1'
            Description = 'Installing or updating Visual Studio from vs/vsconfig.jsonc'
            Admin       = $true
            Tags        = @('packages')
            Parameters  = @{
                Product      = 'Microsoft.VisualStudio.Product.Enterprise'
                WingetId     = 'Microsoft.VisualStudio.Enterprise'
                # vsconfig.jsonc declares .NET 10, which only exists in the 18.x
                # catalog, so an older 17.x install must never be targeted.
                VersionRange = '[18.0,19.0)'
            }
        }
        @{
            # Elevated until Configure-Dotfiles.ps1 is rewritten (todo.md Phase 5):
            # it refuses to run without admin, even with Developer Mode on.
            Name        = 'Dotfiles'
            Script      = 'Configure-Dotfiles.ps1'
            Description = 'Linking dotfiles'
            Admin       = $true
            Tags        = @('config')
        }

        # ── Current user ───────────────────────────────────────────────────
        @{
            Name        = 'SqlPlus'
            Script      = 'Install-SqlPlus.ps1'
            Description = 'Installing Oracle SQL*Plus'
            Tags        = @('packages')
        }
        @{
            Name        = 'LanguageTools'
            Script      = 'Install-LanguageTools.ps1'
            Description = 'Installing uv, cargo and go tools from language-tools.jsonc'
            Tags        = @('packages')
        }
        @{
            Name        = 'GitHubReleases'
            Script      = 'Install-GitHubReleases.ps1'
            Description = 'Installing GitHub release packages'
            Tags        = @('packages')
        }
        @{
            Name        = 'OpenCode'
            Script      = 'Install-OpenCode.ps1'
            Description = 'Installing the OpenCode CLI'
            Tags        = @('packages')
        }
        @{
            Name        = 'Font'
            Script      = 'Install-JetBrainsFont.ps1'
            Description = 'Installing JetBrains Mono Nerd Font'
            Tags        = @('config')
        }
        @{
            Name        = 'WindowsSettings'
            Script      = 'Configure-WindowsSettings.ps1'
            Description = 'Configuring Windows settings'
            Tags        = @('config')
        }
        @{
            Name        = 'Extensions'
            Script      = 'Install-Extensions.ps1'
            Description = 'Installing VS Code and Visual Studio extensions'
            Tags        = @('config')
        }
        @{
            Name        = 'NodeLTS'
            Script      = 'Setup-NodeLTS.ps1'
            Description = 'Setting up Node.js LTS via fnm'
            Tags        = @('packages')
        }
    )
}
