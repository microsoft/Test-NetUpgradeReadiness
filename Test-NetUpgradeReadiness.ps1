Function Test-Environment {
    $PASS = '+'
    $FAIL = '-'
    $testsFailed = 0

    Write-Host "Testing Host System ${$env:ComputerName}" -ForegroundColor Green

    try {   $isClustered = Get-Cluster -ErrorAction SilentlyContinue -WarningAction SilentlyContinue }
    catch { $isClustered = $false }
    
    if ($isClustered) { Write-Host "[$PASS] The system is clustered" -ForegroundColor DarkCyan }
    else {
        Write-Host "[$FAIL] The system is NOT clustered" -ForegroundColor Red
        $testsFailed ++
    }

    $isInstalled = Get-WindowsFeature -Name NetworkATC -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    if ($isInstalled) { Write-Host "[$PASS] The system has Network ATC installed" -ForegroundColor DarkCyan }
    else {
        Write-Host "[$FAIL] The system does not have Network ATC installed" -ForegroundColor Red
        $testsFailed ++
    }

    $failLBFOTeams = Get-NetLbfoTeam -ErrorAction SilentlyContinue
    if (-not($failLBFOTeams)) { Write-Host "[$PASS] No LBFO Teams were found." -ForegroundColor DarkCyan }
    else {
        Write-Host "[$FAIL] LBFO Teams are not supported. To view the LBFO teams found, run the command Get-NetLBFOTeam and remove the team." -ForegroundColor Red
        $testsFailed ++
    }

    # All tests must be above this
    if ($testsFailed -ne 0) {
        throw 'System is not ready for deployment. Please deploy the cluster prior to moving forward.'
    }
}

Function Get-InUseIntentTypes {
    [Flags()] enum IntentEnum {
        None = 0
        Compute = 2
        Storage = 4
        Management = 8
    }
    
    $allIntentTypes = @()
    $foundIntents  = Get-NetIntent
    
    $foundIntents | ForEach-Object {
        $thisIntent = $_
        $thisIntentTypes = [enum]::GetValues([IntentEnum]) | Where-Object {$_.value__ -band $thisIntent.IntentType}
    
        Switch ($thisIntentTypes | Sort-Object Name) {
            Compute    { $allIntentTypes += 'Compute'    }
            Storage    { $allIntentTypes += 'Storage'    }
            Management { $allIntentTypes += 'Management' }
        }
    }
    
    $missingIntentTypes = @()
    if ($allIntentTypes -notcontains 'Management') { $missingIntentTypes += 'Management'}
    if ($allIntentTypes -notcontains 'Storage'   ) { $missingIntentTypes += 'Storage'   }
    if ($allIntentTypes -notcontains 'Compute'   ) { $missingIntentTypes += 'Compute'   }
    
    return $missingIntentTypes    
}

Function Get-FailedIntents {
    $IntentStatus  = Get-NetIntentStatus
    if (-not($IntentStatus)) {
        throw "No Network ATC intents were found. Please refer to the documentation at https://docs.microsoft.com/en-us/azure-stack/hci/concepts/network-atc-overview"
    }

    $IntentStatus | ForEach-Object {
        $thisIntentStatus = $_

        # Statuses such as 'Validating', 'Pending', 'Provisioning', and 'ProvisioningUpdate' have a good chance of resolving on their own - retry status check for up to five minutes
        if ($thisIntentStatus.ConfigurationStatus -eq ( 'Validating' -or 'Pending' -or 'Provisioning' -or 'ProvisioningUpdate' )) {
            throw "The Network ATC intent [$($thisIntentStatus.IntentName)] is in an intermediate state [$($thisIntentStatus.ConfigurationStatus)] and may resolve naturally in a few minutes. Please rerun this validation tool."
        }
        elseif ($thisIntentStatus.ConfigurationStatus -ne 'Success') {
            Write-Host "[$($thisIntentStatus.Host)] The Network ATC intent [$($thisIntentStatus.IntentName)] is in the [$($thisIntentStatus.ConfigurationStatus)] state" -ForegroundColor Red
            $failure = $true
        }
        else {} # No need for this condition as this indicates the intent was in a successful situation.
    }

    if ($Failure) { return $true }
    else { return $false }
}

Function Test-NetUpgradeReadiness {
    $neededIntentTypes = Get-InUseIntentTypes
    if ($neededIntentTypes -ne $null) {
        throw "Could not find an intent with the intent type $($neededIntentTypes -join ', '). For assistance, please review the documentation at https://docs.microsoft.com/en-us/azure-stack/hci/concepts/network-atc-overview"
    }
    
    $hasFailures = Get-FailedIntents
    if ($hasFailures) { throw 'One or more network intents have not completed successfully. Please review Get-NetIntentStatus or call support.' }
    else { Write-Host 'All intents have succeeded' -ForegroundColor Green }
}

Test-NetUpgradeReadiness
