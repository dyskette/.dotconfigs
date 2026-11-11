@{
    # Used by windows/tests/Invoke-Checks.ps1, CI and the VS Code PowerShell
    # extension (which picks up this file from the workspace root).
    Severity     = @('Error', 'Warning', 'Information')

    ExcludeRules = @(
        # The setup scripts are interactive installers. Progress text must not go
        # to the success stream, which carries only the StepResult.
        'PSAvoidUsingWriteHost'

        # PowerShell 7 reads BOM-less UTF-8 correctly. The one 5.1 script,
        # windows/Bootstrap.ps1, is held to ASCII-only by Repository.Tests.ps1.
        'PSUseBOMForUnicodeEncodedFile'
    )

    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('7.4')
        }
    }
}
