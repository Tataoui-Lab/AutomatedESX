#
# Author: Dominic Chan (dominic.chan@tataoui.com)
# Date: 2021-01-11
# Last Update: 2024-05-03
#
# Description: Auto creation of custom VMware ESX installer
# The installer incorporate the standard kickstart configuration to automate and streamline ESX install while also
# provide a simple menu selection to enable the same installer to be use on multiple hosts with unique configuration.
# Ths custom ISO can be used on CD or USB Flashdrive.
#
# Inspired by William Lam work, I just took it up a level
# https://www.virtuallyghetto.com/2015/06/how-to-create-custom-esxi-boot-menu-to-support-multiple-kickstart-files.html
# 
# - tested on ESX6.7
# - tested on ESX7.0
# - tested on ESX8.0
#
# Powershell environment prerequisites:
# 1. Windows 10 version 2004 (Build 19041) or higher
# 2. PowerShell version: 5.1.14393.3866
# 3. WSL 2 (Depreciated)
#    - wsl --install (from PowerShell)
#    - Reboot required afterward
# 4. Ubuntu 20.04 LTS (Depreciated)
#    a. genisoimage installation require - 'sudo apt-get install genisoimage -y'
# 5. xorriso for Windows
#    https://github.com/PeyTy/xorriso-exe-for-windows
#    Direct download at https://github.com/PeyTy/xorriso-exe-for-windows/archive/master.zip
#    Place unzip folder (xorriso) within ESX ISO folders (i.e. D:\esx-iso)
# 6. ImportExcel: 7.1.0
#    Install-Module -Name ImportExcel -RequiredVersion 7.1.0
#
# Include with the script
# 1. VMware Kickstart Template - KS_Template.cfg
# 2. VMware Deployment workbook (optional for static configuration)
#
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false | out-null
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser -Force # Bypass

if ( -not (Get-PackageProvider -ListAvailable Nuget)) {
    Write-Warning "Installing NuGet package manager..."
    Install-PackageProvider -Name NuGet -Force 
}

# Absolute path to your data sources
$ScriptPath = "D:\esx-iso" # Path to this script and custom kickstart template
$pathToISOFiles = "D:\esx-iso" # Path to VMware vSphere ISOs
$DataSourcePath = "D:\esx-iso\VMware.xlsx" # Path to Excel Worksheet as the data sources
$LogVersion = Get-Date -UFormat "%Y-%m-%d_%H-%M"
$verboseLogFile = "VMware-Automated-ESX-USB-Installer-$LogVersion.log"

#$WSLExist = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
#if ($WSLExist.State -eq 'Enabled') {
#    My-Logger 'Windows Subsystem for Linux detected...'
#} else {
#    My-Logger 'Installing Windows Subsystem for Linux' 1
#    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform Microsoft-Windows-Subsystem-Linux  -NoRestart
#    My-Logger 'Ubuntu is being install.  Please provide an UNIX username and password when prompt...' 1
#    wsl --set-default-version 2
#    wsl --install -d Ubuntu
#    My-Logger 'Windows Subsystem for Linux installed, please re-run this script after the reboot...' 2
#    Restart-Computer
#}

# wsl -e bash -c "sudo apt list --installed"

Function My-Logger {
    [CmdletBinding()]
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
function Load-Module ($PS_Module) {
    # If module is imported say that and do nothing
    if (Get-Module | Where-Object {$_.Name -eq $PS_Module}) {
        write-host "Module $PS_Module is already imported."
    }
    else {
        # If module is not imported, but available on disk then import
        if (Get-Module -ListAvailable | Where-Object {$_.Name -eq $PS_Module}) {
            Import-Module $PS_Module # -Verbose
        }
        else {
            # If module is not imported, not available on disk, but is in online gallery then install and import
            if (Find-Module -Name $PS_Module | Where-Object {$_.Name -eq $PS_Module}) {
                Install-Module -Name $PS_Module -Force -Verbose -Scope CurrentUser
                Import-Module $PS_Module # -Verbose
            }
            else {
                # If the module is not imported, not available and not in the online gallery then abort
                write-host "Module $PS_Module not imported, not available and not in an online gallery, exiting."
                EXIT 1
            }
        }
    }
}

Load-Module "ImportExcel"

# Static preset is limited to a single ESX host deployment
$DataSource = Read-Host -Prompt 'Using static preset inputs or import from Excel? (S/E)'
if ($DataSource -eq 'S') {
    $HostPW = 'VMware123!'
    $DriveHW = 'mpx.vmhba33:C0:T0:L0' # vary base on hardware
    $MgmtNIC = 'vmnic0'
    $HostIP = '192.168.10.50'
    $HostSubnet = '255.255.255.0'
    $HostGW = '192.168.10.2'
    $HostMgmtVLAN = '10'
    $ESXHostname = 'esxtemp.tataoui.com'
    $HostDNS1 = '192.168.10.30'
    $HostDNS2 = '8.8.8.8'
    $LocalUser = 'localadmin'
    $LocalPW = 'VMware123!'
    $HostDOmain = 'tataoui.com'
    $VCSAIPAddr = '192.168.10.25'
    $ListOfPhysicalDrives = 'SATA_SSD-SSD_VM Samsung-SSD_VSAN HITACHI-HDD_VSAN' # vary base on hardware
} else {
    $ESXHostsParameters = Import-Excel -Path $DataSourcePath -WorksheetName 'ESXHosts'
}

# DO NOT EDIT BEYOND HERE ###########################################
My-Logger "Begin VMware Automated ESX USB Installer ..."

if ( -not (Get-Module -ListAvailable Storage)) {Write-Warning "Storage module not found, cannot continue.";break }

$remember_pathToISOFiles, $remember_esxiISOFile, $mediaFormat = $null
$KS_Template = "$ScriptPath\KS_Template.cfg"
$KickStartFolderName = 'KS'
$isolinuxTempFile = $pathToISOFiles+'\isolinuxTemp.cfg'

# Determine ESX ISO files/folder location
if (-not $remember_pathToISOFiles) {
    if (($pathToISOFiles = Read-Host "Enter ESX ISO folder path (default D:\esx-iso)") -eq '') { 
        $pathToISOFiles = "D:\esx-iso"; 
    } else { 
        $pathToISOFiles 
    }
    $remember_pathToISOFiles = $pathToISOFiles
} else { 
    Write-Host -ForegroundColor Green "Path to ISO '$remember_pathToISOFiles' file already exists"
}

$pathToISOFiles = $pathToISOFiles.ToLower()

# If more than one ESX version exist, make a selection
if (-not $remember_esxiISOFile) {
    try { $esxiIsoFile = Get-ChildItem $pathToISOFiles\VMware-VMvisor-Installer-*.iso -ErrorAction Stop }
    catch { $_.Exception; break }
    if ($esxiIsoFile -is [array]) {
        Write-host -ForegroundColor Red "More than one file/version detected. Please select which one to use."
        $a = 1
        foreach ($item in $esxiIsoFile ) {
            Write-host -ForegroundColor Yellow "[$a] $($item.Name)"
            $a++
        }
        $select = Read-host -Prompt "Please pick one from the list above (1 to $($a - 1))"
        while ([array](1..$a) -notcontains $select) { 
            $select = Read-host -Prompt "Please pick one from the list above (1 to $($a - 1))"
        }
        $esxiIsoFile = $esxiIsoFile.Item($select - 1)
        $remember_esxiISOFile = $esxiIsoFile
    }
} else { 
    Write-Host -ForegroundColor Red "[ok] esxi ISO file already choosed"
}

My-Logger "Mounting ESX ISO - $esxiIsoFile ..."
try {Mount-DiskImage -ImagePath $esxiIsoFile -StorageType ISO -Access ReadOnly -ErrorAction Stop} catch {$_.exception;break}

$mountedISO = Get-Volume | ? { $_.DriveType -eq "CD-ROM" -and $_.OperationalStatus -eq "OK" -and $_.DriveLetter }
$copyDestination = $pathToISOFiles + "\tmp\" + $mountedISO.FileSystemLabel # copy destination folder name

My-Logger "Remove previous staging folder if it exists ..."
if (Test-Path $copyDestination) { 
    Write-Host -ForegroundColor Red "Removing previous staging folder '$($mountedISO.FileSystemLabel)'"
    Remove-Item $copyDestination -Recurse; 
}

My-Logger "Copying files from ISO to staging folder - $copyDestination ..."
Copy-Item (Get-PSDrive $mountedISO.DriveLetter).root -Recurse -Destination $copyDestination -Force

My-Logger "Dismount ESX ISO - $esxiIsoFile ..."
Dismount-DiskImage -ImagePath $esxiIsoFile

My-Logger "Remove 'Read Only' attribute to ESX source files ..."
Get-ChildItem $copyDestination -Recurse | Set-ItemProperty -Name isReadOnly -Value $false -ErrorAction SilentlyContinue

My-Logger "Create Kickstart folder - '$KickStartFolderName' ..."
New-Item -Path $copyDestination -Name $KickStartFolderName -ItemType "directory"

My-Logger "Prepare Custom Kickstart configuration per hosts - 'ks#.cfg' ..."
for ($esxi=0; $esxi -lt $ESXHostsParameters.Count; $esxi++ ) {
    $HostPW = $ESXHostsParameters.HostPW[$esxi]
    $DriveHW = $ESXHostsParameters.DriveHW[$esxi]
    $MgmtNIC = $ESXHostsParameters.MgmtNIC[$esxi]
    $HostIP = $ESXHostsParameters.HostIP[$esxi]
    $HostSubnet = $ESXHostsParameters.HostSubnet[$esxi]
    $HostGW = $ESXHostsParameters.HostGW[$esxi]
    $HostMgmtVLAN = $ESXHostsParameters.HostMgmtVLAN[$esxi]
    $ESXHostname = $ESXHostsParameters.ESXHostname[$esxi]
    $HostDNS1 = $ESXHostsParameters.HostDNS1[$esxi]
    $HostDNS2 = $ESXHostsParameters.HostDNS2[$esxi]
    $LocalUser = $ESXHostsParameters.LocalUser[$esxi]
    $LocalPW = $ESXHostsParameters.LocalPW[$esxi]
    $HostDOmain = $ESXHostsParameters.HostDomain[$esxi]
    $VCSAIPAddr = $ESXHostsParameters.VCSAIPAddr[$esxi]
    $ListOfPhysicalDrives = $ESXHostsParameters.ListOfPhysicalDrives[$esxi]
    #
    $KS_Temp_Stage1 = (Get-Content -Path $KS_Template).Replace("HostPW", $HostPW).Replace("DriveHW", $DriveHW).Replace("MgmtNIC", $MgmtNIC).Replace("HostIP", $HostIP).Replace("HostSubnet", $HostSubnet).Replace("HostGW", $HostGW).Replace("ESXHostname", $ESXHostname).Replace("HostDNS1", $HostDNS1).Replace("HostDNS2", $HostDNS2).Replace("HostMgmtVLAN", $HostMgmtVLAN)
    Add-Content -Path $ScriptPath\KS_Temp_Stage1.cfg -value $KS_Temp_Stage1
    $KS_Temp_Stage2 = (Get-Content -Path $ScriptPath\KS_Temp_Stage1.cfg).Replace("LocalUser", $LocalUser).Replace("LocalPW", $LocalPW).Replace("HostDomain", $HostDomain).Replace("ListOfPhysicalDrives", $ListOfPhysicalDrives).Replace("VCSAIPAddr", $VCSAIPAddr)
    Add-Content -Path $copyDestination\$KickStartFolderName\KS$($esxi + 1).cfg -value $KS_Temp_Stage2

    Get-ChildItem $copyDestination\$KickStartFolderName\KS$($esxi + 1).cfg | ForEach-Object {
        # get the contents and replace line breaks by U+000A
        $contents = [IO.File]::ReadAllText($_) -replace "`r`n?", "`n"
        # create UTF-8 encoding without signature
        $utf8 = New-Object System.Text.UTF8Encoding $false
        # write the text back
        [IO.File]::WriteAllText($_, $contents, $utf8)
    }
    # Clean up all temp variables
    Remove-Item -Path $ScriptPath\KS_Temp_Stage1.cfg
    $KS_Temp_Stage1, $KS_Temp_Stage2 = $null
}

My-Logger "Set boot.cfg and isolinux.cfg file location ..."
    $bootFile = "$copyDestination\boot.cfg"
    $bootFileEFI = "$copyDestination\efi\boot\boot.cfg"
    $numTimeOut = 100
    $isolinuxTempFile = $pathToISOFiles+'\isolinuxTemp.cfg'

My-Logger "Update isolinux.cfg based on ESX hosts entries ..."
if ($ESXHostsParameters.count -gt 1) {
    Add-Content -Path $isolinuxTempFile -value "DEFAULT menu.c32"
    Add-Content -Path $isolinuxTempFile -value "MENU TITLE $($mountedISO.FileSystemLabel) Boot Menu"
    Add-Content -Path $isolinuxTempFile -value "NOHALT 1"
    Add-Content -Path $isolinuxTempFile -value "PROMPT 0"
    Add-Content -Path $isolinuxTempFile -value "TIMEOUT $numTimeOut"
    for ($j=0; $j -lt $ESXHostsParameters.Count; $j++ ) {
        $index = $j + 1
        $esx = $($ESXHostsParameters.ESXHostname[$j]).ToUpper().split(".")[0]
        Add-Content -Path $isolinuxTempFile -value "LABEL install $esx"
        Add-Content -Path $isolinuxTempFile -value "  KERNEL mboot.c32"
        Add-Content -Path $isolinuxTempFile -value "  APPEND -c boot.cfg ks=usb:/$KickStartFolderName/$KickStartFolderName$index.CFG +++"
        Add-Content -Path $isolinuxTempFile -value "  MENU LABEL ^$index $esx Install"
    }
    # Add-Content -Path $isolinuxTempFile -value "LABEL install Web - Future"
    # Add-Content -Path $isolinuxTempFile -value "  KERNEL mboot.c32"
    # Add-Content -Path $isolinuxTempFile -value "  KERNEL mboot.c32"
    # Add-Content -Path $isolinuxTempFile -value "  APPEND -c boot.cfg ks=http://192.168.30.10/ks/ks4.cfg +++"
    Add-Content -Path $isolinuxTempFile -value "LABEL hddboot"
    Add-Content -Path $isolinuxTempFile -value "  LOCALBOOT 0x80"
    Add-Content -Path $isolinuxTempFile -value "  MENU LABEL ^Boot from local disk"
} else {
    $esx = $($ESXHostsParameters.Hostname[0]).ToUpper().split(".")[0]
    $isolinuxFile = "$copyDestination\isolinux.cfg"
    $isoLinuxFileLabel = Get-Content $isolinuxFile | Select-String "LABEL install"
    $isoLinuxFileLabel2 = Get-Content $isolinuxFile | Select-String "MENU LABEL E"
    $newisoLinuxFileLabel = (Get-Content $isolinuxFile).Replace($isoLinuxFileLabel, "LABEL install $FirstLabel").Replace("APPEND -c boot.cfg", "APPEND -c boot.cfg ks=usb:/$KickStartFolderName/KS1.CFG").Replace($isoLinuxFileLabel2, "MENU LABEL $esx Install")
    Add-Content -Path $isolinuxTempFile -value $newisoLinuxFileLabel
}

My-Logger "Copy isolinux.cfg to its appropriate location ..."
Copy-Item $isolinuxTempFile -Destination $copyDestination\isolinux.cfg -Force

My-Logger "Update title to boot.cfg and efi-boot.cfg ..."
$bootFileTitle = Get-Content $bootFile | Select-String "title"
$bootFileKernelOpt = Get-Content $bootFile  | Select-String "kernelopt"
$time = (Get-Date -f "HHmmss")

$newBootFileContent = (Get-Content $bootFile).Replace($bootFileTitle, "title=Loading Automated kickstart ESXi installer - $time").Replace($bootFileKernelOpt, "kernelopt=runweasel cdromBoot allowLegacyCPU=true")
    # .Replace("kernelopt=cdromBoot runweasel", "kernelopt=cdromBoot runweasel ks=cdrom:/KS1.CFG")

Set-Content $bootFile -Value $newBootFileContent -Force
Set-Content $bootFileEFI -Value $newBootFileContent -Force

My-Logger "Preparing ISO parameters ..."
$ISOFilename = "CustomESXInstaller-"+$($esxiisofile.Name).Substring(25,22) # check 22 from 23
# $isoSourceFiles = "/mnt/" + $copyDestination.Replace("\", "/").replace(":", "")
$isoSourceFiles = '..\tmp\' + $mountedISO.FileSystemLabel
# e.g. $isoSourceFiles = "/mnt/d/iso/tmp/ESXI-6.7.0-20181002001-STANDARD"
$isoDestinationFile = $ISOFilename + ".iso"
# $isoDestinationFilePath = "/mnt/" + $pathToISOFiles.Replace("\", "/").replace(":", "") + "/tmp/" + $isoDestinationFile
$isoDestinationFilePath = $pathToISOFiles + "\tmp\" + $isoDestinationFile
# https://docs.vmware.com/en/VMware-vSphere/7.0/com.vmware.esxi.upgrade.doc/GUID-C03EADEA-A192-4AB4-9B71-9256A9CB1F9C.html
# $rCommand = "genisoimage -relaxed-filenames -J -R -o $isoDestinationFilePath -b ISOLINUX.BIN -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e EFIBOOT.IMG -no-emul-boot $isoSourceFiles"
# $rCommand = "mkisofs -relaxed-filenames -J -R -o $isoDestinationFilePath -b isolinux.bin -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -b efiboot.img -no-emul-boot $isoSourceFiles"
# -eltorito-platform efi 

My-Logger "Create custom ESX ISO image ..."
Set-Location -Path $pathToISOFiles\xorriso
$makeISO = "xorriso.exe -as mkisofs -relaxed-filenames -J -R -o $isoDestinationFilePath -b ISOLINUX.BIN -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e EFIBOOT.IMG -no-emul-boot $isoSourceFiles"
$makeISO | Out-File $pathToISOFiles\makeISO.bat -Encoding ASCII
Start $pathToISOFiles\makeISO.bat

# My-Logger "Create custom ESX ISO image on Ubuntu with WSL ..."
# wsl bash -c $rCommand
# Option to copy to existing datastore
# wsl bash -c "scp $isoDestinationFilePath root@192.168.2.20:/vmfs/volumes/datastore1"

My-Logger "Clean up and deleting working area - $copyDestination ..."
Remove-Item $isolinuxTempFile
Remove-Item $copyDestination -Recurse -Force

My-Logger "Final customer ESX installer ISO place at - $pathToISOFiles\tmp\$isoDestinationFile ..."
Invoke-Item $pathToISOFiles\tmp\
