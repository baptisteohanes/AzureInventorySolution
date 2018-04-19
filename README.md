# Azure Quotas Monitoring tool

Tools and script to monitor Azure quotas and usage. This runbook is intended to run in an Azure Automation account and push the data to a Log Analytics cube of your choice.

[![Deploy to Azure](http://azuredeploy.net/deploybutton.png)](https://azuredeploy.net/)

## Prerequistes

To run this tool, you'll need :

- a Log Analytics workspace, with is WorkspaceID and Access Key

- an Automation account, where all modules have to be up to date AND the AzureRM.Network module added
