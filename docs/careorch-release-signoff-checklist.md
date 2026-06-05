# CareOrch Release Sign-Off Checklist (Epic 1-5)

Date: 2026-05-28
Target Org: careorchdev

## 1) Salesforce Metadata Deployment

- [x] Epic-critical CareOrch metadata deployed successfully to careorchdev
- [x] `CareOrchEmarSignalsRest` deployed
- [x] `CareOrchEmarSignalActionPlanService` deployed
- [x] `ManageGroupMemberAction` deployed
- [x] `CareOrchEmarSignalsRestTest` deployed
- [x] `CareOrch_Medication_Refused_Action_Plan` deployed
- [x] `CareOrch_Clinical_Workspace` permission set deployed
- [x] `CareOrch_Case_Runtime_Access` permission set deployed
- [x] `SC_Case_ObjectPermissions` intentionally excluded from Epic-critical deployment path

## 2) Runtime Security and Access

- [x] USER_MODE hardening in targeted CareOrch classes completed
- [x] Focused replacement permission model deployed for CareOrch runtime path
- [ ] Assign `CareOrch_Clinical_Workspace` to required non-admin users
- [ ] Assign `CareOrch_Case_Runtime_Access` to required non-admin users
- [ ] Confirm assigned users can execute CareOrch Case/Flow/runtime actions

## 3) Validation and Testing

- [x] `CareOrchEmarSignalsRestTest` executed in careorchdev
- [x] Test result: 8/8 passing, 0 failing
- [ ] Run additional UAT scenario pass for end-user profiles (non-admin)

## 4) Epic 3 Mobile Offline (Manual Setup)

- [ ] Configure Briefcase Builder in Setup for `CareOrch_Floor_Cache`
- [ ] Add Task and Account offline rules per validation guide
- [ ] Assign briefcase to `CareOrch Floor Carer` permission set
- [ ] Verify offline read/write sync behavior on mobile client

Reference:
- `docs/epic3-mobile-offline-validation.md`

## 5) Epic 5 Commercial/Listing Path

- [x] Security scanner run and findings reviewed for targeted CareOrch classes
- [x] Local website updates completed under `tmp/wilfredandkaizer-website`
- [ ] Publish/deploy website assets to intended hosting environment
- [ ] Validate contact/web-to-case route in live hosted context
- [ ] Complete 2GP packaging/version creation process
- [ ] Run subscriber install + smoke tests for package submission readiness

Reference:
- `docs/epic5-appExchange-compliance-validation.md`

## 6) Phase 5 Custom Lightning App Wrapper

- [x] Created and deployed `CustomApplication` metadata for `CareOrch`
- [x] Created and deployed custom LWC navigation tab `careOrchCarerWorkspace`
- [x] Secured app visibility to `CareOrch Floor Carer` permission set
- [x] Default app navigation prioritizes:
  - `careOrchCarerWorkspace`
  - `Patients` via `standard-Account`
  - `standard-Task`
  - `standard-Dashboard`
- [ ] Add native `HealthCloudGA__EHR_Observation__c` app nav item
  - Blocker: object/tab not available in careorchdev (managed-package dependency not present)
- [ ] Deploy utility bar notifications item
  - Blocker: notification utility component design metadata unavailable in careorchdev
- [x] Added focused shift operations tab: `CareOrch Shift Inbox` (LWC tab + Apex controller)
- [x] Added compact agenda tab: `CareOrch My Calendar` (next 14 days shift schedule for current user)
- [x] Extended app navigation with `standard-Event` (Calendar) and `standard-ActionPlan` tabs
- [x] Enabled `CareOrch_Floor_Carer` read access to `ActionPlan` so carers can use Action Plan tab in-app

Deployment References (App UX Enhancements):
- Shift Inbox + nav update deploy: `0AfQ100000RXgiVKAT`
- My Calendar + nav update deploy: `0AfQ100000RXheXKAT`
- Floor Carer ActionPlan access deploy: `0AfQ100000RXhgAKAT`

## 7) Deferred / Separate Workstream

- [ ] Execute manual cleanup for SC_Case_ObjectPermissions dependency artifacts (API-blocked items)
- [x] Remove SC-derived Case record type visibilities from `CareOrch_Case_Runtime_Access`
- [x] Deactivate 9 non-CareOrch Case record types introduced during SC dependency unblocking
- [ ] Resolve `Case.Integration` last-active-record-type dependency and deactivate/delete when safe
- [ ] Complete UI-led deletion of remaining SC-derived custom fields after dependency detach
- [ ] Reconcile source-to-org delta for wider Service Cloud permission parity

Reference:
- `docs/careorchdev-careorch-deployment-note.md`
- `docs/sc-case-objectpermissions-manual-cleanup-runbook.md`

## 8) Multilingual Translation Phase 1

- [x] Deployed `CareOrch_Observation_Translation_Prep` record-triggered flow
- [x] Flow enforces translation prep behavior on `CareObservation` create/update:
  - English or blank language: `English_Translation__c` mirrors `Original_Observation__c`, `Translation_Status__c = Not Required`
  - Non-English with no English translation yet: `Translation_Status__c = Pending Translation`
- [x] Deployed `CareOrch_Observation_Auto_Translate` record-triggered flow
- [x] Deployed `CareOrchObservationAutoTranslateAction` invocable Apex action for automatic translation handoff
- [x] Pending translation records now auto-populate `English_Translation__c` and set `Translation_Status__c = Auto Translated`
- [x] Added managed AI translation callout path in `CareOrchObservationAutoTranslateAction` via Named Credential endpoint `callout:CareOrchTranslationService/translate`
- [x] Added admin setup runbook: `docs/careorch-translation-provider-runbook.md`
- [x] Added one-record validation script: `scripts/validate_careorch_translation_provider.apex`
- [ ] Configure Named Credential `CareOrchTranslationService` auth + endpoint in careorchdev and validate provider responses
- [ ] Add reviewer process for translated notes (`Reviewed` lifecycle)

## 9) Shift Assignment Notifications and Escalation

- [x] Deployed Activity-level custom fields for shift orchestration (Task/Event shared model):
  - `CareOrch_Shift_Start__c`
  - `CareOrch_Shift_End__c`
  - `CareOrch_Shift_Status__c`
  - `CareOrch_Handover_Comment__c`
  - `CareOrch_Shift_Manager__c`
  - `CareOrch_Contacted_Caregiver_Ids__c`
  - `CareOrch_Contacted_Count__c`
  - `CareOrch_Rejected_Count__c`
- [x] Deployed `CareOrchShiftAssignmentTrigger`
- [x] Deployed `CareOrchShiftAssignmentService`
- [x] Deployed `CareOrchShiftResponseRest` (accept/reject endpoint)
- [x] Updated `CareOrch_Floor_Carer` permission set with new class + field access
- [x] Updated `CareOrch_Clinical_Workspace` permission set with new class + field access
- [x] Assignment email now includes shift window, patient, handover details, and Accept/Reject action links
- [x] Reject path now routes to next available caregiver and notifies manager
- [x] Exhaustion path now marks shift as `Unfilled` and notifies manager with contacted/rejected counts
- [x] Post-deploy metadata smoke checks passed in careorchdev:
  - Apex classes present: `CareOrchShiftAssignmentService`, `CareOrchShiftResponseRest`
  - Trigger present: `CareOrchShiftAssignmentTrigger`
  - Task fields present: all 8 `CareOrch_*` shift fields
  - Permission set field access confirmed for `CareOrch_Floor_Carer` and `CareOrch_Clinical_Workspace`
- [x] Trigger behavior smoke check passed:
  - Created Task `Smoke Shift Assignment` (`00TQ100000GIjryMAD`)
  - Auto-initialized values observed: `CareOrch_Shift_Status__c=Pending`, `CareOrch_Contacted_Count__c=1`, `CareOrch_Rejected_Count__c=0`
- [ ] Run UAT: caregiver accepts assigned shift via email link and manager receives acceptance notification
- [ ] Run UAT: caregiver rejects assigned shift and confirm automatic reassignment to next caregiver
- [ ] Run UAT: reject until caregiver pool exhausted and confirm manager escalation includes counters
- [ ] Confirm HTTP GET access behavior for `/services/apexrest/careorch/shift-response` for intended user profile/session context

UAT Script (Shift Notification and Escalation):

Pre-conditions:
- At least 3 active users exist with `CareOrch_Floor_Carer` permission set and valid email addresses.
- Manager user has valid email and is referenced in `Task.CareOrch_Shift_Manager__c` (or caregiver `User.ManagerId` fallback is populated).
- Email deliverability is set to `All Email` in the test org.

Test Data Setup:
1. Create Task A with values:
  - `Subject = UAT Shift Accept`
  - `CareOrch_Shift_Start__c` and `CareOrch_Shift_End__c` populated
  - `CareOrch_Handover_Comment__c = UAT accept path handover`
  - `CareOrch_Shift_Manager__c` populated
  - Owner = Caregiver 1
2. Create Task B with values:
  - `Subject = UAT Shift Reject Reroute`
  - Same required shift fields as Task A
  - Owner = Caregiver 1
3. Create Task C with values:
  - `Subject = UAT Shift Exhaustion`
  - Same required shift fields as Task A
  - Owner = Caregiver 1

Scenario 1 - Accept Path:
1. Open Caregiver 1 mailbox and locate the shift assignment email for Task A.
2. Verify email contains shift start/end, patient context, handover text, and both action links.
3. Click `Accept Shift`.
4. Query Task A and verify:
  - `CareOrch_Shift_Status__c = Accepted`
  - `CareOrch_Contacted_Count__c >= 1`
  - `CareOrch_Rejected_Count__c = 0`
5. Verify manager received `CareOrch Shift Accepted` email.

Scenario 2 - Reject Then Reroute:
1. Open Caregiver 1 mailbox and click `Reject Shift` for Task B.
2. Query Task B and verify:
  - `OwnerId` changed from Caregiver 1 to another caregiver
  - `CareOrch_Shift_Status__c = Pending`
  - `CareOrch_Rejected_Count__c = 1`
  - `CareOrch_Contacted_Count__c` incremented
3. Verify manager received `CareOrch Shift Rejected - Reassigned` email.
4. Verify new owner caregiver received assignment email for Task B.

Scenario 3 - Exhaustion Escalation:
1. For Task C, each newly assigned caregiver clicks `Reject Shift` until no eligible caregiver remains.
2. Query Task C and verify:
  - `CareOrch_Shift_Status__c = Unfilled`
  - `CareOrch_Contacted_Count__c` equals total contacted caregivers
  - `CareOrch_Rejected_Count__c` equals total rejections
3. Verify manager receives `CareOrch Shift Escalation - No Caregiver Accepted` email.
4. Verify escalation email includes contacted/rejected counters.

SOQL Snippets (Copy/Paste):

- Validate Task A (Accept path)
  SELECT Id, Subject, OwnerId, CareOrch_Shift_Status__c, CareOrch_Contacted_Count__c, CareOrch_Rejected_Count__c, CareOrch_Contacted_Caregiver_Ids__c, LastModifiedDate
  FROM Task
  WHERE Subject = 'UAT Shift Accept'
  ORDER BY CreatedDate DESC
  LIMIT 1

- Validate Task B (Reject then reroute)
  SELECT Id, Subject, OwnerId, CareOrch_Shift_Status__c, CareOrch_Contacted_Count__c, CareOrch_Rejected_Count__c, CareOrch_Contacted_Caregiver_Ids__c, LastModifiedDate
  FROM Task
  WHERE Subject = 'UAT Shift Reject Reroute'
  ORDER BY CreatedDate DESC
  LIMIT 1

- Validate Task C (Exhaustion escalation)
  SELECT Id, Subject, OwnerId, CareOrch_Shift_Status__c, CareOrch_Contacted_Count__c, CareOrch_Rejected_Count__c, CareOrch_Contacted_Caregiver_Ids__c, LastModifiedDate
  FROM Task
  WHERE Subject = 'UAT Shift Exhaustion'
  ORDER BY CreatedDate DESC
  LIMIT 1

- Validate class deployment (Tooling API)
  SELECT Name, NamespacePrefix
  FROM ApexClass
  WHERE Name IN ('CareOrchShiftAssignmentService','CareOrchShiftResponseRest')
  ORDER BY Name

- Validate trigger deployment (Tooling API)
  SELECT Name, NamespacePrefix
  FROM ApexTrigger
  WHERE Name = 'CareOrchShiftAssignmentTrigger'

- Validate field-level permissions for both permission sets
  SELECT Parent.Name, SobjectType, Field, PermissionsRead, PermissionsEdit
  FROM FieldPermissions
  WHERE Parent.Name IN ('CareOrch_Floor_Carer','CareOrch_Clinical_Workspace')
    AND SobjectType = 'Task'
    AND Field IN (
      'Task.CareOrch_Shift_Start__c',
      'Task.CareOrch_Shift_End__c',
      'Task.CareOrch_Shift_Status__c',
      'Task.CareOrch_Handover_Comment__c',
      'Task.CareOrch_Shift_Manager__c',
      'Task.CareOrch_Contacted_Caregiver_Ids__c',
      'Task.CareOrch_Contacted_Count__c',
      'Task.CareOrch_Rejected_Count__c'
    )
  ORDER BY Parent.Name, Field

Evidence to Capture:
- Screenshot of assignment email body with action links.
- SOQL output for Task A, Task B, and Task C final states.
- Screenshot or headers of manager notification emails (Accepted, Reassigned, Unfilled).

Exit Criteria:
- All three scenarios pass expected status, ownership, counters, and notifications.
- No unexpected automation impacts observed on non-CareOrch Task flows.

Deployment References:
- Activity fields deploy: `0AfQ100000RXfhZKAT`
- Apex/trigger/permset deploy: `0AfQ100000RXeQZKA1`

## Sign-Off

Technical deployment status for CareOrch Epic-critical scope: READY

Final readiness status for Epic 1-5 program scope: PENDING MANUAL/UI AND PACKAGING TASKS
