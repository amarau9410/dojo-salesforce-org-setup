# CareOrch Phase 5 Go-Live Gate

This script enforces the production promotion checks defined for GOVERN Phase 5.

## Required checks

1. Journey pass rate must be >= 95%.
2. Crash count must be 0.
3. Activation baseline must be >= 80% of pilot users, with both login and interactive update activity.
4. Unresolved High/Critical defects must be 0 for these areas:
   - SLA timers
   - Validation rules
   - Profile security

## Input files

- `scripts/careorch_uat_journey_summary_template.csv`
- `scripts/careorch_activation_audit_template.csv`
- `scripts/careorch_defect_export_template.csv`

## Usage

```powershell
./scripts/careorch_go_live_gate.ps1 `
  -JourneySummaryCsv ./scripts/careorch_uat_journey_summary.csv `
  -ActivationAuditCsv ./scripts/careorch_activation_audit.csv `
  -DefectExportCsv ./scripts/careorch_defect_export.csv
```

The script exits with code `1` when any gate condition fails and `0` when all conditions pass.
