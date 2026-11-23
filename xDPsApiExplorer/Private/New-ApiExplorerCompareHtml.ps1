function Compare-ApiNodeTrees {
    <#
    .SYNOPSIS
        Recursively compares two ApiNodeTree structures of the same root type and produces a flat list of property comparison rows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$LeftNode,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$RightNode,

        [Parameter(Mandatory = $true)]
        [string]$LeftRootName,

        [Parameter(Mandatory = $true)]
        [string]$RightRootName
    )

    $rows = New-Object System.Collections.Generic.List[object]

    function Get-RelativePathFromRoot {
        param([string]$FullPath, [string]$RootPrefix)
        if ([string]::IsNullOrWhiteSpace($FullPath)) { return '' }
        if ($FullPath -eq $RootPrefix) { return '' }
        if ($FullPath.StartsWith("$RootPrefix.") -or $FullPath.StartsWith("$RootPrefix[")) {
            return $FullPath.Substring($RootPrefix.Length)
        }
        return $FullPath
    }

    function Get-TopSectionName {
        param([string]$RelPath)
        if ([string]::IsNullOrWhiteSpace($RelPath)) { return '(Root)' }
        $clean = $RelPath.TrimStart('.')
        if ($clean -match '^([a-zA-Z0-9_]+)') {
            return $Matches[1]
        }
        return '(Root)'
    }

    function Get-ChildCanonicalKey {
        param([object]$ChildNode)
        if ($null -eq $ChildNode -or [string]::IsNullOrWhiteSpace($ChildNode.Name)) { return '' }
        if ($ChildNode.Name -match '^(\[\d+\])') {
            return $Matches[1]
        }
        return $ChildNode.Name
    }

    function Walk-ComparePair {
        param(
            [object]$LNode,
            [object]$RNode,
            [string]$CurrentRelPath
        )

        if ($null -eq $LNode -and $null -eq $RNode) { return }

        # If both nodes are schema-only ($null parents on both sides), their actual runtime values are both $null (identical)
        if ($null -ne $LNode -and $null -ne $RNode -and $LNode.IsSchemaOnly -and $RNode.IsSchemaOnly) {
            return
        }

        $lProps = if ($null -ne $LNode -and $null -ne $LNode.Properties) { @($LNode.Properties) } else { @() }
        $rProps = if ($null -ne $RNode -and $null -ne $RNode.Properties) { @($RNode.Properties) } else { @() }

        $lKids = if ($null -ne $LNode -and $null -ne $LNode.Children) { @($LNode.Children) } else { @() }
        $rKids = if ($null -ne $RNode -and $null -ne $RNode.Children) { @($RNode.Children) } else { @() }

        # Build set of child keys that will be expanded recursively so we don't duplicate complex child object placeholders
        $expandedChildKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($lk in $lKids) { [void]$expandedChildKeys.Add((Get-ChildCanonicalKey -ChildNode $lk)) }
        foreach ($rk in $rKids) { [void]$expandedChildKeys.Add((Get-ChildCanonicalKey -ChildNode $rk)) }

        $rPropMap = @{}
        foreach ($rp in $rProps) {
            if ($null -ne $rp -and -not [string]::IsNullOrWhiteSpace($rp.Name)) {
                $rPropMap[$rp.Name] = $rp
            }
        }

        $lPropMap = @{}
        foreach ($lp in $lProps) {
            if ($null -ne $lp -and -not [string]::IsNullOrWhiteSpace($lp.Name)) {
                $lPropMap[$lp.Name] = $lp
            }
        }

        $allPropNames = New-Object System.Collections.Generic.List[string]
        $seenNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($lp in $lProps) {
            if ($null -ne $lp -and $seenNames.Add($lp.Name)) {
                $allPropNames.Add($lp.Name)
            }
        }
        foreach ($rp in $rProps) {
            if ($null -ne $rp -and $seenNames.Add($rp.Name)) {
                $allPropNames.Add($rp.Name)
            }
        }

        foreach ($pName in $allPropNames) {
            if ($pName -like '... (+* more)') { continue }

            $lp = if ($lPropMap.ContainsKey($pName)) { $lPropMap[$pName] } else { $null }
            $rp = if ($rPropMap.ContainsKey($pName)) { $rPropMap[$pName] } else { $null }

            $lIsSchema = ($null -ne $LNode -and $LNode.IsSchemaOnly)
            $rIsSchema = ($null -ne $RNode -and $RNode.IsSchemaOnly)

            # If this property is a complex object or collection element that is already expanded as a child node:
            # Only skip the summary row if both sides are non-null complex placeholders (unless it is a collection Count difference or one side is $null).
            if ($expandedChildKeys.Contains($pName)) {
                $lValTmp = if ($null -ne $lp) { "$($lp.Value)" } else { '' }
                $rValTmp = if ($null -ne $rp) { "$($rp.Value)" } else { '' }
                $isCollectionSummary = ($lValTmp -match '\(Count:\s*\d+\)') -or ($rValTmp -match '\(Count:\s*\d+\)')
                $oneIsNull = ($null -eq $lp) -or ($null -eq $rp) -or $lp.IsNull -or $rp.IsNull -or $lIsSchema -or $rIsSchema
                $isArrayElementRow = $pName -match '^\[\d+\]$'

                if ($isArrayElementRow) {
                    # Complex array element [0], [1] will be compared property-by-property in the recursive child walk
                    continue
                }
                if (-not $isCollectionSummary -and -not $oneIsNull) {
                    # Standard complex property summary like [VMware.Vim.VirtualMachineConfigInfo] on both sides
                    continue
                }
            }

            $propRelPath = if ($pName.StartsWith('[')) {
                "$CurrentRelPath$pName"
            } else {
                "$CurrentRelPath.$pName"
            }

            $effProp = if ($null -ne $lp) { $lp } else { $rp }
            $pType = if ($null -ne $effProp -and -not [string]::IsNullOrWhiteSpace($effProp.Type)) { $effProp.Type } else { 'System.Object' }
            $pDesc = if ($null -ne $lp -and -not [string]::IsNullOrWhiteSpace($lp.Description)) {
                $lp.Description
            } elseif ($null -ne $rp -and -not [string]::IsNullOrWhiteSpace($rp.Description)) {
                $rp.Description
            } else {
                $null
            }

            $lValStr = $null
            $rValStr = $null
            $lNull = $false
            $rNull = $false
            $diffKind = 'Same'
            $isDiff = $false

            if ($null -eq $lp -or $lIsSchema) {
                $lValStr = if ($lIsSchema) { '$null (parent is $null)' } else { '<Not present in Object 1>' }
                $lNull = $true
                $rValStr = if ($null -ne $rp) { "$($rp.Value)" } else { '$null' }
                $rNull = if ($null -ne $rp) { [bool]$rp.IsNull } else { $true }
                $isDiff = $true
                $diffKind = 'OnlyInB'
            } elseif ($null -eq $rp -or $rIsSchema) {
                $lValStr = "$($lp.Value)"
                $lNull = [bool]$lp.IsNull
                $rValStr = if ($rIsSchema) { '$null (parent is $null)' } else { '<Not present in Object 2>' }
                $rNull = $true
                $isDiff = $true
                $diffKind = 'OnlyInA'
            } else {
                $lValStr = "$($lp.Value)"
                $rValStr = "$($rp.Value)"
                $lNull = [bool]$lp.IsNull
                $rNull = [bool]$rp.IsNull

                if ($lValStr -cne $rValStr) {
                    $isDiff = $true
                    if ($pName -eq 'Count' -or $lValStr -match '\(Count:\s*\d+\)' -or $rValStr -match '\(Count:\s*\d+\)') {
                        $diffKind = 'ArraySize'
                    } else {
                        $diffKind = 'Changed'
                    }
                }
            }

            $rows.Add([PSCustomObject]@{
                RelPath      = $propRelPath
                Section      = (Get-TopSectionName -RelPath $propRelPath)
                PropName     = $pName
                Type         = $pType
                Description  = $pDesc
                LeftValue    = $lValStr
                RightValue   = $rValStr
                LeftIsNull   = $lNull
                RightIsNull  = $rNull
                IsMoRef      = [bool]($effProp.IsMoRef)
                IsDifferent  = $isDiff
                DiffKind     = $diffKind
            })
        }

        # Pair and recurse into children
        $rKidMap = @{}
        foreach ($rk in $rKids) {
            $kKey = Get-ChildCanonicalKey -ChildNode $rk
            if (-not [string]::IsNullOrWhiteSpace($kKey)) {
                $rKidMap[$kKey] = $rk
            }
        }
        $seenKidKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

        foreach ($lk in $lKids) {
            $kKey = Get-ChildCanonicalKey -ChildNode $lk
            if ([string]::IsNullOrWhiteSpace($kKey)) { continue }
            [void]$seenKidKeys.Add($kKey)
            $rk = if ($rKidMap.ContainsKey($kKey)) { $rKidMap[$kKey] } else { $null }
            $nextRel = if ($kKey.StartsWith('[')) { "$CurrentRelPath$kKey" } else { "$CurrentRelPath.$kKey" }
            Walk-ComparePair -LNode $lk -RNode $rk -CurrentRelPath $nextRel
        }

        foreach ($rk in $rKids) {
            $kKey = Get-ChildCanonicalKey -ChildNode $rk
            if ([string]::IsNullOrWhiteSpace($kKey)) { continue }
            if (-not $seenKidKeys.Contains($kKey)) {
                [void]$seenKidKeys.Add($kKey)
                $nextRel = if ($kKey.StartsWith('[')) { "$CurrentRelPath$kKey" } else { "$CurrentRelPath.$kKey" }
                Walk-ComparePair -LNode $null -RNode $rk -CurrentRelPath $nextRel
            }
        }
    }

    Walk-ComparePair -LNode $LeftNode -RNode $RightNode -CurrentRelPath ''
    return $rows.ToArray()
}

function New-ApiExplorerCompareHtml {
    <#
    .SYNOPSIS
        Generates a 100% offline HTML5 Side-by-Side Property Diff Table Explorer for 2 objects of the same type.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$ComparisonRows,

        [Parameter(Mandatory = $true)]
        [string]$TypeName,

        [Parameter(Mandatory = $false)]
        [string]$TypeDescription,

        [Parameter(Mandatory = $true)]
        [int]$MaxDepth,

        [Parameter(Mandatory = $true)]
        [string]$LeftRootName,

        [Parameter(Mandatory = $true)]
        [string]$RightRootName,

        [Parameter(Mandatory = $false)]
        [string]$LeftLabel,

        [Parameter(Mandatory = $false)]
        [string]$RightLabel
    )

    $jsonRows = ConvertTo-Json -InputObject @($ComparisonRows) -Depth 10 -Compress
    if ([string]::IsNullOrWhiteSpace($jsonRows)) { $jsonRows = '[]' }

    $effLeftLabel = if (-not [string]::IsNullOrWhiteSpace($LeftLabel)) { $LeftLabel } else { $LeftRootName }
    $effRightLabel = if (-not [string]::IsNullOrWhiteSpace($RightLabel)) { $RightLabel } else { $RightRootName }

    $html = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>xDlabs | ApiExplorer Compare - __LEFT_LABEL__ vs __RIGHT_LABEL__</title>
<style>
    :root {
        --bg-main: #090d16;
        --bg-panel: #111827;
        --bg-card: #151f32;
        --border-color: #2e3f5c;
        --accent-emerald: #10b981;
        --accent-cyan: #06b6d4;
        --accent-purple: #a855f7;
        --accent-amber: #f59e0b;
        --accent-rose: #f43f5e;
        --text-primary: #f8fafc;
        --text-secondary: #94a3b8;
        --text-muted: #64748b;
        --font-mono: 'Cascadia Code', 'Consolas', 'JetBrains Mono', monospace;
        --font-sans: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
        background-color: var(--bg-main);
        color: var(--text-primary);
        font-family: var(--font-sans);
        height: 100vh;
        width: 100vw;
        overflow: hidden;
        display: flex;
        flex-direction: column;
    }
    header {
        min-height: 60px;
        background: linear-gradient(90deg, #090d16 0%, #0f2942 50%, #090d16 100%);
        border-bottom: 1px solid var(--border-color);
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 8px 20px;
        gap: 14px;
        flex-wrap: wrap;
        z-index: 20;
        box-shadow: 0 4px 20px rgba(0,0,0,0.45);
    }
    .brand {
        display: flex;
        align-items: center;
        gap: 10px;
        flex-wrap: wrap;
    }
    .brand-logo {
        background: linear-gradient(135deg, var(--accent-emerald), var(--accent-cyan));
        color: #042f2e;
        font-weight: 900;
        font-family: var(--font-mono);
        padding: 5px 10px;
        border-radius: 6px;
        font-size: 14px;
        letter-spacing: 0.5px;
    }
    .brand-title { font-size: 16px; font-weight: 700; }
    .brand-subtitle {
        font-size: 12px;
        color: #34d399;
        font-family: var(--font-mono);
        background: rgba(16, 185, 129, 0.14);
        padding: 3px 8px;
        border-radius: 4px;
        border: 1px solid rgba(16, 185, 129, 0.35);
    }
    .brand-mode-pill {
        font-size: 11.5px;
        color: #fda4af;
        font-family: var(--font-mono);
        font-weight: 800;
        background: rgba(244, 63, 94, 0.16);
        padding: 3px 10px;
        border-radius: 5px;
        border: 1px solid rgba(244, 63, 94, 0.45);
    }
    .brand-type-pill {
        font-size: 12px;
        color: #67e8f9;
        font-family: var(--font-mono);
        background: rgba(6, 182, 212, 0.12);
        padding: 3px 9px;
        border-radius: 4px;
        border: 1px solid rgba(6, 182, 212, 0.35);
    }
    .brand-social-link {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 24px;
        height: 24px;
        border-radius: 5px;
        text-decoration: none;
        font-family: var(--font-sans);
        font-weight: 800;
        font-size: 12px;
        transition: all 0.15s;
    }
    .brand-li {
        background: #0a66c2;
        color: #ffffff;
        border: 1px solid rgba(255, 255, 255, 0.2);
    }
    .brand-li:hover {
        background: #004182;
        box-shadow: 0 0 10px rgba(10, 102, 194, 0.6);
    }
    .brand-gh {
        background: #1e293b;
        color: #f8fafc;
        border: 1px solid #475569;
    }
    .brand-gh:hover {
        background: #334155;
        border-color: var(--accent-emerald);
        color: #34d399;
    }
    .toolbar {
        display: flex;
        align-items: center;
        gap: 10px;
        flex-wrap: wrap;
    }
    .root-var-group {
        display: flex;
        align-items: center;
        gap: 6px;
        background: #060911;
        border: 1px solid var(--border-color);
        padding: 5px 9px;
        border-radius: 6px;
        font-size: 11px;
        color: var(--text-secondary);
        font-family: var(--font-mono);
    }
    .root-var-group input {
        width: 95px;
        background: transparent;
        border: none;
        font-family: var(--font-mono);
        font-size: 12px;
        font-weight: 700;
        outline: none;
    }
    .search-box {
        position: relative;
        width: 310px;
        display: flex;
        align-items: center;
    }
    .search-box input {
        width: 100%;
        background: #060911;
        border: 1px solid var(--border-color);
        color: var(--text-primary);
        padding: 7px 12px;
        border-radius: 6px;
        font-size: 12.5px;
        font-family: var(--font-mono);
        outline: none;
    }
    .search-box input:focus {
        border-color: var(--accent-cyan);
        box-shadow: 0 0 0 2px rgba(6, 182, 212, 0.25);
    }
    .filter-select {
        background: #060911;
        color: #e2e8f0;
        border: 1px solid var(--border-color);
        padding: 6px 10px;
        border-radius: 6px;
        font-size: 12px;
        font-family: var(--font-mono);
        outline: none;
        cursor: pointer;
    }
    .filter-toggle-label {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        background: #060911;
        border: 1px solid var(--border-color);
        padding: 6px 10px;
        border-radius: 6px;
        font-size: 12px;
        font-weight: 600;
        color: #e2e8f0;
        cursor: pointer;
        user-select: none;
    }
    .filter-toggle-label:hover {
        border-color: var(--accent-emerald);
    }
    .filter-toggle-label input {
        accent-color: var(--accent-emerald);
        cursor: pointer;
    }
    .summary-strip {
        background: #0d1424;
        border-bottom: 1px solid var(--border-color);
        padding: 10px 24px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 16px;
        flex-wrap: wrap;
    }
    .summary-pills {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-wrap: wrap;
    }
    .stat-tab {
        background: #131c2e;
        border: 1px solid #2e3f5c;
        color: #cbd5e1;
        font-family: var(--font-mono);
        font-size: 11.5px;
        font-weight: 700;
        padding: 5px 12px;
        border-radius: 6px;
        cursor: pointer;
        transition: all 0.15s;
    }
    .stat-tab:hover {
        border-color: var(--accent-cyan);
        color: #fff;
    }
    .stat-tab.active {
        background: rgba(244, 63, 94, 0.2);
        border-color: #f43f5e;
        color: #fda4af;
        box-shadow: 0 0 12px rgba(244, 63, 94, 0.25);
    }
    .stat-tab.active-all {
        background: rgba(6, 182, 212, 0.2);
        border-color: var(--accent-cyan);
        color: #67e8f9;
    }
    .table-viewport {
        flex: 1;
        overflow-y: auto;
        padding: 16px 24px 40px 24px;
    }
    .compare-table {
        width: 100%;
        border-collapse: separate;
        border-spacing: 0;
        background: #0e1626;
        border: 1px solid var(--border-color);
        border-radius: 8px;
        overflow: hidden;
        box-shadow: 0 10px 30px rgba(0, 0, 0, 0.55);
    }
    .compare-table thead th {
        position: sticky;
        top: 0;
        z-index: 10;
        background: #162238;
        padding: 12px 14px;
        text-align: left;
        font-family: var(--font-mono);
        font-size: 12px;
        font-weight: 800;
        color: #e2e8f0;
        border-bottom: 2px solid #2e3f5c;
        letter-spacing: 0.4px;
    }
    .th-obj-a {
        color: #67e8f9 !important;
        border-left: 1px solid #2e3f5c;
        background: linear-gradient(180deg, rgba(6, 182, 212, 0.16) 0%, #162238 100%) !important;
    }
    .th-obj-b {
        color: #fcd34d !important;
        border-left: 1px solid #2e3f5c;
        background: linear-gradient(180deg, rgba(245, 158, 11, 0.16) 0%, #162238 100%) !important;
    }
    .compare-table tbody tr {
        transition: background 0.12s;
    }
    .compare-table tbody tr:hover {
        background: rgba(30, 41, 59, 0.75) !important;
    }
    .compare-table td {
        padding: 10px 14px;
        border-bottom: 1px solid rgba(46, 63, 92, 0.55);
        vertical-align: top;
        font-family: var(--font-mono);
        font-size: 12px;
    }
    .tr-diff-changed {
        background: rgba(244, 63, 94, 0.06);
    }
    .tr-diff-array {
        background: rgba(168, 85, 247, 0.08);
    }
    .tr-diff-only {
        background: rgba(56, 189, 248, 0.07);
    }
    .td-path-cell {
        width: 38%;
        max-width: 560px;
    }
    .td-val-a {
        width: 28%;
        border-left: 1px solid rgba(46, 63, 92, 0.55);
    }
    .td-val-b {
        width: 28%;
        border-left: 1px solid rgba(46, 63, 92, 0.55);
    }
    .td-actions {
        width: 6%;
        white-space: nowrap;
        text-align: right;
        border-left: 1px solid rgba(46, 63, 92, 0.55);
    }
    .path-top-row {
        display: flex;
        align-items: center;
        gap: 7px;
        flex-wrap: wrap;
    }
    .section-pill {
        font-size: 10px;
        font-weight: 800;
        padding: 1px 6px;
        border-radius: 4px;
        background: #1e293b;
        color: #93c5fd;
        border: 1px solid #334155;
    }
    .prop-path-code {
        color: #f8fafc;
        font-weight: 700;
        font-size: 12.5px;
        word-break: break-all;
    }
    .prop-type-line {
        color: var(--accent-cyan);
        font-size: 11px;
        margin-top: 3px;
        word-break: break-all;
    }
    .diff-badge {
        font-size: 9.5px;
        font-weight: 900;
        padding: 1px 6px;
        border-radius: 3px;
        letter-spacing: 0.4px;
    }
    .diff-badge-changed {
        background: rgba(244, 63, 94, 0.22);
        color: #fda4af;
        border: 1px solid rgba(244, 63, 94, 0.55);
    }
    .diff-badge-array {
        background: rgba(168, 85, 247, 0.25);
        color: #e9d5ff;
        border: 1px solid rgba(168, 85, 247, 0.55);
    }
    .diff-badge-only-a {
        background: rgba(6, 182, 212, 0.22);
        color: #67e8f9;
        border: 1px solid rgba(6, 182, 212, 0.55);
    }
    .diff-badge-only-b {
        background: rgba(245, 158, 11, 0.22);
        color: #fde68a;
        border: 1px solid rgba(245, 158, 11, 0.55);
    }
    .diff-badge-same {
        background: rgba(16, 185, 129, 0.16);
        color: #6ee7b7;
        border: 1px solid rgba(16, 185, 129, 0.4);
    }
    .val-box-a {
        display: inline-block;
        color: #67e8f9;
        font-weight: 700;
        background: rgba(6, 182, 212, 0.11);
        border: 1px solid rgba(6, 182, 212, 0.32);
        padding: 4px 8px;
        border-radius: 5px;
        word-break: break-word;
    }
    .val-box-b {
        display: inline-block;
        color: #fde68a;
        font-weight: 700;
        background: rgba(245, 158, 11, 0.12);
        border: 1px solid rgba(245, 158, 11, 0.35);
        padding: 4px 8px;
        border-radius: 5px;
        word-break: break-word;
    }
    .val-box-same {
        color: #94a3b8;
        word-break: break-word;
    }
    .val-box-missing {
        display: inline-block;
        color: #fb7185;
        font-style: italic;
        background: rgba(244, 63, 94, 0.1);
        border: 1px dashed rgba(244, 63, 94, 0.4);
        padding: 3px 8px;
        border-radius: 5px;
    }
    .val-cell-footer {
        margin-top: 6px;
        display: flex;
        align-items: center;
        gap: 6px;
        flex-wrap: wrap;
    }
    .mini-copy-btn {
        background: #1e293b;
        border: 1px solid #475569;
        color: #cbd5e1;
        border-radius: 4px;
        padding: 2px 7px;
        font-size: 10px;
        font-family: var(--font-mono);
        cursor: pointer;
    }
    .mini-copy-btn:hover {
        border-color: var(--accent-emerald);
        color: #6ee7b7;
    }
    .doc-desc {
        margin-top: 5px;
        font-family: var(--font-sans);
        font-size: 11px;
        line-height: 1.4;
        color: #94a3b8;
        background: rgba(15, 23, 42, 0.65);
        border-left: 2px solid #38bdf8;
        padding: 4px 7px;
        border-radius: 0 4px 4px 0;
    }
    body.hide-docs .doc-desc {
        display: none !important;
    }
    .doc-exp-btn {
        display: inline-block;
        margin-left: 5px;
        color: var(--accent-emerald);
        font-family: var(--font-mono);
        font-weight: 800;
        font-size: 10.5px;
        cursor: pointer;
        background: rgba(16, 185, 129, 0.14);
        border: 1px solid rgba(16, 185, 129, 0.4);
        padding: 0 5px;
        border-radius: 3px;
        user-select: none;
    }
    mark.hl {
        background: rgba(245, 158, 11, 0.45);
        color: #fef08a;
        padding: 0 2px;
        border-radius: 2px;
        font-weight: 700;
    }
    .empty-state {
        text-align: center;
        padding: 45px 20px;
        color: var(--text-secondary);
        font-family: var(--font-mono);
        font-size: 13px;
    }
    .toast {
        position: fixed;
        bottom: 24px;
        right: 24px;
        background: var(--accent-emerald);
        color: #022c22;
        padding: 8px 16px;
        border-radius: 6px;
        font-weight: 700;
        font-size: 12px;
        font-family: var(--font-mono);
        opacity: 0;
        pointer-events: none;
        transition: opacity 0.2s;
        z-index: 100;
    }
    .toast.show { opacity: 1; }
</style>
</head>
<body>
<header>
    <div class="brand">
        <a href="https://xdlabs.info" target="_blank" rel="noopener noreferrer" style="text-decoration:none;" title="Visit https://xdlabs.info"><span class="brand-logo" style="cursor:pointer;">xDlabs</span></a>
        <a class="brand-social-link brand-li" href="https://www.linkedin.com/company/xdlabs/home/" target="_blank" rel="noopener noreferrer" title="xDlabs on LinkedIn">in</a>
        <a class="brand-social-link brand-gh" href="https://github.com/qlikq/xDPsApiExplorer" target="_blank" rel="noopener noreferrer" title="xDPsApiExplorer on GitHub"><svg viewBox="0 0 16 16" width="14" height="14" fill="currentColor"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"></path></svg></a>
        <span class="brand-title">ApiExplorer</span>
        <span class="brand-mode-pill">OBJECT COMPARISON MODE</span>
        <span class="brand-type-pill">[__TYPE_NAME__]</span>
        <span class="brand-subtitle">MaxDepth: __MAX_DEPTH__</span>
    </div>
    <div class="toolbar">
        <div class="root-var-group" title="First Object PowerShell variable name">
            <span style="color:#67e8f9;">First Object:</span>
            <input type="text" id="leftVarInput" value="__LEFT_ROOT_NAME__" style="color:#67e8f9;" />
        </div>
        <div class="root-var-group" title="Second Object PowerShell variable name">
            <span style="color:#fcd34d;">Second Object:</span>
            <input type="text" id="rightVarInput" value="__RIGHT_ROOT_NAME__" style="color:#fcd34d;" />
        </div>
        <div class="search-box">
            <input type="text" id="searchInput" placeholder="Filter by property path, [Type], or values..." />
        </div>
        <select class="filter-select" id="sectionFilter" title="Filter properties by top-level object section">
            <option value="ALL">All Sections</option>
        </select>
        <label class="filter-toggle-label" title="Show/hide official Broadcom vSphere SDK documentation descriptions">
            <input type="checkbox" id="chkShowDocs" checked />
            <span>Show Docs</span>
        </label>
    </div>
</header>

<div class="summary-strip">
    <div class="summary-pills">
        <button class="stat-tab active" id="tabOnlyDiffs" onclick="setDiffFilterMode('DIFFS')">
            ShowDifferent (<span id="countAllDiffs">0</span>)
        </button>
        <button class="stat-tab" id="tabChanged" onclick="setDiffFilterMode('CHANGED')">
            Value Differences (<span id="countChanged">0</span>)
        </button>
        <button class="stat-tab" id="tabIncludeEqual" onclick="setDiffFilterMode('ALL')">
            IncludeEqual (<span id="countTotal">0</span>)
        </button>
    </div>
    <div style="font-family:var(--font-mono);font-size:12px;color:#94a3b8;">
        Showing <strong id="visibleRowsCount" style="color:#f8fafc;">0</strong> rows
    </div>
</div>

<div class="table-viewport">
    <table class="compare-table">
        <thead>
            <tr>
                <th>PROPERTY PATH &amp; [FULL TYPE]</th>
                <th class="th-obj-a" id="thLeftHeader">__LEFT_HEADER__</th>
                <th class="th-obj-b" id="thRightHeader">__RIGHT_HEADER__</th>
                <th style="text-align:right;">COPY</th>
            </tr>
        </thead>
        <tbody id="compareTableBody"></tbody>
    </table>
</div>

<div class="toast" id="toastMsg">Copied!</div>

<script>
const COMPARE_ROWS = __JSON_ROWS__;
let leftVarName = "__LEFT_ROOT_NAME__";
let rightVarName = "__RIGHT_ROOT_NAME__";
const LEFT_LABEL = "__LEFT_LABEL__";
const RIGHT_LABEL = "__RIGHT_LABEL__";

let diffFilterMode = 'DIFFS'; // Default: show only properties where values are different
let expandedDocsSet = new Set();

function escapeHtml(str) {
    if (str === null || str === undefined) return '';
    return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function escapeJs(str) {
    if (!str) return '';
    return String(str).replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

function highlightMatchText(str, q) {
    const safe = escapeHtml(str);
    if (!q) return safe;
    const escapedQ = escapeHtml(q).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    if (!escapedQ) return safe;
    const re = new RegExp(`(${escapedQ})`, 'gi');
    return safe.replace(re, '<mark class="hl">$1</mark>');
}

function getShortDocSnippet(text) {
    if (!text) return { short: '', isTruncated: false };
    const clean = String(text).trim();
    if (clean.length <= 200) return { short: clean, isTruncated: false };
    const sentenceRegex = /[^.!?]+[.!?]+(\s|$)/g;
    let match;
    let endIdx = 0;
    let sentences = 0;
    while ((match = sentenceRegex.exec(clean)) !== null) {
        endIdx = sentenceRegex.lastIndex;
        sentences++;
        if (sentences >= 2 || endIdx >= 180) break;
    }
    if (endIdx >= 60 && endIdx < clean.length) {
        return { short: clean.substring(0, endIdx).trim(), isTruncated: true };
    }
    return { short: clean.substring(0, 185).trim() + '...', isTruncated: true };
}

function renderExpandableDocHtml(docKey, fullText, query) {
    if (!fullText) return '';
    const isExp = expandedDocsSet.has(docKey);
    const snippetInfo = getShortDocSnippet(fullText);
    if (!snippetInfo.isTruncated) {
        return highlightMatchText(fullText, query);
    }
    if (isExp) {
        return `${highlightMatchText(fullText, query)} <span class="doc-exp-btn" onclick="toggleDocExpand('${escapeJs(docKey)}', event)" title="Collapse description">[-]</span>`;
    } else {
        return `${highlightMatchText(snippetInfo.short, query)} <span class="doc-exp-btn" onclick="toggleDocExpand('${escapeJs(docKey)}', event)" title="Expand full description">[+]</span>`;
    }
}

function toggleDocExpand(docKey, ev) {
    if (ev) ev.stopPropagation();
    if (expandedDocsSet.has(docKey)) {
        expandedDocsSet.delete(docKey);
    } else {
        expandedDocsSet.add(docKey);
    }
    renderCompareTable();
}

function initCountersAndSections() {
    let diffCount = 0;
    let changedCount = 0;
    const sections = new Set();

    COMPARE_ROWS.forEach(r => {
        if (r.Section) sections.add(r.Section);
        if (r.IsDifferent) {
            diffCount++;
            if (r.DiffKind === 'Changed') changedCount++;
        }
    });

    document.getElementById('countAllDiffs').textContent = String(diffCount);
    document.getElementById('countChanged').textContent = String(changedCount);
    document.getElementById('countTotal').textContent = String(COMPARE_ROWS.length);

    const secSelect = document.getElementById('sectionFilter');
    Array.from(sections).sort().forEach(sec => {
        const opt = document.createElement('option');
        opt.value = sec;
        opt.textContent = `Section: ${sec}`;
        secSelect.appendChild(opt);
    });
}

function setDiffFilterMode(mode) {
    diffFilterMode = mode;
    document.getElementById('tabOnlyDiffs').className = 'stat-tab' + (mode === 'DIFFS' ? ' active' : '');
    document.getElementById('tabChanged').className = 'stat-tab' + (mode === 'CHANGED' ? ' active' : '');
    document.getElementById('tabIncludeEqual').className = 'stat-tab' + (mode === 'ALL' ? ' active-all' : '');
    renderCompareTable();
}

function buildFullPsPath(rootVar, relPath) {
    if (!relPath) return rootVar;
    if (relPath.startsWith('.') || relPath.startsWith('[')) {
        return rootVar + relPath;
    }
    return rootVar + '.' + relPath;
}

let userEditedLeftVar = false;
let userEditedRightVar = false;

function renderCompareTable() {
    const q = (document.getElementById('searchInput').value || '').trim().toLowerCase();
    const secFilter = document.getElementById('sectionFilter').value || 'ALL';
    document.getElementById('thLeftHeader').textContent = userEditedLeftVar ? leftVarName : LEFT_LABEL;
    document.getElementById('thRightHeader').textContent = userEditedRightVar ? rightVarName : RIGHT_LABEL;

    const filtered = COMPARE_ROWS.filter(r => {
        if (diffFilterMode === 'DIFFS' && !r.IsDifferent) return false;
        if (diffFilterMode === 'CHANGED' && r.DiffKind !== 'Changed') return false;
        if (secFilter !== 'ALL' && r.Section !== secFilter) return false;

        if (q.length > 0) {
            const pathHit = (r.RelPath && r.RelPath.toLowerCase().includes(q));
            const typeHit = (r.Type && r.Type.toLowerCase().includes(q));
            const lHit = (r.LeftValue !== null && r.LeftValue !== undefined && String(r.LeftValue).toLowerCase().includes(q));
            const rHit = (r.RightValue !== null && r.RightValue !== undefined && String(r.RightValue).toLowerCase().includes(q));
            return pathHit || typeHit || lHit || rHit;
        }
        return true;
    });

    document.getElementById('visibleRowsCount').textContent = String(filtered.length);
    const tbody = document.getElementById('compareTableBody');

    if (filtered.length === 0) {
        tbody.innerHTML = `<tr><td colspan="4" class="empty-state">No properties match the current filter criteria.</td></tr>`;
        return;
    }

    const leftColTitle = userEditedLeftVar ? leftVarName : LEFT_LABEL;
    const rightColTitle = userEditedRightVar ? rightVarName : RIGHT_LABEL;

    tbody.innerHTML = filtered.map((r, idx) => {
        const leftPath = buildFullPsPath(leftVarName, r.RelPath);
        const rightPath = buildFullPsPath(rightVarName, r.RelPath);
        const docKey = 'cmp_doc_' + idx + '_' + r.RelPath;

        let trClass = '';
        let badgeHtml = '<span class="diff-badge diff-badge-same">IDENTICAL</span>';
        if (r.DiffKind === 'Changed') {
            trClass = 'tr-diff-changed';
            badgeHtml = '<span class="diff-badge diff-badge-changed">VALUE DIFF</span>';
        } else if (r.DiffKind === 'ArraySize') {
            trClass = 'tr-diff-array';
            badgeHtml = '<span class="diff-badge diff-badge-array">ARRAY COUNT DIFF</span>';
        } else if (r.DiffKind === 'OnlyInA') {
            trClass = 'tr-diff-only';
            badgeHtml = `<span class="diff-badge diff-badge-only-a">ONLY IN ${escapeHtml(leftColTitle.toUpperCase())}</span>`;
        } else if (r.DiffKind === 'OnlyInB') {
            trClass = 'tr-diff-only';
            badgeHtml = `<span class="diff-badge diff-badge-only-b">ONLY IN ${escapeHtml(rightColTitle.toUpperCase())}</span>`;
        }

        const valAClass = !r.IsDifferent
            ? 'val-box-same'
            : (r.DiffKind === 'OnlyInB' ? 'val-box-missing' : 'val-box-a');
        const valBClass = !r.IsDifferent
            ? 'val-box-same'
            : (r.DiffKind === 'OnlyInA' ? 'val-box-missing' : 'val-box-b');

        const compareCmd = `Compare-Object (${leftPath}) (${rightPath})`;

        return `
        <tr class="${trClass}">
            <td class="td-path-cell">
                <div class="path-top-row">
                    <span class="section-pill">${escapeHtml(r.Section)}</span>
                    <code class="prop-path-code">${highlightMatchText(r.RelPath, q)}</code>
                    ${badgeHtml}
                </div>
                <div class="prop-type-line">[${highlightMatchText(r.Type, q)}]</div>
                ${r.Description ? `<div class="doc-desc">${renderExpandableDocHtml(docKey, r.Description, q)}</div>` : ''}
            </td>
            <td class="td-val-a">
                <div class="${valAClass}">${highlightMatchText(String(r.LeftValue ?? ''), q)}</div>
                <div class="val-cell-footer">
                    <button class="mini-copy-btn" onclick="copyText('${escapeJs(leftPath)}')" title="Copy ${escapeHtml(leftPath)}">Copy Path</button>
                    ${r.IsMoRef && r.DiffKind !== 'OnlyInB' ? `<button class="mini-copy-btn" onclick="copyText('Get-View -Id ${escapeJs(leftPath)}')">Copy Get-View</button>` : ''}
                </div>
            </td>
            <td class="td-val-b">
                <div class="${valBClass}">${highlightMatchText(String(r.RightValue ?? ''), q)}</div>
                <div class="val-cell-footer">
                    <button class="mini-copy-btn" onclick="copyText('${escapeJs(rightPath)}')" title="Copy ${escapeHtml(rightPath)}">Copy Path</button>
                    ${r.IsMoRef && r.DiffKind !== 'OnlyInA' ? `<button class="mini-copy-btn" onclick="copyText('Get-View -Id ${escapeJs(rightPath)}')">Copy Get-View</button>` : ''}
                </div>
            </td>
            <td class="td-actions">
                <button class="mini-copy-btn" onclick="copyText('${escapeJs(compareCmd)}')" title="Copy PowerShell Compare-Object expression">Copy Diff</button>
            </td>
        </tr>
        `;
    }).join('');
}

document.getElementById('leftVarInput').addEventListener('input', (e) => {
    let val = e.target.value.trim();
    if (!val) val = '$firstObj';
    if (!val.startsWith('$')) val = '$' + val;
    leftVarName = val;
    userEditedLeftVar = true;
    renderCompareTable();
});

document.getElementById('rightVarInput').addEventListener('input', (e) => {
    let val = e.target.value.trim();
    if (!val) val = '$secondObj';
    if (!val.startsWith('$')) val = '$' + val;
    rightVarName = val;
    userEditedRightVar = true;
    renderCompareTable();
});

document.getElementById('searchInput').addEventListener('input', () => {
    renderCompareTable();
});

document.getElementById('sectionFilter').addEventListener('change', () => {
    renderCompareTable();
});

document.getElementById('chkShowDocs').addEventListener('change', (e) => {
    if (e.target.checked) {
        document.body.classList.remove('hide-docs');
    } else {
        document.body.classList.add('hide-docs');
    }
});

function showToast(msg) {
    const toast = document.getElementById('toastMsg');
    toast.textContent = msg;
    toast.classList.add('show');
    setTimeout(() => toast.classList.remove('show'), 2000);
}

function copyText(txt) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(txt);
    } else {
        const ta = document.createElement('textarea');
        ta.value = txt;
        document.body.appendChild(ta);
        ta.select();
        document.execCommand('copy');
        document.body.removeChild(ta);
    }
    showToast('Copied: ' + txt);
}

initCountersAndSections();
renderCompareTable();
</script>
</body>
</html>
'@

    $html = $html.Replace('__TYPE_NAME__', $TypeName)
    $html = $html.Replace('__MAX_DEPTH__', "$MaxDepth")
    $html = $html.Replace('__LEFT_ROOT_NAME__', $LeftRootName)
    $html = $html.Replace('__RIGHT_ROOT_NAME__', $RightRootName)
    $html = $html.Replace('__LEFT_HEADER__', $effLeftLabel)
    $html = $html.Replace('__RIGHT_HEADER__', $effRightLabel)
    $html = $html.Replace('__LEFT_LABEL__', $effLeftLabel)
    $html = $html.Replace('__RIGHT_LABEL__', $effRightLabel)
    $html = $html.Replace('__JSON_ROWS__', $jsonRows)
    return $html
}
