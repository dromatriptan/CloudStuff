param (
    [Parameter(Position = 1, Mandatory = $false)]
    [Switch]$repair
)

[String]$scriptDir = $PSScriptRoot
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object -TypeName System.Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

function UninstallConfigMgr {
    Write-Host "Stopping ConfigMgr Agent ..." -NoNewline
    Get-Service -Name ccmexec -ErrorAction SilentlyContinue | Stop-Service -Force -WarningAction SilentlyContinue
    Write-Host "done." -ForegroundColor Green
    if (Test-Path -Path "${env:SystemRoot}\CCMSetup\ccmsetup.exe" -PathType Leaf) {
        Write-Host "Uninstalling ConfigMgr Agent ..." -NoNewline
        Start-Process -FilePath "${env:SystemRoot}\CCMSetup\ccmsetup.exe" -ArgumentList "/uninstall" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
        Get-Process -Name ccmsetup -ErrorAction SilentlyContinue | Wait-Process -Timeout 600
        Write-Host "done."
    }

    Write-Host "Removing leftover ConfigMgr Agent Files ..." -NoNewline
    Remove-Item -Path "${env:SystemRoot}\CCM" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "${env:SystemRoot}\CCMcache" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "${env:SystemRoot}\CCMsetup" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "done." -ForegroundColor Green
}
function InstallConfigMgr {
    $siteCode = "MCM"
    $dnsSuffix = "domain.local"
    $cacheSize = 10240
    $paramsCMClient = @{
        FilePath = Join-Path -Path $scriptDir -ChildPath "ccmsetup.exe"
        ArgumentList = "SMSSITECODE=$siteCode SMSCACHESIZE=$cacheSize DNSSUFFIX=$dnsSuffix RESETKEYINFORMATION=True"
        WindowStyle = "Hidden"
        Wait = $true
    }
    Write-Host "Installing ConfigMgr Agent ..." -NoNewline
    Start-Process @paramsCMClient
    Get-Process -Name ccmsetup -ErrorAction SilentlyContinue | Wait-Process -Timeout 600 -ErrorAction SilentlyContinue -ErrorVariable TimedOut
    if ($TimedOut) {
        # Commonly occurring error easily remediated by manually re-compiling ExtendedDiscovery.mof
        Write-Host "CCMsetup still in memory, manually re-compiling ExtendedDiscovery.mof ..." -NoNewline
        Set-Location -Path "${env:ProgramFiles}\Microsoft Policy Platform" -ErrorAction SilentlyContinue -ErrorVariable mppDirError
        if (-not $mppDirError) {
            $paramsMofComp = @{
                FilePath = "mofcomp.exe"
                ArgumentList = "ExtendedDisvoery.mof"
                WindowStyle = "Hidden"
                Wait = $true
                WorkingDirectory = "${env:ProgramFiles}\Microsoft Policy Platform"
            }
            Start-Process @paramsMofComp
            Write-Host "done." -ForegroundColor Green
        } else { Write-Host "Could not change directory to `"${env:ProgramFiles}\Microsoft Policy Platform`", failing." -ForegroundColor Red}
    } else { Write-Host "done." -ForegroundColor Green }
}
function RepairWmi {
    Write-Host "Repairing Windows Management Instrumentation ..." -NoNewline
    Get-Service -Name winmgmt | Stop-Service -Force -WarningAction SilentlyContinue
    Start-Process -FilePath "winmgmt.exe" -ArgumentList "/resetrepository" -WindowStyle Hidden -Wait 
    Get-Service -Name winmgmt | Start-Service
    Write-Host "done." -ForegroundColor Green
}
function RecompileMofs {
    $params = @{
        FilePath = "mofcomp.exe"
        ArgumentList = $null
        WindowStyle = "Hidden"
        Wait = $true
        WorkingDirectory = $null
    }
    Set-Location -Path "${env:ProgramFiles}\Microsoft Policy Platform" -ErrorAction SilentlyContinue -ErrorVariable mppDirError
    if (-not $mppDirError) {
        Write-Host "Re-registering Windows Policy Platform MOF/MFL files ..." -NoNewline
        $params.WorkingDirectory = "${env:ProgramFiles}\Microsoft Policy Platform"
        Get-ChildItem -Path . -Filter "*.mof" -Recurse |`
        Select-Object -ExpandProperty FullName |`
        ForEach-Object { 
            $params.ArgumentList = $_
            Start-Process @params
        }
        Get-ChildItem -Path . -Filter "*.mfl" -Recurse |`
        Select-Object -ExpandProperty FullName |`
        ForEach-Object { 
            $params.ArgumentList = $_
            Start-Process @params
        }
    }
    Set-Location -Path "${env:SystemRoot}\System32\wbem" -ErrorAction SilentlyContinue -ErrorVariable wbemDirError
    if (-not $wbemDirError) {
        Write-Host "Re-registering System MOF/MFL files ..." -NoNewline
        $params.WorkingDirectory = "${env:SystemRoot}\System32\wbem"
        Get-ChildItem -Path . -Filter "*.mof" -Recurse |`
        Select-Object -ExpandProperty FullName |`
        ForEach-Object { 
            $params.ArgumentList = $_
            Start-Process @params
        }
        Get-ChildItem -Path . -Filter "*.mfl" -Recurse |`
        Select-Object -ExpandProperty FullName |`
        ForEach-Object { 
            $params.ArgumentList = $_
            Start-Process @params
        }
    }
}

Write-Host "Verifying administrative privileges ..." -NoNewline
if ($isAdmin) {
    Write-Host "verified." -ForegroundColor Green
    if ($repair)  {
        UninstallConfigMgr
        RepairWmi
        RecompileMofs
    }
    InstallConfigMgr    
} else {
    Write-Hosft "failed." -ForegroundColor Red
    Write-Host "Attempting to reload as Administrator" -NoNewline
    $scriptFullPath = Join-Path -Path $scriptDir -ChildPath $MyInvocation.MyCommand
    $paramsPwsh = @{
        FilePath = "${env:SystemRoot}\System32\WindowsPowerShell\v1.0\powershell.exe"
        ArgumentList = "-Version 5.0 -ExecutionPolicy Bypass -File `"$scriptFullPath`""
        WindowStyle = 'Normal'
        Wait = $false
        PassThru = $true
        Verb = "RunAs"
    }
    $p = Start-Process @paramsPwsh
    $processExists = Get-WmiObject -Class Win32_Process -Filter "ProcessId = '$($p.Id)'" -ErrorAction SilentlyContinue
    if ($null -ne $processExists) { Write-Host "done." -ForegroundColor Green } else { Write-Host "failed." -ForegroundColor Red }
    Write-Host "This window will automatically close in 60 seconds ..."
    Start-Sleep -Seconds 60
    [System.Environment]::Exit(0)
}