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
$EnableSiteNetwork = 1 # (1 - Verify / create Holodeck vritual networks on ESX host, 2 - delete previous Holodeck virtual networks on ESX host)
$RefreshHoloConsoleISO  = 0 # (1 - Upload / refresh the latest HoloConsole ISO on ESX host)
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
    # Deleting vSwitches and Portgroups for Site 2 and Site 2
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
        if( $vSwtichSite1.Name -eq $HoloDeckSite1vSwitch) {
            if( $PortGroupSite1.Name -eq $HoloDeckSite1PortGroup) {
                Remove-VirtualPortGroup -VirtualPortGroup $PortGroupSite1 -Confirm:$false
                My-Logger "Portgroup '$HoloDeckSite1PortGroup' on Standard Switch '$HoloDeckSite1vSwitch' for Site #1 has been deleted." 1
            } else {
                My-Logger "Portgroup '$HoloDeckSite1PortGroup' does not exist on Standard Switch '$HoloDeckSite1vSwitch' for Site #1." 2
                exit
            }
            Remove-VirtualSwitch -VirtualSwitch $HoloDeckSite1vSwitch  -Confirm:$false
            My-Logger "Standard Switch '$HoloDeckSite1vSwitch' for Site #1 has been deleted." 1
        } else {
            My-Logger "vSphere Standard Switch '$HoloDeckSite1vSwitch' for Site #1 does not exist." 2
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
CreatedSiteNetwork 1 $EnableSiteNetwork
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
