function Show-ApiContext {
    <#
    .SYNOPSIS
        Generates an interactive, 100% offline browser-based API & Object Graph Explorer (or 2-Object Property Diff Table) for PowerShell and VMware PowerCLI objects.

    .DESCRIPTION
        Part of the xDPsApiExplorer module by xDlabs (https://xdlabs.info).
        Show-ApiContext (aliases: Show-ApiGraph, sac) accepts any PowerShell or .NET object from the pipeline
        (such as VMware PowerCLI Get-View objects, ExtensionData, or standard .NET / PowerShell objects),
        inspects both its live runtime values and its .NET Reflection schema (even for $null properties) up to -MaxDepth (1..10),
        and opens a self-contained, zero-dependency interactive HTML explorer.

        Compare Mode (2 Objects of the Same Type):
        When exactly 2 objects of the same type are passed (e.g., $vm1, $vm2 | Show-ApiContext), Show-ApiContext
        automatically switches to Object Comparison Mode, generating a side-by-side comparison table showing
        every property path where Object A and Object B have different values, array counts, or missing elements.

    .PARAMETER InputObject
        The PowerShell or .NET object(s) to inspect. Pass 1 object for UML Graph Explorer Mode, or 2 objects of the same type for Comparison Mode.

    .PARAMETER MaxDepth
        Maximum traversal depth for nested complex objects (valid range: 1 to 10; default: 4).
        Array/collection indexing ([0], [1], ...) does not consume an extra depth level.

    .PARAMETER MaxCollectionItems
        Maximum number of elements sampled from each array or collection property (valid range: 1 to 200; default: 5 in Single Mode, 25 in Compare Mode).

    .PARAMETER RootName
        Optional root variable name displayed in generated PowerShell paths (e.g., '$vm' or Object A in Compare Mode).
        When omitted, Show-ApiContext automatically infers the variable expression from the pipeline invocation.

    .PARAMETER RightRootName
        Optional right root variable name displayed for Object B when Compare Mode is active (e.g., '$vm2').

    .PARAMETER ExcludeMethods
        If specified, skips collecting .NET and PSObject method signatures on inspected objects.

    .PARAMETER OutputPath
        Optional file path for the generated HTML report. Defaults to a timestamped file in the system temporary folder.

    .PARAMETER NoBrowser
        If specified, generates the HTML file without automatically launching the default web browser.

    .PARAMETER PassThru
        If specified, returns a summary object containing HtmlPath, IsCompareMode, RootName, RightRootName, RootType, MaxDepth, NodeTree, and (in Compare Mode) DiffCount and ComparisonRows.

    .INPUTS
        System.Object
        You can pipe any PowerShell or .NET object (or 2 objects of the same type) to Show-ApiContext.

    .OUTPUTS
        None by default, or PSCustomObject when -PassThru is specified.

    .EXAMPLE
        $vm = Get-View -ViewType VirtualMachine -Filter @{ Name = 'prod-db-01' }
        $vm | Show-ApiContext -MaxDepth 6

        Inspects a VMware vSphere VirtualMachine View object up to 6 levels deep and opens the interactive API Explorer in the default browser.

    .EXAMPLE
        $vm1, $vm2 | Show-ApiContext -MaxDepth 6

        Compares two VMware vSphere VirtualMachine View objects side-by-side and displays a table of all differing property paths and values.

    .LINK
        https://github.com/qlikq/xDPsApiExplorer
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
        [ValidateRange(1, 200)]
        [int]$MaxCollectionItems = 5,

        [Parameter(Mandatory = $false)]
        [string]$RootName,

        [Parameter(Mandatory = $false)]
        [string]$RightRootName,

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

        # Try to infer variable expression(s) from pipeline invocation
        $inferredRootName = '$obj'
        $inferredLeftName = $null
        $inferredRightName = $null
        try {
            $invLine = $MyInvocation.Line
            if ([string]::IsNullOrWhiteSpace($invLine)) {
                $lastHist = Get-History -Count 1 -ErrorAction SilentlyContinue
                if ($null -ne $lastHist) { $invLine = $lastHist.CommandLine }
            }
            if (-not [string]::IsNullOrWhiteSpace($invLine)) {
                if ($invLine -match '(?<left>\$[a-zA-Z0-9_:\.\[\]''"]+)\s*,\s*(?<right>\$[a-zA-Z0-9_:\.\[\]''"]+)\s*\)?\s*\|\s*(?:Show-ApiContext|Show-ApiGraph|sac)\b') {
                    $inferredLeftName = $Matches['left'].Trim()
                    $inferredRightName = $Matches['right'].Trim()
                    $inferredRootName = $inferredLeftName
                } elseif ($invLine -match '(?:^|[=;])\s*(?<expr>\$[a-zA-Z0-9_:\.\[\]''"]+)\s*\|\s*(?:Show-ApiContext|Show-ApiGraph|sac)\b') {
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

        # Normalize input items (handle both pipeline stream and single array argument)
        $effectiveItems = if (
            $collectedItems.Count -eq 1 -and
            $null -ne $collectedItems[0] -and
            ($collectedItems[0] -is [System.Collections.IList]) -and
            ($collectedItems[0] -isnot [string])
        ) {
            @($collectedItems[0])
        } else {
            $collectedItems.ToArray()
        }

        if ($effectiveItems.Count -gt 2) {
            $errMsg = "Show-ApiContext accepts either 1 object (Single Explorer Mode) or 2 objects of the same type (Compare Mode), but received $($effectiveItems.Count) objects."
            $PSCmdlet.ThrowTerminatingError(
                (New-Object System.Management.Automation.ErrorRecord(
                    (New-Object System.ArgumentException($errMsg)),
                    'InvalidObjectCountForCompareMode',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $effectiveItems
                ))
            )
        }

        $isCompareMode = $false
        $pairCandidate = $null

        if ($effectiveItems.Count -eq 2) {
            $pairCandidate = @($effectiveItems[0], $effectiveItems[1])
            $itemA = $pairCandidate[0]
            $itemB = $pairCandidate[1]

            if ($null -eq $itemA -or $null -eq $itemB) {
                $errMsg = 'Compare Mode requires 2 non-null objects of the same type, but one of the provided objects is $null.'
                $PSCmdlet.ThrowTerminatingError(
                    (New-Object System.Management.Automation.ErrorRecord(
                        (New-Object System.ArgumentException($errMsg)),
                        'NullObjectInCompareMode',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument,
                        $pairCandidate
                    ))
                )
            }

            $rawA = if ($itemA -is [psobject] -and $null -ne $itemA.PSObject.BaseObject) { $itemA.PSObject.BaseObject } else { $itemA }
            $rawB = if ($itemB -is [psobject] -and $null -ne $itemB.PSObject.BaseObject) { $itemB.PSObject.BaseObject } else { $itemB }

            $typeFullA = $rawA.GetType().FullName
            $typeFullB = $rawB.GetType().FullName
            $psTypeA = if ($itemA -is [psobject] -and $itemA.PSObject.TypeNames.Count -gt 0) { $itemA.PSObject.TypeNames[0] } else { $typeFullA }
            $psTypeB = if ($itemB -is [psobject] -and $itemB.PSObject.TypeNames.Count -gt 0) { $itemB.PSObject.TypeNames[0] } else { $typeFullB }

            if ($typeFullA -ne $typeFullB -or $psTypeA -ne $psTypeB) {
                $errMsg = "Compare Mode only supports objects of the same type, but received '[$psTypeA]' and '[$psTypeB]'."
                $PSCmdlet.ThrowTerminatingError(
                    (New-Object System.Management.Automation.ErrorRecord(
                        (New-Object System.ArgumentException($errMsg)),
                        'MismatchedObjectTypesInCompareMode',
                        [System.Management.Automation.ErrorCategory]::InvalidType,
                        $pairCandidate
                    ))
                )
            }

            $isCompareMode = $true
        }

        $includeMethodsBool = -not $ExcludeMethods.IsPresent

        if ($isCompareMode) {
            $effectiveMaxCollection = if ($PSBoundParameters.ContainsKey('MaxCollectionItems')) {
                $MaxCollectionItems
            } else {
                [Math]::Max($MaxCollectionItems, 25)
            }

            $hasCustomLeftVar = $true
            $effectiveRootName = if (-not [string]::IsNullOrWhiteSpace($RootName)) {
                if ($RootName.StartsWith('$')) { $RootName } else { "`$$RootName" }
            } elseif (-not [string]::IsNullOrWhiteSpace($inferredLeftName)) {
                $inferredLeftName
            } elseif ($inferredRootName -ne '$obj') {
                "$($inferredRootName)[0]"
            } else {
                $hasCustomLeftVar = $false
                '$firstObj'
            }

            $hasCustomRightVar = $true
            $effectiveRightRootName = if (-not [string]::IsNullOrWhiteSpace($RightRootName)) {
                if ($RightRootName.StartsWith('$')) { $RightRootName } else { "`$$RightRootName" }
            } elseif (-not [string]::IsNullOrWhiteSpace($inferredRightName)) {
                $inferredRightName
            } elseif ($inferredRootName -ne '$obj' -and [string]::IsNullOrWhiteSpace($inferredLeftName)) {
                "$($inferredRootName)[1]"
            } else {
                $hasCustomRightVar = $false
                '$secondObj'
            }

            $leftLabel = if ($hasCustomLeftVar) { $effectiveRootName } else { 'First Object' }
            $rightLabel = if ($hasCustomRightVar) { $effectiveRightRootName } else { 'Second Object' }

            $nodeTree = ConvertTo-ApiNodeTree `
                -InputObject $pairCandidate[0] `
                -Name $effectiveRootName `
                -PsPath $effectiveRootName `
                -MaxDepth $MaxDepth `
                -CurrentDepth 0 `
                -MaxCollectionItems $effectiveMaxCollection `
                -IncludeMethods $false

            $rightNodeTree = ConvertTo-ApiNodeTree `
                -InputObject $pairCandidate[1] `
                -Name $effectiveRightRootName `
                -PsPath $effectiveRightRootName `
                -MaxDepth $MaxDepth `
                -CurrentDepth 0 `
                -MaxCollectionItems $effectiveMaxCollection `
                -IncludeMethods $false

            $comparisonRows = Compare-ApiNodeTrees `
                -LeftNode $nodeTree `
                -RightNode $rightNodeTree `
                -LeftRootName $effectiveRootName `
                -RightRootName $effectiveRightRootName
        } else {
            $targetObj = if ($collectedItems.Count -eq 1) { $collectedItems[0] } else { $collectedItems.ToArray() }
            $effectiveRootName = if (-not [string]::IsNullOrWhiteSpace($RootName)) {
                if ($RootName.StartsWith('$')) { $RootName } else { "`$$RootName" }
            } else {
                $inferredRootName
            }
            $effectiveRightRootName = $null
            $rightNodeTree = $null
            $comparisonRows = $null

            $nodeTree = ConvertTo-ApiNodeTree `
                -InputObject $targetObj `
                -Name $effectiveRootName `
                -PsPath $effectiveRootName `
                -MaxDepth $MaxDepth `
                -CurrentDepth 0 `
                -MaxCollectionItems $MaxCollectionItems `
                -IncludeMethods $includeMethodsBool
        }

        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            $outDir = Join-Path ([System.IO.Path]::GetTempPath()) 'xDPsApiExplorer'
            if (-not (Test-Path -LiteralPath $outDir)) {
                New-Item -ItemType Directory -Path $outDir -Force | Out-Null
            }
            $safeName = ($effectiveRootName -replace '[^a-zA-Z0-9_-]', '')
            if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'object' }
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $prefix = if ($isCompareMode) { 'ApiCompare' } else { 'ApiContext' }
            $OutputPath = Join-Path $outDir "${prefix}_${safeName}_${timestamp}.html"
        } else {
            $parentDir = Split-Path -Path $OutputPath -Parent
            if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }
        }

        if ($isCompareMode) {
            $htmlContent = New-ApiExplorerCompareHtml `
                -ComparisonRows $comparisonRows `
                -TypeName $nodeTree.TypeName `
                -TypeDescription $nodeTree.Description `
                -MaxDepth $MaxDepth `
                -LeftRootName $effectiveRootName `
                -RightRootName $effectiveRightRootName `
                -LeftLabel $leftLabel `
                -RightLabel $rightLabel
        } else {
            $htmlContent = New-ApiExplorerHtml `
                -NodeTree $nodeTree `
                -MaxDepth $MaxDepth `
                -RootName $effectiveRootName
        }

        [System.IO.File]::WriteAllText($OutputPath, $htmlContent, [System.Text.Encoding]::UTF8)

        if (-not $NoBrowser.IsPresent) {
            Start-Process -FilePath $OutputPath
        }

        if ($PassThru.IsPresent) {
            $diffCount = if ($isCompareMode -and $null -ne $comparisonRows) {
                @($comparisonRows | Where-Object { $_.IsDifferent }).Count
            } else {
                0
            }
            return [PSCustomObject]@{
                HtmlPath           = (Resolve-Path -LiteralPath $OutputPath).Path
                IsCompareMode      = $isCompareMode
                RootName           = $effectiveRootName
                RightRootName      = $effectiveRightRootName
                RootType           = $nodeTree.FullTypeName
                MaxDepth           = $MaxDepth
                DiffCount          = $diffCount
                TotalComparedCount = if ($null -ne $comparisonRows) { $comparisonRows.Count } else { 0 }
                ComparisonRows     = $comparisonRows
                NodeTree           = $nodeTree
                RightNodeTree      = $rightNodeTree
            }
        }
    }
}
