Param(
    [Parameter(Mandatory = $true)] [string] $SubscriptionId
)

# Get OMS settings from assets

$workspaceId = Get-AutomationVariable -Name 'AzureQuotasMonitorSolution_WorkspaceId'
Write-Output "OMS Workspace ID: $workspaceId"
$workspaceKey = Get-AutomationVariable -Name 'AzureQuotasMonitorSolution_WorkspaceKey'


# Specify the name of the record type that you'll be creating
$LogType = "AzureQuotaMonitorSolution"

# Specify a field with the created time for the records
$TimeStampField = "Time"

$connectionName = "AzureRunAsConnection"

try {
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         

    $account = Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint `
        -SubscriptionId $SubscriptionId
}
catch {
    if (!$servicePrincipalConnection) {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    }
    else {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}


Write-Output "The follwoing context will be used:"
$subscription = Get-AzureRmSubscription -subscriptionId $SubscriptionId


$azureLocations = Get-AzureRmLocation


# Create the function to create the authorization signature
Function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource)
{
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)

    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
    return $authorization
}


# Create the function to create and post the request
Function Post-LogAnalyticsData($customerId, $sharedKey, $body, $logType, $timeGeneratedField)
{
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -customerId $customerId `
        -sharedKey $sharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -fileName $fileName `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
        "time-generated-field" = $timeGeneratedField;
    }

    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    return $response.StatusCode

}

$currentDate = [System.DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:00Z")

# Gets the virtual machine core count usage for all locations

$computeResult = foreach ($location in $azureLocations) {
    $location | Get-AzureRmVMUsage -ErrorAction SilentlyContinue |
        Select-Object -Property `
    @{N = 'Type'; E = {'Compute'}}, `
    @{N = 'SubscriptionName'; E = {$subscription.Name}}, `
    @{N = 'subscriptionId'; E = {$subscription.Id}}, `
    @{N = 'CurrentValue'; E = {$_.CurrentValue}}, `
    @{N = 'Limit'; E = {$_.Limit}}, `
    @{N = 'Location'; E = {$location.Location}}, `
    @{N = 'Name'; E = {$_.Name.Value}}, `
    @{N = 'Unit'; E = {$_.Unit}}, `
    @{N = 'Time'; E = {$currentDate}}
}
$computeJson = $computeResult | ConvertTo-Json -Compress
Write-Output $computeJson

# Gets the Storage resource usage

$storageResult = Get-AzureRmStorageUsage -ErrorAction SilentlyContinue |
    Select-Object -Property `
@{N = 'Type'; E = {'Storage'}}, `
@{N = 'SubscriptionName'; E = {$subscription.Name}}, `
@{N = 'subscriptionId'; E = {$subscription.Id}}, `
@{N = 'CurrentValue'; E = {$_.CurrentValue}}, `
@{N = 'Limit'; E = {$_.Limit}}, `
@{N = 'Location'; E = {'global'}}, `
@{N = 'Name'; E = {$_.Name}}, `
@{N = 'Unit'; E = {'Count'}}, `
@{N = 'Time'; E = {$currentDate}}
$storageJson = $storageResult | ConvertTo-Json -Compress
Write-Output $storageJson

# Lists network usages for all locations

$networkResult = foreach ($location in $azureLocations) {
    $location | Get-AzureRmNetworkUsage -ErrorAction SilentlyContinue |
        Select-Object -Property `
    @{N = 'Type'; E = {'Network'}}, `
    @{N = 'SubscriptionName'; E = {$subscription.Name}}, `
    @{N = 'subscriptionId'; E = {$subscription.Id}}, `
    @{N = 'CurrentValue'; E = {$_.CurrentValue}}, `
    @{N = 'Limit'; E = {$_.Limit}}, `
    @{N = 'Location'; E = {$location.Location}}, `
    @{N = 'Name'; E = {$_.Name.Value}}, `
    @{N = 'Unit'; E = {'Count'}}, `
    @{N = 'Time'; E = {$currentDate}}
}
$networkJson = $networkResult | ConvertTo-Json -Compress
Write-Output $networkJson


# Submit the data to the API endpoint
Post-LogAnalyticsData -customerId $workspaceId -sharedKey $workspaceKey -body ([System.Text.Encoding]::UTF8.GetBytes($storageJson)) -logType $logType -timeGeneratedField $timeStampField
Post-LogAnalyticsData -customerId $workspaceId -sharedKey $workspaceKey -body ([System.Text.Encoding]::UTF8.GetBytes($computeJson)) -logType $logType -timeGeneratedField $timeStampField
Post-LogAnalyticsData -customerId $workspaceId -sharedKey $workspaceKey -body ([System.Text.Encoding]::UTF8.GetBytes($networkJson)) -logType $logType -timeGeneratedField $timeStampField