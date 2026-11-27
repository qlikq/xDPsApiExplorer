function ConvertTo-ApiNodeTree {
    <#
    .SYNOPSIS
        Inspects a PowerShell/.NET object using both live instance data and .NET Reflection,
        producing a hierarchical node tree with full .NET type names suitable for interactive API visualization.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $false)]
        [System.Type]$DeclaredType,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$PsPath,

        [Parameter(Mandatory = $true)]
        [int]$MaxDepth,

        [Parameter(Mandatory = $false)]
        [int]$CurrentDepth = 0,

        [Parameter(Mandatory = $false)]
        [int]$MaxCollectionItems = 5,

        [Parameter(Mandatory = $false)]
        [bool]$IncludeMethods = $true,

        [Parameter(Mandatory = $false)]
        [System.Collections.Generic.HashSet[int]]$VisitedIds,

        [Parameter(Mandatory = $false)]
        [bool]$IsSchemaOnly = $false
    )

    if ($null -eq $VisitedIds) {
        $VisitedIds = New-Object 'System.Collections.Generic.HashSet[int]'
    }

    # Unwrap PSObject if needed (never unwrap PSCustomObject, whose BaseObject is a shared singleton)
    $rawObj = $InputObject
    if ($null -ne $rawObj -and $rawObj -is [psobject]) {
        $baseObj = $rawObj.PSObject.BaseObject
        if ($null -ne $baseObj -and $baseObj -isnot [System.Management.Automation.PSCustomObject]) {
            $rawObj = $baseObj
        }
    }

    $actualType = $null
    if ($null -ne $rawObj) {
        $actualType = $rawObj.GetType()
    } elseif ($null -ne $DeclaredType) {
        $actualType = $DeclaredType
        $IsSchemaOnly = $true
    }

    $typeName = if ($null -ne $actualType) { Get-FriendlyTypeName -Type $actualType } else { 'System.Object' }
    $fullTypeName = if ($null -ne $actualType -and -not [string]::IsNullOrWhiteSpace($actualType.FullName)) { $actualType.FullName } else { $typeName }
    $typeDescription = Get-VSphereTypeDescription -Type $actualType

    # Detect VMware MoRef (ManagedObjectReference)
    $isMoRef = $false
    $moRefValue = $null
    $moRefCmd = $null
    if ($null -ne $actualType -and ($actualType.Name -eq 'ManagedObjectReference' -or $fullTypeName -like '*ManagedObjectReference*')) {
        $isMoRef = $true
        if ($null -ne $rawObj) {
            try {
                $mType = $rawObj.Type
                $mVal = $rawObj.Value
                $moRefValue = "$mType-$mVal"
            } catch {
                $moRefValue = "$rawObj"
            }
        }
        $moRefCmd = "Get-View -Id $PsPath"
    }

    $nodeId = "node_" + ([guid]::NewGuid().ToString("N").Substring(0, 10))
    $scalarProperties = New-Object System.Collections.Generic.List[object]
    $methodsList = New-Object System.Collections.Generic.List[object]
    $childrenList = New-Object System.Collections.Generic.List[object]

    $isCollection = $false
    $collectionCount = $null
    $isCycle = $false
    $truncatedByDepth = $false

    # Cycle detection for live reference types
    $objHash = 0
    $trackedInPath = $false
    if ($null -ne $rawObj -and -not $actualType.IsValueType -and $actualType -ne [string]) {
        $objHash = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($rawObj)
        if ($VisitedIds.Contains($objHash)) {
            $isCycle = $true
        } else {
            [void]$VisitedIds.Add($objHash)
            $trackedInPath = $true
        }
    }

    try {
        # Collect Methods on this type (always inspect root object even if it is a simple type like System.String or System.DateTime)
        if ($IncludeMethods -and $null -ne $actualType -and ($CurrentDepth -eq 0 -or -not (Test-IsSimpleType -Type $actualType))) {
            $ignoredMethods = @(
                'Equals', 'GetHashCode', 'GetType', 'ToString',
                'CompareTo', 'Clone', 'CopyTo', 'GetEnumerator'
            )
            $rawMethods = $actualType.GetMethods([System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Instance) |
                Where-Object { -not $_.IsSpecialName -and ($ignoredMethods -notcontains $_.Name) }

            $groupedMethods = $rawMethods | Group-Object -Property Name | Sort-Object -Property Name
            foreach ($mGroup in $groupedMethods) {
                $mInfo = $mGroup.Group[0]
                $params = $mInfo.GetParameters()
                $paramSigParts = @()
                $paramCallParts = @()
                foreach ($p in $params) {
                    $pType = Get-FriendlyTypeName -Type $p.ParameterType
                    $paramSigParts += "[$pType] `$$($p.Name)"
                    $paramCallParts += "`$$($p.Name)"
                }
                $returnType = Get-FriendlyTypeName -Type $mInfo.ReturnType
                $signature = "$($mInfo.Name)($($paramSigParts -join ', '))"
                $callSnippet = "$PsPath.$($mInfo.Name)($($paramCallParts -join ', '))"
                $isTask = $mInfo.Name -like '*_Task'
                $mDesc = Get-VSphereMemberDescription -Type $actualType -MemberName $mInfo.Name -IsMethod $true

                $methodsList.Add([PSCustomObject]@{
                    Name        = $mInfo.Name
                    ReturnType  = $returnType
                    Signature   = $signature
                    CallSnippet = $callSnippet
                    Overloads   = $mGroup.Count
                    IsTask      = $isTask
                    Description = $mDesc
                })
            }

            if ($null -ne $InputObject -and $InputObject -is [psobject]) {
                foreach ($psMethod in $InputObject.PSObject.Methods) {
                    if ($ignoredMethods -notcontains $psMethod.Name -and -not ($methodsList | Where-Object { $_.Name -eq $psMethod.Name })) {
                        $methodsList.Add([PSCustomObject]@{
                            Name        = $psMethod.Name
                            ReturnType  = 'System.Management.Automation.PSObject'
                            Signature   = "$($psMethod.Name)()"
                            CallSnippet = "$PsPath.$($psMethod.Name)()"
                            Overloads   = 1
                            IsTask      = ($psMethod.Name -like '*_Task')
                        })
                    }
                }
            }
        }

        if (-not $isCycle -and $null -ne $actualType) {
            # Check if collection / array
            if ((Test-IsCollectionType -Type $actualType) -and $actualType -ne [string]) {
                $isCollection = $true
                $elemType = Get-CollectionElementType -Type $actualType
                $elemTypeName = if ($null -ne $elemType) { Get-FriendlyTypeName -Type $elemType } else { 'System.Object' }

                if ($null -ne $rawObj -and -not $IsSchemaOnly) {
                    $itemsArray = @($rawObj)
                    $collectionCount = $itemsArray.Count

                    $scalarProperties.Add([PSCustomObject]@{
                        Name        = 'Count'
                        Type        = 'System.Int32'
                        FullType    = 'System.Int32'
                        Value       = "$collectionCount"
                        PsPath      = "$PsPath.Count"
                        IsNull      = $false
                        IsMoRef     = $false
                        MoRefCmd    = $null
                    })

                    if ($collectionCount -gt 0) {
                        $limit = [Math]::Min($collectionCount, $MaxCollectionItems)
                        for ($i = 0; $i -lt $limit; $i++) {
                            $itemVal = $itemsArray[$i]
                            $itemPath = "$PsPath[$i]"
                            $itemType = if ($null -ne $itemVal) { $itemVal.GetType() } else { $elemType }
                            $itemTypeName = if ($null -ne $itemType) { Get-FriendlyTypeName -Type $itemType } else { $elemTypeName }

                            if ($null -ne $itemType -and (Test-IsSimpleType -Type $itemType)) {
                                $scalarProperties.Add([PSCustomObject]@{
                                    Name     = "[$i]"
                                    Type     = $itemTypeName
                                    FullType = $itemType.FullName
                                    Value    = (Format-ScalarValue -Value $itemVal)
                                    PsPath   = $itemPath
                                    IsNull   = ($null -eq $itemVal)
                                    IsMoRef  = $false
                                    MoRefCmd = $null
                                })
                            } else {
                                # Build a concise preview summary of the element's scalar properties for the parent collection's Properties table
                                $itemPreview = Get-ObjectInlinePreview -Object $itemVal -Type $itemType
                                $itemIsMoRef = ($null -ne $itemType -and ($itemType.Name -eq 'ManagedObjectReference' -or $itemType.FullName -like '*ManagedObjectReference*'))
                                $scalarProperties.Add([PSCustomObject]@{
                                    Name     = "[$i]"
                                    Type     = $itemTypeName
                                    FullType = $itemTypeName
                                    Value    = $itemPreview
                                    PsPath   = $itemPath
                                    IsNull   = ($null -eq $itemVal)
                                    IsMoRef  = $itemIsMoRef
                                    MoRefCmd = if ($itemIsMoRef) { "Get-View -Id $itemPath" } else { $null }
                                })

                                # IMPORTANT: Unwrapping collection elements [0], [1] does NOT consume an extra MaxDepth level!
                                # Unless the element itself is another collection, we keep CurrentDepth so $vm.Guest.IpStack[0].IpRouteConfig.IpRoute[0] works within expected depth.
                                $nextDepthForElement = if ($null -ne $itemType -and (Test-IsCollectionType -Type $itemType)) { $CurrentDepth + 1 } else { $CurrentDepth }

                                if ($nextDepthForElement -le $MaxDepth) {
                                    $itemLabel = "[$i]"
                                    if ($null -ne $itemVal) {
                                        try {
                                            if ($null -ne $itemVal.Name) {
                                                $itemLabel = "[$i] ($($itemVal.Name))"
                                            } elseif ($null -ne $itemVal.DeviceInfo -and $null -ne $itemVal.DeviceInfo.Label) {
                                                $itemLabel = "[$i] ($($itemVal.DeviceInfo.Label))"
                                            } elseif ($null -ne $itemVal.Network) {
                                                $itemLabel = "[$i] ($($itemVal.Network)/$($itemVal.PrefixLength))"
                                            } elseif ($null -ne $itemVal.IpAddress) {
                                                $itemLabel = "[$i] ($($itemVal.IpAddress))"
                                            } elseif ($null -ne $itemVal.Key) {
                                                $itemLabel = "[$i] (Key: $($itemVal.Key))"
                                            }
                                        } catch {}
                                    }
                                    $childNode = ConvertTo-ApiNodeTree `
                                        -InputObject $itemVal `
                                        -DeclaredType $elemType `
                                        -Name $itemLabel `
                                        -PsPath $itemPath `
                                        -MaxDepth $MaxDepth `
                                        -CurrentDepth $nextDepthForElement `
                                        -MaxCollectionItems $MaxCollectionItems `
                                        -IncludeMethods $IncludeMethods `
                                        -VisitedIds $VisitedIds `
                                        -IsSchemaOnly ($null -eq $itemVal)
                                    $childrenList.Add($childNode)
                                } else {
                                    $truncatedByDepth = $true
                                }
                            }
                        }
                        if ($collectionCount -gt $MaxCollectionItems) {
                            $remaining = $collectionCount - $MaxCollectionItems
                            $scalarProperties.Add([PSCustomObject]@{
                                Name     = "... (+$remaining more)"
                                Type     = "$elemTypeName[]"
                                FullType = if ($null -ne $elemType) { $elemType.FullName } else { 'System.Object' }
                                Value    = "Sampled first $MaxCollectionItems of $collectionCount items (use -MaxCollectionItems to increase)"
                                PsPath   = $PsPath
                                IsNull   = $false
                                IsMoRef  = $false
                                MoRefCmd = $null
                            })
                        }
                    } elseif ($null -ne $elemType -and -not (Test-IsSimpleType -Type $elemType)) {
                        # Empty array -> inspect element schema via reflection (1 level deep)
                        if ($CurrentDepth -lt $MaxDepth) {
                            $childNode = ConvertTo-ApiNodeTree `
                                -InputObject $null `
                                -DeclaredType $elemType `
                                -Name "[0] (Schema)" `
                                -PsPath "$PsPath[0]" `
                                -MaxDepth ([Math]::Min($MaxDepth, $CurrentDepth + 1)) `
                                -CurrentDepth ($CurrentDepth + 1) `
                                -MaxCollectionItems $MaxCollectionItems `
                                -IncludeMethods $IncludeMethods `
                                -VisitedIds $VisitedIds `
                                -IsSchemaOnly $true
                            $childrenList.Add($childNode)
                        } else {
                            $truncatedByDepth = $true
                        }
                    }
                } else {
                    # Null/Schema collection
                    $collectionCount = 0
                    if ($null -ne $elemType -and -not (Test-IsSimpleType -Type $elemType)) {
                        if ($CurrentDepth -lt $MaxDepth) {
                            $childNode = ConvertTo-ApiNodeTree `
                                -InputObject $null `
                                -DeclaredType $elemType `
                                -Name "[0] (Schema)" `
                                -PsPath "$PsPath[0]" `
                                -MaxDepth ([Math]::Min($MaxDepth, $CurrentDepth + 1)) `
                                -CurrentDepth ($CurrentDepth + 1) `
                                -MaxCollectionItems $MaxCollectionItems `
                                -IncludeMethods $IncludeMethods `
                                -VisitedIds $VisitedIds `
                                -IsSchemaOnly $true
                            $childrenList.Add($childNode)
                        } else {
                            $truncatedByDepth = $true
                        }
                    }
                }
            }
            elseif ($CurrentDepth -eq 0 -or -not (Test-IsSimpleType -Type $actualType)) {
                # Complex object (class / struct / PSCustomObject / IDictionary)
                if ($rawObj -is [System.Collections.IDictionary]) {
                    foreach ($key in $rawObj.Keys) {
                        $val = $rawObj[$key]
                        $valType = if ($null -ne $val) { $val.GetType() } else { [object] }
                        $keyStr = "$key"
                        $childPath = if ($keyStr -match '^[a-zA-Z_][a-zA-Z0-9_]*$') { "$PsPath.$keyStr" } else { "$PsPath['$keyStr']" }
                        if ($null -eq $val -or (Test-IsSimpleType -Type $valType)) {
                            $scalarProperties.Add([PSCustomObject]@{
                                Name     = $keyStr
                                Type     = (Get-FriendlyTypeName -Type $valType)
                                FullType = $valType.FullName
                                Value    = (Format-ScalarValue -Value $val)
                                PsPath   = $childPath
                                IsNull   = ($null -eq $val)
                                IsMoRef  = $false
                                MoRefCmd = $null
                            })
                        } elseif ($CurrentDepth -lt $MaxDepth) {
                            $childNode = ConvertTo-ApiNodeTree `
                                -InputObject $val `
                                -DeclaredType $valType `
                                -Name $keyStr `
                                -PsPath $childPath `
                                -MaxDepth $MaxDepth `
                                -CurrentDepth ($CurrentDepth + 1) `
                                -MaxCollectionItems $MaxCollectionItems `
                                -IncludeMethods $IncludeMethods `
                                -VisitedIds $VisitedIds `
                                -IsSchemaOnly $false
                            $childrenList.Add($childNode)
                        } else {
                            $truncatedByDepth = $true
                        }
                    }
                } else {
                    # Collect .NET public instance properties + PSObject NoteProperties
                    $propDescriptors = New-Object System.Collections.Generic.List[object]
                    $seenPropNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

                    $netProps = $actualType.GetProperties([System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Instance) |
                        Where-Object { $_.GetIndexParameters().Count -eq 0 } |
                        Sort-Object -Property Name

                    foreach ($np in $netProps) {
                        if ($seenPropNames.Add($np.Name)) {
                            $propVal = $null
                            $readError = $null
                            if ($null -ne $rawObj -and -not $IsSchemaOnly) {
                                try {
                                    $propVal = $np.GetValue($rawObj, $null)
                                } catch {
                                    $readError = $_.Exception.Message
                                }
                            }
                            $propDescriptors.Add([PSCustomObject]@{
                                Name         = $np.Name
                                DeclaredType = $np.PropertyType
                                Value        = $propVal
                                ReadError    = $readError
                            })
                        }
                    }

                    if ($null -ne $InputObject -and $InputObject -is [psobject] -and -not $IsSchemaOnly) {
                        foreach ($psProp in ($InputObject.PSObject.Properties | Sort-Object -Property Name)) {
                            if ($seenPropNames.Add($psProp.Name)) {
                                $pVal = $null
                                try { $pVal = $psProp.Value } catch {}
                                $dType = [object]
                                if ($null -ne $pVal) {
                                    $dType = $pVal.GetType()
                                } elseif ($null -ne $psProp.TypeNameOfValue) {
                                    $resolvedType = $psProp.TypeNameOfValue -as [type]
                                    if ($null -ne $resolvedType) { $dType = $resolvedType }
                                }
                                $propDescriptors.Add([PSCustomObject]@{
                                    Name         = $psProp.Name
                                    DeclaredType = $dType
                                    Value        = $pVal
                                    ReadError    = $null
                                })
                            }
                        }
                    }

                    foreach ($pd in $propDescriptors) {
                        $pName = $pd.Name
                        $pPath = "$PsPath.$pName"
                        $pVal = $pd.Value
                        if ($null -ne $pVal -and $pVal -is [psobject] -and $null -ne $pVal.PSObject.BaseObject -and $pVal.PSObject.BaseObject -isnot [System.Management.Automation.PSCustomObject]) {
                            $pVal = $pVal.PSObject.BaseObject
                        }
                        $effectiveType = if ($null -ne $pVal) { $pVal.GetType() } elseif ($null -ne $pd.DeclaredType) { $pd.DeclaredType } else { [object] }
                        $effectiveTypeName = Get-FriendlyTypeName -Type $effectiveType

                        $propIsMoRef = ($effectiveType.Name -eq 'ManagedObjectReference' -or $effectiveType.FullName -like '*ManagedObjectReference*')
                        $propMoRefCmd = if ($propIsMoRef) { "Get-View -Id $pPath" } else { $null }
                        $propDesc = Get-VSphereMemberDescription -Type $actualType -MemberName $pName -IsMethod $false

                        if (Test-IsSimpleType -Type $effectiveType) {
                            $scalarProperties.Add([PSCustomObject]@{
                                Name        = $pName
                                Type        = $effectiveTypeName
                                FullType    = $effectiveType.FullName
                                Value       = if ($IsSchemaOnly) { '<Schema ($null parent)>' } else { (Format-ScalarValue -Value $pVal) }
                                PsPath      = $pPath
                                IsNull      = ($null -eq $pVal)
                                IsMoRef     = $false
                                MoRefCmd    = $null
                                Description = $propDesc
                            })
                        } else {
                            $valSummary = if ($null -eq $pVal) {
                                '$null (Reflected Schema)'
                            } elseif ($propIsMoRef) {
                                try { "$($pVal.Type)-$($pVal.Value)" } catch { "$pVal" }
                            } elseif (Test-IsCollectionType -Type $effectiveType) {
                                $cnt = @($pVal).Count
                                "$effectiveTypeName (Count: $cnt)"
                            } else {
                                "[$effectiveTypeName]"
                            }

                            $scalarProperties.Add([PSCustomObject]@{
                                Name        = $pName
                                Type        = $effectiveTypeName
                                FullType    = $effectiveType.FullName
                                Value       = $valSummary
                                PsPath      = $pPath
                                IsNull      = ($null -eq $pVal)
                                IsMoRef     = $propIsMoRef
                                MoRefCmd    = $propMoRefCmd
                                Description = $propDesc
                            })

                            if ($CurrentDepth -lt $MaxDepth) {
                                # If property is $null, we reflect 1 level of its schema so the user sees its properties without exploding 10 levels of null trees
                                $childEffectiveMaxDepth = if ($null -eq $pVal) { [Math]::Min($MaxDepth, $CurrentDepth + 1) } else { $MaxDepth }
                                $childNode = ConvertTo-ApiNodeTree `
                                    -InputObject $pVal `
                                    -DeclaredType $effectiveType `
                                    -Name $pName `
                                    -PsPath $pPath `
                                    -MaxDepth $childEffectiveMaxDepth `
                                    -CurrentDepth ($CurrentDepth + 1) `
                                    -MaxCollectionItems $MaxCollectionItems `
                                    -IncludeMethods $IncludeMethods `
                                    -VisitedIds $VisitedIds `
                                    -IsSchemaOnly ($IsSchemaOnly -or ($null -eq $pVal))
                                $childrenList.Add($childNode)
                            } else {
                                $truncatedByDepth = $true
                            }
                        }
                    }
                }
            }
        }
    } finally {
        if ($trackedInPath -and $objHash -ne 0) {
            [void]$VisitedIds.Remove($objHash)
        }
    }

    return [PSCustomObject]@{
        Id               = $nodeId
        Name             = $Name
        TypeName         = $typeName
        FullTypeName     = $fullTypeName
        Description      = $typeDescription
        PsPath           = $PsPath
        Depth            = $CurrentDepth
        IsNull           = ($null -eq $rawObj)
        IsSchemaOnly     = $IsSchemaOnly
        IsCollection     = $isCollection
        CollectionCount  = $collectionCount
        IsMoRef          = $isMoRef
        MoRefValue       = $moRefValue
        MoRefCmd         = $moRefCmd
        IsCycle          = $isCycle
        TruncatedByDepth = $truncatedByDepth
        Properties       = $scalarProperties.ToArray()
        Methods          = $methodsList.ToArray()
        Children         = $childrenList.ToArray()
    }
}

function Get-VSphereApiDocCatalog {
    if ($null -ne $script:VSphereApiDocsCache) {
        return $script:VSphereApiDocsCache
    }
    $script:VSphereApiDocsCache = @{}
    $jsonFile = Join-Path $PSScriptRoot 'Data\vSphereApiDocs.json'
    if (-not (Test-Path -LiteralPath $jsonFile)) {
        $parentDir = Split-Path -Path $PSScriptRoot -Parent
        if (-not [string]::IsNullOrWhiteSpace($parentDir)) {
            $jsonFile = Join-Path $parentDir 'Data\vSphereApiDocs.json'
        }
    }
    if (Test-Path -LiteralPath $jsonFile) {
        try {
            $rawJson = [System.IO.File]::ReadAllText($jsonFile, [System.Text.Encoding]::UTF8)
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                $script:VSphereApiDocsCache = $rawJson | ConvertFrom-Json -AsHashtable
            } else {
                $psObj = $rawJson | ConvertFrom-Json
                foreach ($prop in $psObj.PSObject.Properties) {
                    $tEntry = @{
                        d = $prop.Value.d
                        p = @{}
                        m = @{}
                    }
                    if ($null -ne $prop.Value.p) {
                        foreach ($pp in $prop.Value.p.PSObject.Properties) {
                            $tEntry.p[$pp.Name] = $pp.Value
                        }
                    }
                    if ($null -ne $prop.Value.m) {
                        foreach ($mp in $prop.Value.m.PSObject.Properties) {
                            $tEntry.m[$mp.Name] = $mp.Value
                        }
                    }
                    $script:VSphereApiDocsCache[$prop.Name] = $tEntry
                }
            }
        } catch {}
    }
    return $script:VSphereApiDocsCache
}

function Get-VSphereTypeDescription {
    param([System.Type]$Type)
    if ($null -eq $Type) { return $null }
    $catalog = Get-VSphereApiDocCatalog
    $checkType = if ($Type.IsArray) { $Type.GetElementType() } else { $Type }
    while ($null -ne $checkType -and $checkType -ne [object]) {
        $shortName = $checkType.Name
        if ($catalog.ContainsKey($shortName)) {
            $desc = $catalog[$shortName]['d']
            if (-not [string]::IsNullOrWhiteSpace($desc)) {
                return $desc
            }
        }
        $checkType = $checkType.BaseType
    }
    return $null
}

function Get-VSphereMemberDescription {
    param(
        [System.Type]$Type,
        [string]$MemberName,
        [bool]$IsMethod = $false
    )
    if ($null -eq $Type -or [string]::IsNullOrWhiteSpace($MemberName)) { return $null }
    $catalog = Get-VSphereApiDocCatalog
    $bucketKey = if ($IsMethod) { 'm' } else { 'p' }

    # Walk inheritance chain (e.g. VirtualVmxnet3 -> VirtualEthernetCard -> VirtualDevice, or VirtualMachine -> ManagedEntity)
    $candidates = New-Object System.Collections.Generic.List[string]
    $curr = $Type
    while ($null -ne $curr -and $curr -ne [object]) {
        [void]$candidates.Add($curr.Name)
        $curr = $curr.BaseType
    }
    # In PowerCLI, ViewBase objects (like VirtualMachine) may inherit from ManagedEntity or EntityViewBase; always check ManagedEntity & ExtensibleManagedObject as fallback
    foreach ($fallbackType in @('ManagedEntity', 'ExtensibleManagedObject', 'VirtualDevice')) {
        if (-not $candidates.Contains($fallbackType)) {
            [void]$candidates.Add($fallbackType)
        }
    }

    foreach ($tName in $candidates) {
        if ($catalog.ContainsKey($tName)) {
            $bucket = $catalog[$tName][$bucketKey]
            if ($null -ne $bucket) {
                if ($bucket -is [hashtable]) {
                    if ($bucket.ContainsKey($MemberName)) {
                        return $bucket[$MemberName]
                    }
                    foreach ($k in $bucket.Keys) {
                        if ([string]::Equals($k, $MemberName, [System.StringComparison]::OrdinalIgnoreCase)) {
                            return $bucket[$k]
                        }
                    }
                } else {
                    $val = $bucket.$MemberName
                    if (-not [string]::IsNullOrWhiteSpace($val)) {
                        return $val
                    }
                }
            }
        }
    }
    return $null
}

function Get-ObjectInlinePreview {
    param(
        [object]$Object,
        [System.Type]$Type
    )
    if ($null -eq $Object) { return '$null' }
    if ($null -ne $Type -and ($Type.Name -eq 'ManagedObjectReference' -or $Type.FullName -like '*ManagedObjectReference*')) {
        try { return "$($Object.Type)-$($Object.Value)" } catch { return "$Object" }
    }
    try {
        $props = $Object.GetType().GetProperties([System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Instance) |
            Where-Object { $_.GetIndexParameters().Count -eq 0 -and (Test-IsSimpleType -Type $_.PropertyType) } |
            Select-Object -First 4
        if ($props) {
            $parts = @()
            foreach ($p in $props) {
                try {
                    $v = $p.GetValue($Object, $null)
                    if ($null -ne $v -and "$v" -ne '') {
                        $parts += "$($p.Name)=$v"
                    }
                } catch {}
            }
            if ($parts.Count -gt 0) {
                return ($parts -join ', ')
            }
        }
    } catch {}
    return "[$(Get-FriendlyTypeName -Type $Object.GetType())]"
}

function Test-IsSimpleType {
    param([System.Type]$Type)
    if ($null -eq $Type) { return $true }
    $underlying = [System.Nullable]::GetUnderlyingType($Type)
    if ($null -ne $underlying) { $Type = $underlying }

    if ($Type.IsPrimitive -or $Type.IsEnum) { return $true }
    $simpleTypes = @(
        [string], [decimal], [datetime], [datetimeoffset],
        [timespan], [guid], [uri], [version], [ipaddress]
    )
    return ($simpleTypes -contains $Type)
}

function Test-IsCollectionType {
    param([System.Type]$Type)
    if ($null -eq $Type -or $Type -eq [string]) { return $false }
    if ($Type.IsArray) { return $true }
    if ([System.Collections.IDictionary].IsAssignableFrom($Type)) { return $false }
    return [System.Collections.IEnumerable].IsAssignableFrom($Type)
}

function Get-CollectionElementType {
    param([System.Type]$Type)
    if ($null -eq $Type) { return $null }
    if ($Type.IsArray) {
        return $Type.GetElementType()
    }
    if ($Type.IsGenericType) {
        $genArgs = $Type.GetGenericArguments()
        if ($genArgs.Count -gt 0) {
            return $genArgs[0]
        }
    }
    foreach ($iface in $Type.GetInterfaces()) {
        if ($iface.IsGenericType -and $iface.GetGenericTypeDefinition() -eq [System.Collections.Generic.IEnumerable`1]) {
            return $iface.GetGenericArguments()[0]
        }
    }
    return [object]
}

function Get-FriendlyTypeName {
    <#
    .SYNOPSIS
        Returns full namespace-qualified .NET type name (e.g. VMware.Vim.VirtualMachine, VMware.Vim.VirtualDevice[]).
    #>
    param([System.Type]$Type)
    if ($null -eq $Type) { return 'System.Object' }
    $underlying = [System.Nullable]::GetUnderlyingType($Type)
    if ($null -ne $underlying) {
        return "$(Get-FriendlyTypeName -Type $underlying)?"
    }
    if ($Type.IsArray) {
        $elem = Get-FriendlyTypeName -Type ($Type.GetElementType())
        return "$elem[]"
    }
    if ($Type.IsGenericType) {
        $ns = if (-not [string]::IsNullOrWhiteSpace($Type.Namespace)) { "$($Type.Namespace)." } else { '' }
        $baseName = $ns + ($Type.Name -replace '`.*$', '')
        $argsNames = ($Type.GetGenericArguments() | ForEach-Object { Get-FriendlyTypeName -Type $_ }) -join ', '
        return "$baseName<$argsNames>"
    }
    if (-not [string]::IsNullOrWhiteSpace($Type.FullName)) {
        return ($Type.FullName -replace '\+', '.')
    }
    if (-not [string]::IsNullOrWhiteSpace($Type.Namespace)) {
        return "$($Type.Namespace).$($Type.Name)"
    }
    return $Type.Name
}

function Format-ScalarValue {
    param([object]$Value)
    if ($null -eq $Value) { return '$null' }
    if ($Value -is [bool]) { return "`$$($Value.ToString().ToLower())" }
    if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM-dd HH:mm:ss') }
    return "$Value"
}
