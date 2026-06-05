# SC Case Permissions Manual Cleanup Runbook (careorchdev)

Date: 2026-05-28
Target org: careorchdev

## Objective

Remove or neutralize non-CareOrch metadata that was introduced only to unblock SC_Case_ObjectPermissions dependency deployment.

## Current state from automation

Completed by API/script:
- SC-derived Case business process removed.
- SC-derived custom fields targeted for deletion in metadata deployment.
- 9 Case record types set inactive:
  - CardMachineCharges
  - ChangeofLegalEntity
  - Chargebacks
  - Collections
  - Complaint
  - EnterpriseAccountManagement
  - Funding
  - GDPR
  - General_Queries
- CareOrch_Case_Runtime_Access no longer references SC-derived record type visibilities.

Blocked by API permissions/platform rules:
- RecordType hard delete via Metadata API: blocked.
- RecordType hard delete via Data API: insufficient access/read-only.
- One record type cannot be deactivated because it is the last active record type for Integration.
- Some custom field deletions are blocked by cross-reference constraints and must be removed after dependency cleanup in Setup UI.

## Manual cleanup steps (Setup UI)

1. Record type cleanup on Case
- Go to Setup -> Object Manager -> Case -> Record Types.
- For each non-CareOrch record type listed above:
  - Confirm Active is unchecked.
  - Remove profile/permission-set assignments where still present.
  - If Delete is available and no dependencies remain, delete it.

2. Integration record type exception
- Go to Setup -> Object Manager -> Case -> Record Types -> Integration.
- Determine whether this record type is needed outside CareOrch.
- If not needed:
  - Repoint dependencies (flows, assignment/routing logic, profile defaults) to an approved remaining record type.
  - Then deactivate or delete Integration when Salesforce allows it.

3. SC-derived custom field cleanup
- Go to Setup -> Object Manager -> Asset -> Fields & Relationships.
- Remove fields (after removing all dependent formulas, layouts, automation):
  - Building_Type__c
  - Door_Type__c
  - Fire_Door_Status__c
  - Inspection_Frequency_Months__c
  - Inspection_Overdue__c
  - Last_Inspection_Date__c
  - Next_Inspection_Due_Date__c
- Go to Setup -> Object Manager -> Case -> Fields & Relationships.
- Remove fields (after removing all dependent references):
  - Acquirer__c
  - Remedial_Due_Date__c

4. Dependency checks before delete
- Update/remove references from:
  - Validation rules
  - Formula fields
  - Flows
  - Page layouts
  - Compact layouts
  - Permission sets and profiles
  - Reports/list views where required

## Post-clean verification

1. Query Case record types
- Only approved CareOrch-compatible record types remain active.

2. Query custom fields
- Asset and Case SC-derived fields above are absent.

3. CareOrch regression smoke test
- Run CareOrchEmarSignalsRestTest and confirm pass.

4. Permission verification
- Confirm users assigned to CareOrch_Clinical_Workspace and CareOrch_Case_Runtime_Access can complete CareOrch runtime actions.
