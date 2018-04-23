<#
    .DESCRIPTION
        This child runbook gets detailed information about Azure quotas for a specific subscription, and sends it to Operations Management Suite (OMS)

    .NOTES
        AUTHOR: Baptiste Ohanes

    .DISCLAIMER
        THE SAMPLE CODE BELOW IS GIVEN “AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL MICROSOFT OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) SUSTAINED BY YOU OR A THIRD PARTY, HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT ARISING IN ANY WAY OUT OF THE USE OF THIS SAMPLE CODE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#>

##############
# Parameters #
##############

Param(
    [Parameter(Mandatory = $true)] [string] $subscriptionId,
    [Parameter(Mandatory = $true)] [string] $subscriptionName,
    [Parameter(Mandatory = $true)] [string] $jobCorrelationId
)

#############
# Functions #
#############get-azure

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

########
# Main #
########

# Set context for child script execution

$customDeploymentPrefix = Get-AutomationVariable "AzureInventorySolution_CustomDeploymentPrefix"
$customSolutionNameForVariables = ($customDeploymentprefix + "_AzureInventorySolution")
$workspaceId = Get-AutomationVariable -Name ($customSolutionNameForVariables + "_WorkspaceId")
$workspaceKey = Get-AutomationVariable -Name ($customSolutionNameForVariables + "_WorkspaceKey")

Write-Output "The following context will be used:"
Write-Output "Subscription Name: $subscriptionName"
Write-Output "OMS Workspace ID: $workspaceId"
Write-Output "Current Job Correlation ID: $jobCorrelationId"

# Specify the name of the record type that you'll be creating and the field with the created time for the records

$LogType = "AzureInventorySolution_Quotas"
$TimeStampField = "Time"

# Connect to the subscription

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


# Execution context definition

$azureLocations = Get-AzureRmLocation
$currentDate = [System.DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:00Z")

# Gets the virtual machine core count usage for all locations

$computeResult = foreach ($location in $azureLocations) {
    $location | Get-AzureRmVMUsage -ErrorAction SilentlyContinue |
        Select-Object -Property `
    @{N = 'Provider'; E = {'Compute'}}, `
    @{N = 'SubscriptionName'; E = {$subscriptionName}}, `
    @{N = 'subscriptionId'; E = {$subscriptionId}}, `
    @{N = 'CurrentValue'; E = {$_.CurrentValue}}, `
    @{N = 'Limit'; E = {$_.Limit}}, `
    @{N = 'Location'; E = {$location.Location}}, `
    @{N = 'Name'; E = {$_.Name.Value}}, `
    @{N = 'Unit'; E = {$_.Unit}}, `
    @{N = 'JobCorrelationId'; E = {$jobCorrelationIdv}}, `
    @{N = 'Time'; E = {$currentDate}}
}
$computeJson = $computeResult | ConvertTo-Json -Compress
Write-Output $computeJson

# Gets the Storage resource usage

$storageResult = Get-AzureRmStorageUsage -ErrorAction SilentlyContinue |
    Select-Object -Property `
@{N = 'Provider'; E = {'Storage'}}, `
@{N = 'SubscriptionName'; E = {$subscriptionName}}, `
@{N = 'subscriptionId'; E = {$subscriptionId}}, `
@{N = 'CurrentValue'; E = {$_.CurrentValue}}, `
@{N = 'Limit'; E = {$_.Limit}}, `
@{N = 'Location'; E = {'global'}}, `
@{N = 'Name'; E = {$_.Name}}, `
@{N = 'Unit'; E = {'Count'}}, `
@{N = 'JobCorrelationId'; E = {$jobCorrelationId}}, `
@{N = 'Time'; E = {$currentDate}}

$storageJson = $storageResult | ConvertTo-Json -Compress
Write-Output $storageJson

# Lists network usages for all locations

$networkResult = foreach ($location in $azureLocations) {
    $location | Get-AzureRmNetworkUsage -ErrorAction SilentlyContinue |
        Select-Object -Property `
    @{N = 'Provider'; E = {'Network'}}, `
    @{N = 'SubscriptionName'; E = {$subscriptionName}}, `
    @{N = 'subscriptionId'; E = {$subscriptionId}}, `
    @{N = 'CurrentValue'; E = {$_.CurrentValue}}, `
    @{N = 'Limit'; E = {$_.Limit}}, `
    @{N = 'Location'; E = {$location.Location}}, `
    @{N = 'Name'; E = {$_.Name.Value}}, `
    @{N = 'Unit'; E = {'Count'}}, `
    @{N = 'JobCorrelationId'; E = {$jobCorrelationId}}, `
    @{N = 'Time'; E = {$currentDate}}
}
$networkJson = $networkResult | ConvertTo-Json -Compress
Write-Output $networkJson

# Submit the data to the API endpoint
Post-LogAnalyticsData -customerId $workspaceId -sharedKey $workspaceKey -body ([System.Text.Encoding]::UTF8.GetBytes($storageJson)) -logType $logType -timeGeneratedField $timeStampField
Post-LogAnalyticsData -customerId $workspaceId -sharedKey $workspaceKey -body ([System.Text.Encoding]::UTF8.GetBytes($computeJson)) -logType $logType -timeGeneratedField $timeStampField
Post-LogAnalyticsData -customerId $workspaceId -sharedKey $workspaceKey -body ([System.Text.Encoding]::UTF8.GetBytes($networkJson)) -logType $logType -timeGeneratedField $timeStampField