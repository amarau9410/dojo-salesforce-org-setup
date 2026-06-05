param(
    [Parameter(Mandatory = $true)]
    [string]$JourneySummaryCsv,

    [Parameter(Mandatory = $true)]
    [string]$ActivationAuditCsv,

    [Parameter(Mandatory = $true)]
    [string]$DefectExportCsv,

    [double]$JourneyPassRateThreshold = 95,
    [double]$ActivationThreshold = 80
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-FileExists {
    param([string]$Path, [string]$Label)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label file not found: $Path"
    }
}

function To-Bool {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $normalized = $Value.Trim().ToLowerInvariant()
    return $normalized -in @('true', '1', 'yes', 'y')
}

function To-NormalizedString {
    param($Value)

    if ($null -eq $Value) {
        return ''
    }

    return [string]$Value
}

Ensure-FileExists -Path $JourneySummaryCsv -Label 'Journey summary'
Ensure-FileExists -Path $ActivationAuditCsv -Label 'Activation audit'
Ensure-FileExists -Path $DefectExportCsv -Label 'Defect export'

$journeyRows = @(Import-Csv -LiteralPath $JourneySummaryCsv)
if ($journeyRows.Count -eq 0) {
    throw 'Journey summary file is empty.'
}

$journeyTotals = $journeyRows | ForEach-Object {
    $passed = [double]($_.PassedCount)
    $failed = [double]($_.FailedCount)
    $crashes = [double]($_.CrashCount)

    [pscustomobject]@{
        Passed  = $passed
        Failed  = $failed
        Crashes = $crashes
        Total   = $passed + $failed
    }
}

$totalPassed = ($journeyTotals | Measure-Object -Property Passed -Sum).Sum
$totalFailed = ($journeyTotals | Measure-Object -Property Failed -Sum).Sum
$totalCrashes = ($journeyTotals | Measure-Object -Property Crashes -Sum).Sum
$totalJourneys = $totalPassed + $totalFailed

if ($totalJourneys -le 0) {
    throw 'Journey summary has no executed journeys (PassedCount + FailedCount = 0).'
}

$journeyPassRate = [math]::Round(($totalPassed / $totalJourneys) * 100, 2)

$activationRows = @(Import-Csv -LiteralPath $ActivationAuditCsv)
if ($activationRows.Count -eq 0) {
    throw 'Activation audit file is empty.'
}

$pilotRows = @($activationRows | Where-Object { To-Bool $_.IsPilotUser })
if ($pilotRows.Count -eq 0) {
    throw 'Activation audit contains no pilot users (IsPilotUser=true).'
}

$activePilotUsers = @(
    $pilotRows | Where-Object {
        (To-Bool $_.LoggedInDuringPilot) -and (To-Bool $_.PerformedInteractiveUpdate)
    }
)

$activationRate = [math]::Round(($activePilotUsers.Count / $pilotRows.Count) * 100, 2)

$defectRows = @(Import-Csv -LiteralPath $DefectExportCsv)
$protectedAreas = @('sla timers', 'validation rules', 'profile security')
$targetDefects = @(
    $defectRows | Where-Object {
        $severity = (To-NormalizedString $_.Severity).Trim().ToLowerInvariant()
        $status = (To-NormalizedString $_.Status).Trim().ToLowerInvariant()
        $area = (To-NormalizedString $_.Area).Trim().ToLowerInvariant()

        $isHighSeverity = $severity -in @('high', 'critical')
        $isResolved = $status -in @('closed', 'resolved', 'done', 'verified')
        $isProtectedArea = $false
        foreach ($candidate in $protectedAreas) {
            if ($area -like "*$candidate*") {
                $isProtectedArea = $true
                break
            }
        }

        $isHighSeverity -and (-not $isResolved) -and $isProtectedArea
    }
)

$failures = @()
if ($journeyPassRate -lt $JourneyPassRateThreshold) {
    $failures += "Journey pass rate $journeyPassRate% is below required $JourneyPassRateThreshold%."
}
if ($totalCrashes -ne 0) {
    $failures += "Crash count is $totalCrashes. Requirement is zero crashes."
}
if ($activationRate -lt $ActivationThreshold) {
    $failures += "Activation baseline $activationRate% is below required $ActivationThreshold%."
}
if ($targetDefects.Count -ne 0) {
    $failures += "Found $($targetDefects.Count) unresolved High/Critical defects in SLA timers, validation rules, or profile security."
}

Write-Host '=== CareOrch Phase 5 Go-Live Gate ==='
Write-Host "Journey pass rate: $journeyPassRate%"
Write-Host "Journey crashes: $totalCrashes"
Write-Host "Activation baseline: $activationRate%"
Write-Host "Unresolved High/Critical defects (protected areas): $($targetDefects.Count)"

if ($failures.Count -gt 0) {
    Write-Error "Go-live gate failed:`n - $($failures -join "`n - ")"
    exit 1
}

Write-Host 'Go-live gate passed. Deployment promotion is allowed.'
exit 0
