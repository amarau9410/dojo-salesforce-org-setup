# CareOrch Deployment Note (careorchdev)

Date: 2026-05-27
Target org alias: careorchdev

## Scope decision

To keep Epic-critical CareOrch delivery stable, `SC_Case_ObjectPermissions` was intentionally excluded from the deployment target set for this run.

Reason:
- It belongs to broader Service Cloud case security and has deep non-Epic dependencies in this org.
- Including it caused repeated dependency failures unrelated to CareOrch runtime behavior.

## Protective replacement implemented

A focused permission set was created and deployed:
- `CareOrch_Case_Runtime_Access`

File:
- `force-app/main/default/permissionsets/CareOrch_Case_Runtime_Access.permissionset-meta.xml`

This permission set grants access needed for CareOrch runtime paths:
- Apex class access:
  - `CareOrchEmarSignalsRest`
  - `CareOrchEmarSignalActionPlanService`
  - `ManageGroupMemberAction`
- Object permissions:
  - Case
  - Account
  - Contact
  - CareObservation
  - ActionPlan
- User permissions:
  - ApiEnabled
  - ApexRestServices
  - RunFlow
- Case record type visibility for active record types currently present in careorchdev.

## Epic-critical deployment result

Focused CareOrch deployment completed successfully:
- Status: Succeeded
- Components: 7/7
- Component errors: 0
- Test errors: 0

Included metadata:
- `ApexClass:CareOrchEmarSignalsRest`
- `ApexClass:CareOrchEmarSignalActionPlanService`
- `ApexClass:ManageGroupMemberAction`
- `ApexClass:CareOrchEmarSignalsRestTest`
- `Flow:CareOrch_Medication_Refused_Action_Plan`
- `PermissionSet:CareOrch_Clinical_Workspace`
- `PermissionSet:CareOrch_Case_Runtime_Access`

## Validation

Test run executed in careorchdev:
- Test class: `CareOrchEmarSignalsRestTest`
- Result: 8/8 passing
- Failures: 0

## Follow-up (deferred)

Deferred item:
- `SC_Case_ObjectPermissions`

Recommended next step:
- Plan a separate controlled deployment for broader Service Cloud permission parity after resolving remaining non-Epic dependencies.
