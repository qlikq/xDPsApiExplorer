function Show-ApiContext {
    <#
    .SYNOPSIS
        Generates an interactive, 100% offline browser-based API & Object Graph Explorer for PowerShell and VMware PowerCLI objects.

    .DESCRIPTION
        Part of the xDPsApiExplorer module by xDlabs (https://xdlabs.info).
        Show-ApiContext (aliases: Show-ApiGraph, sac) accepts any PowerShell or .NET object from the pipeline
        (such as VMware PowerCLI Get-View objects, ExtensionData, or standard .NET / PowerShell objects),
        inspects both its live runtime values and its .NET Reflection schema (even for $null properties) up to -MaxDepth (1..10),
        and opens a self-contained, zero-dependency interactive HTML explorer.

        Key Features:
        - 100% Offline Execution: No external CDNs or internet access required; safe for air-gapped datacenter/vSphere environments.
        - Live Instance + Reflected $null Schema: Displays live property values and reflects full .NET schemas for $null properties.
        - Embedded Broadcom vSphere SDK Documentation: Built-in descriptions for 4,880+ vSphere API types, properties, and methods.
        - Interactive Where-Object (?{ }) Filter Builder: Click '?' next to any property to build multi-condition PowerShell filters.
        - ManagedObjectReference (MoRef) Detection: Automatically highlights MoRef pointers and generates ready-to-run Get-View commands.
        - Pinned Boxes Dock: Pin up to 5 objects to the bottom-left dock for instant navigation across large object graphs.

    .PARAMETER InputObject
        The PowerShell or .NET object to inspect. Accepts pipeline input (e.g., $vm | Show-ApiContext).

    .PARAMETER MaxDepth
        Maximum traversal depth for nested complex objects (valid range: 1 to 10; default: 4).
        Array/collection indexing ([0], [1], ...) does not consume an extra depth level.

    .PARAMETER MaxCollectionItems
        Maximum number of elements sampled from each array or collection property (valid range: 1 to 50; default: 5).

    .PARAMETER RootName
        Optional root variable name displayed in generated PowerShell paths (e.g., '$vm').
        When omitted, Show-ApiContext automatically infers the variable expression from the pipeline invocation.

    .PARAMETER ExcludeMethods
        If specified, skips collecting .NET and PSObject method signatures on inspected objects.

    .PARAMETER OutputPath
        Optional file path for the generated HTML report. Defaults to a timestamped file in the system temporary folder.

    .PARAMETER NoBrowser
        If specified, generates the HTML file without automatically launching the default web browser.

    .PARAMETER PassThru
        If specified, returns a summary object containing HtmlPath, RootName, RootType, MaxDepth, and the inspected NodeTree.

    .INPUTS
        System.Object
        You can pipe any PowerShell or .NET object to Show-ApiContext.

    .OUTPUTS
        None by default, or PSCustomObject when -PassThru is specified.

    .EXAMPLE
        $vm = Get-View -ViewType VirtualMachine -Filter @{ Name = 'prod-db-01' }
        $vm | Show-ApiContext -MaxDepth 6

        Inspects a VMware vSphere VirtualMachine View object up to 6 levels deep and opens the interactive API Explorer in the default browser.

    .EXAMPLE
        (Get-VM 'prod-db-01').ExtensionData | sac -MaxDepth 5

        Uses the 'sac' alias to inspect the ExtensionData property of a PowerCLI virtual machine.

    .EXAMPLE
        Get-Process -Id $PID | Show-ApiGraph -MaxDepth 3

        Inspects the current PowerShell process object up to 3 levels deep.

    .EXAMPLE
        $report = $vm | Show-ApiContext -MaxDepth 4 -OutputPath 'C:\Reports\vm-api.html' -NoBrowser -PassThru

        Generates the offline HTML file at a custom path without opening a browser and returns the inspection metadata object.

    .LINK
        https://xdlabs.info
    #>
    [CmdletBinding()]
    [Alias('Show-ApiGraph', 'sac')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 10)]
        [int]$MaxDepth = 4,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 50)]
        [int]$MaxCollectionItems = 5,

        [Parameter(Mandatory = $false)]
        [string]$RootName,

        [Parameter(Mandatory = $false)]
        [switch]$ExcludeMethods,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [switch]$NoBrowser,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    begin {
        $collectedItems = New-Object System.Collections.Generic.List[object]

        # Try to infer variable expression from pipeline invocation
        $inferredRootName = '$obj'
        try {
            $invLine = $MyInvocation.Line
            if ([string]::IsNullOrWhiteSpace($invLine)) {
                $lastHist = Get-History -Count 1 -ErrorAction SilentlyContinue
                if ($null -ne $lastHist) { $invLine = $lastHist.CommandLine }
            }
            if (-not [string]::IsNullOrWhiteSpace($invLine)) {
                # Match expression immediately before '| Show-ApiContext' / '| Show-ApiGraph' / '| sac'
                if ($invLine -match '(?:^|[=;])\s*(?<expr>\$[a-zA-Z0-9_:\.\[\]''"]+)\s*\|\s*(?:Show-ApiContext|Show-ApiGraph|sac)\b') {
                    $inferredRootName = $Matches['expr'].Trim()
                } elseif ($invLine -match '(?<expr>\$[a-zA-Z0-9_:\.\[\]]+)\s*\|') {
                    $inferredRootName = $Matches['expr'].Trim()
                }
            }
        } catch {}
    }

    process {
        $collectedItems.Add($InputObject)
    }

    end {
        if ($collectedItems.Count -eq 0) {
            Write-Warning "No input object provided to Show-ApiContext."
            return
        }

        $targetObj = if ($collectedItems.Count -eq 1) { $collectedItems[0] } else { $collectedItems.ToArray() }
        $effectiveRootName = if (-not [string]::IsNullOrWhiteSpace($RootName)) {
            if ($RootName.StartsWith('$')) { $RootName } else { "`$$RootName" }
        } else {
            $inferredRootName
        }

        $includeMethodsBool = -not $ExcludeMethods.IsPresent

        $nodeTree = ConvertTo-ApiNodeTree `
            -InputObject $targetObj `
            -Name $effectiveRootName `
            -PsPath $effectiveRootName `
            -MaxDepth $MaxDepth `
            -CurrentDepth 0 `
            -MaxCollectionItems $MaxCollectionItems `
            -IncludeMethods $includeMethodsBool

        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            $outDir = Join-Path ([System.IO.Path]::GetTempPath()) 'xDPsApiExplorer'
            if (-not (Test-Path -LiteralPath $outDir)) {
                New-Item -ItemType Directory -Path $outDir -Force | Out-Null
            }
            $safeName = ($effectiveRootName -replace '[^a-zA-Z0-9_-]', '')
            if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'object' }
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $OutputPath = Join-Path $outDir "ApiContext_${safeName}_${timestamp}.html"
        } else {
            $parentDir = Split-Path -Path $OutputPath -Parent
            if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }
        }

        $htmlContent = New-ApiExplorerHtml -NodeTree $nodeTree -MaxDepth $MaxDepth -RootName $effectiveRootName
        [System.IO.File]::WriteAllText($OutputPath, $htmlContent, [System.Text.Encoding]::UTF8)

        if (-not $NoBrowser.IsPresent) {
            Start-Process -FilePath $OutputPath
        }

        if ($PassThru.IsPresent) {
            return [PSCustomObject]@{
                HtmlPath  = (Resolve-Path -LiteralPath $OutputPath).Path
                RootName  = $effectiveRootName
                RootType  = $nodeTree.FullTypeName
                MaxDepth  = $MaxDepth
                NodeTree  = $nodeTree
            }
        }
    }
}
