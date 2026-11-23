@{
    RootModule           = 'xDPsApiExplorer.psm1'
    ModuleVersion        = '1.1.0'
    CompatiblePSEditions = @('Desktop', 'Core')
    GUID                 = 'a18f40d2-9c5b-4e82-84b7-11d85a9e0101'
    Author               = 'Grzegorz Kulikowski (xDlabs)'
    CompanyName          = 'xDlabs (https://xdlabs.info)'
    Copyright            = '(c) 2026 Grzegorz Kulikowski / xDlabs (https://xdlabs.info). All rights reserved.'
    Description          = 'Interactive 100% offline API & Object Graph Explorer for PowerShell and VMware PowerCLI / vSphere Web Services SDK with interactive Where-Object (?{ }) filter builder.'
    PowerShellVersion    = '5.1'
    FunctionsToExport    = @('Show-ApiContext')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @('Show-ApiGraph', 'sac')
    PrivateData          = @{
        PSData = @{
            Tags         = @(
                'PowerShell',
                'VMware',
                'PowerCLI',
                'vSphere',
                'API',
                'Explorer',
                'UML',
                'Graph',
                'ObjectExplorer',
                'xDlabs',
                'PSEdition_Desktop',
                'PSEdition_Core',
                'Windows',
                'Linux',
                'MacOS'
            )
            ProjectUri   = 'https://github.com/qlikq/xDPsApiExplorer'
            LicenseUri   = 'https://github.com/qlikq/xDPsApiExplorer/blob/main/LICENSE'
            ReleaseNotes = @'
xDPsApiExplorer 1.1.0 by xDlabs (https://xdlabs.info)
- Added 2-Object Comparison Mode ($obj1, $obj2 | Show-ApiContext): side-by-side deep property diff table with ShowDifferent, Value Differences, and IncludeEqual filters, array count & missing element detection, and section filtering.
- Digitally signed with the official xDlabs Grzegorz Kulikowski (Certum Code Signing CA) Authenticode certificate.
- Interactive 100% offline HTML5 API & Object Graph Explorer (Show-ApiContext / Show-ApiGraph / sac).
- Deep object graph inspection (-MaxDepth 1..10) combining live PowerShell instance values with .NET Reflection schema for $null properties.
- Embedded offline Broadcom vSphere Web Services SDK documentation (4,880+ types, properties, and methods) with expandable [+] descriptions.
- Interactive Where-Object (?{ }) Filter Builder with one-click condition toggles and -and / -or operators.
- Automatic VMware ManagedObjectReference (MoRef) detection with ready-to-copy Get-View commands.
- Instant search across properties, methods, and [Type.FullName] with match highlighting, Hide Unmatched tree filtering, and Pinned Boxes dock (up to 5 items).
'@
        }
    }
}
