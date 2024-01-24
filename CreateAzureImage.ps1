param([Parameter(Position = 1, Mandatory = $true)][String]$VirtualMachineName)

<#
    This script illustrates how one could take an existing Azure VM and capture it to serve as an image for a session host pool.
#>

$global:resourceGroupName = "rg-avd"
$global:location = "eastus"
$global:vmName = "cloudpc-00"
$global:snapshotName = "snapshot-win10-22h2-240123"
$global:imageName = "image-win10-22h2-240123"
$global:galleryName = "sig-companyname"
$global:galleryImageImageDefinitionName = "windows10enterprise"
$global:galleryImageVersionName = "24.01.23.0"
$global:endOfLifeDate = "2025-10-31T00:00:00+00:00"

function CreateSnapshot {
    $vm = Get-AzVM - ResourceGroupName $resourceGroupName -Name $vmName -ErrorAction SilentlyContinue -ErrorVariable GetVmError
    if ($null -ne $vm -and -not $GetVmError) {
        $snapshot = New-AzSnapshotConfig -SourceUri $vm.StorageProfile.OsDisk.ManagedDisk.Id -Location $location -CreateOption copy
        New-AzSnapshot -Snapshot $snapshot -SnapshotName $snapshotName -ResourceGroupName $resourceGroupName
        $snapshotExists = Get-AzSnapshot -ResourceGroupName $resourceGroupName
        if ($null -ne $snapshotExists) { return $true }
        else { return $false }
    } else { return $false }
}

function SaveToImage {
    Stop-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -Force -ErrorAction SilentlyContinue -ErrorVariable ErrorStoppingVM
    if (-not $ErrorStoppingVM) {
        Set-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -Generalized -ErrorAction SilentlyContinue -ErrorVariable ErrorSettingVM
        $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vName -ErrorAction SilentlyContinue
        $image = NewAzImageConfig -Location $location -SourceVirtualMachineId $vm.Id
        New-AzImage -Image $image -ImageName $imageName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
        $ImageExists = Get-AzImage -ImageName $imageName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
        if ($null -ne $ImageExists) { return $true }
        else { return $false }
    } else { return $false }
}

function AddVersionToSharedGallery {
    $image = Get-AImage -ResourceGroupName $resourceGroupName -ImageName $imageName -ErrorAction SilentlyContinue
    if ($null -ne $image) {
        $parameters = @{
            ResourceGroupName = $resourceGroupName 
            GalleryName = $galleryName 
            GalaryImageDefinitionName = $galleryImageImageDefinitionName 
            Name = $galleryImageVersionName 
            Location = $location 
            SourceImageId = $image.Id 
            PublishingProfileEndOfLifeDate = $endOfLifeDate 
            ErrorAction = 'SilentlyContinue'
        }
        $imageExists = New-AzGalleryImageVersion @parameters
        if ($null -ne $imageExists) { return $true }
        else { return $false }
    } else { return $false }
}

Write-Host "Creating Snapshot of $vmName ..." -NoNewLine
$created = CreateSnapshot
if ($created) {
    Write-Host "done." -ForegroundColor Green
    Write-Host "Saving the Snapshot to an Image ..." -NoNewline
    $saved = SaveToImage
    If ($saved) {
        Write-Host "done." -ForegroundColor Green
        Write-Host "Adding Image to the Shared Gallery ..." -NoNewline
        $added = AddVersionToSharedGallery
        If ($added) {
            Write-Host "done." -ForegroundColor Green
        } else { Write-Host "failed." -ForegroundColor Red }
    } else { Write-Host "failed." -ForegroundColor Red }
    
} else { Write-Host "failed." -ForegroundColor Red }