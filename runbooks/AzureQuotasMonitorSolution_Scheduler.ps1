<#
    .DESCRIPTION
        A runbook that gets detailed information about Azure usages and quotas, and sends it to Operations Management Suite (OMS)

    .NOTES
        AUTHOR: Baptiste Ohanes

    .DISCLAIMER
        THE SAMPLE CODE BELOW IS GIVEN “AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL MICROSOFT OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) SUSTAINED BY YOU OR A THIRD PARTY, HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT ARISING IN ANY WAY OUT OF THE USE OF THIS SAMPLE CODE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#>

#Connect to Azure and list all readable subscriptions

$connectionName = "AzureRunAsConnection"
$automationAccountName = Get-AutomationVariable -Name "AzureQuotasMonitorSolution_AAName"
$automationAccountResourceGroupName = Get-AutomationVariable -Name "AzureQuotasMonitorSolution_AARGName"
$childRunBookName = "AzureQuotasMonitorSolution_Child"

Write-Output "Following parameters will be used :"
Write-Output $connectionName
Write-Output $automationAccountName
Write-Output $automationAccountResourceGroupName
Write-Output $childRunBookName

Write-Output "Trying to connect to the master subscription"

try
{
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         

    $account = Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint

    Write-Output "Connection confirmed"
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

#List all subscription

$subscriptions = Get-AzureRmSubscription

Write-Output $subscriptions

#Launch child runbook

foreach($subscription in $subscriptions){
    $params = @{"SubscriptionId"=$subscription.Id}
    Start-AzureRmAutomationRunbook -ResourceGroupName $automationAccountResourceGroupName -AutomationAccountName $automationAccountName -Name $childRunBookName -Parameters $params
}