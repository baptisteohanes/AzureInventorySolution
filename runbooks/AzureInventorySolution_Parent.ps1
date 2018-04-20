<#
    .DESCRIPTION
        A scheduler runbook that lists the subscriptions to analyze and lauch the corresponding child runbook.

    .NOTES
        AUTHOR: Baptiste Ohanes

    .DISCLAIMER
        THE SAMPLE CODE BELOW IS GIVEN “AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL MICROSOFT OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) SUSTAINED BY YOU OR A THIRD PARTY, HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT ARISING IN ANY WAY OUT OF THE USE OF THIS SAMPLE CODE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#>

########
# Main #
########

# Global context definiton

$connectionName = "AzureRunAsConnection"
$customSolutionName = "AzureInventorySolution_CustomName"
$childQuotasRunbookName = ($customSolutionName + "-Quotas-Child")
$childAssetsRunbookName = ($customSolutionName + "-Assets-Child")
$workspaceId = Get-AutomationVariable -Name ($customSolutionName + "_WorkspaceId")

Write-Output "Following parameters will be used :"
Write-Output ("Azure Automation connection: "+ $connectionName)
Write-Output ("Child runbook name for quotas: "+ $childQuotasRunbookName)
Write-Output ("Child runbook name for assets: "+ $childAssetsRunbookName)
Write-Output "OMS Workspace Id: $workspaceId"
Write-Output "Trying to connect to the master subscription..."

# Connect to Azure

try
{
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         

    $account = Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint `
        -Subscription $servicePrincipalConnection.SubscriptionId
    
    Write-Output "Connected to the master subscription"
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

# List all subscription that can be accessed by the service principal

$subscriptions = Get-AzureRmSubscription

Write-Output "The following subscriptions will be analyzed:"

foreach($subscription in $subscriptions){
    Write-Output $subscription.Name
}

# Start child runbook instances for each subscription

Write-Output "Launching analyze jobs:"

foreach($subscription in $subscriptions){
    $params = @{"subscriptionId"=$subscription.Id; "subscriptionName"=$subscription.Name}
    Start-AutomationRunbook -Name $childQuotasRunbookName -Parameters $params
    Start-AutomationRunbook -Name $childAssetsRunbookName -Parameters $params
    
}