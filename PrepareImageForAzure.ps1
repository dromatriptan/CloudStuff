<#
    1. Download and Install Windows ADK on Build Machine (not the system you seek capturing)
        a. https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
    2. Prepare your Windows PE Media
        a. Include ImageX.exe
        b. Include the WinPE Optional Components (i.e., PowerShell, DISM, etc.)
        c. Create a bootable ISO
    3. Build your VM as neeeded
    4. Prepare the Image for Azure
        a. PrepareImageForAzure.ps1 (* Your Are Here)
    5. Sysprep /OOBE /Generalize
    6. Boot VM with WinPE ISO
        a. ImageX.exe /Capture /Compress Maximum C: "\\PATH\TO\SHARE\CustomWindowsBuild.wim" "FIRM - Windows 10 22H2 2024.01.23"
    7. Use CreateVHD-GPT.ps1 script to:
        a. Create an Azure-ready VHD
        b. Apply your custom image to this VHD
    8. Upload VHD to Azure AVD workspace
    9. Test it, kick the tires, then use CreateAzureImage.ps1 to build your AVD image for use in Session Host Pool(s)
#>

# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/prepare-for-upload-vhd-image

& sfc.exe  /scannow
& winmgmt.exe /verifyrepository
& netsh.exe winhttp reset proxy
& powercfg.exe /SetActive SCHEME_MIN
Out-File -FilePath "$PSScriptRoot\SanPolicy.txt" -InputObject "san policy=onlineall" -Force -Encoding ascii
Out-File -FilePath "$PSScriptRoot\SanPolicy.txt" -InputObject "exit" -Append -Encoding ascii
& diskpart.exe /s "%~dp0SANPolicy.txt"

Set-Service -Name w32Time -StartupType Automatic
Set-Service -Name WerSvc -StartupType Manual
Get-Service -Name BFE, Dhcp, Dnscache, IKEEXT, iphlpsvc, nsi, mpssvc, RemoteRegistry |`
    Where-Object -Property StartupType -new Automatic |`
        Set-Service -StartupType Automatic
Get-Service -Name Netlogon, Netman, TermService |`
    Where-Object -Property StartupType -ne Manual |`
        Set-Service -StartupType Manual

Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' -Name RealTimeIsUniversal -Value 1 -Type Dword -Force
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name TEMP -Value "%SystemRoot%\TEMP" -Type ExpandString -Force
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name TMP -Value "%SystemRoot%\TEMP" -Type ExpandString -Force
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0 -Type Dword -Force
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name fDenyTSConnections -Value 0 -Type Dword -Force
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name KeepAliveEnable -Value 1 -Type Dword -Force
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name KeepAliveInterval -Value 1 -Type Dword -Force
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name fDisableAutoReconnect -Value 0 -Type Dword -Force
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name PortNumber -Value 3389 -Type Dword -Force
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name LanAdapter -Value 0 -Type Dword -Force
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 1 -Type Dword -Force
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name SecurityLayer -Value 1 -Type Dword -Force
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name fAllowSecProtocolNegotiation -Value 1 -Type Dword -Force
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name KeepAliveTimeout -Value 1 -Type Dword -Force
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name fInheritReconnectSame -Value 1 -Type Dword -Force
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name fReconnectSame -Value 0 -Type Dword -Force
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name MaxInstanceCount -Value 4294967295 -Type Dword -Force
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name CrashDumpEnabled -Value 2 -Type Dword -Force
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name DumpFile -Value "%SystemRoot%\MEMORY.DMP" -Type ExpandString -Force
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name NMICrashDump -Valu 1 -Type Dword -Force

if ( (Get-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp').Property -contains 'SSLCertificateSHA1Hash') {
    Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name SSLCertificateSHA1Hash -Force
}

if ( (Test-Path -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps' -PathType Container) -eq $false ) {
    New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps' -Name LocalDumps
}
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps' -Name DumpFolder -Value "%SYSTEMDRIVE%\CrashDumps" -Type ExpandString -Force
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps' -Name CrashCount -Value 10 -Type Dword -Force
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps' -Name DumpType -Value 2 -Type Dword -Force


$AzurePlatformIP = '168.63.129.16'
Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled True
Enable-PSRemoting -Force
Set-NetFirewallRule -DisplayName 'Windows Remote Management (HTTP-In)' -Enabled True
Set-NetFirewallRule -DisplayName 'File and Printer Sharing (Echo Request - ICMPv4-In)' -Enabled True
New-NetFirewallRule -DisplayName 'AzurePlatform' -Direction Inbound -RemoteAddress $AzurePlatformIP -Profile Any -Action Allow -EdgeTraversalPolicy Allow
New-NetFirewallRule -DisplayName 'AzurePlatform' -Direction Outbound -RemoteAddress $AzurePlatformIP -Profile Any -Action Allow

& bcdedit.exe /set "{default}" device partition=c:
& bcdedit.exe /set "{default}" integrityservices enable
& bcdedit.exe /set "{default}" recoveryenabled Off
& bcdedit.exe /set "{default}" osdevice partition=c:
& bcdedit.exe /set "{default}" bootstatuspolicy IgnoreAllFailures
& bcdEdit.exe /set "{bootmgr}" integrityservices enable
& bcdEdit.exe /set "{bootmgr}" displaybootmenu yes
& bcdEdit.exe /set "{bootmgr}" timeout 5
& bcdEdit.exe /set "{bootmgr}" bootems yes
& bcdedit.exe /set "{current}" ON
& bcdEdit.exe /emssettings EMSPORT:1 EMSBAUDRATE:115200

# Prepare ConfigMgr Client for Azure
Get-Service -Name 'SMS Agent Host' -ErrorAction SilentlyContinue | Stop-Service -Force -NoWait
Get-ChildItem -Path 'Cert:\LocalMachine\SMS\' -ErrorAction SilentlyContinue | Remove-Item -Force
Get-ChildItem -Path "${env:SystemRoot}\SMSCFG.INI" -ErrorAction SilentlyContinue | Remove-Item -Force

