[String]$global:scriptDir = $PSScriptRoot
[String]$wimSource = "install.wim"
[String]$vhdTarget = "Windows.vhd"
[int]$vhdMaxSize = 120 * 1024 # 120 GiB

function CreateTheVHD {
    param (
        [Parameter(Position = 1, Mandatory = $true)]
        [String]$target,
        [Parameter(Position = 2, Mandatory = $true)]
        [int]$sizeMB
    )
    [String]$diskPartScriptName = "CreatePartitions-UEFI.txt"
    [String]$diskPartScriptPath = (Join-Path -Path $scriptDir -ChildPath $diskPartScriptName)

    # Create the Script to feed DiskPart the commands needed to partition the VHD file
    Get-ChildItem -Path $diskPartScriptName -ErrorAction SilentlyContinue | Remove-Item -Path $diskPartScriptPath -Force -ErrorAction SilentlyContinue
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "create vdisk file=`"$target`" maximum=$sizeMB type=fixed"
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "select vdisk file=`"$target`""
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "attach vdisk"
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "clean"
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "convert gpt"
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "create partition efi size=100"
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "format quick fs=fat32 label=`"System`""
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "assign letter=`"S`""
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "create partition msr size=16"
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "create partition primary"
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "shrink minimum=650"
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "format quick fs=ntfs label=`"Windows`""
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "assign letter=`"W`""
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "create partition primary"
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "format quick fs=ntfs label=`"Recovery Tools`""
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "assign letter=`"R`""
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "set id=`"de94bba4-06d1-4d40-a16a-bfd50179d6ac`""
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "gpt attributes=0x8000000000000001"
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "detach vdisk"
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "exit"

    # Run DiskPart with the command file we just assembled
    $p = Start-Process -FilePath "${env:SystemRoot}\System32\diskpart.exe" -ArgumentList "/s `"$diskPartScriptPath`"" -PassThru -Wait -ErrorAction SilentlyContinue
    if ($null -ne $p) { return $false } 
    elseif ($p.exitCode -eq 0) { return $true }
    else { return $false }
}
function MountTheVHD {
    param (
        [Parameter(Position = 1, Mandatory = $true)]
        [String]$target    
    )
    [String]$scriptDir = $PSScriptRoot
    [String]$diskPartScriptName = "Mount-VHD.txt"
    [String]$diskPartScriptPath = (Join-Path -Path $scriptDir -ChildPath $diskPartScriptName)

    # Create the Script to feed DiskPart the commands needed to partition the VHD file
    Get-ChildItem -Path $diskPartScriptName -ErrorAction SilentlyContinue | Remove-Item -Path $diskPartScriptPath -Force -ErrorAction SilentlyContinue
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "select vdisk file=`"$target`""
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "attach vdisk"
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "exit"
    
    # Run DiskPart with the command file we just assembled
    $p = Start-Process -FilePath "${env:SystemRoot}\System32\diskpart.exe" -ArgumentList "/s `"$diskPartScriptPath`"" -PassThru -Wait -ErrorAction SilentlyContinue
    
    if ($null -ne $p) { return $false } 
    elseif ($p.exitCode -eq 0) { return $true }
    else { return $false }
}
function UnmountTheVHD {
    param (
        [Parameter(Position = 1, Mandatory = $true)]
        [String]$target    
    )
    [String]$scriptDir = $PSScriptRoot
    [String]$diskPartScriptName = "Unmount-VHD.txt"
    [String]$diskPartScriptPath = (Join-Path -Path $scriptDir -ChildPath $diskPartScriptName)

    # Create the Script to feed DiskPart the commands needed to partition the VHD file
    Get-ChildItem -Path $diskPartScriptName -ErrorAction SilentlyContinue | Remove-Item -Path $diskPartScriptPath -Force -ErrorAction SilentlyContinue
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "select vdisk file=`"$target`""
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "detach vdisk"
    Out-File -FilePath $diskPartScriptPath -Encoding ascii -Append -InputObject "exit"
    
    # Run DiskPart with the command file we just assembled
    $p = Start-Process -FilePath "${env:SystemRoot}\System32\diskpart.exe" -ArgumentList "/s `"$diskPartScriptPath`"" -PassThru -Wait -ErrorAction SilentlyContinue
    
    if ($null -ne $p) { return $false } 
    elseif ($p.exitCode -eq 0) { return $true }
    else { return $false }
}

Write-Host "Creating the VHD ..." -NoNewLine
$created = CreateTheVHD -target $vhdTarget -sizeMB $vhdMaxSize
if ($created) {
    Write-Host "done." -ForegroundColor Green
    
    Write-Host "Mounting the VHD ..." -NoNewLine
    $mounted = MountTheVHD -target $vhdTarget
    if ($mounted) {
        Write-Host "done." -ForegroundColor Green
        
        Write-Host "Verifying existence of $wimSource at $scriptDir ..." -NoNewLine
        if ( (Test-Path -Path (Join-Path -Path $scriptDir -ChildPath $wimSource) -PathType Leaf) -eq $true ) {
            Write-Host "done." -ForegroundColor Green
            
            Write-Host "Applying $wimSource to VHD ..." -NoNewLine
            $appliedImage = Start-Process -FilePath "${env:SystemRoot}\System32\dism.exe" -ArgumentList "/Apply-Image /ImageFile:`"$wimSource`" /Index:1 /ApplyDir:W:\" -PassThru -Wait -ErrorVariable errorApplyingImage -ErrorAction SilentlyContinue
            if (-not $errorApplyingImage -and $appliedImage.ExitCode -eq 0) { Write-Host "done." -ForegroundColor Green } else { Write-Host "failed." -ForegroundColor Red }
            
            Write-Host "Updating the Boot Manager in VHD ..." -NoNewLine
            $updatedBootMgr = Start-Process -FilePath "W:\Windows\System32\bcdboot.exe" -ArgumentList "W:\Windows /s S:" -PassThru -Wait -ErrorVariable errorUpdatingBootMgr -ErrorAction SilentlyContinue
            if (-not $errorUpdatingBootMgr -and $updatedBootMgr.ExitCode -eq 0) { Write-Host "done." -ForegroundColor Green } else { Write-Host "failed." -ForegroundColor Red }
            
            Write-Host "Build the Windows Recovery Environment in VHD ..." -NoNewLine
            New-Item -Path R:\Recovery\WindowsRE -Force -ErrorAction SilentlyContinue -ErrorVariable errorCreatingDir | Out-Null
            if (-not $errorCreatingDir) {
                Copy-Item -Path W:\Windows\System32\Recovery\Winre.wim -Destination R:\Recovery\WindowsRE -ErrorAction SilentlyContinue -ErrorVariable errorCopyingRE
                if (-not $errorCopyingRE) {
                    $createdRE = Start-Process -FilePath "W:\Windows\System32\Reagentc.exe" -ArgumentList "/Setreimage /Path R:\Recovery\WinRE /Target W:\Windows" -ErrorAction SilentlyContinue -ErrorVariable errorSettingRE -PassThru -Wait
                    if (-not $errorSettingRE -and $createdRE.ExitCode -eq 0) { Write-Host "done." -ForegroundColor Green } else { Write-Host "failed." -ForegroundColor Red }
                } else { Write-Host "failed." -ForegroundColor Red }
            } else { Write-Host "failed." -ForegroundColor Red }
        } else { Write-Host "failed." -ForegroundColor Red }
        
        Write-Host "Unmounting the VHD ..." -NoNewLine
        $unmounted = UnmountTheVHD -target $vhdTarget
        if ($unmounted) { Write-Host "done." -ForegroundColor Green } else { Write-Host "failed." -ForegroundColor Red }
    
    } else { Write-Host "failed." -ForegroundColor Red }
} else { Write-Host "failed." -ForegroundColor Red }



