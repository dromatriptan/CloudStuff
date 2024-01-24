$unzipPath = "${env:SystemDrive}\ConfigMgr"
$zipFileName = "ConfigMgr_5.00.9106.1022.7z"
$scriptDir = $PSScriptRoot

Write-Host "Verifying existence of $unzipPath directory ..." -NoNewline
if (-not (Test-Path -Path $unzipPath -PathType Container)) {
    Write-Host "does not exist, creating ..." -NoNewline
    New-item -Path (Split-Path -Path $unzipPath -Parent) -Name (Split-Path -Path 4unzipPath -Leaf) -ItemType Directory -Force -ErrorAction SilentlyContinue -ErrorVariable DirError | Out-Null
    if (-not $DirError) { Write-Host "done." -ForegroundColor Green } else { Write-Host "failed" -ForegroundColor Red }
} else { Write-Host "exists." -ForegroundColor Green }

if (-not $DirError) {
    Write-Host "Verifying 7zip.exe and 7z.dll exist ..." -NoNewline
    if ( (Test-Path -Path (Join-Path -Path $scriptDir -ChildPath "7z.exe") -PathType Leaf) -and (Test-Path -Path (Join-Path -Path $scriptDir -ChildPath "7z.dll") -PathType Leaf) ) {
        Write-Host "done." -ForegroundColor Green
        Write-Host "Unzipping $zipFileName, please wait." -ForegroundColor Yellow
        $params7zip = @{
            FilePath = Join-Path -Path $scriptDir -ChildPath "7z.exe"
            ArgumentList = "x -y -o`"$(Join-Path -Path $unzipPath -ChildPath "\")`" `"$(Join-Path -Path $scriptDir -ChildPath $zipFileName)`""
            NoNewWindow = $true
            Wait = $true
            PassThru = $true
            WorkingDirectory = $scriptDir
        }
        $process7zip = Start-Process @params7zip
        if ($process7zip.ExitCode -eq 0) {
            Write-Host "Changing directory, to $(Join-Path -Path $unzipPath -ChildPath "5.00.9106.1022") ..." -NoNewLine
            Set-Location -Path (Join-Path -Path $unzipPath -ChildPath "5.00.9106.1022") -ErrorAction SilentlyContinue -ErrorVariable cdError
            if (-not $cdError) {
                Write-Host "done." -ForegroundColor Green
                $paramsPwsh = @{
                    FilePath = "${env:SystemRoot}\System32\WindowsPowerShell\v1.0\powershell.exe"
                    ArgumentList = "-Version 5.0 -ExecutionPolicy Bypass -File `"Install-ConfigMgr.ps1`""
                    NoNewWindow = $true
                    Wait = $true
                    PassThru = $true
                    WorkingDirectory = Join-Path -Path $unzipPath -ChildPath "5.00.9106.1022"
                }
                Write-Host "Installing Configuration Manager Client, please wait ..."
                $processPwsh = Start-Process @paramsPwsh
                if ($processPwsh.ExitCode -eq 0) {
                    Write-Host "done." -ForegroundColor Green
                } else { Write-Host "failed." -ForegroundColor Red }
            } else { Write-Host "failed." -ForegroundColor Red }
        } else { Write-Host "Unzip terminated with non-zero exit code, failing." -ForegroundColor Red }
    } else { Write-Host "failed." -ForegroundColor Red }
}