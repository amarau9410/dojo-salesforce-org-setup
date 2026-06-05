$ErrorActionPreference = 'Stop'
Set-Location "c:\Users\NnamdiUdoye\Dojo Salesforce Org Setup\Dojo Salesforce Org Setup"

$max = 20
for ($i = 1; $i -le $max; $i++) {
  sf project deploy start --target-org careorchdev --ignore-conflicts --wait 90 --metadata "PermissionSet:SC_Case_ObjectPermissions" --json *> "tmp\deploy-sc-case-perm-loop-$i.json"
  $raw = Get-Content "tmp\deploy-sc-case-perm-loop-$i.json" -Raw
  $idx = $raw.IndexOf('{')
  if ($idx -lt 0) {
    Write-Output "LOOP_${i}:PARSE_FAIL"
    break
  }

  $j = $raw.Substring($idx) | ConvertFrom-Json
  if ($j.result.status -eq 'Succeeded') {
    Write-Output "LOOP_${i}:SC_CASE_PERMSET_SUCCEEDED"
    break
  }

  $fails = @($j.result.details.componentFailures)
  $rtFail = $fails | Where-Object { $_.problem -match 'no RecordType named Case\.([A-Za-z0-9_]+)' } | Select-Object -First 1
  if (-not $rtFail) {
    Write-Output "LOOP_${i}:NON_RECORDTYPE_BLOCKER"
    $fails | ForEach-Object { "  {0}`t{1}`t{2}" -f $_.componentType, $_.fullName, $_.problem }
    break
  }

  $rt = [regex]::Match($rtFail.problem, 'no RecordType named Case\.([A-Za-z0-9_]+)').Groups[1].Value
  $rtPath = "force-app/main/default/objects/Case/recordTypes/$rt.recordType-meta.xml"
  if (-not (Test-Path $rtPath)) {
    Write-Output "LOOP_${i}:MISSING_LOCAL_RECORDTYPE_FILE:$rt"
    break
  }

  $xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<RecordType xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>$rt</fullName>
    <active>true</active>
    <businessProcess>Card Machine Charges Process</businessProcess>
    <description>$rt record type for careorchdev compatibility.</description>
    <label>$rt</label>
</RecordType>
"@
  Set-Content -Path $rtPath -Value $xml -NoNewline

  sf project deploy start --target-org careorchdev --ignore-conflicts --wait 90 --source-dir $rtPath --source-dir "force-app/main/default/objects/Case/businessProcesses/Card Machine Charges Process.businessProcess-meta.xml" --json *> "tmp\deploy-sc-case-rt-loop-$i.json"
  $raw2 = Get-Content "tmp\deploy-sc-case-rt-loop-$i.json" -Raw
  $idx2 = $raw2.IndexOf('{')
  if ($idx2 -lt 0) {
    Write-Output "LOOP_${i}:RT_DEPLOY_PARSE_FAIL:$rt"
    break
  }

  $j2 = $raw2.Substring($idx2) | ConvertFrom-Json
  Write-Output "LOOP_${i}:DEPLOYED_RT=$rt STATUS=$($j2.result.status) ERRORS=$($j2.result.numberComponentErrors)"
}
