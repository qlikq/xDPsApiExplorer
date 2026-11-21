# Mock vSphere / PowerCLI ViewBase classes for testing and demonstration
if (-not ('VMware.Vim.VirtualMachine' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;

namespace VMware.Vim
{
    public class ManagedObjectReference
    {
        public string Type { get; set; }
        public string Value { get; set; }
        public override string ToString() { return Type + "-" + Value; }
    }

    public class Description
    {
        public string Label { get; set; }
        public string Summary { get; set; }
    }

    public class VirtualDevice
    {
        public int Key { get; set; }
        public Description DeviceInfo { get; set; }
        public int? ControllerKey { get; set; }
        public int? UnitNumber { get; set; }
    }

    public class VirtualVmxnet3 : VirtualDevice
    {
        public string MacAddress { get; set; }
        public string AddressType { get; set; }
        public bool WakeOnLanEnabled { get; set; }
    }

    public class VirtualDisk : VirtualDevice
    {
        public long CapacityInKB { get; set; }
        public bool ThinProvisioned { get; set; }
        public string DiskMode { get; set; }
    }

    public class VirtualHardware
    {
        public int NumCPU { get; set; }
        public int NumCoresPerSocket { get; set; }
        public int MemoryMB { get; set; }
        public VirtualDevice[] Device { get; set; }
    }

    public class VirtualMachineConfigInfo
    {
        public string Name { get; set; }
        public string Uuid { get; set; }
        public string InstanceUuid { get; set; }
        public string GuestFullName { get; set; }
        public string Version { get; set; }
        public VirtualHardware Hardware { get; set; }
    }

    public class VirtualMachineRuntimeInfo
    {
        public string PowerState { get; set; }
        public string ConnectionState { get; set; }
        public DateTime? BootTime { get; set; }
        public ManagedObjectReference Host { get; set; }
    }

    public class VirtualMachineGuestSummary
    {
        public string GuestId { get; set; }
        public string ToolsStatus { get; set; }
        public string HostName { get; set; }
        public string IpAddress { get; set; }
    }

    public class VirtualMachineConfigSpec
    {
        public string Name { get; set; }
        public int? NumCPUs { get; set; }
        public long? MemoryMB { get; set; }
    }

    public class VirtualMachine
    {
        public string Name { get; set; }
        public ManagedObjectReference MoRef { get; set; }
        public ManagedObjectReference Parent { get; set; }
        public VirtualMachineConfigInfo Config { get; set; }
        public VirtualMachineRuntimeInfo Runtime { get; set; }
        public VirtualMachineGuestSummary GuestSummary { get; set; } // Intentionally left $null in tests to verify .NET Reflection!
        public ManagedObjectReference[] Datastore { get; set; }
        public VirtualMachine SelfCycleRef { get; set; }

        public ManagedObjectReference ReconfigVM_Task(VirtualMachineConfigSpec spec)
        {
            return new ManagedObjectReference { Type = "Task", Value = "task-901" };
        }

        public ManagedObjectReference PowerOnVM_Task(ManagedObjectReference host)
        {
            return new ManagedObjectReference { Type = "Task", Value = "task-902" };
        }

        public void Reload() { }
    }
}
'@
}

function New-MockVirtualMachineView {
    [CmdletBinding()]
    param(
        [string]$VmName = 'prod-sql-01',
        [switch]$WithCycle
    )

    $vm = New-Object VMware.Vim.VirtualMachine
    $vm.Name = $VmName
    $vm.MoRef = New-Object VMware.Vim.ManagedObjectReference -Property @{ Type = 'VirtualMachine'; Value = 'vm-402' }
    $vm.Parent = New-Object VMware.Vim.ManagedObjectReference -Property @{ Type = 'Folder'; Value = 'group-v22' }

    $nic = New-Object VMware.Vim.VirtualVmxnet3 -Property @{
        Key              = 4000
        ControllerKey    = 100
        UnitNumber       = 7
        MacAddress       = '00:50:56:9a:31:f2'
        AddressType      = 'assigned'
        WakeOnLanEnabled = $true
        DeviceInfo       = (New-Object VMware.Vim.Description -Property @{ Label = 'Network adapter 1'; Summary = 'VM Network (VLAN 120)' })
    }

    $disk1 = New-Object VMware.Vim.VirtualDisk -Property @{
        Key             = 2000
        ControllerKey   = 1000
        UnitNumber      = 0
        CapacityInKB    = 104857600
        ThinProvisioned = $true
        DiskMode        = 'persistent'
        DeviceInfo      = (New-Object VMware.Vim.Description -Property @{ Label = 'Hard disk 1'; Summary = '104,857,600 KB' })
    }

    $disk2 = New-Object VMware.Vim.VirtualDisk -Property @{
        Key             = 2001
        ControllerKey   = 1000
        UnitNumber      = 1
        CapacityInKB    = 524288000
        ThinProvisioned = $false
        DiskMode        = 'independent_persistent'
        DeviceInfo      = (New-Object VMware.Vim.Description -Property @{ Label = 'Hard disk 2 (SQL Data)'; Summary = '524,288,000 KB' })
    }

    $hw = New-Object VMware.Vim.VirtualHardware -Property @{
        NumCPU            = 8
        NumCoresPerSocket = 4
        MemoryMB          = 32768
        Device            = [VMware.Vim.VirtualDevice[]]@($disk1, $disk2, $nic)
    }

    $vm.Config = New-Object VMware.Vim.VirtualMachineConfigInfo -Property @{
        Name          = $VmName
        Uuid          = '421a8e0b-93c1-4422-b84c-8d19a4f00192'
        InstanceUuid  = '501a4c9f-7108-9e12-33f4-110293847561'
        GuestFullName = 'Microsoft Windows Server 2022 (64-bit)'
        Version       = 'vmx-20'
        Hardware      = $hw
    }

    $vm.Runtime = New-Object VMware.Vim.VirtualMachineRuntimeInfo -Property @{
        PowerState      = 'poweredOn'
        ConnectionState = 'connected'
        BootTime        = (Get-Date).AddDays(-14)
        Host            = (New-Object VMware.Vim.ManagedObjectReference -Property @{ Type = 'HostSystem'; Value = 'host-28' })
    }

    # Intentionally keep GuestSummary = $null so .NET Reflection inspects VirtualMachineGuestSummary schema!
    $vm.GuestSummary = $null

    $vm.Datastore = [VMware.Vim.ManagedObjectReference[]]@(
        (New-Object VMware.Vim.ManagedObjectReference -Property @{ Type = 'Datastore'; Value = 'datastore-101' }),
        (New-Object VMware.Vim.ManagedObjectReference -Property @{ Type = 'Datastore'; Value = 'datastore-102' })
    )

    if ($WithCycle.IsPresent) {
        $vm.SelfCycleRef = $vm
    }

    return $vm
}
