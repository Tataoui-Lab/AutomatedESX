# Author: Dominic Chan
# Website: www.vmware.com
# Description: PowerCLI script to deploy or refresh a VMware Holodeck environment.
#              ----
# Reference: https://core.vmware.com/introducing-holodeck-toolkit
# Credit: 
#
# Changelog
# 01/10/24
#   * Initital draft
#   - automated ESXi host network preparation according to VMware Holo-Setup-Host-Prep (January 2023)
#   - uploading custom Holo Console iso to ESXi host datastore
#   - automated the deployment of Holo-Console VM according to VMware Holo-Setup-Deploy-Console (January 2023)
#   - automated the deployment of Holo-Router according to VMware Holo-Setup-Deploy-Router (January 2023)
# 
$StartTime = Get-Date
$verboseLogFile = "VMware Holodeck Deployment.log"
#
# Customer lab environment variables - Must update to work with your lab environment
############################################################################################################################
#
$VIServer = "192.168.10.11" # or "esx01.tataoui.com"
$VIUsername = 'root'
$VIPassword = 'VMware123!'
$vmhost = Get-VMHost -Name $VIServer
# Specifies whether deployment is on ESXi host or vCenter Server (ESXI or VCENTER)
# $DeploymentTarget = "ESXI" - Future
#
# Full Path to HoloRouter ova and generated HoloConsole iso
$DSFolder = '' # Datastore folder / subfolder name if any - i.e. 'iso\'
$HoloConsoleISOName = 'Holo-Console-4.5.2.iso'
$HoloConsoleISOPath = 'C:\Users\cdominic\Downloads\holodeck-standard-main\Holo-Console'
$HoloConsoleISO = $HoloConsoleISOPath + '\' + $HoloConsoleISOName
$HoloRouterOVAName = 'HoloRouter-2.0.ova'
$HoloRouterOVAPath = 'C:\Users\cdominic\Downloads\holodeck-standard-main\Holo-Router'
$HoloRouterOVA = $HoloRouterOVAPath  + '\' + $HoloRouterOVAName
#
$EnablePreCheck = 1 # Verfiy Holodeck core binaries are accessible on Build Host
$EnableCheckDS = 1 # Verfiy assign datastore for both HoloConsole and HoloRouter are accessible on the ESX host
$EnableSiteNetwork = 1 # (1 - Upload / refresh the latest HoloConsole ISO to ESX host, 2 - to delete)
$RefreshHoloConsoleISO  = 0 # (1 - Upload / refresh the latest HoloConsole ISO to ESX host)
$EnableDeployHoloConsole = 0 # (1 - to create HoloConsole VM, 2 - to delete HoloConsole VM)
$EnableDeployHoloRouter = 1 # (1 - to create HoloConsole VM, 2 - to delete HoloConsole VM)
#
############################################################################################################################
# Default VMware Holodeck settings align to VMware Holodeck 5.0 documentation
#
# Holodeck ESXi host vSwitch and Portgroup settings
$HoloDeckSite1vSwitch = "VLC-A"
$HoloDeckSite1vSwitchMTU = 9000
$HoloDeckSite1PortGroup = "VLC-A-PG"
$HoloDeckSite1PGVLAN = 4095
$HoloDeckSite2vSwitch = "VLC-A2"
$HoloDeckSite2vSwitchMTU = 9000
$HoloDeckSite2PortGroup = "VLC-A2-PG"
$HoloDeckSite2PGVLAN = 4095
#
# HoloConsole VM settings
$HoloConsoleVMName = "Holo-A-Console"
$HoloConsoleDS = "Repository"
$HoloConsoleHW = "vmx-19"
$HoloConsoleOS = "windows2019srv_64Guest"
$HoloConsoleCPU = 2
$HoloConsoleMEM = 4 #GB
$HoloConsoleDisk = 90 #GB
$HoloConsoleNIC = "VLC-A-PG"
#
# HoloRouter OVA settings
$HoloRouterVMName = "Holo-C-Router"
$HoloRouterEULA = "1"
$HoloRouterDS = "Repository"
$HoloRouterExtNetwork = "VM Network"
$HoloRouterSite1Network = $HoloDeckSite1PortGroup
$HoloRouterSite2Network = $HoloDeckSite2PortGroup
$HoloRouterDiskProvision = "thin"
$HoloRouterExternalIP = "192.168.10.4"
$HoloRouterExternalSubnet = "255.255.255.0"
$HoloRouterExternalGW = "192.168.10.2"
#
Function My-Logger {
    param(
    [Parameter(Mandatory=$true, Position=0)]
    [String]$message,
    [Parameter(Mandatory=$false, Position=1)]
    [Int]$level
    )
    $timeStamp = Get-Date -Format "MM-dd-yyyy_hh:mm:ss"
    Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
    if ($level -eq 1) {
        $msgColor = "Yellow"
    } elseif ($level -eq 2) {
        $msgColor = "Red"  
    } else {
        $msgColor = "Green"  
    }
    Write-Host -ForegroundColor $msgColor " $message"
    $logMessage = "[$timeStamp] $message"
    $logMessage | Out-File -Append -LiteralPath $verboseLogFile   
}
Function PreCheck {
    # Verfiy Holodeck core binaries are accessible 
    param(
        [Parameter(Mandatory=$true)]
        [int]$PreCheck
        )
    if($PreCheck -eq 1) {
        if(!(Test-Path $HoloConsoleISO)) {
            My-Logger "Unable to locate '$HoloConsoleISO' on your Build Host ...`nexiting" 2
            exit
        } else {
            My-Logger "HoloConsole ISO '$HoloConsoleISOName' located on Build Host"
        }
        if(!(Test-Path $HoloRouterOVA)) {
            My-Logger "`nUnable to locate '$HoloRouterOVA' on your Build Host ...`nexiting" 2
            exit
        } else {
            My-Logger "HoloRouter OVA '$HoloRouterOVAName' located on Build Host"
        }
    }
}
Function CheckDS {
    # Verfiy ESX Host datastore is accessible 
    param(
        [Parameter(Mandatory=$true)]
        [int]$CheckDS
        )
    if($CheckDS -eq 1) {
        if($HCdatastore -eq $null) {
            My-Logger "Predefined HoloConsole datastore not found on ESX host $VIServer, please confirm Datastore name entry..." 2
            Exit
        } else {
            My-Logger "HoloConsole assign datastore '$HoloConsoleDS' located on ESX host $VIServer"
        }
        if($HRdatastore -eq $null) {
            My-Logger "Predefined HoloRouter datastore not found on ESX host $VIServer, please confirm Datastore name entry..." 2
            Exit
        } else {
            WMy-Logger "HoloRouter assign datastore '$HoloConsoleDS' located on ESX host $VIServer"
        }
    }
}
Function CreatedSiteNetwork {
    # Configure / delete virtual networks for site 1 & 2
    param(
        [Parameter(Mandatory=$false)]
        [int]$CreatedSiteNetwork
        )
    # Create vSwitches and Portgroups for Site 1 and Site 2
    if($CreatedSiteNetwork -eq 1) {
        $vSwtichSite1 = Get-VirtualSwitch -Server $viConnection -Name $HoloDeckSite1vSwitch -ErrorAction SilentlyContinue
        $PortGroupSite1 = Get-VirtualPortGroup -Server $viConnection -VirtualSwitch $HoloDeckSite1vSwitch -Name $HoloDeckSite1PortGroup -ErrorAction SilentlyContinue
        if( $vSwtichSite1.Name -eq $HoloDeckSite1vSwitch) {
            Write-Host -ForegroundColor Green "vSphere Standard Switch '$HoloDeckSite1vSwitch' for Site #1 already exists"
            if( $PortGroupSite1.Name -eq $HoloDeckSite1PortGroup) {
                Write-Host -ForegroundColor Green "Portgroup '$HoloDeckSite1PortGroup' on vSphere Standard Switch '$HoloDeckSite1vSwitch' for Site #1 already exists"
            } else {
                Write-Host -ForegroundColor Green "Creating Portgroup '$HoloDeckSite1PortGroup' on ESX host $VIServer for Site #1"
                New-VirtualPortGroup -VirtualSwitch $HoloDeckSite1vSwitch -Name $HoloDeckSite1PortGroup -VLanId $HoloDeckSite1PGVLAN
                Get-VirtualPortGroup -VirtualSwitch $HoloDeckSite1vSwitch -name $HoloDeckSite1PortGroup | Get-SecurityPolicy | Set-SecurityPolicy -AllowPromiscuous $true -ForgedTransmits $true -MacChanges $true
            }   
        } else {
            Write-Host -ForegroundColor Red "vSphere Standard Switch '$HoloDeckSite1vSwitch' for Site #1 not found..."
            Write-Host -ForegroundColor Green "Creating Virtual Switch '$HoloDeckSite1vSwitch' on ESX host $VIServer for Site #1"
            New-VirtualSwitch -Server $viConnection -Name $HoloDeckSite1vSwitch -Mtu $HoloDeckSite1vSwitchMTU
            # For setting Security Policy on the vSwitch level - Get-VirtualSwitch -server $viConnection -name $HoloDeckSite1vSwitch | Get-SecurityPolicy | Set-SecurityPolicy -AllowPromiscuous $true -ForgedTransmits $true -MacChanges $true
            Write-Host -ForegroundColor Green "Creating Portgroup '$HoloDeckSite1PortGroup' on ESX host $VIServer for Site #1"
            New-VirtualPortGroup -VirtualSwitch $HoloDeckSite1vSwitch -Name $HoloDeckSite1PortGroup -VLanID $HoloDeckSite1PGVLAN
            Write-Host -ForegroundColor Green "Setting Security Policy for Portgroup '$HoloDeckSite1PortGroup'"
            Get-VirtualPortGroup -server $viConnection -name $HoloDeckSite1PortGroup | Get-SecurityPolicy | Set-SecurityPolicy -AllowPromiscuous $true -ForgedTransmits $true -MacChanges $true
        }
    #
        $vSwtichSite2 = Get-VirtualSwitch -Server $viConnection -Name $HoloDeckSite2vSwitch -ErrorAction SilentlyContinue
        $PortGroupSite2 = Get-VirtualPortGroup -Server $viConnection -VirtualSwitch $HoloDeckSite2vSwitch -Name $HoloDeckSite2PortGroup -ErrorAction SilentlyContinue
        if( $vSwtichSite2.Name -eq $HoloDeckSite2vSwitch) {
            Write-Host -ForegroundColor Green "vSphere Standard Switch '$HoloDeckSite1vSwitch' for Site #2 already exists"
            if( $PortGroupSite2.Name -eq $HoloDeckSite2PortGroup) {
                Write-Host -ForegroundColor Green "Portgroup '$HoloDeckSite2PortGroup' on vSphere Standard Switch '$HoloDeckSite2vSwitch' for Site #2 already exists"
            } else {
                Write-Host -ForegroundColor Green "Creating Portgroup '$HoloDeckSite1PortGroup' on ESX host $VIServer for Site #2"
                New-VirtualPortGroup -VirtualSwitch $HoloDeckSite2vSwitch -Name $HoloDeckSite2PortGroup -VLanId $HoloDeckSite2PGVLAN
                Get-VirtualPortGroup -VirtualSwitch $HoloDeckSite2vSwitch -name $HoloDeckSite2PortGroup | Get-SecurityPolicy | Set-SecurityPolicy -AllowPromiscuous $true -ForgedTransmits $true -MacChanges $true
            }   
        } else {
            Write-Host -ForegroundColor Red "vSphere Standard Switch '$HoloDeckSite2vSwitch' for Site #2 not found..."
            Write-Host -ForegroundColor Green "Creating Virtual Switch '$HoloDeckSite2vSwitch' on ESX host $VIServer for Site #2"
            New-VirtualSwitch -Server $viConnection -Name $HoloDeckSite2vSwitch -Mtu $HoloDeckSite2vSwitchMTU
            Write-Host -ForegroundColor Green "Creating Portgroup '$HoloDeckSite2PortGroup' on ESX host $VIServer for Site #2"
            New-VirtualPortGroup -VirtualSwitch $HoloDeckSite2vSwitch -Name $HoloDeckSite2PortGroup -VLanID $HoloDeckSite2PGVLAN
            Write-Host -ForegroundColor Green "Setting Security Policy for Portgroup '$HoloDeckSite2PortGroup'"
            Get-VirtualPortGroup -server $viConnection -name $HoloDeckSite2PortGroup | Get-SecurityPolicy | Set-SecurityPolicy -AllowPromiscuous $true -ForgedTransmits $true -MacChanges $true
        }
    # Deleting vSwitches and Portgroups for Site 1 and Site 2
    } elseif ($CreatedSiteNetwork -eq 2) {
        $vSwtichSite2 = Get-VirtualSwitch -Server $viConnection -Name $HoloDeckSite2vSwitch -ErrorAction SilentlyContinue
        $PortGroupSite2 = Get-VirtualPortGroup -Server $viConnection -VirtualSwitch $HoloDeckSite2vSwitch -Name $HoloDeckSite2PortGroup -ErrorAction SilentlyContinue
        if( $vSwtichSite2.Name -eq $HoloDeckSite2vSwitch) {
            if( $PortGroupSite2.Name -eq $HoloDeckSite2PortGroup) {
                Remove-VirtualPortGroup -VirtualPortGroup $PortGroupSite2 -Confirm:$false
                My-Logger "Portgroup '$HoloDeckSite2PortGroup' on Standard Switch '$HoloDeckSite2vSwitch' for Site #2 has been deleted." 1
            } else {
                My-Logger "Portgroup '$HoloDeckSite2PortGroup' does not exist on Standard Switch '$HoloDeckSite2vSwitch' for Site #2." 2
                exit
            }
            Remove-VirtualSwitch -VirtualSwitch $HoloDeckSite2vSwitch  -Confirm:$false
            My-Logger "Standard Switch '$HoloDeckSite2vSwitch' for Site #2 has been deleted." 1
        } else {
            My-Logger "vSphere Standard Switch '$HoloDeckSite2vSwitch' for Site #2 does not exist." 2
            exit
        }
        #
        $vSwtichSite1 = Get-VirtualSwitch -Server $viConnection -Name $HoloDeckSite1vSwitch -ErrorAction SilentlyContinue
        $PortGroupSite1 = Get-VirtualPortGroup -Server $viConnection -VirtualSwitch $HoloDeckSite1vSwitch -Name $HoloDeckSite1PortGroup -ErrorAction SilentlyContinue
        if( $vSwtichSite2.Name -eq $HoloDeckSite2vSwitch) {
            if( $PortGroupSite2.Name -eq $HoloDeckSite2PortGroup) {
                Remove-VirtualPortGroup -VirtualPortGroup $PortGroupSite2 -Confirm:$false
                My-Logger "Portgroup '$HoloDeckSite2PortGroup' on Standard Switch '$HoloDeckSite2vSwitch' for Site #2 has been deleted." 1
            } else {
                My-Logger "Portgroup '$HoloDeckSite2PortGroup' does not exist on Standard Switch '$HoloDeckSite2vSwitch' for Site #2." 2
                exit
            }
            Remove-VirtualSwitch -VirtualSwitch $HoloDeckSite2vSwitch  -Confirm:$false
            My-Logger "Standard Switch '$HoloDeckSite2vSwitch' for Site #2 has been deleted." 1
        } else {
            My-Logger "vSphere Standard Switch '$HoloDeckSite2vSwitch' for Site #2 does not exist." 2
            exit
        }
    # Do nothing
    } else {
        exit 
    }
}
Function UploadHoloConsoleISO {
    # Upload custom HoloConsole ISO to assigned ESXi Datastore
    param(
        [Parameter(Mandatory=$true)]
        [int]$UploadHoloConsoleISO
        )
    if( $UploadHoloConsoleISO -eq 1) {
        # Upload custom HoloConsole ISO to assigned ESXi Datastore
        New-PSDrive -Location $HCdatastore -Name DS -PSProvider VimDatastore -Root "\" > $null
        if(!(Test-Path -Path "DS:/$($DSFolder)")){
            My-Logger "New subfolder '$DSFolder' created" 1
            New-Item -ItemType Directory -Path "DS:/$($DSFolder)" > $null
        }
        My-Logger "Uploading HoloConsole iso '$HoloConsoleISOName' to ESXi Datastore '$HCdatastore'"
        Copy-DatastoreItem -Item $HoloConsoleISO -Destination "DS:/$($DSFolder)"
        My-Logger "Upload completed"
        Remove-PSDrive -Name DS -Force -Confirm:$false
    }
}
Function DeployHoloConsole {
     # Create or delete HoloConsole VM
    param(
        [Parameter(Mandatory=$true)]
        [int]$DeployHoloConsole
        )
    if( $DeployHoloConsole -eq 1) {
        My-Logger "Create HoloConsole VM and mount custom iso"
        New-VM -Name $HoloConsoleVMName -HardwareVersion $HoloConsoleHW -CD -Datastore $HoloConsoleDS -NumCPU $HoloConsoleCPU -MemoryGB $HoloConsoleMEM -DiskGB $HoloConsoleDisk -NetworkName $HoloConsoleNIC -DiskStorageFormat Thin -GuestId $HoloConsoleOS
        Get-VM $HoloConsoleVMName | Get-NetworkAdapter | Where { $_.Type -eq "e1000e"} | Set-NetworkAdapter -Type "Vmxnet3" -NetworkName $HoloConsoleNIC -Confirm:$false
        # Create a VirtualMachineConfigSpec object to set VMware Tools Upgrades to true, set synchronize guest time with host to true (Optional)
            $vmConfigSpec = New-Object VMware.Vim.VirtualMachineConfigSpec
            $vmConfigSpec.Tools = New-Object VMware.Vim.ToolsConfigInfo
            $vmConfigSpec.Tools.ToolsUpgradePolicy = "UpgradeAtPowerCycle"
            $vmConfigSpec.Tools.syncTimeWithHost = $true
            $vmConfigSpec.Tools.syncTimeWithHostAllowed = $true
            $vm = Get-View -ViewType VirtualMachine -Filter @{"Name" = $HoloConsoleVMName}
            $vm.ReconfigVM_Task($vmConfigSpec)
        Start-Sleep -seconds 3  
        # Mount HoloConsole custom ISO to HoloConsole VM
        Get-VM -Name $HoloConsoleVMName | Get-CDDrive | Set-CDDrive -StartConnected $True -IsoPath "[$HoloConsoleDS]$HoloConsoleISOName" -confirm:$false
        # Power on HoloConsole VM
        My-Logger "Power on HoloConsole VM - HoloConsoleVMName" 1
        Start-VM -VM $HoloConsoleVMName
        # Get-VM -Name $HoloConsoleVMName | Get-CDDrive | Set-CDDrive -NoMedia # Remove iso from VM
    } else {
        $VMExists = Get-VM -Name $HoloConsoleVMName -ErrorAction SilentlyContinue
        If ($VMExists) {
            if ($VMExists.PowerState -eq "PoweredOn") {
                My-Logger "Powering off HoloConsole VM - '$HoloConsoleVMName'" 1
                Stop-VM -VM $HoloConsoleVMName -Confirm:$false
                Start-Sleep -seconds 5
            }
            Remove-VM -VM $HoloConsoleVMName -DeletePermanently -Confirm:$false
            My-Logger "HoloConsole VM '$HoloConsoleVMName' deleted" 2
        } else {
            My-Logger "HoloConsole VM '$HoloConsoleVMName' does not seem to exist" 2
        }
    }
}
Function DeployHoloRouter {
    # Deploy or delete HoloRouter
    param(
       [Parameter(Mandatory=$true)]
       [int]$DeployHoloRouter
       )
    if($DeployHoloRouter -eq 1) {
        My-Logger "Import Holo-Router OVA"
        #Convert OVA to OVF
        $HoloRouterOVF = $HoloRouterOVAPath  + '\' + 'HoloRouter-2.0.ovf'
        #$HoloRouterMF = $HoloRouterOVAPath  + '\' + 'HoloRouter-2.0.mf'
        #Set-Location “C:\Program Files\VMware\VMware OVF Tool”
        Start-Process -FilePath "C:\Program Files\VMware\VMware OVF Tool\ovftool.exe "$HoloRouterOVA" "$HoloRouterOVF"" -NoNewWindow -Wait
        Import-vApp -Name $HoloRouterVMName -Datastore $HRdataStore -VMHost $vmhost -Source $HoloRouterOVF -DiskStorageFormat $HoloRouterDiskProvision -Force
        #Import-VApp -Name $HoloRouterVMName -OvfConfiguration $ovfConfig -Datastore $dataStore -VMHost $VMHost -Source $OVF -DiskStorageFormat Thin
        # Configure Holo Router network adapters        
        $HoloRouterNIC1 = Get-VM -Name $HoloRouterVMName | Get-NetworkAdapter -Name "Network adapter 1"
        $HoloRouterNIC2 = Get-VM -Name $HoloRouterVMName | Get-NetworkAdapter -Name "Network adapter 2"
        $HoloRouterNIC3 = Get-VM -Name $HoloRouterVMName | Get-NetworkAdapter -Name "Network adapter 3"
        Set-NetworkAdapter -NetworkAdapter $HoloRouterNIC1 -Portgroup $HoloRouterExtNetwork -Confirm:$false
        Set-NetworkAdapter -NetworkAdapter $HoloRouterNIC2 -Portgroup $HoloRouterSite1Network -Confirm:$false
        Set-NetworkAdapter -NetworkAdapter $HoloRouterNIC3 -Portgroup $HoloRouterSite2Network -Confirm:$false
        # Power on HoloRouter VM
        My-Logger "Power on HoloRouter VM - $HoloRouterVMName" 1
        Start-VM -VM $HoloRouterVMName
        # Deleting working ovf files that are no longer needed
        Remove-Item -Path "$HoloRouterOVAPath\*.ovf" -Confirm:$false
        Remove-Item -Path "$HoloRouterOVAPath\*.mf" -Confirm:$false
        Remove-Item -Path "$HoloRouterOVAPath\*.vmdk" -Confirm:$false
    } else {
        $VMExists = Get-VM -Name $HoloRouterVMName -ErrorAction SilentlyContinue
        If ($VMExists) {
            if ($VMExists.PowerState -eq "PoweredOn") {
                My-Logger "Powering off HoloRouter VM - '$HoloRouterVMName'" 1
                Stop-VM -VM $HoloRouterVMName -Confirm:$false
                Start-Sleep -seconds 5
            }
            Remove-VM -VM $HoloRouterVMName -DeletePermanently -Confirm:$false
            My-Logger "HoloRouter VM '$HoloRouterVMName' deleted" 2
        } else {
            My-Logger "HoloRouter VM '$HoloRouterVMName' does not seem to exist" 2
        }
    }
}
# Main
My-Logger "VMware Holodeck Lab Deployment Started."
Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -WebOperationTimeoutSeconds 900 -Scope Session -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null
# Optional, setting ESXi Host Client timeout period from 15 minutes to 1 hour during setup to prevent pre-mature logoff from ESXi Host Client
# Get-VMHost | Get-AdvancedSetting -Name UserVars.HostClientSessionTimeout | Set-AdvancedSetting -Value 3600
#
if (-not(Find-Module -Name VMware.PowerCLI)){
    Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force
    My-Logger "VMware PowerCLI $VMwareModule.Version installed" 1
}   
My-Logger "Connecting to ESX host $VIServer ..."
$viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue
# Get ESX host datastore objects
$HCdatastore = Get-Datastore -Server $viConnection -Name $HoloConsoleDS -ErrorAction SilentlyContinue
$HRdatastore = Get-Datastore -Server $viConnection -Name $HoloRouterDS -ErrorAction SilentlyContinue
#
PreCheck $EnablePreCheck
CheckDS $EnableCheckDS
CreatedSiteNetwork $EnableSiteNetwork
UploadHoloConsoleISO $RefreshHoloConsoleISO
DeployHoloConsole $EnableDeployHoloConsole
DeployHoloRouter $EnableDeployHoloRouter
#
$EndTime = Get-Date
$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)
My-Logger "VMware Holodeck Lab Deployment Completed!"
My-Logger "StartTime: $StartTime" 1
My-Logger "  EndTime: $EndTime" 1
My-Logger " Duration: $duration minutes" 1

###################################################################################################
#
# WIP = HoloRouter Config
# Logon to newly deployed HoloRouter to change your password
# Run the following to update network adapter IP
# sudo ifconfig eth0 192.168.10.4 netmask 255.255.255.0
# #cd /etc/systemd/network
# vi 10-eth0.network
# [Network]
# Address=192.168.10.4/24
# Gateway=192.168.10.2
# DNS=192.168.111.1

Connect-VIServer 192.168.10.11

$ovfConfig = Get-OvfConfiguration $HoloRouterOVF
$ovfConfig = Get-OvfConfiguration -ovf $HoloRouterOVF
$ovfConfig.ToHashTable()
$ovfConfig = @{
   "vami.ip0.VM_1"="192.168.10.4";
   "vami.netmask0.VM_1"="255.255.255.0";
   "vami.gateway.VM_1"="192.168.10.2"
}

#Requires -Version 3

Function Invoke-OvfTool {

    <#
          .DESCRIPTION
            Deploy a VMware vCenter Server using Microsoft PowerShell. In the vCenter Server ISO, there is a complete folder-based layout of tools
            that support the deployment of OVA. The binary is known as OVFTool and is available for many devices. Here we focus on Windows as our
            client that we will deploy from.
            
            To use this kit, download and extract the vCenter Server ISO to a directory, using a POSIX compliant unzipper such as 7zip.
            By default, we expect it to be in the Downloads folder (i.e. "$env:USERPROFILE\Downloads"). However, you can also populate the Path
            parameter with the location to the uncompressed bits.
  
            Note: You may see mention of 32bit because that is how OVFTOOL works. However, all binaries support 64 bit Windows.
  
            Important: Currently a utility called dos2unix.exe is also required to get the JSON file in the proper unix format.
            Much like the VC binaries, dos2unix.exe is a folder-based runtime, so there is no need to install. Simply download it
            and populate the Dos2UnixPath parameter with the full path. By default we expect it to be in "$env:USERPROFILE\Downloads",
            like everything else.
  
            Download 7zip:
            https://www.7-zip.org/download.html
            
            Download dos2unix:
            https://sourceforge.net/projects/dos2unix/files/dos2unix/
  
            Download vCenter Server (requires login; Create account if needed):
            https://my.vmware.com/group/vmware/details?downloadGroup=VC670B&productId=742&rPId=24515
  
          .NOTES
            Name:         Invoke-OvfTool.ps1
            Author:       Mike Nisk
            Dependencies: Extracted vCenter Server installation ISO for the latest vCenter Server 6.7
            Dependencies: dos2unix.exe (not provided by VMware). This is needed to convert the OutputJson file into unix filetype
            Dependencies: Account on ESXi that can be used for login and deployment. The recommendation is to create an account for
                          the duration of the deployment and then remove it. In the examples, we refer to a ficticious account called
                          ovauser which you can manually create on ESXi as a local user. After the OVA is deployed you can remove the user.
                          Creating and removing ESXi users is optional and is not handled by the script herein. Alternatively, just use root.
      
          .PARAMETER Path
            String. The path to the win32 directory of the extracted vCenter Server installation ISO.
            By default we expect "$env:USERPROFILE\Downloads\VMware-VCSA-all-6.7.0-8832884\vcsa-cli-installer\win32"
  
          .PARAMETER OvfConfig
            PSObject. A hashtable containing the deployment options for a new vCenter Server appliance. See the help for details on creating and using a variable for this purpose.
  
          .PARAMETER Interactive
            Switch. Optionally be prompted for all required values to deploy the vCenter OVA. Not recommended. Instead, use the OvfConfig parameter. See the help for details.
  
          .PARAMETER TemplatePath
            String. Path to the JSON file to model after. This would be the example file provided by VMware or one that you customized previously to become your master.
            We assume no previous work was done and we use the template from VMware and modify as needed.
            The default is "$env:USERPROFILE\Downloads\VMware-VCSA-all-6.7.0-8832884\vcsa-cli-installer\templates\install\embedded_vCSA_on_ESXi.json".
  
          .PARAMETER OutputPath
            String. The full path to the JSON configuration file to create. If the file exists, we overwrite it.
            The default is "$env:Temp\myConfig.JSON".
  
          .PARAMETER JsonPath
            String. The full path to the JSON configuration file to use when deploying a new vCenter appliance.
  
          .PARAMETER Mode
            String. Tab complete through options of Design, Test, Deploy or LogView.
      
          .PARAMETER Description
            String. The name of the site or other friendly identifier for this job.
  
          .PARAMETER Depth
            Integer. Optionally, enter an integer value denoting how many objects to support when importing a JSON template.
            The default is '10', which is up from the Microsoft default Depth of '2'. The maximum is 100.  The Depth must be
            higher than the number of items in the JSON template that we read in.
      
          .EXAMPLE
          #Paste this into PowerShell
  
          $OvfConfig = @{
            esxHostName            = "esx01.lab.local"
            esxUserName            = "root"
            esxPassword            = "VMware123!!"
            esxPortGroup           = "VM Network"
            esxDatastore           = "datastore1"
            ThinProvisioned        = $true
            DeploymentSize         = "tiny"
            DisplayName            = "vcsa01"
            IpFamily               = "ipv4"
            IpMode                 = "static"
            Ip                     = "10.100.1.201"
            FQDN                   = "vcsa01.lab.local"
            Dns                    = "10.100.1.10"
            SubnetLength           = "24"
            Gateway                = "10.100.1.1"
            VcRootPassword         = "VMware123!!!"
            VcNtp                  = "0.pool.ntp.org, 1.pool.ntp.org,2.pool.ntp.org,3.pool.ntp.org"
            SshEnabled             = $true
            ssoPassword            = "VMware123!!!"
            ssoDomainName          = "vsphere.local"
            ceipEnabled            = $false
          }
  
      Note: Passwords must be complex.
      
          This example created a PowerShell object to hold the desired deployment options.
          Please note that some values are case sensitive (i.e. datastore).
          
          .EXAMPLE
          $Json = Invoke-OvfTool -OvfConfig $OvfConfig -Mode Design
          $Json  | fl *  #observe output and get the path
      Invoke-OvfTool -OvfConfig $OvfConfig -Mode Deploy -JsonPath <path-to-your-json-file>
  
          This example creates a variable pointing to a default VMware JSON configuration.
          We then overlay our settings at deploy time using the $OvfConfig variable we created previously.
          This results in a customized vCenter Appliance.
  
          .EXAMPLE
          $result = Invoke-OvfTool -Mode LogView -LogDir "c:\Temp\workflow_1525282021542"
          $result            # returns brief overview of each log file
          $result |fl *      # returns all detail
  
          This example shows how to review logs from previous runs. If you do not specify Logir parameter, we search for all JSON files in the default LogDir location.
  
          ABOUT WINDOWS CLIENT REQUIREMENTS
  
            It is recommended that you have already run the test script that VMware includes to
            check for the required 32bit C++ runtime package:
  
              vcsa-cli-installer\win32\check_windows_vc_redist.bat
  
            If the above script indicates that you are out of date, the minimum required version
            is included on the vCenter Server ISO. You can also download the latest version directly
            from Microsoft.com.
  
  
          ABOUT SSL CERTIFICATE HANDLING
  
            When using vcsa-deploy.exe (which we call in the background), one can optionally set a preference at runtime
            to determine how invalid certificates are handled. The "--no-esx-ssl-verify" is deprecated and "--no-ssl-certificate-verification"
            is used instead.
  
          ABOUT UNICODE ESCAPE (u0027)
      
            When dealing with JSON files in PowerShell you may notice the characters u0027 accidentally placed throughout your text content.
            This is a known issue and we handle it. We prevent these unicode escape characters (u0027) from being injected into the outputted
            JSON file by adjusting the Depth parameter of ConvertTo-Json.
            
            Over time, and depending on the deployment options required, you may need to adjust the Depth to suit your needs.
            By keeping the default depth of 2, you will notice 'u0027' throughout your JSON configuration file.
  
            To avoid this, we attempt to increase the Depth to something greater than the total count of sections VMware currently provides in the JSON template.
            The Microsoft supported maximum for PowerShell 5.1 is a Depth of 100, or 100 items that can be ported in as objects. For our purposes, in doing
            an ESXi deployment of an embedded VC, we only need a Depth of '4' or '5'. However, you can safely make it something like 50 or 99 without issue.
  
            More about unicode escape:
            http://www.azurefieldnotes.com/2017/05/02/replacefix-unicode-characters-created-by-convertto-json-in-powershell-for-arm-templates/
  
      
          ABOUT UTF8 REQUIREMENTS (and dos2unix.exe)
      
            When saving the JSON file with PowerShell's Out-File cmdlet, we encode using utf8 and then run dos2unix.exe (with the -o parameter)
            to ensure that the file is encoded as unix utf8. If you skip this final step of running dos2unix, the VMware pre-deployment tests may fail.
      
          More on SSL Errors
            For ovatool contained in the latest vCenter 6.7 build 8832884, the command parameter '--no-esx-ssl-verify' is deprecated and 
            you must use the new parameter '--no-ssl-certificate-verification' instead.
  
      #>
  
    [CmdletBinding()]
    Param(
          
      #String. The path to the win32 directory of the extracted vCenter Server installation ISO.
      [ValidateScript({ Test-Path $_ -PathType Container })]
      [string]$Path = "$env:USERPROFILE\Downloads\VMware-VCSA-all-6.7.0-8832884\vcsa-cli-installer\win32",
          
      #PSObject. A hashtable containing the deployment options for a new vCenter Server appliance.
      [PSObject]$OvfConfig,
          
      #String. Path to the JSON file to model after. This would be the example file provided by VMware or one that you have customized.
      [ValidateScript({Test-Path $_ -PathType Leaf})]
      [string]$TemplatePath = "$env:USERPROFILE\Downloads\VMware-VCSA-all-6.7.0-8832884\vcsa-cli-installer\templates\install\embedded_vCSA_on_ESXi.json",
  
      #String. The full path to the JSON configuration file to create. This is used in Design Mode to create a JSON file on disk containing all customizations for this deployment.
      [string]$OutputPath = "$env:Temp\myConfig.JSON",
    
      #String. The Config File to use when deploying a new vCenter Server appliance.
      [ValidateScript({Test-Path -PathType Leaf $_})]
      [string]$JsonPath,
      
      #String. Tab complete through options of Design, Test, Deploy or LogView.
      [ValidateSet('Design','Test','Deploy','LogView')]
      [string]$Mode,
  
      #String. Dos2Unix binary location. Adjust as needed and download if you do not have it.
      [string]$Dos2UnixPath = "$env:USERPROFILE\Downloads\dos2unix-7.4.0-win64\bin\dos2unix.exe",
      
      #Switch. Optionally, activate to skip all dos2unix requirements and file conversion steps.
      [switch]$SkipDos2Unix,
  
      #String. The directory to write or read logs related to ovftool. This is not PowerShell transcript logging, this is purely deployment related and the resuling output paths are long, so keep this path short for best results.
      [string]$LogDir = $env:Temp,
    
      #String. The name of the site or other friendly identifier for this job.
      [string]$Description,
    
      #Integer. The Depth is an integer value denoting how many objects to support when importing a JSON template. Max is 100, default is here is 10.
      [ValidateRange(1,100)]
      [int]$Depth = '10'
    )
  
    Process {
    
      ## Path to vcsa-deploy.exe binary
      $vcsa_deploy = "$Path\vcsa-deploy.exe" 
      
      switch($Mode){
        Design{
  
          If(-Not($SkipDos2Unix)){
            try{
              Test-Path -Path $Dos2unixPath -PathType Leaf -ErrorAction Stop
            }
            catch{
              throw 'Dos2Unix is required!'
            }
          }
    
          ## JSON to Object
          $obj_Json_Template = (Get-Content -Raw $TemplatePath) -join "`n" | ConvertFrom-Json
  
          ## New variable to hold our options
          $myOpts = $obj_Json_Template
  
          ## If user did not populate the OvaConfig parameter
          If(-Not($OvfConfig)){
  
            Write-Warning -Message 'OvfConfig parameter was not populated!'
            Write-Output -InputObject 'Enter the details below (~20 items), or press CTRL + C to exit.'
            Write-Output -InputObject ''
      
            ## Build the object
            $OvfConfig = New-Object -TypeName PSObject -Property @{
  
              esxHostName       =  Read-Host -Prompt 'esxHostName'
              esxUserName       =  Read-Host -Prompt 'esxUserName'
              esxPassword       =  Read-Host -Prompt 'esxPassword'
              esxPortGroup      =  Read-Host -Prompt 'esxPortGroup'
              esxDatastore      =  Read-Host -Prompt 'esxDatastore'
              ThinProvisioned   = (Read-Host -Prompt 'ThinProvisioned (true/false)').ToLower()
              DeploymentSize    =  Read-Host -Prompt 'DeploymentSize (i.e. tiny,small,etc.)'
              DisplayName       =  Read-Host -Prompt 'DisplayName'
              IpFamily          =  Read-Host -Prompt 'IpFamily (i.e. ipv4)'
              IpMode            =  Read-Host -Prompt 'IpMode (i.e static)'
              Ip                =  Read-Host -Prompt 'IP Address'
              Dns               =  Read-Host -Prompt 'Dns Address'
              SubnetLength      =  Read-Host -Prompt 'Subnet Length (i.e. 16, 24, etc.)'
              Gateway           =  Read-Host -Prompt 'Gateway'
              FQDN              =  Read-Host -Prompt 'FQDN'
              VcRootPassword    =  Read-Host -Prompt 'VcRootPassword'
              VcNtp             =  Read-Host -Prompt 'VcNtp'
              SshEnabled        = (Read-Host -Prompt 'SSH Enabled (true/false)').ToLower()
              ssoPassword       =  Read-Host -Prompt 'ssoPassword'
              ssoDomainName     =  Read-Host -Prompt 'ssoDomainName'
              ceipEnabled       = (Read-Host -Prompt 'ceipEnabled (true/false)').ToLower()
            }
          }
        
          #region Ovf Configuration
          If($OvfConfig){
  
            ## Comments
            If($Description){
              $myOpts.__comments                            = "Custom deployment template for $($Description) using embedded VC deployment type"
            }
            Else{
              $myOpts.__comments                            = "Custom deployment template using embedded VC deployment type"
            }
            $myOpts.new_vcsa.appliance.__comments           = "appliance options"
            $myOpts.ceip.description.__comments             = "ceip options"
      
            ## Options esxi
            $myOpts.new_vcsa.esxi.hostname                  = $OvfConfig.esxHostName
            $myOpts.new_vcsa.esxi.username                  = $OvfConfig.esxUserName
            $myOpts.new_vcsa.esxi.password                  = $OvfConfig.esxPassword
            $myOpts.new_vcsa.esxi.deployment_network        = $OvfConfig.esxPortGroup
            $myOpts.new_vcsa.esxi.datastore                 = $OvfConfig.esxDatastore
  
            ## Options appliance
            $myOpts.new_vcsa.appliance.thin_disk_mode       = $OvfConfig.ThinProvisioned
            $myOpts.new_vcsa.appliance.deployment_option    = $OvfConfig.DeploymentSize
            $myOpts.new_vcsa.appliance.name                 = $OvfConfig.DisplayName
  
            ## Options network
            $myOpts.new_vcsa.network.ip_family              = $OvfConfig.IpFamily
            $myOpts.new_vcsa.network.mode                   = $OvfConfig.IpMode
            $myOpts.new_vcsa.network.ip                     = $OvfConfig.IP
            $myOpts.new_vcsa.network.dns_servers            = $OvfConfig.Dns
            $myOpts.new_vcsa.network.prefix                 = $OvfConfig.SubnetLength
            $myOpts.new_vcsa.network.gateway                = $OvfConfig.Gateway
            $myOpts.new_vcsa.network.system_name            = $OvfConfig.FQDN
  
            ## Options os
            $myOpts.new_vcsa.os.password                    = $OvfConfig.VcRootPassword
            $myOpts.new_vcsa.os.ntp_servers                 = $OvfConfig.VcNtp
            $myOpts.new_vcsa.os.ssh_enable                  = $OvfConfig.SshEnabled
  
            ## Options sso
            $myOpts.new_vcsa.sso.password                   = $OvfConfig.ssoPassword
            $myOpts.new_vcsa.sso.domain_name                = $OvfConfig.ssoDomainName
  
            ## Options ceip
            $myOpts.ceip.settings.ceip_enabled              = $OvfConfig.ceipEnabled
          } #End If
          #endregion
    
          ## Output to file
          Write-Verbose -Message ('Saving {0} to disk' -f $OutputPath)
          $myOpts | Select-Object -Property * | ConvertTo-Json -Depth $Depth | ForEach-Object { [System.Text.RegularExpressions.Regex]::Unescape($_) } | Out-File -Encoding utf8 $OutputPath
  
          ## Convert to unix format
          $wrappedCmd = "-o $OutputPath"
          Write-Verbose -Message ('Converting {0} to unix format' -f $OutputPath)
          Start-Process $Dos2unixPath $wrappedCmd -NoNewWindow -Wait
          
          ## Output FullName
          try{
              $JsonFile = Get-ChildItem $OutputPath -ErrorAction Stop
              return ($JsonFile | Select-Object -ExpandProperty FullName)
          }
          catch{
              Write-Error -Message $Error[0].exception.Message
          }
        }
        Test{
          Write-Verbose -Message ('Testing JSON file {0}' -f $JsonPath)
          $result = Start-Process $vcsa_deploy "install $JsonPath --accept-eula --precheck-only --log-dir $LogDir" -NoNewWindow -Wait
          return $result
        }
        Deploy{
      
          ## Deploy OVA
          Write-Verbose -Message 'Deploying vCenter Server OVA!'
          try{
            $result = Start-Process $vcsa_deploy "install $JsonPath --accept-eula --no-ssl-certificate-verification --log-dir $LogDir" -NoNewWindow -Wait
          }
          catch{
            Write-Warning -Message 'Problem deploying OVA!'
            Write-Error -Message ('{0}' -f $_.Exception.Message)
          }
          return $result
        }
        LogView{
          $result = Get-ChildItem $logDir -Recurse -Include *.JSON | ForEach-Object {$file = $_; "Processing: $file"; (Get-Content $file) -join "`n" | ConvertFrom-Json}
          return $result
        }
      } #End Switch
    } #End Process
  }