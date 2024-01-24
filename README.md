# CloudStuff

Mixed bag of PowerShell scripts that interact with Microsoft's Azure Virtual Desktops offering and Configuration Manager

## Overview

These scripts all work to help an administrator take their custom/in-house Windows 1X build and convert it for use with Azure's Virtual Desktops offering.
Here is an overly simplified steps list:

* Download and Install [Windows ADK](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install) on Build Machine (not the system you seek capturing)
* Prepare your Windows PE Media
  * Include ImageX.exe
  * Include the WinPE Optional Components (i.e., PowerShell, DISM, etc.)
  * Create a bootable ISO
* Build your VM as neeeded
* Prepare the Image for Azure
  * See [PrepareImageForAzure.ps1](PrepareImageForAzure.ps1)
* Sysprep the VM as such `C:\Windows\System32\Sysprep\Sysprep.exe /OOBE /Generalize /Shutdown`
* Boot VM with WinPE ISO
  * Use ImageX to capture the VM as such `ImageX.exe /Capture /Compress Maximum C: "\\PATH\TO\SHARE\CustomWindowsBuild.wim" "FIRM - Windows 10 22H2 2024.01.23"`
* Create a Virtual Hard Disk file that we will apply the newly-created image to
  * See [CreateVHD-GPT.ps1](CreateVHD-GPT.ps1)
* Upload VHD to Azure AVD workspace
  * Test it, kick the tires
* Capture the Azure VD, converting it to an image we can use for Session Hosts Pool(s)
  * See [CreateAzureImage.ps1](CreateAzureImage.ps1)

With a customized image and a Session Hosts Pool in place, the following scripts illustrate how to:

* Deploy additional session hosts to a pool
  * See [DeployCloudPCs.ps1](DeployCloudPCs.ps1)
* Include a custom script extension that calls a powershell script to install a Configuration Manager client
  * See [Unzip.ps1](Unzip.ps1) and [InstallConfigMgr.ps1](InstallConfigMgr.ps1)

### Notes on Unzip.ps1 and InstallConfigMgr.ps1

* Grab the ConfigMgr folder off your primary site server and copy it somewhere, say `\\domain.local\ConfigMgr\5.00.9106.1022`
* Drop `InstallConfigMgr.ps1` into this share
* Use [7Zip](https://7-zip.org) to compress the folder (i.e., `5.00.9106.1022`) into a 7z file, say `ConfigMgr_5.00.9106.1022.7z`
* Grab the following files from your 7Zip installation and copy them into, say `\\domain.local\ConfigMgr`:
  * `7z.exe`
  * `7z.dll`
* Grab the following files and copy it to `\\domain.local\ConfigMgr`:
  * `ConfigMgr_5.00.9106.1022.7z`
  * Grab `Unzip.ps1`
* Upload `\\domain.local\ConfigMgr` to a storage blob container that is accessible to the session hosts you will be deploying.

### Additional Notes on InstallConfigMgr.ps1

I added a repair feature to this script due to the corruption issues I've encountered with SCCM (or more recently referrer to as MECM) throughout my career.

The repair feature performs the following:

* Uninstall the MECM agent
* Removes leftover MECM agent directories
* Repairs the WMI repository
* Re-compiles system MOFs and the extended MOFs found in Microsoft Policy Platform
  * Microsoft Policy Platform is installed as a pre-req
* Manually re-registers the `ExtendedStatus.MOF` file if the `ccmsetup.exe` process hangs
  * You will see evidence of this in `C:\Windows\CCMSetup\ccmsetup.msi.log`, but the MOF file is incorrectly referred to as `DiscoveryStatus.MOF` within the log file.
