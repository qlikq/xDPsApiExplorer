#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }

BeforeAll {
    $ErrorActionPreference = 'Stop'
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $PSScriptRoot 'Mock-VSphereObjects.ps1')

    # Locate the compiled module built by PoshCode ModuleBuilder (or build it on the fly if missing)
    $outputBase = Join-Path $script:RepoRoot 'output\xDPsApiExplorer'
    $builtManifest = Get-ChildItem -Path $outputBase -Filter 'xDPsApiExplorer.psd1' -Recurse -ErrorAction SilentlyContinue |
        Sort-Object { [version](Split-Path $_.DirectoryName -Leaf) } -Descending |
        Select-Object -First 1

    if ($null -eq $builtManifest) {
        Import-Module ModuleBuilder -Force
        $buildSpec = Join-Path $script:RepoRoot 'xDPsApiExplorer\build.psd1'
        $builtMod = Build-Module -SourcePath $buildSpec -Passthru
        $script:ManifestPath = $builtMod.Path
    } else {
        $script:ManifestPath = $builtManifest.FullName
    }

    Remove-Module xDPsApiExplorer -Force -ErrorAction SilentlyContinue
    Import-Module $script:ManifestPath -Force
}

Describe 'xDPsApiExplorer Built Module (PoshCode ModuleBuilder + Native UML Engine)' {

    Context 'ModuleBuilder Packaging, Manifest Metadata & Exports' {
        It 'Produces a valid compiled module manifest with LicenseUri and ProjectUri' {
            $manifest = Test-ModuleManifest -Path $script:ManifestPath
            $manifest | Should -Not -BeNullOrEmpty
            $manifest.Name | Should -Be 'xDPsApiExplorer'
            $manifest.ProjectUri.ToString() | Should -Match '^https://xdlabs\.info'
            $manifest.LicenseUri.ToString() | Should -Be 'https://github.com/qlikq/xDPsApiExplorer/blob/main/LICENSE'
            ($manifest.Tags -contains 'VMware') | Should -BeTrue
            ($manifest.Tags -contains 'PowerCLI') | Should -BeTrue
        }

        It 'Copies Data/vSphereApiDocs.json, README.md, and LICENSE into the built module output' {
            $builtDir = Split-Path -Path $script:ManifestPath -Parent
            (Test-Path -LiteralPath (Join-Path $builtDir 'Data\vSphereApiDocs.json')) | Should -BeTrue
            (Test-Path -LiteralPath (Join-Path $builtDir 'README.md')) | Should -BeTrue
            (Test-Path -LiteralPath (Join-Path $builtDir 'LICENSE')) | Should -BeTrue
        }

        It 'Exports Show-ApiContext and convenience aliases Show-ApiGraph and sac' {
            $cmd = Get-Command -Module xDPsApiExplorer -Name Show-ApiContext -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty

            $alias1 = Get-Alias -Name Show-ApiGraph -ErrorAction SilentlyContinue
            $alias2 = Get-Alias -Name sac -ErrorAction SilentlyContinue
            $alias1.ResolvedCommandName | Should -Be 'Show-ApiContext'
            $alias2.ResolvedCommandName | Should -Be 'Show-ApiContext'
        }
    }

    Context 'Parameter Validation (-MaxDepth 1..10)' {
        It 'Rejects -MaxDepth 0 (below minimum)' {
            $myVM = New-MockVirtualMachineView
            { $myVM | Show-ApiContext -MaxDepth 0 -NoBrowser } | Should -Throw
        }

        It 'Rejects -MaxDepth 11 (above maximum)' {
            $myVM = New-MockVirtualMachineView
            { $myVM | Show-ApiContext -MaxDepth 11 -NoBrowser } | Should -Throw
        }
    }

    Context 'Full .NET Type Names, Pipeline Variable Detection & Deep Inspection' {
        It 'Detects variable name $myVM from the pipeline and uses full .NET type names' {
            $myVM = New-MockVirtualMachineView
            $res = $myVM | Show-ApiContext -MaxDepth 4 -NoBrowser -PassThru

            $res.RootName | Should -Be '$myVM'
            $res.RootType | Should -Be 'VMware.Vim.VirtualMachine'
            $res.NodeTree.TypeName | Should -Be 'VMware.Vim.VirtualMachine'
            $res.MaxDepth | Should -Be 4
            (Test-Path -LiteralPath $res.HtmlPath) | Should -BeTrue
        }

        It 'Reflects .NET schema even for $null properties (GuestSummary) with full type name' {
            $myVM = New-MockVirtualMachineView
            $res = $myVM | Show-ApiContext -MaxDepth 3 -NoBrowser -PassThru

            $guestNode = $res.NodeTree.Children | Where-Object { $_.Name -eq 'GuestSummary' }
            $guestNode | Should -Not -BeNullOrEmpty
            $guestNode.IsNull | Should -BeTrue
            $guestNode.IsSchemaOnly | Should -BeTrue
            $guestNode.TypeName | Should -Be 'VMware.Vim.VirtualMachineGuestSummary'

            $ipProp = $guestNode.Properties | Where-Object { $_.Name -eq 'IpAddress' }
            $ipProp | Should -Not -BeNullOrEmpty
            $ipProp.Type | Should -Be 'System.String'
            $ipProp.PsPath | Should -Be '$myVM.GuestSummary.IpAddress'
        }

        It 'Unwraps polymorphic arrays without wasting MaxDepth and includes inline element previews' {
            $myVM = New-MockVirtualMachineView
            $res = $myVM | Show-ApiContext -MaxDepth 3 -NoBrowser -PassThru

            $configNode = $res.NodeTree.Children | Where-Object { $_.Name -eq 'Config' }
            $hwNode = $configNode.Children | Where-Object { $_.Name -eq 'Hardware' }
            $devNode = $hwNode.Children | Where-Object { $_.Name -eq 'Device' }

            $devNode | Should -Not -BeNullOrEmpty
            $devNode.IsCollection | Should -BeTrue
            $devNode.TypeName | Should -Be 'VMware.Vim.VirtualDevice[]'
            $devNode.CollectionCount | Should -Be 3

            $previewRow = $devNode.Properties | Where-Object { $_.Name -eq '[2]' }
            $previewRow | Should -Not -BeNullOrEmpty
            $previewRow.Type | Should -Be 'VMware.Vim.VirtualVmxnet3'

            $nicNode = $devNode.Children | Where-Object { $_.TypeName -eq 'VMware.Vim.VirtualVmxnet3' }
            $nicNode | Should -Not -BeNullOrEmpty
            $nicNode.PsPath | Should -Be '$myVM.Config.Hardware.Device[2]'

            $macProp = $nicNode.Properties | Where-Object { $_.Name -eq 'MacAddress' }
            $macProp.Value | Should -Be '00:50:56:9a:31:f2'
            $macProp.PsPath | Should -Be '$myVM.Config.Hardware.Device[2].MacAddress'
        }

        It 'Detects VMware ManagedObjectReference (MoRef) and builds Get-View helper command' {
            $myVM = New-MockVirtualMachineView
            $res = $myVM | Show-ApiContext -MaxDepth 3 -NoBrowser -PassThru

            $runtimeNode = $res.NodeTree.Children | Where-Object { $_.Name -eq 'Runtime' }
            $hostNode = $runtimeNode.Children | Where-Object { $_.Name -eq 'Host' }

            $hostNode | Should -Not -BeNullOrEmpty
            $hostNode.IsMoRef | Should -BeTrue
            $hostNode.TypeName | Should -Be 'VMware.Vim.ManagedObjectReference'
            $hostNode.MoRefValue | Should -Be 'HostSystem-host-28'
            $hostNode.MoRefCmd | Should -Be 'Get-View -Id $myVM.Runtime.Host'
        }

        It 'Collects API methods with full .NET parameter and return type signatures' {
            $myVM = New-MockVirtualMachineView
            $res = $myVM | Show-ApiContext -MaxDepth 2 -NoBrowser -PassThru

            $reconfigMethod = $res.NodeTree.Methods | Where-Object { $_.Name -eq 'ReconfigVM_Task' }
            $reconfigMethod | Should -Not -BeNullOrEmpty
            $reconfigMethod.IsTask | Should -BeTrue
            $reconfigMethod.ReturnType | Should -Be 'VMware.Vim.ManagedObjectReference'
            $reconfigMethod.Signature | Should -Match 'VMware\.Vim\.VirtualMachineConfigSpec'
            $reconfigMethod.CallSnippet | Should -Match '^\$myVM\.ReconfigVM_Task\('
        }

        It 'Marks TruncatedByDepth = true when complex child objects exceed MaxDepth' {
            $myVM = New-MockVirtualMachineView
            $res = $myVM | Show-ApiContext -MaxDepth 1 -NoBrowser -PassThru

            $configNode = $res.NodeTree.Children | Where-Object { $_.Name -eq 'Config' }
            $configNode.TruncatedByDepth | Should -BeTrue
        }

        It 'Safely handles cyclic object references without infinite recursion' {
            $myVM = New-MockVirtualMachineView -WithCycle
            $res = $myVM | Show-ApiContext -MaxDepth 4 -NoBrowser -PassThru

            $cycleChild = $res.NodeTree.Children | Where-Object { $_.Name -eq 'SelfCycleRef' }
            $cycleChild | Should -Not -BeNullOrEmpty
            $cycleChild.IsCycle | Should -BeTrue
        }

        It 'Attaches official Broadcom vSphere SDK offline documentation descriptions to types, properties, and methods' {
            $myVM = New-MockVirtualMachineView
            $res = $myVM | Show-ApiContext -MaxDepth 4 -NoBrowser -PassThru

            $res.NodeTree.Description | Should -Match 'VirtualMachine is the managed object type'

            $configProp = $res.NodeTree.Properties | Where-Object { $_.Name -eq 'Config' }
            $configProp.Description | Should -Match 'Configuration of this virtual machine'

            $reconfigMethod = $res.NodeTree.Methods | Where-Object { $_.Name -eq 'ReconfigVM_Task' }
            $reconfigMethod.Description | Should -Match 'Reconfigures this virtual machine'
        }

        It 'Generates a 100% self-contained offline HTML file with Where-Object (?{ }) filter builder, Hide Unmatched, Panel Resizer, Pinned Boxes (0/5), and [Type] notation' {
            $myVM = New-MockVirtualMachineView
            $res = $myVM | Show-ApiContext -MaxDepth 4 -NoBrowser -PassThru
            $html = [System.IO.File]::ReadAllText($res.HtmlPath)

            ($html -match '<script\s+src="https?://') | Should -BeFalse
            $html | Should -Match 'VMware\.Vim\.VirtualVmxnet3'
            $html | Should -Match 'buildWhereFilterCommand'
            $html | Should -Match 'mini-where-btn'
            $html | Should -Match 'chkHideUnmatched'
            $html | Should -Match 'panelResizer'
            $html | Should -Match 'renderExpandableDocHtml'
            ($html -match '&laquo;') | Should -BeFalse
            $html | Should -Match '<span class="brand-logo">xDlabs</span>'
            $html | Should -Match '<span class="brand-title">ApiExplorer</span>'
            ($html -match 'Native UML Box-Tree') | Should -BeFalse
            $html | Should -Match 'userClickedNode'
            $html | Should -Match 'subtreeStartY'
            $html | Should -Match '#22c55e'
            $html | Should -Match 'id="pinnedDock"'
            $html | Should -Match 'MAX_PINNED_NODES = 5'
            $html | Should -Match 'togglePinNode'
        }

        It 'Inspects properties (Length) and methods (Substring, Replace) when a simple type like [System.String] is passed as root object' {
            $res = 'mojstring' | Show-ApiContext -MaxDepth 5 -NoBrowser -PassThru
            $res.NodeTree.TypeName | Should -Be 'System.String'
            $lenProp = $res.NodeTree.Properties | Where-Object { $_.Name -eq 'Length' }
            $lenProp | Should -Not -BeNullOrEmpty
            $lenProp.Value | Should -Be '9'
            ($res.NodeTree.Methods | Where-Object { $_.Name -eq 'Substring' }) | Should -Not -BeNullOrEmpty
            ($res.NodeTree.Methods | Where-Object { $_.Name -eq 'Replace' }) | Should -Not -BeNullOrEmpty
        }
    }
}
