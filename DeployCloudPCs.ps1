param (
    [Parameter(Position = 1, Mandatory = $false)]
    [Int]$NumberOfVMs = 1
)

<#
    This script highlights how to use the template and parameter json files generated in Azure AVD after deploying your 1st session host.
    You can re-use these files to automate future deployments and potentially hand this process over to an operations team for future VM assignments, onboarding, etc.
#>

$templateFileName = "template.json"
$parameterFileName = "parameters.json"
$customScriptExtension = "Unzip.ps1"
$hostPoolName = "Cumulus"
$resourceGroupName = "rg-avd"
$storageAccountName = "storavd12345"
$storageContainerName = "scripts"
$sessionHostNamePrefix = "cloudpc"
$templateUri = "https://$storageAccountName.blob.core.windows.net/$storageContainerName/$templateFileName"
$parameterUri = "https://$storageAccountName.blob.core.windows.net/$storageContainerName/$parameterFileName"
$customScriptUri = "https://$storageAccountName.blob.core.windows.net/$storageContainerName/$customScriptExtension"
$scriptDir = Get-Location | Select-Object -ExpandProperty Path
$storageAccount = $null
$storageContainer = $null
$storageBlob = $null
$sessionHosts = $null
$webrequest = $null
$parameters = $null
$blobItem = $null
$deploymentJob = $null

Write-Host "Getting Storage Account ..." -NoNewline
$storageAccount = Get-AZStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction SilentlyContinue
if ($null -ne $storageAccount) { Write-Host "done." -ForegroundColor Green }
else {
    Write-Host "failed." -ForegroundColor Red
    Write-Host "could not complete all steps, please provision session hosts manually." -ForegroundColor White
    return $null
}
Write-Host "Getting Storage Container ..." -NoNewLine
$storageContainer = Get-AZStorageContainer -Name $storageContainerName -Context $storageAccount.Context -ErrorAction SilentlyContinue
if ($null -ne $storageContainer) { Write-Host "done." -ForegroundColor Green }
else {
    Write-Host "failed." -ForegroundColor Red
    Write-Host "could not complete all steps, please provision session hosts manually." -ForegroundColor White
    return $null
}
Write-Host "Getting Storage Blob ..." -NoNewline
$storageBlob = Get-AzStorageBlob -Container $storageContainer.Name -Context $storageAccount.Context
if ($null -ne $storageBlob) { Write-Host "done." -ForegroundColor Green }
else {
    Write-Host "failed." -ForegroundColor Red
    Write-Host "could not complete all steps, please provision session hosts manually." -ForegroundColor White
    return $null
}
Write-Host "Getting parameters file ..." -NoNewline
$webRequest = Invoke-WebRequest -Uri $parameterUri -ErrorAction SilentlyContinue -ErrorVariable webError
if ($null -ne $webrequest) {
    Write-Host "done." -ForegroundColor Green
    try {
        Write-Host "Parsing $parameterFileName ..." -NoNewLine
        $parameters = ($webRequest | Select-Object -ExpandProperty Content) | ConvertFrom-Json
    }
    catch { $parameters = $null }
    if ($null -ne $parameters) { Write-Host "done." -ForegroundColor Green }
    else {
        Write-Host "failed." -ForegroundColor Red
        Write-Host "could not complete all steps, please provision session hosts manually." -ForegroundColor White
        return $null
    }
} else {
    Write-Host "failed." -ForegroundColor Red
    Write-Host "could not complete all steps, please provision session hosts manually." -ForegroundColor White
    return $null
}
Write-Host "Getting Host Pool Registration Token ..." -NoNewline
$token = Get-AzWvdHostPoolRegistrationToken -HostPoolName $hostPoolName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if ($null -ne $token) { 
    Write-Host "done." -ForegroundColor Green
    $parameters.parameters.hostpoolToken.value = $token.Token
    $parameters.parameters.hostpoolProperties.value.registrationInfo.expirationTime = $token.ExpirationTime
    $parameters.parameters.hostpoolProperties.value.registrationInfo.token = $token.Token
}
else {
    Write-Host "failed." -ForegroundColor Red
    Write-Host "could not complete all steps, please provision session hosts manually." -ForegroundColor White
    return $null
}
Write-Host "Getting Session Hosts ..." -NoNewline
$sessionHosts = Get-AzWvdSessionHost -HostPoolName $hostPoolName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if ($null -ne $sessionHosts) { 
    Write-Host "done." -ForegroundColor Green
    $Numbers = ( $sessionHosts.Foreach({ [int]($_.Replace(".domain.local","").Split(".")[1]) }) ) | Sort-Object
    $NextNum = $Numbers[$Numbers.GetUpperBound(0)] + 1
    Write-Host "Changing vmInitialNumber property in $parameterFileName to $NextNum ..." -NoNewline
    $parameters.parameters.vmInitialNumber.value = $NextNum
    $parameters.parameters.vmNumberOfInstances.value = $NumberOfVMs
    $parameters | ConvertTo-Json -Depth 99 | Out-File -FilePath "$scriptDir/$parameterFileName" -Force -ErrorVariable WriteError -ErrorAction SilentlyContinue
    if (-not $WriteError) { Write-Host "done." -ForegroundColor Green } else { Write-Host "failed." -ForegroundColor Red; return $null }
    Write-Host "Updating $parameterFileName in blob storage ..." -NoNewline
    $blobItem = Set-AzStorageBlobContent -File "$scriptDir/$parameterFileName" -Container $storageContainer.Name -Blob "$parameterFileName" -Context $storageAccount.Context -Properties @{"ContentType" = "application/json"} -Force -ErrorAction SilentlyContinue
    if ($null -ne $blobItem) { Write-Host "done." -ForegroundColor Green } else { Write-Host "failed." -ForegroundColor Red; return $null }
    Write-Host "Creating deployment job ..." -NoNewline
    $deploymentJob = New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateParameterUri $parameterUri -TemplateUri $templateUri -AsJob
    if ($null -ne $deploymentJob)     {
        Write-Host "done." -ForegroundColor Green
        Do {
            Write-Host "Waiting for deployment job to complete ..."
            $isRunning = $false
            if ( ($deploymentJob | Select-Object -ExpandProperty State) -like 'running') { $isRunning = $true }
            Start-Sleeping -Seconds 5
        } Until (-not $isRunning)
        for ($i = $NextNum; $i -lt ($NextNum + $NumberOfVMs); $i++) {
            Write-Host "Running Custom Script Extension [$customScriptExtension] on $($sessionHostNamePrefix + '-' + $i) ..."
            $vm = Get-AzVM -Name $($sessionHostNamePrefix + '-' + $i)
            Set-AzVMCustomScriptExtension -VMObject $vm -FileUri $customScriptUri -Run $customScriptExtension -Name "CustomScriptExtension" -Location "East US" -TypeHandlerVersion 1.10
            Update-AzVM - -ResourceGroupName $resourceGroupName -VM $vm
        }
    } else { Write-Host "failed." -ForegroundColor Red; return $null }
}
else {
    Write-Host "failed." -ForegroundColor Red
    Write-Host "could not complete all steps, please provision session hosts manually." -ForegroundColor White
    return $null
}