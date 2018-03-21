<#
    .DESCRIPTION
        A runbook that gets detailed information about Azure usages and quotas, and sends it to Operations Management Suite (OMS)

    .NOTES
        AUTHOR: Baptiste Ohanes

    .DISCLAIMER
        THE SAMPLE CODE BELOW IS GIVEN “AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL MICROSOFT OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) SUSTAINED BY YOU OR A THIRD PARTY, HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT ARISING IN ANY WAY OUT OF THE USE OF THIS SAMPLE CODE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#>

#$ErrorActionPreference = "Stop"

# Functions used to create the authorization signature, create the request and post it

Function Build-Signature ($workspaceId, $workspaceKey, $date, $contentLength, $method, $contentType, $resource)
{
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($workspaceKey)

    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $workspaceId,$encodedHash
    return $authorization
}

Function Post-OMSData($workspaceId, $workspaceKey, $body, $logType, $timeGeneratedField)
{
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -customerId $workspaceId `
        -sharedKey $workspaceKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -fileName $fileName `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $workspaceId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
        "time-generated-field" = $timeGeneratedField;
    }

    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    return $response.StatusCode
}

#Connect to the analyzed subscription

$connectionName = "AzureRunAsConnection"

try
{
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         

    $account = Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

# Get OMS settings from assets

$workspaceId = Get-AutomationVariable -Name 'AzureQuotasMonitor_WorkspaceId'
Write-Output "OMS Workspace ID: $workspaceId"
$workspaceKey = Get-AutomationVariable -Name 'AzureQuotasMonitor_WorkspaceKey'

# Get current time

$timeGeneratedField = "Time"
$currentDate = [System.DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:00Z")
Write-Output "Current time is $currentDate."

# Load location

$azureLocations = Get-AzureRmLocation

# Gets the virtual machine core count usage for all locations

$computeLogType = "AzureQuotaMonitor_ComputeUsage"
$computeResult = foreach ($location in $azureLocations) {
    $location | Get-AzureRmVMUsage |
        Select-Object -Property `
            @{N='CurrentValue';E={$_.CurrentValue}}, `
            @{N='Limit';E={$_.Limit}}, `
            @{N='Location';E={$location.Location}}, `
            @{N='Name';E={$_.Name.Value}}, `
            @{N='Unit';E={$_.Unit}}, `
            @{N='Time';E={$currentDate}}
}
$computeJson = $computeResult | ConvertTo-Json -Compress
Write-Output $computeJson

# Gets the Storage resource usage

$storageLogType = "AzureQuotaMonitor_StorageUsage"
$storageResult = Get-AzureRmStorageUsage |
    Select-Object -Property `
        @{N='CurrentValue';E={$_.CurrentValue}}, `
        @{N='Limit';E={$_.Limit}}, `
        @{N='Name';E={$_.Name}}, `
        @{N='Unit';E={$_.Unit}}, `
        @{N='Time';E={$currentDate}}
$storageJson = $storageResult | ConvertTo-Json -Compress
Write-Output $storageJson

# Lists network usages for all locations

$networkLogType = "AzureQuotaMonitor_NetworkUsage"
$networkResult = foreach ($location in $azureLocations) {
    $location | Get-AzureRmNetworkUsage |
        Select-Object -Property `
            @{N='CurrentValue';E={$_.CurrentValue}}, `
            @{N='Limit';E={$_.Limit}}, `
            @{N='Location';E={$location.Location}}, `
            @{N='Name';E={$_.Name.Value}}, `
            @{N='Unit';E={$_.Unit}}, `
            @{N='Time';E={$currentDate}}
}
$networkJson = $networkResult | ConvertTo-Json -Compress
Write-Output $networkJson


# Submit the data to the OMS API endpoint

Post-OMSData -customerId $workspaceId -sharedKey $workspaceKey -body ([System.Text.Encoding]::UTF8.GetBytes($computeJson)) -logType $computeLogType -timeGeneratedField $timeGeneratedField
Post-OMSData -customerId $workspaceId -sharedKey $workspaceKey -body ([System.Text.Encoding]::UTF8.GetBytes($networkJson)) -logType $networkLogType -timeGeneratedField $timeGeneratedField
Post-OMSData -customerId $workspaceId -sharedKey $workspaceKey -body ([System.Text.Encoding]::UTF8.GetBytes($storageJson)) -logType $storageLogType -timeGeneratedField $timeGeneratedField