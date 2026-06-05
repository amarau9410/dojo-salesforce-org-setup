param(
    [string]$OutputPath = "scripts/uat_execution_log_seed.csv",
    [int]$RecordsPerScenario = 10,
    [string]$BuildVersion = "careorchdev-uat-2026-05-28"
)

$scenarios = @(
    @{ UatId = "FC-01"; Persona = "Floor Carer"; Journey = "View assigned shifts" },
    @{ UatId = "FC-02"; Persona = "Floor Carer"; Journey = "Accept shift from email link" },
    @{ UatId = "FC-03"; Persona = "Floor Carer"; Journey = "Reject shift and auto-reroute" },
    @{ UatId = "FC-04"; Persona = "Floor Carer"; Journey = "At-risk detection visibility" },
    @{ UatId = "FC-05"; Persona = "Floor Carer"; Journey = "Incident logging with context" },
    @{ UatId = "FC-06"; Persona = "Floor Carer"; Journey = "Observation authoring" },
    @{ UatId = "CR-01"; Persona = "Clinical Reviewer"; Journey = "Pending translation queue" },
    @{ UatId = "CR-02"; Persona = "Clinical Reviewer"; Journey = "Translation edit and handoff" },
    @{ UatId = "CR-03"; Persona = "Clinical Reviewer"; Journey = "Reviewed-status gate" },
    @{ UatId = "CR-04"; Persona = "Clinical Reviewer"; Journey = "Medication refused follow-up" },
    @{ UatId = "OL-01"; Persona = "Operations Lead"; Journey = "Cockpit KPI snapshot" },
    @{ UatId = "OL-02"; Persona = "Operations Lead"; Journey = "Critical breach drill-down" },
    @{ UatId = "OL-03"; Persona = "Operations Lead"; Journey = "Shift corrective action" },
    @{ UatId = "OL-04"; Persona = "Operations Lead"; Journey = "In-line save" },
    @{ UatId = "OL-05"; Persona = "Operations Lead"; Journey = "Phone override logging" },
    @{ UatId = "OL-06"; Persona = "Operations Lead"; Journey = "SLA threshold governance" },
    @{ UatId = "RL-01"; Persona = "Release Lead"; Journey = "Golden Rule enforcement" },
    @{ UatId = "RL-02"; Persona = "Release Lead"; Journey = "Clinical close gate" },
    @{ UatId = "RL-03"; Persona = "Release Lead"; Journey = "Escalation automation" },
    @{ UatId = "RL-04"; Persona = "Release Lead"; Journey = "Go-live gate automation" }
)

$rows = @()
$nowUtc = (Get-Date).ToUniversalTime().ToString("s") + "Z"

foreach ($scenario in $scenarios) {
    for ($i = 1; $i -le $RecordsPerScenario; $i++) {
        $rows += [PSCustomObject]@{
            UAT_ID                 = $scenario.UatId
            Persona                = $scenario.Persona
            Journey                = $scenario.Journey
            Tester_Username        = "uat.$($scenario.UatId.ToLower()).$i@careorch.test"
            Build_Version_Timestamp = $BuildVersion
            Selected_Options_Values = "Scenario-run-$i"
            Actual_Result_Summary  = "Pending execution"
            Result_Code            = "Not Run"
            Defect_ID              = ""
            Evidence_Links         = ""
            Attempt_Number         = $i
            Generated_At_Utc       = $nowUtc
        }
    }
}

$outputDir = Split-Path -Path $OutputPath -Parent
if (![string]::IsNullOrWhiteSpace($outputDir) -and !(Test-Path -Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
}

$rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
Write-Host "Generated $($rows.Count) UAT execution records across $($scenarios.Count) scenarios at $OutputPath"
