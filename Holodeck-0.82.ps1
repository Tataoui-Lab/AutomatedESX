# Author: Dominic Chan
# Website: www.broadcom.com
# Description: PowerCLI script to deploy or refresh a VMware Holodeck environment.
#              ----
# Reference: https://core.vmware.com/introducing-holodeck-toolkit
# Credit: VMware Holodeck / VMware Lab Configurator Teams
#
# Changelog
# 07/02/24
#   * Update for Holodeck 5.1.1
#   - Autoextract Holodeck zip package
#   - Automate download require binaries based on Holodeck specification
#     * (manual download still requires for PowerCLI, OVFTools, CloudBuilder, and Aria)
#   - Update 'CreateISO.ps1' to match existing build environment and binaries versions based on Holodeck specification
#   - Update 'additionalfiles.txt' to match existing build environment and binaries versions
#   - Update 'additionalcommands.bat' to match existing build environment and binaries versions
#   - Update 'Holo-A1-511.ini' for VLC to match existing build environment and binaries versions
#
# 01/17/24
#   * Initital draft
#   - kickoff initial or refresh HoloConsole ISO as needed while renaming prior version
#   - automate the creation/deletion of ESXi host network according to 'VMware Holo-Setup-Host-Prep' (January 2023)
#   - uploading custom Holo Console iso from Build Host to ESXi host datastore
#   - automate the deployment/deletion of Holo-Console VM according to 'VMware Holo-Setup-Deploy-Console' (January 2023)
#   - automated the deployment/deletion of Holo-Router according to 'VMware Holo-Setup-Deploy-Router' (January 2023)
#   - automate ESX host clean up to remove prior Holodeck deployment (i.e. HoloConsole, HoloRouter, Holodeck Network, Holodeck related ISO)
#   - Synchronize custom VLC configuration files between Build Host and HoloConsole VM
#   - Kickoff VLC process in headless mode from Build Host 
# 
# To Do
#   - Headless VLC process for dual sites
#
# Required 
#   - Windows 10/11 Desktop with PowerShell (Optional: Visual Studio Code)
#   - VMware OVFTools install
#   - VMware ESX host with reasonable CPU cores, memory capacity, and storage
#   - List of require binaries from Broadcom / VMware support portal (see 'Note' section below)
#   - Minor edit/update to few (dozen) variables within this script that are marked with "UPDATE ACCORDINGLY TO YOUR LAB ENVIRONNMENT"
#       $VIServer - FQDN to your physical ESX host
#       $VIIP - Management IP address to your physical ESX host
#       $VIPassword - ROOT password to your physical ESX host
#       $labDNS = Lab DNS server with external DNS resolution (i.e. 8.8.8.8)
#       $HoloDeckPath - Path on your local desktop housing Holodeck and required binaries (min 250 GB)
#       $HoloDeckDS - ESX datastore for the automated nested VCF build (This also include any Aria components)
#       $HoloConsoleDS - ESX datastore to where Holodeck jumpbox (HoloConsole) would be deploy - can be the same $HoloDeckDS
#       $HoloRouterDS - ESX datastore to where Holodeck custom router (HoloRouter) would be deploy - can be the same $HoloDeckDS
#       $HoloConsoleISOName - Name to custom build ISO craeted by Holodeck for this automated build
#       $HoloRouterExternalIP = Static IP address dedicate for HoloRouter to faciliate all outbound VCF traffic (This is MUST to gain jumpbox access)
#       $HoloRouterExternalSubnet = Subnet mask from your lab environment
#       $HoloRouterExternalGW = IP address / Gateway for Internet access
#
# Note
#   The following binaries require a Broadcom / VMware account and must be download manually
#   - Latest VMware PowerCLI 13.2.1-22851661
#   - Latest VMware OVFTool 4.6.2 MSI
#   - VMware Cloud Foundation 5.1.1 Cloud Builder OVA
#   - VMware Aria Suite Lifecycle 8.16.0 Easy Installer for Aria Automation 8.16.2 ISO
#
$StartTime = Get-Date
$verboseLogFile = 'VMware Holodeck 5.1.1 Deployment.log'
#
# Custom lab environment variables - Must update to work with your lab environment
###############################################################################################################################
#
# Physical ESX Host
$VIServer = 'esx01.tataoui.com' # <------------------------------------- UPDATE ACCORDINGLY TO YOUR LAB ENVIRONNMENT (ESX HOST)
$VIIP = '192.168.10.11' # <--------------------------------------------- UPDATE ACCORDINGLY TO YOUR LAB ENVIRONNMENT (ESX HOST)
$VIUsername = 'root'
$VIPassword = 'VMware123!' # <------------------------------------------ UPDATE ACCORDINGLY TO YOUR LAB ENVIRONNMENT (ESX HOST)
$labDNS = '8.8.8.8' # <------------------------------------------------------------ UPDATE ACCORDINGLY TO YOUR LAB ENVIRONNMENT
# $vmhost = Get-VMHost -Name $VIServer
# Specifies whether deployment is on ESXi host or vCenter Server (ESXI or VCENTER)
# $DeploymentTarget = "ESXI" - Future
#
$HoloDeckZip = 'holodeck-standard-main5.1.1.zip'
$HoloDeckFileName = [System.IO.Path]::GetFileNameWithoutExtension($HoloDeckZip)
# Uncomment line below if your local disk 'C:' has sufficient storage space.  Path would be set to C:\Users\UserID\Downloads
# $HoloDeckPath = "$env:USERPROFILE\Downloads"
# or set $HoloDeckPath to your desire location
$HoloDeckPath = 'D:\Holodeck' # <-------------------------------------------------- UPDATE ACCORDINGLY TO YOUR LAB ENVIRONNMENT
If (-not (Test-Path -Path "$HoloDeckPath\$HoloDeckZip")) {
    Write-Error "Holodeck zip file not find.  Please ensure is donwload and place at $HoloDeckPath"
    Exit
    }
If (-not (Test-Path -Path "$HoloDeckPath\$HoloDeckFileName" -PathType Container)) {
        Write-Host "Expanding Holodeck zip to $env:USERPROFILE\Downloads"
        Expand-Archive -LiteralPath "$HoloDeckPath\$HoloDeckZip" -DestinationPath "$HoloDeckPath\$HoloDeckFileName\"
    }
# Full Path to HoloRouter ova and generated HoloConsole iso
$DSFolder = '' # Datastore folder / subfolder name if any (i.e. 'iso\' or '' for ESX datastore root)
# Holodeck Datastore to use for VFC build out
$HoloDeckDS = 'VCF_1' # <---------------------------------------------------------- UPDATE ACCORDINGLY TO YOUR LAB ENVIRONNMENT
$HoloConsoleISOName = 'Holo-Console-5.1.1.iso' # <--------------------------------- UPDATE ACCORDINGLY TO YOUR LAB ENVIRONNMENT
# $HoloConsoleISOName = 'Holo-Console-5.0.0.iso'
# $HoloConsoleISOName = 'Holo-Console-4.5.2.iso'
$HoloConsoleISOPath = "$HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\Holo-Console"
$HoloConsoleISO = $HoloConsoleISOPath + '\' + $HoloConsoleISOName
$HoloRouterOVAName = 'HoloRouter-2.0.ova'
$HoloRouterOVAPath = "$HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\Holo-Router"
$HoloRouterOVA = $HoloRouterOVAPath  + '\' + $HoloRouterOVAName
$OVFToolEXE = "C:\Program Files\VMware\VMware OVF Tool\ovftool.exe"
$VLCSite1Config = 'Holo-A1-511.ini'
$VLCSite2Config = 'Holo-A2-511.ini'
$VLCSite1Path = "$HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\VLC-Holo-Site-1"
$VLCSite2Path = "$HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\VLC-Holo-Site-2"
#
# Require binaries location and filename
#
$WinIso_URL = 'https://software-download.microsoft.com/download/pr/17763.737.190906-2324.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us_1.iso'
$chromeInstallerExe_URL = 'https://dl.google.com/tag/s/appguid%3D%7B8A69D345-D564-463C-AFF1-A69D9E530F96%7D%26iid%3D%7B7A811669-A664-381D-7947-7BFEED928070%7D%26lang%3Den%26browser%3D5%26usagestats%3D1%26appname%3DGoogle%2520Chrome%26needsadmin%3Dprefers%26ap%3Dx64-statsdef_1%26installdataindex%3Dempty/chrome/install/ChromeStandaloneSetup64.exe'
$puttyMSI_URL = 'https://tartarus.org/~simon/putty-snapshots/w64/putty-64bit-installer.msi'
$PowerVCFZip_URL = 'https://github.com/vmware/powershell-module-for-vmware-cloud-foundation/archive/refs/heads/main.zip'
$PowerVSZip_URL = 'https://github.com/vmware-samples/power-validated-solutions-for-cloud-foundation/archive/refs/heads/main.zip'
$NotePadPlusPlus_URL = 'https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.6.5/npp.8.6.5.Installer.x64.exe'
$vmToolsExe_URL = 'https://packages.vmware.com/tools/releases/12.4.0/windows/x64/VMware-tools-12.4.0-23259341-x86_64.exe'
$powerCLIZip_URL = 'https://developer.broadcom.com/tools/vmware-powercli/latest/'
$ovfToolMsi_URL = 'https://developer.broadcom.com/tools/open-virtualization-format-ovf-tool/latest/'
$cloudBuilderISO_URL = 'https://support.broadcom.com/group/ecx/productfiles?subFamily=VMware%20Cloud%20Foundation&displayGroup=VMware%20Cloud%20Foundation%205.1&release=5.1.1&os=&servicePk=208634&language=EN'
$lcmInstallOVA_URL = 'https://support.broadcom.com/group/ecx/productfiles?subFamily=VMware%20Aria%20Automation&displayGroup=VMware%20Aria%20Automation&release=8.16.2&os=&servicePk=208521&language=EN'

$winIso_Filename = '17763.737.190906-2324.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us_1.iso'
$chromeInstallerExe_Filename = 'ChromeStandaloneSetup64.exe'
$puttyMSI_Filename = 'putty-64bit-2024-05-25-installer.msi'
$powerVCFZip_Filename = 'powershell-module-for-vmware-cloud-foundation-main.zip'
$powerVSZip_Filename = 'power-validated-solutions-for-cloud-foundation-main.zip'
$NotePadPlusPlus_Filename = 'npp.8.6.5.Installer.x64.exe' # default - npp.8.5.4.Installer.x64.exe
$vmToolsExe_Filename = 'VMware-tools-12.4.0-23259341-x86_64.exe'
$powerCLIZip_Filename = 'VMware-PowerCLI-13.2.1-22851661.zip'
$ovfToolMsi_Filename = 'VMware-ovftool-4.6.2-22220919-win.x86_64.msi'
$cloudBuilderISO_Filename = 'VMware-Cloud-Builder-5.1.1.0-23480823_OVF10.ova'
$lcmInstallOVA_Filename = 'VMware-Aria-Automation-Lifecycle-Installer-23508932.iso'
$DownloadDestination = $HoloDeckPath
#
###############################################################################################################################
# EDIT WITH CAUTIOUS BEYOND THIS POINT - SET TO MATCH DEFAULT HOLODECK DOCUMENTATION
###############################################################################################################################
#
# Default Holodeck settings align to VMware Holodeck 5.1.1 documentation
# ESXi host vSwitch and Portgroup settings
$HoloDeckSite1vSwitch = 'VLC-A'
$HoloDeckSite1vSwitchMTU = 9000
$HoloDeckSite1PortGroup = 'VLC-A-PG'
$HoloDeckSite1PGVLAN = 4095
$HoloDeckSite2vSwitch = 'VLC-A2'
$HoloDeckSite2vSwitchMTU = 9000
$HoloDeckSite2PortGroup = 'VLC-A2-PG'
$HoloDeckSite2PGVLAN = 4095
#
# HoloConsole VM settings
$HoloConsoleVMName = "Holo-A-Console"
$HoloConsoleDS = 'Repository' # <--------------------------------------- UPDATE ACCORDINGLY TO YOUR LAB ENVIRONNMENT (ESX host)
$HoloConsoleHW = 'vmx-19'
$HoloConsoleOS = 'windows2019srv_64Guest'
$HoloConsoleCPU = 2
$HoloConsoleMEM = 4 #GB
$HoloConsoleDisk = 150 #GB
$HoloConsoleNIC = 'VLC-A-PG'
#
# HoloRouter OVA settings
$HoloRouterVMName = 'Holo-D-Router'
#$HoloRouterEULA = '1'
$HoloRouterDS = "Repository" # <--------------------------------------------------- UPDATE ACCORDINGLY TO YOUR LAB ENVIRONNMENT
$HoloRouterExtNetwork = 'VM Network'
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
$HoloRouterExternalIP = "192.168.10.4" # <----------------------------------------- UPDATE ACCORDINGLY TO YOUR LAB ENVIRONNMENT
$HoloRouterExternalSubnet = "255.255.255.0" # <------------------------------------ UPDATE ACCORDINGLY TO YOUR LAB ENVIRONNMENT
$HoloRouterExternalGW = "192.168.10.2" # <----------------------------------------- UPDATE ACCORDINGLY TO YOUR LAB ENVIRONNMENT
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
Function PrepDownloadandBuildFiles {
    param(
        [Parameter(Mandatory=$true)]
        [int]$PrepDownloadandBuildFiles
        )
    if($PrepDownloadandBuildFiles -gt 0) {
        If (Test-Path -Path $HoloDeckPath\$winIso_Filename) {
            My-Logger 'Windows 2019 ISO located ...'
        } else {
            My-Logger 'Windows 2019 ISO is missing, attempting download ...' 1
            Invoke-WebRequest -Uri $WinIso_URL -OutFile $DownloadDestination
        }
        If (Test-Path -Path $HoloDeckPath\$chromeInstallerExe_Filename) {
            My-Logger 'Chrome installer located ...'
        } else {
            My-Logger 'Chrome installer is missing, attempting download ...' 1
            Invoke-WebRequest -Uri $chromeInstallerExe_URL -OutFile $DownloadDestination
        }
        If (Test-Path -Path $HoloDeckPath\$puttyMSI_Filename) {
            My-Logger 'Putty MSI installer located ...'
        } else {
            My-Logger 'Putty MSI installer is missing, attempting download ...' 1
            Invoke-WebRequest -Uri $puttyMSI_URL -OutFile $DownloadDestination
        }
        If (Test-Path -Path $HoloDeckPath\$PowerVCFZip_Filename) {
            My-Logger 'VMware PowerShell Module for VCF located ...'
        } else {
            My-Logger 'VMware PowerShell Module for VCF is missing, attempting download ...' 1
            Invoke-WebRequest -Uri $PowerVCFZip_URL -OutFile $DownloadDestination
        }
        If (Test-Path -Path $HoloDeckPath\$PowerVSZip_Filename) {
            My-Logger 'VMware Power Validated Solutions Module for VCF located ...'
        } else {
            My-Logger 'VMware Power Validated Solutions Module for VCF is missing, attempting download ...' 1
            Invoke-WebRequest -Uri $PowerVSZip_URL -OutFile $DownloadDestination
        }
        If (Test-Path -Path $HoloDeckPath\$NotePadPlusPlus_Filename) {
            My-Logger 'NotePad++ installer located ...'
        } else {
            My-Logger 'Notepad++ installer is missing, attempting download ...' 1
            Invoke-WebRequest -Uri $NotePadPlusPlus_URL -OutFile $DownloadDestination
        }
        If (Test-Path -Path $HoloDeckPath\$vmToolsExe_Filename) {
            My-Logger 'VMware Tools for Windows, 64-bit in-guest installer (EXE) located ...'
        } else {
            My-Logger 'VMware Tools for Windows, 64-bit in-guest installer (EXE) is missing, attempting download ...' 1
            Invoke-WebRequest -Uri $vmToolsExe_URL -OutFile $DownloadDestination
        }
        #
        # If missing, the following manual downloads require Broadcom/VMware log in
        #
        If (Test-Path -Path $HoloDeckPath\$powerCLIZip_Filename) {
            My-Logger 'Latest VMware PowerCLI 13.2.1-22851661 located ...'
        } else {
            My-Logger 'Latest VMware PowerCLI 13.2.1-22851661 not find.  Please ensure is donwload and place at $HoloDeckPath' 2
            Start-Process $powerCLIZip_URL
            Exit
        }
        If (Test-Path -Path $HoloDeckPath\$ovfToolMsi_Filename) {
            My-Logger 'Latest VMware OVFTool 4.6.2 MSI located ...'
        } else {
            My-Logger 'Latest VMware OVFTool 4.6.2 MSI not find.  Please ensure is donwload and place at $HoloDeckPath' 2
            Start-Process $ovfToolMsi_URL
            Exit
        }
        If (Test-Path -Path $HoloDeckPath\$cloudBuilderISO_Filename) {
            My-Logger 'VMware Cloud Foundation 5.1.1 Cloud Builder OVA located ...'
        } else {
            My-Logger 'VMware Cloud Foundation 5.1.1 Cloud Builder OVA not find.  Please ensure is donwload and place at $HoloDeckPath' 2
            Start-Process $cloudBuilderISO_URL
            Exit
        }
        If (Test-Path -Path $HoloDeckPath\$lcmInstallOVA_Filename) {
            My-Logger 'VMware Aria Suite Lifecycle 8.16.0 Easy Installer for Aria Automation 8.16.2 iso located ...'
        } else {
            My-Logger 'VMware Aria Suite Lifecycle 8.16.0 Easy Installer for Aria Automation 8.16.2 iso not find.  Please ensure is donwload and place at $HoloDeckPath' 2
            Start-Process $lcmInstallOVA_URL
            Exit
        }
        #
        # Update Holodeck default 'CreateISO.ps1' to match build environment
        #
        If (-not (Test-Path -Path $HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\Holo-Console\createISO_Original.ps1)){
            My-Logger "Make backup of 'CreateISO.ps1' as 'CreateISO_Original.ps1'" 1
            Rename-Item -Path "$HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\Holo-Console\createISO.ps1" -NewName "createISO_Original.ps1"
        }
        $newContent = $null
        $CreateISOScript = Get-Content "$HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\Holo-Console\createISO_Original.ps1"
        $newContent = $CreateISOScript.replace('C:\Users\Administrator\Downloads', $HoloDeckPath)
        $newContent = $newContent.replace('C:\users\Administrator\Downloads', $HoloDeckPath)
        $newContent = $newContent.replace('VMware-ovftool-4.6.0-21452615-win.x86_64.msi', $ovfToolMsi_Filename)
        $newContent = $newContent.replace('putty-64bit-2023-10-21-installer.msi', $puttyMSI_Filename)
        $newContent = $newContent.replace('VMware-tools-12.2.6-22229486-x86_64.exe', $vmToolsExe_Filename)
        $newContent = $newContent.replace('VMware-Aria-Automation-Lifecycle-Installer-23838682.iso', $lcmInstallOVA_Filename)
        $newContent | Set-Content "$HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\Holo-Console\createISO.ps1"
        My-Logger "Update make to 'CreateISO.ps1' ..."
        #
        # Update Holodeck default 'additionalfiles.txt' to match build environment
        #
        If (-not (Test-Path -Path $HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\Holo-Console\additionalfiles_Original.txt)){
            My-Logger "Make backup of 'additionalfiles.txt' as 'additionalfiles_Original.txt'" 1
            Rename-Item -Path "$HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\Holo-Console\additionalfiles.txt" -NewName "additionalfiles_Original.txt"
        }
        $newContent = $null
        $AddFilesTxt = Get-Content "$HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\Holo-Console\additionalfiles_Original.txt"
        $newContent = $AddFilesTxt.replace('C:\Users\Administrator\Downloads', $HoloDeckPath)
        $newContent = $newContent.replace('npp.8.5.4.Installer.x64.exe', $NotePadPlusPlus_Filename)
        $newContent | Set-Content "$HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\Holo-Console\additionalfiles.txt"
        My-Logger "Update make to 'additionalfiles.txt' ..."
        #
        # Update Holodeck default 'additionalcommands.bat' to match build environment
        #
        If (-not (Test-Path -Path $HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\Holo-Console\additionalcommands_Original.bat)){
            My-Logger "Make backup of 'additionalcommands.bat' as 'additionalcommands_Original.bat'" 1
            Rename-Item -Path "$HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\Holo-Console\additionalcommands.bat" -NewName "additionalcommands_Original.bat"
        }
        $newContent = $null
        $AddCommandBat = Get-Content "$HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\Holo-Console\additionalcommands_Original.bat"
        $newContent = $AddCommandBat.replace('C:\Users\Administrator\Downloads', $HoloDeckPath)
        $newContent = $newContent.replace('npp.8.5.4.Installer.x64.exe', $NotePadPlusPlus_Filename)
        $newContent | Set-Content "$HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\Holo-Console\additionalcommands.bat"
        My-Logger "Update make to 'additionalcommands.bat' ..."
        #
        # Update Holodeck Site 1 default 'Holo-A1-511.ini' to match build environment
        #
        $VLCSite1ConfigFilename = [System.IO.Path]::GetFileNameWithoutExtension($VLCSite1Config)
        $VLCSite1Config_Backup = $VLCSite1ConfigFilename + "_Original.ini"
        If (-not (Test-Path -Path $HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\VLC-Holo-Site-1\$VLCSite1Config_Backup)){
            My-Logger "Make backup of '$VLCSite1Config' as '$VLCSite1Config_Backup'" 1
            Rename-Item -Path "$HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\VLC-Holo-Site-1\$VLCSite1Config" -NewName $VLCSite1Config_Backup
        }
        $newContent = $null
        $HoloA1ini = Get-Content "$HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\VLC-Holo-Site-1\$VLCSite1Config_Backup"
        $newContent = $HoloA1ini.replace('Holo-A1-511', 'Holo-A') # nestedVMPrefix
        $newContent = $newContent.replace('VLC-A-PG', $HoloDeckSite1PortGroup) # netName
        $newContent = $newContent.replace('3.5T-NVME-1', $HoloDeckDS) # ds
        $newContent = $newContent.replace('10.203.42.1', $VIIP) # esxhost
        $newContent = $newContent.replace('H0l@123!', $VIPassword) # password
        $newContent = $newContent.replace('10.172.40.1', $labDNS) # labDNS
        $newContent = $newContent.replace('addHostsJson=', 'addHostsJson=C:\VLC\VLC-Holo-Site-1\add_3_hosts.json') # addHostsJson
        $newContent = $newContent.replace('buildOps=', 'buildOps=None') # buildOps
        $newContent | Set-Content "$HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\VLC-Holo-Site-1\$VLCSite1Config"
        Add-content  -Path "$HoloDeckPath\$HoloDeckFileName\holodeck-standard-main\VLC-Holo-Site-1\$VLCSite1Config" -Value 'vSphereISOLoc=C:\VLC\VLC-Holo-Site-1\cb_esx_iso\VMware-VMvisor-Installer-8.0U2b-23305546.x86_64' # vSphereISOLoc
        My-Logger "Update make to '$VLCSite1Config' ..." 1
    }
}
Function CreateHoloConsoleISO {
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
        $NewlyHCISO  = $HoloConsoleISOPath + '\' + $NewlyHCISOName.Name
        Rename-Item -Path $NewlyHCISO -NewName $HoloConsoleISOName
        My-Logger "HoloConsole ISO renamed to $HoloConsoleISOName" 1
        if( $CreateHoloConsoleISO -eq 2) {
            Pause 60
            Get-ChildItem $HoloConsoleISOPath\Temp -Recurse | Remove-Item -Force -Confirm:$false
            # Remove-Item -Path $HoloConsoleISOPath\Temp -Recurse -Force -Confirm:$false
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
            My-Logger "HoloRouter assign datastore '$HoloConsoleDS' located on ESX host $VIServer"
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
    if($CreateSiteNetwork -eq 1) {
        $vSwtichSite1 = Get-VirtualSwitch -Server $viConnection -Name $HoloDeckSite1vSwitch -ErrorAction SilentlyContinue
        $PortGroupSite1 = Get-VirtualPortGroup -Server $viConnection -VirtualSwitch $HoloDeckSite1vSwitch -Name $HoloDeckSite1PortGroup -ErrorAction SilentlyContinue
        if( $vSwtichSite1.Name -eq $HoloDeckSite1vSwitch) {
            My-Logger "vSphere Standard Switch '$HoloDeckSite1vSwitch' for Site #1 already exists"
            if( $PortGroupSite1.Name -eq $HoloDeckSite1PortGroup) {
                My-Logger "Portgroup '$HoloDeckSite1PortGroup' on vSphere Standard Switch '$HoloDeckSite1vSwitch' for Site #1 already exists"
            } else {
                My-Logger "Creating Portgroup '$HoloDeckSite1PortGroup' on ESX host $VIServer for Site #1"
                New-VirtualPortGroup -VirtualSwitch $HoloDeckSite1vSwitch -Name $HoloDeckSite1PortGroup -VLanId $HoloDeckSite1PGVLAN
                Get-VirtualPortGroup -VirtualSwitch $HoloDeckSite1vSwitch -name $HoloDeckSite1PortGroup | Get-SecurityPolicy | Set-SecurityPolicy -AllowPromiscuous $true -ForgedTransmits $true -MacChanges $true
            }   
        } else {
            My-Logger "vSphere Standard Switch '$HoloDeckSite1vSwitch' for Site #1 not found..." 2
            WMy-Logger "Creating Virtual Switch '$HoloDeckSite1vSwitch' on ESX host $VIServer for Site #1"
            ew-VirtualSwitch -Server $viConnection -Name $HoloDeckSite1vSwitch -Mtu $HoloDeckSite1vSwitchMTU
            # For setting Security Policy on the vSwitch level - Get-VirtualSwitch -server $viConnection -name $HoloDeckSite1vSwitch | Get-SecurityPolicy | Set-SecurityPolicy -AllowPromiscuous $true -ForgedTransmits $true -MacChanges $true
            My-Logger "Creating Portgroup '$HoloDeckSite1PortGroup' on ESX host $VIServer for Site #1"
            New-VirtualPortGroup -VirtualSwitch $HoloDeckSite1vSwitch -Name $HoloDeckSite1PortGroup -VLanID $HoloDeckSite1PGVLAN
            My-Logger "Setting Security Policy for Portgroup '$HoloDeckSite1PortGroup'"
            Get-VirtualPortGroup -server $viConnection -name $HoloDeckSite1PortGroup | Get-SecurityPolicy | Set-SecurityPolicy -AllowPromiscuous $true -ForgedTransmits $true -MacChanges $true
        }
    #
        $vSwtichSite2 = Get-VirtualSwitch -Server $viConnection -Name $HoloDeckSite2vSwitch -ErrorAction SilentlyContinue
        $PortGroupSite2 = Get-VirtualPortGroup -Server $viConnection -VirtualSwitch $HoloDeckSite2vSwitch -Name $HoloDeckSite2PortGroup -ErrorAction SilentlyContinue
        if( $vSwtichSite2.Name -eq $HoloDeckSite2vSwitch) {
            My-Logger "vSphere Standard Switch '$HoloDeckSite1vSwitch' for Site #2 already exists"
            if( $PortGroupSite2.Name -eq $HoloDeckSite2PortGroup) {
                My-Logger "Portgroup '$HoloDeckSite2PortGroup' on vSphere Standard Switch '$HoloDeckSite2vSwitch' for Site #2 already exists"
            } else {
                My-Logger "Creating Portgroup '$HoloDeckSite1PortGroup' on ESX host $VIServer for Site #2"
                New-VirtualPortGroup -VirtualSwitch $HoloDeckSite2vSwitch -Name $HoloDeckSite2PortGroup -VLanId $HoloDeckSite2PGVLAN
                Get-VirtualPortGroup -VirtualSwitch $HoloDeckSite2vSwitch -name $HoloDeckSite2PortGroup | Get-SecurityPolicy | Set-SecurityPolicy -AllowPromiscuous $true -ForgedTransmits $true -MacChanges $true
            }   
        } else {
            My-Logger "vSphere Standard Switch '$HoloDeckSite2vSwitch' for Site #2 not found..." 2
            My-Logger "Creating Virtual Switch '$HoloDeckSite2vSwitch' on ESX host $VIServer for Site #2"
            New-VirtualSwitch -Server $viConnection -Name $HoloDeckSite2vSwitch -Mtu $HoloDeckSite2vSwitchMTU
            My-Logger "Creating Portgroup '$HoloDeckSite2PortGroup' on ESX host $VIServer for Site #2"
            New-VirtualPortGroup -VirtualSwitch $HoloDeckSite2vSwitch -Name $HoloDeckSite2PortGroup -VLanID $HoloDeckSite2PGVLAN
            My-Logger "Setting Security Policy for Portgroup '$HoloDeckSite2PortGroup'"
            Get-VirtualPortGroup -server $viConnection -name $HoloDeckSite2PortGroup | Get-SecurityPolicy | Set-SecurityPolicy -AllowPromiscuous $true -ForgedTransmits $true -MacChanges $true
        }
    # Deleting vSwitches and Portgroups for Site 2 and Site 2
    } elseif ($CreateSiteNetwork -eq 2) {
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
        My-Logger 'Skipping Virtual network tasks ...'
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
        My-Logger "Uploading HoloConsole iso '$HoloConsoleISOName' to ESXi Datastore '$HCdatastore'" 1
        Copy-DatastoreItem -Item $HoloConsoleISO -Destination "DS:/$($DSFolder)"
        My-Logger "Upload completed"
        Remove-PSDrive -Name DS -Force -Confirm:$false
    } elseif ( $UploadHoloConsoleISO -eq 2) {
        # Remove prior HoloConsole ISO (only work if it was previously uploaded by this script and iso dismounted on HoloConsole VM)
        New-PSDrive -Location $HCdatastore -Name DS -PSProvider VimDatastore -Root "\" > $null
        My-Logger "Deleting HoloConsole ISO '$HoloConsoleISOName' from ESXi Datastore '$HCdatastore'" 2
        Remove-Item -Path "DS:/$($DSFolder)/$HoloConsoleISOName"
        Remove-PSDrive -Name DS -Force -Confirm:$false
        My-Logger "HoloConsole ISO deleted" 2
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
        $HRargumentlist = "--noDestinationSSLVerify --acceptAllEulas --disableVerification --name=$HoloRouterVMName --net:ExternalNet=`"$HoloRouterExtNetwork`" --net:Site_1_Net=`"$HoloRouterSite1Network`" --net:Site_2_Net=`"$HoloRouterSite2Network`" --prop:External_IP=$HoloRouterExternalIP --prop:External_Subnet=$HoloRouterExternalSubnet --prop:External_Gateway=$HoloRouterExternalGW --prop:Site_1_VLAN=$HoloRouterSite1VLAN --prop:Site_1_IP=$HoloRouterSite1IP --prop:Site_1_Subnet=$HoloRouterSite1Subnet  --prop:Site_2_VLAN=$HoloRouterSite2VLAN --prop:Site_2_IP=$HoloRouterSite2IP --prop:Site_2_Subnet=$HoloRouterSite2Subnet --prop:Internal_FWD_IP=$HoloRouterInternalFWDIP --prop:Internal_FWD_PORT=$HoloRouterInternalFWDPort --datastore=$HoloRouterDS --diskMode=$HoloRouterDiskProvision --ipAllocationPolicy=fixedPolicy --allowExtraConfig --X:injectOvfEnv --powerOn $HoloRouterOVA $HoloRouterHost"
        #  append to HRargumentlist to enable logging --X:logFile=D:\ovflog.txt --X:logLevel=verbose
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
            cmdkey /generic:$HoloRouterExternalIP /user:"Administrator" /pass:"VMware123!"
            Start-Process "$env:windir\system32\mstsc.exe" -ArgumentList "/v:$HoloRouterExternalIP /f" #  /w:1280 /h:1024
            cmdkey /delete:TERMSRV/$HoloRouterExternalIP
            # $credMyGuestCred = Get-Credential vcf\Administrator
            # Copy VLC configuration ini from Build Host to VLC Site 1 folder on HoloConsole VM
            Copy-VMGuestFile -VM $HoloConsoleVMName -LocalToGuest -Source "$VLCSite1Path\$VLCSite1Config" -Destination 'C:\VLC\VLC-Holo-Site-1\' -GuestUser 'vcf\administrator' -GuestPassword 'VMware123!' -Force
        } elseif ($VLC -eq 2) {
            # Holo-Site-1-vcf-ems-public.json
            $VLCGUI = "C:\VLC\VLC-Holo-Site-1\VLCGui.ps1 -iniConfigFile .\$VLCSite1Config -isCLI $true"
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
###############################################################################################################################
$RefreshBaseline = 0
#   0 - Use existing downloaded binaries and Holodeck build files
#   1 - Check and download required binaries, update Holodeck build files
#
$NewHoloConsoleISO = 0
#   0 - Use existing HoloConsole Custom ISO
#   1 - Create a fresh HoloConsole Custom ISO
#   2 - Create a fresh HoloConsole Custom ISO with Temp cleanup
#
$EnablePreCheck = 0
#   0 - No core binaries verification on Build Host
#   1 - Verfiy Holodeck core binaries are accessible on Build Host
#
$EnableCheckDS = 0
#   0 - No datastores validation
#   1 - Verfiy assigned datastores for HoloConsole and HoloRouter are accessible on ESX host
#
$EnableSiteNetwork = 0
#   0 - Use existing virtual networks on ESX host
#   1 - Verify / create Holodeck vritual networks on ESX host
#   2 - Delete previous Holodeck virtual networks on ESX host
#
$RefreshHoloConsoleISO  = 0
#   0 - Use existing HoloConsole ISO on ESX host
#   1 - Upload / refresh the latest HoloConsole ISO on ESX host
#   2 - Delete previously uploaded HoloConsole ISO on ESX host
#
$EnableDeployHoloRouter = 0
#   1 - Create HoloRouter VM
#   2 - Delete HoloRouter VM
#
$EnableDeployHoloConsole = 0
#   1 - Create HoloConsole VM
#   2 - Delete HoloConsole VM
#
$EnableDeployHoloRouter = 0
#   1 - Create HoloRouter VM
#   2 - Delete HoloRouter VM
#
$EnableVLC = 0
#   1 - Copy saved VLC configuration onto HoloConsole VM
#   2 - Kick off VLC in headless mode on HoloConsole VM
#
###############################################################################################################################
PrepDownloadandBuildFiles $RefreshBaseline
CreateHoloConsoleISO $NewHoloConsoleISO
PreCheck $EnablePreCheck
CheckDS $EnableCheckDS
CreateSiteNetwork $EnableSiteNetwork
UploadHoloConsoleISO $RefreshHoloConsoleISO
DeployHoloRouter $EnableDeployHoloRouter
DeployHoloConsole $EnableDeployHoloConsole
VLC $EnableVLC
########################################################
# Use the following sequence for lab tear down
#
# DeployHoloConsole 2
# DeployHoloRouter 2
# UploadHoloConsoleISO 2
# CreateSiteNetwork 2
#
$EndTime = Get-Date
$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)
My-Logger "VMware Holodeck Lab Deployment Completed!"
My-Logger "StartTime: $StartTime" 1
My-Logger "  EndTime: $EndTime" 1
My-Logger " Duration: $duration minutes" 1