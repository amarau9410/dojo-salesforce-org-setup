param(
    [string]$TargetOrg = 'careorchdev'
)

$ErrorActionPreference = 'Stop'

Write-Host "Running lead-access segregation check on org: $TargetOrg" -ForegroundColor Cyan

# Persona permission sets should never overlap with admissions lead-processing sets.
$query = "SELECT Assignee.Username, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name IN ('CareOrch_Floor_Carer','CareOrch_Clinical_Workspace','CareOrch_Operations_Lead','CareOrch_Admissions_Admin','CareOrch_Admissions_Manager') ORDER BY Assignee.Username, PermissionSet.Name"

$resultJson = sf data query --target-org $TargetOrg --query $query --json
$result = $resultJson | ConvertFrom-Json

if ($result.status -ne 0) {
    Write-Host "FAILED: Unable to query permission set assignments." -ForegroundColor Red
    Write-Host $resultJson
    exit 2
}

$records = @($result.result.records)
if ($records.Count -eq 0) {
    Write-Host "WARN: No matching permission-set assignments found." -ForegroundColor Yellow
    exit 0
}

$groupedByUser = $records | Group-Object { $_.PSObject.Properties['Assignee.Username'].Value }
$violations = @()

foreach ($entry in $groupedByUser) {
    $username = $entry.Name
    $permNames = @($entry.Group | ForEach-Object { $_.PSObject.Properties['PermissionSet.Name'].Value })

    $hasCaregiverPersona = ($permNames -contains 'CareOrch_Floor_Carer') -or ($permNames -contains 'CareOrch_Clinical_Workspace') -or ($permNames -contains 'CareOrch_Operations_Lead')
    $hasAdmissionsLeadAccess = ($permNames -contains 'CareOrch_Admissions_Admin') -or ($permNames -contains 'CareOrch_Admissions_Manager')

    if ($hasCaregiverPersona -and $hasAdmissionsLeadAccess) {
        $violations += [PSCustomObject]@{
            Username = $username
            PermissionSets = ($permNames -join ', ')
        }
    }
}

Write-Host "Checked users: $($groupedByUser.Count)" -ForegroundColor Gray

if ($violations.Count -gt 0) {
    Write-Host "FAILED: Caregiver persona users also have admissions lead-processing permissions." -ForegroundColor Red
    $violations | Format-Table -AutoSize | Out-String | Write-Host
    exit 1
}

Write-Host "PASS: No caregiver persona user has admissions lead-processing permission sets." -ForegroundColor Green
exit 0
