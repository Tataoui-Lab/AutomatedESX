# Author: Dominic Chan
# Website: www.vmware.com
# Description: PowerCLI script to deploy or refresh a VMware Holodeck environment.
#              ----
# Reference: https://core.vmware.com/introducing-holodeck-toolkit
# Credit: VMware Holodeck / VMware Lab Configurator Teams
#
# Changelog
# 01/17/24
#   * Initital draft
#   - kickoff initial or refresh HoloConsole ISO as needed while renaming prior version
#   - automate the creation/deletion of ESXi host network according to 'VMware Holo-Setup-Host-Prep' (January 2023)
#   - uploading custom Holo Console iso from Build Host to ESXi host datastore
#   - automate the deployment/deletion of Holo-Console VM according to 'VMware Holo-Setup-Deploy-Console' (January 2023)
#   - automated the deployment/deletion of Holo-Router according to 'VMware Holo-Setup-Deploy-Router' (January 2023)
#   - automate ESX host clean up to remove prior Holodeck deployment (i.e. HoloConsole, HoloRouter, Holodeck Network, Holodeck related ISO)
#   - Synchronize custom VLC configuration files between Build Host and HoloConsole VM
# 
# To Do
#   - Kickoff VLC process in headless mode from Build Host or during newly ESX host refresh (WIP)
#
$StartTime = Get-Date
$verboseLogFile = "VMware Holodeck Deployment.log"
#
# Customer lab environment variables - Must update to work with your lab environment
############################################################################################################################
#
# Physical ESX Host
$VIServer = "192.168.10.11" # <-------------------------------- Must update with your lab info (ESX host)
$VIUsername = 'root' # <--------------------------------------- Must update with your lab info (ESX host)
$VIPassword = 'VMware123!' # <--------------------------------- Must update with your lab info (ESX host)
# $vmhost = Get-VMHost -Name $VIServer
# Specifies whether deployment is on ESXi host or vCenter Server (ESXI or VCENTER)
# $DeploymentTarget = "ESXI" - Future
#
# Full Path to HoloRouter ova and generated HoloConsole iso
$DSFolder = '' # Datastore folder / subfolder name if any - i.e. 'iso\' or '' for datastore root
# $HoloConsoleISOName = 'Holo-Console-4.5.2.iso'
$HoloConsoleISOName = 'Holo-Console-5.0.0.iso' # <---------------------------------------------- Must update with your lab info (Build Host)
$HoloConsoleISOPath = 'C:\Users\cdominic\Downloads\holodeck-standard-main\Holo-Console' # <----- Must update with your lab info (Build Host)
$HoloConsoleISO = $HoloConsoleISOPath + '\' + $HoloConsoleISOName
$HoloRouterOVAName = 'HoloRouter-2.0.ova'
$HoloRouterOVAPath = 'C:\Users\cdominic\Downloads\holodeck-standard-main\Holo-Router' # <------- Must update with your lab info (Build Host)
$HoloRouterOVA = $HoloRouterOVAPath  + '\' + $HoloRouterOVAName
$OVFToolEXE = "C:\Program Files\VMware\VMware OVF Tool\ovftool.exe"
$VLCHeadlessConfig = 'VLC-HeadLess-Config.ini'
$VLCSite1Path = 'C:\Users\cdominic\Downloads\holodeck-standard-main\VLC-Holo-Site-1' # <-------- Must update with your lab info (Build Host)
$VLCSite2Path = 'C:\Users\cdominic\Downloads\holodeck-standard-main\VLC-Holo-Site-2' # <-------- Must update with your lab info (Build Host)
#
$NewHoloConsoleISO = 0 # (0 - Use existing HoloConsole Custom ISO, 1 - Create a fresh HoloConsole Custom ISO, 2 - Create a fresh HolocConsole Custom ISO with Temp cleanup)
$EnablePreCheck = 0 # (0 - No core binaries verification on Build Host, 1 - Verfiy Holodeck core binaries are accessible on Build Host)
$EnableCheckDS = 0 # (1 - Verfiy assigned datastores for HoloConsole and HoloRouter are accessible on ESX host)
$EnableSiteNetwork = 0 # (1 - Verify / create Holodeck vritual networks on ESX host, 2 - delete previous Holodeck virtual networks on ESX host)
$RefreshHoloConsoleISO  = 0 # (1 - Upload / refresh the latest HoloConsole ISO on ESX host, 2 - Delete previously uploaded HoloConsole ISO on ESX host)
$EnableDeployHoloConsole = 0 # (1 - Create HoloConsole VM, 2 - Delete HoloConsole VM)
$EnableDeployHoloRouter = 0 # (1 - Create HoloRouter VM, 2 - Delete HoloRouter VM)
$EnableVLC = 0  # (1 - copy save VLC configuration onto HoloConsole VM, 2 - Kick off VLC in headless mode on HoloConsole VM)
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
$HoloConsoleDS = "Repository" # <------------------- Must update with your lab info (ESX host)
$HoloConsoleHW = "vmx-19"
$HoloConsoleOS = "windows2019srv_64Guest"
$HoloConsoleCPU = 2
$HoloConsoleMEM = 4 #GB
$HoloConsoleDisk = 90 #GB
$HoloConsoleNIC = "VLC-A-PG"
#
# HoloRouter OVA settings
$HoloRouterVMName = "Holo-C-Router"
#$HoloRouterEULA = "1"
$HoloRouterDS = "Repository" # <------------------- Must update with your lab info (ESX host)
$HoloRouterExtNetwork = "VM_Network" # <----------- Must update with your lab info (ESX host)
$HoloRouterSite1Network = $HoloDeckSite1PortGroup
$HoloRouterSite2Network = $HoloDeckSite2PortGroup
$HoloRouterDiskProvision = "thin"
$HoloRouterSite1VLAN = "10"
$HoloRouterSite1IP = "10.0.0.1"
$HoloRouterSite1Subnet = "255.255.255.0"
$HoloRouterSite2VLAN = "20"
$HoloRouterSite2IP = "10.0.20.1"
$HoloRouterSite2Subnet = "255.255.255.0"
$HoloRouterInternalFWDIP = "10.0.0.201"
$HoloRouterInternalFWDPort = "3389"
$HoloRouterExternalIP = "192.168.10.4" # <--------- Must update with your lab info
$HoloRouterExternalSubnet = "255.255.255.0" # <---- Must update with your lab info
$HoloRouterExternalGW = "192.168.10.2" # <--------- Must update with your lab info
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
Function CreateHoloConsoleISO {
    # Backup prior HoloConsole custom ISO and generate a new one
    param(
        [Parameter(Mandatory=$true)]
        [int]$CreateHoloConsoleISO
        )
    if($CreateHoloConsoleISO -gt 0) {
        $ExistHCISOCount = 0
        $ExistHCISO = Get-ChildItem -Path $HoloConsoleISOPath -Filter "CustomWindows*.iso"
        foreach( $i in $ExistHCISO) { 
            Rename-Item $i.FullName ($i.basename.substring(0,$i.BaseName.length-4)+".isoold")
            $ExistHCISOCount = $ExistHCISOCount + 1
        }
        if ($ExistHCISOCount -gt 0) {
            My-Logger "$ExistHCISOCount prior Custom HoloConsole ISO was found and renamed (.isoold extension)" 1 
        } else {
            My-Logger "No prior Custom HoloConsole ISO was found" 1
        }
        My-Logger "New HoloConsole ISO creation started" 
        $CreateISO = $HoloConsoleISOPath+"\"+"createISO.ps1"
        & $CreateISO
        My-Logger "New HoloConsole ISO file '$HoloConsoleISOName' created" 1
        $NewlyHCISOName = Get-ChildItem -Path $HoloConsoleISOPath -Filter "CustomWindows*.iso"
        $NewlyHCISO  = $HoloConsoleISOPath + '\' + $NewlyHCISOName
        Rename-Item -Path $NewlyHCISO -NewName $HoloConsoleISOName
        My-Logger "HoloConsole ISO renamed to $HoloConsoleISOName" 1
        if( $CreateHoloConsoleISO -eq 2) {
            Remove-Item -Path $HoloConsoleISOPath\Temp -Recurse -Force
        }
    } 
}
Function PreCheck {
    # Verfiy Holodeck core binaries and OVFTool are accessible 
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
        if(!(Test-Path $OVFToolEXE)) {
            My-Logger "`nUnable to locate Open Virtualization Format Tool (ovftool) on your Build Host ...`nexiting" 2
            exit
        } else {
            My-Logger "Open Virtualization Format Tool (ovftool) located on Build Host"
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
Function CreateSiteNetwork {
    # Configure / delete virtual networks for site 1 & 2
    param(
        [Parameter(Mandatory=$false)]
        [int]$CreateSiteNetwork
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
    } else {
        # Do nothing
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
    } elseif ( $UploadHoloConsoleISO -eq 2) {
        # Remove prior HoloConsole ISO (only work if it was previously uploaded by this script and iso dismounted on HoloConsole VM)
        New-PSDrive -Location $HCdatastore -Name DS -PSProvider VimDatastore -Root "\" > $null
        My-Logger "Deleting HoloConsole ISO '$HoloConsoleISOName' from ESXi Datastore '$HCdatastore'"
        Remove-Item -Path "DS:/$($DSFolder)/Holo-Console-4.5.2.iso"
        Remove-PSDrive -Name DS -Force -Confirm:$false
        My-Logger "HoloConsole ISO deleted" 2
    } else {
        # Do nothing
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
        My-Logger "Power on HoloConsole VM - $HoloConsoleVMName" 1
        Start-VM -VM $HoloConsoleVMName
        # Get-VM -Name $HoloConsoleVMName | Get-CDDrive | Set-CDDrive -NoMedia # Remove iso from VM
    } elseif ($DeployHoloConsole -eq 2) {
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
    } else {
        # Do nothing
    }
}
Function DeployHoloRouter {
    # Deploy or delete HoloRouter
    param(
       [Parameter(Mandatory=$true)]
       [int]$DeployHoloRouter
       )
    if($DeployHoloRouter -eq 1) {
        # Deploy HoloRouter OVA
        My-Logger "Import Holo-Router OVA"
        $HoloRouterHost = "vi://root:"+$VIPassword+"@"+$VIServer
        $OVFToolEXE = "C:\Program Files\VMware\VMware OVF Tool\ovftool.exe"
        $HRargumentlist = "--noDestinationSSLVerify --acceptAllEulas --disableVerification --name=$HoloRouterVMName --net:ExternalNet=$HoloRouterExtNetwork --net:Site_1_Net=$HoloRouterSite1Network --net:Site_2_Net=$HoloRouterSite2Network --prop:External_IP=$HoloRouterExternalIP --prop:External_Subnet=$HoloRouterExternalSubnet --prop:External_Gateway=$HoloRouterExternalGW --prop:Site_1_VLAN=$HoloRouterSite1VLAN --prop:Site_1_IP=$HoloRouterSite1IP --prop:Site_1_Subnet=$HoloRouterSite1Subnet  --prop:Site_2_VLAN=$HoloRouterSite2VLAN --prop:Site_2_IP=$HoloRouterSite2IP --prop:Site_2_Subnet=$HoloRouterSite2Subnet --prop:Internal_FWD_IP=$HoloRouterInternalFWDIP --prop:Internal_FWD_PORT=$HoloRouterInternalFWDPort --datastore=$HoloRouterDS --diskMode=$HoloRouterDiskProvision --ipAllocationPolicy=fixedPolicy --allowExtraConfig --X:injectOvfEnv --powerOn $HoloRouterOVA $HoloRouterHost"
        #  append to HRargumentlist to enable logging --X:logFile=C:\ovflog.txt
        Start-Process -FilePath $OVFToolEXE -argumentlist $HRargumentlist -NoNewWindow -Wait
        My-Logger "Power on HoloRouter VM - $HoloRouterVMName" 1
    } elseif ($DeployHoloRouter -eq 2) {
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
    } else {
        # Do nothing
    }
}
Function VLC {
       # Upload custom VLC configuration from Build Host, initate VLC bring-up process
       param(
        [Parameter(Mandatory=$true)]
        [int]$VLC
        )
        Do {
            My-Logger "Waiting for HoloConsole VM '$HoloConsoleVMName' to come online" 1
            $HoloConsoleVM = Get-VM -Name $HoloConsoleVMName
            $HCCondition = $HoloConsoleVM.ExtensionData.Guest.ToolsStatus
            Start-Sleep 5
        } While (
            $HoloConsoleVM.ExtensionData.Guest.ToolsStatus -eq 'toolsNotRunning') # toolsNotRunning vs toolsOK
            My-Logger "HoloConsole VM '$HoloConsoleVMName' is now online"
            Start-Sleep 5
        if($VLC -gt 0) {
            # $credMyGuestCred = Get-Credential vcf\Administrator
            # Copy VLC files (headless.ini for now) from Build Host to VLC Site 1 folder on HoloConsole VM
            Copy-VMGuestFile -VM $HoloConsoleVMName -LocalToGuest -Source $VLCSite1Path\$VLCHeadlessConfig -Destination 'C:\VLC\VLC-Holo-Site-1\' -GuestUser 'vcf\administrator' -GuestPassword 'VMware123!'
        } elseif ($VLC -eq 2) {
            #Holo-Site-1-vcf-ems-public.json
            $VLCGUI = "C:\VLC\VLC-Holo-Site-1\VLCGui.ps1 -iniConfigFile .\VLC-HeadLess-Config.ini -isCLI $true"
            Invoke-VMScript -VM $HoloConsoleVM -ScriptText $VLCGUI -GuestUser 'vcf\administrator' -GuestPassword 'VMware123!' -ScriptType Powershell
            # Invoke-VMScript -VM $HoloConsoleVM -ScriptText $VLCGUI -GuestCredential $credMyGuestCred -ScriptType Powershell
        } else {
            # Do nothing
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
CreateHoloConsoleISO $NewHoloConsoleISO
PreCheck $EnablePreCheck
CheckDS $EnableCheckDS
CreateSiteNetwork $EnableSiteNetwork
UploadHoloConsoleISO $RefreshHoloConsoleISO
DeployHoloConsole $EnableDeployHoloConsole
DeployHoloRouter $EnableDeployHoloRouter
VLC $EnableVLC

########################################################
# Use the following sequence for lab tear down
# 
# DeployHoloRouter 2
# DeployHoloConsole 2
# UploadHoloConsoleISO 2
# CreateSiteNetwork 2
#
$EndTime = Get-Date
$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)
My-Logger "VMware Holodeck Lab Deployment Completed!"
My-Logger "StartTime: $StartTime" 1
My-Logger "  EndTime: $EndTime" 1
My-Logger " Duration: $duration minutes" 1