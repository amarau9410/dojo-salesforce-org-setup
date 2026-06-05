# CareOrch End-to-End Implementation Walkthrough

Date: 2026-06-03  
Primary org: careorchdev  
Reference target org: careorchuat

## 1. Executive Summary

CareOrch is a safety-critical Service Cloud implementation for shift reliability, incident management, communication closed-loop controls, clinical translation quality, and manager-led intervention.

The implementation is declarative-first with focused Apex services where runtime orchestration, secure server-side checks, or integration behavior is required.

Business outcomes delivered:
1. Shift assignment, acceptance, rejection, reroute, and at-risk detection.
2. Incident capture with active-shift context and geolocation.
3. Mandatory family communication and escalation with hard-stop close controls.
4. Translation workflow with reviewer-only governance controls.
5. Manager cockpit for triage, intervention, and SLA governance.
6. Operational Alert case triage model and charting by priority.
7. Persona-based least-privilege access model using permission sets.
8. Nutritional intake capture with immutable post-create audit protection.

## 2. Architectural Scope

Core architecture and module inventory are documented in:
1. [docs/careorch-solution-design-deep-dive.md](docs/careorch-solution-design-deep-dive.md)
2. [docs/careorch-uat-persona-map.md](docs/careorch-uat-persona-map.md)
3. [docs/careorch-caregiver-training-guide.md](docs/careorch-caregiver-training-guide.md)

High-level component areas:
1. Carer UX: workspace, shift inbox, calendar, incident logger.
2. Incident pipeline: Critical Event trigger, dispatch service, escalation job.
3. Translation pipeline: pre-save and post-save flow plus invocable translation action.
4. Manager operations: cockpit LWC + controller, in-line save, reassignment, phone override.
5. Governance controls: SLA thresholds, validation rules, UAT gate script.

## 3. Data Model and Record Responsibilities

### 3.1 Shift and Reliability

Primary object: Task (Activity extensions)

Key custom fields include:
1. CareOrch_Shift_Start__c
2. CareOrch_Shift_End__c
3. CareOrch_Shift_Status__c
4. CareOrch_Contacted_Count__c
5. CareOrch_Rejected_Count__c
6. CareOrch_Time_to_First_Response_Minutes__c
7. CareOrch_Time_to_Fill_Minutes__c
8. CareOrch_At_Risk__c
9. CareOrch_At_Risk_Reason__c
10. CareOrch_Handover_Comment__c
11. Likely_To_Fail__c

Supporting object: Shift_Lifecycle__c

### 3.2 Critical Incident and Communication

Primary object: Critical_Event__c

Supporting object: Communication_Log__c (master-detail to Critical_Event__c)

Critical controls include:
1. Acknowledged_Communication_Count__c roll-up evidence.
2. Closed-loop acknowledgement validation.
3. Mandatory clinical documentation validation.

### 3.3 Clinical Observation and Translation

Primary object: CareObservation

Controls include:
1. Translation_Status__c lifecycle.
2. Draft_Unverified_Translation__c and translation text fields.
3. Reviewer-only guard on Reviewed status transitions.
4. Nutritional capture fields for meal period, consumption level, and refusal notes.
5. Nutritional records become immutable after creation via validation rule.

### 3.4 Operational Alert Triage

Primary object: Case, Record Type Operational_Alert

CareOrch fields:
1. CareOrch_Alert_Source__c
2. CareOrch_Severity__c
3. CareOrch_Critical_Event__c
4. CareOrch_Resident_Impact__c

Validation rules enforce:
1. Required classification fields.
2. Coherence between Alert Source and Critical Event link.

## 4. End-to-End Runtime Journeys

### 4.1 Shift Execution Journey (Floor Carer)

1. Task shift is created or routed.
2. Trigger and service initialize metrics and assignment metadata.
3. Assignment email is sent with accept and reject links.
4. Carer accepts or rejects via REST endpoint.
5. Service updates counters, status, response times, and risk indicators.
6. Manager is notified on key events.

Main implementation points:
1. [force-app/main/default/triggers/CareOrchShiftAssignmentTrigger.trigger](force-app/main/default/triggers/CareOrchShiftAssignmentTrigger.trigger)
2. [force-app/main/default/classes/CareOrchShiftAssignmentService.cls](force-app/main/default/classes/CareOrchShiftAssignmentService.cls)
3. [force-app/main/default/classes/CareOrchShiftResponseRest.cls](force-app/main/default/classes/CareOrchShiftResponseRest.cls)

### 4.2 Critical Incident to Communication Closed Loop

1. Carer opens incident logger.
2. Controller resolves active shift and resident context.
3. Critical event is created with taxonomy, mapped category, shift context, and location.
4. Trigger invokes dispatch service.
5. Initial communication log and outbound comm are created.
6. Escalation job is scheduled based on SLA thresholds.
7. If no acknowledgement, escalation sends backup dispatch and updates status.
8. Close action is blocked until acknowledgement evidence exists.

Main implementation points:
1. [force-app/main/default/lwc/careOrchIncidentLogger/careOrchIncidentLogger.js](force-app/main/default/lwc/careOrchIncidentLogger/careOrchIncidentLogger.js)
2. [force-app/main/default/classes/CareOrchCriticalIncidentController.cls](force-app/main/default/classes/CareOrchCriticalIncidentController.cls)
3. [force-app/main/default/triggers/CareOrchCriticalEventTrigger.trigger](force-app/main/default/triggers/CareOrchCriticalEventTrigger.trigger)
4. [force-app/main/default/classes/CareOrchCriticalEventDispatchService.cls](force-app/main/default/classes/CareOrchCriticalEventDispatchService.cls)
5. [force-app/main/default/classes/CareOrchCriticalEventEscalationJob.cls](force-app/main/default/classes/CareOrchCriticalEventEscalationJob.cls)
6. [force-app/main/default/objects/Critical_Event__c/validationRules/CareOrch_Closed_Loop_Acknowledgement.validationRule-meta.xml](force-app/main/default/objects/Critical_Event__c/validationRules/CareOrch_Closed_Loop_Acknowledgement.validationRule-meta.xml)
7. [force-app/main/default/objects/Critical_Event__c/validationRules/CareOrch_Mandatory_Clinical_Doc.validationRule-meta.xml](force-app/main/default/objects/Critical_Event__c/validationRules/CareOrch_Mandatory_Clinical_Doc.validationRule-meta.xml)

### 4.3 Translation and Reviewer Governance

1. Observation is authored.
2. Before-save flow determines translation path.
3. After-save flow invokes translation action.
4. Translation output and status flags are updated.
5. Reviewer-only controls restrict final Reviewed transitions.

Main implementation points:
1. [force-app/main/default/flows/CareOrch_Observation_Translation_Prep.flow-meta.xml](force-app/main/default/flows/CareOrch_Observation_Translation_Prep.flow-meta.xml)
2. [force-app/main/default/flows/CareOrch_Observation_Auto_Translate.flow-meta.xml](force-app/main/default/flows/CareOrch_Observation_Auto_Translate.flow-meta.xml)
3. [force-app/main/default/classes/CareOrchObservationAutoTranslateAction.cls](force-app/main/default/classes/CareOrchObservationAutoTranslateAction.cls)
4. [force-app/main/default/objects/CareObservation/validationRules/CareOrch_Reviewed_Status_Admin_Only.validationRule-meta.xml](force-app/main/default/objects/CareObservation/validationRules/CareOrch_Reviewed_Status_Admin_Only.validationRule-meta.xml)

### 4.4 Manager Cockpit Intervention Journey

1. Cockpit loads KPI snapshot and exception datasets.
2. Manager can drill down critical breaches and at-risk shifts.
3. Manager can perform in-line edits.
4. Manager can reassign shifts to eligible floor carers.
5. Manager can log phone override communication.
6. Operational Alert case priority chart drives triage sequencing.

Main implementation points:
1. [force-app/main/default/lwc/careOrchManagerCockpit/careOrchManagerCockpit.js](force-app/main/default/lwc/careOrchManagerCockpit/careOrchManagerCockpit.js)
2. [force-app/main/default/classes/CareOrchManagerCockpitController.cls](force-app/main/default/classes/CareOrchManagerCockpitController.cls)
3. [force-app/main/default/objects/CareOrch_SLA_Threshold__c/CareOrch_SLA_Threshold__c.object-meta.xml](force-app/main/default/objects/CareOrch_SLA_Threshold__c/CareOrch_SLA_Threshold__c.object-meta.xml)
4. [force-app/main/default/classes/CareOrchSlaThresholdService.cls](force-app/main/default/classes/CareOrchSlaThresholdService.cls)

### 4.5 Nutritional Logging Journey (E11-R1)

1. Carer opens CareOrch Workspace.
2. Carer clicks Log Nutritional Intake.
3. Modal captures Resident Account Id, Meal Period, Consumption Level, and optional refusal notes.
4. Workspace invokes CareOrchResidentClinicalLogger.createNutritionalObservation.
5. CareObservation is created with:
	- Metric_Type__c = Food Intake (Quarter/Half/Full)
	- ObservationStatus = Preliminary
	- Meal_Period__c, CareOrch_Consumption_Level__c, and Food_Record__c populated.
6. Post-create edits to nutritional fields are blocked by CareOrch_Nutritional_Log_Immutable.

Main implementation points:
1. [force-app/main/default/lwc/careOrchCarerWorkspace/careOrchCarerWorkspace.html](force-app/main/default/lwc/careOrchCarerWorkspace/careOrchCarerWorkspace.html)
2. [force-app/main/default/lwc/careOrchCarerWorkspace/careOrchCarerWorkspace.js](force-app/main/default/lwc/careOrchCarerWorkspace/careOrchCarerWorkspace.js)
3. [force-app/main/default/classes/CareOrchResidentClinicalLogger.cls](force-app/main/default/classes/CareOrchResidentClinicalLogger.cls)
4. [force-app/main/default/objects/CareObservation/fields/CareOrch_Consumption_Level__c.field-meta.xml](force-app/main/default/objects/CareObservation/fields/CareOrch_Consumption_Level__c.field-meta.xml)
5. [force-app/main/default/objects/CareObservation/validationRules/CareOrch_Nutritional_Log_Immutable.validationRule-meta.xml](force-app/main/default/objects/CareObservation/validationRules/CareOrch_Nutritional_Log_Immutable.validationRule-meta.xml)

## 5. Role and Security Model

Permission sets are the primary access-control model.

Primary personas:
1. Floor Carer: CareOrch_Floor_Carer
2. Clinical Reviewer: CareOrch_Clinical_Workspace
3. Operations Lead: CareOrch_Operations_Lead
4. Admissions roles: CareOrch_Admissions_Admin and CareOrch_Admissions_Manager

Authority boundaries:
1. Shift reassignment is Operations Lead via Manager Cockpit.
2. Floor Carer responds to assigned shifts and does not assign shifts.
3. Clinical Reviewer does not assign shifts.

References:
1. [force-app/main/default/permissionsets/CareOrch_Floor_Carer.permissionset-meta.xml](force-app/main/default/permissionsets/CareOrch_Floor_Carer.permissionset-meta.xml)
2. [force-app/main/default/permissionsets/CareOrch_Clinical_Workspace.permissionset-meta.xml](force-app/main/default/permissionsets/CareOrch_Clinical_Workspace.permissionset-meta.xml)
3. [force-app/main/default/permissionsets/CareOrch_Operations_Lead.permissionset-meta.xml](force-app/main/default/permissionsets/CareOrch_Operations_Lead.permissionset-meta.xml)

## 6. Lead Pipeline and Admissions Scope

Lead is used for pre-admission Care_Enquiry intake and conversion guardrails.

Implementation points:
1. Record type: Lead.Care_Enquiry
2. Validation rules for required funding and care type fields.
3. Assignment routing service and trigger.
4. Post-conversion preparation task automation through record-triggered flow.
5. Admissions-focused permission sets with Lead tab visibility.

References:
1. [force-app/main/default/classes/CareOrchLeadAssignmentService.cls](force-app/main/default/classes/CareOrchLeadAssignmentService.cls)
2. [force-app/main/default/triggers/CareOrchLeadAssignmentTrigger.trigger](force-app/main/default/triggers/CareOrchLeadAssignmentTrigger.trigger)
3. [force-app/main/default/flows/CareOrch_Lead_Post_Conversion_Preparation_Task.flow-meta.xml](force-app/main/default/flows/CareOrch_Lead_Post_Conversion_Preparation_Task.flow-meta.xml)
4. [force-app/main/default/objects/Lead/recordTypes/Care_Enquiry.recordType-meta.xml](force-app/main/default/objects/Lead/recordTypes/Care_Enquiry.recordType-meta.xml)
5. [force-app/main/default/permissionsets/CareOrch_Admissions_Admin.permissionset-meta.xml](force-app/main/default/permissionsets/CareOrch_Admissions_Admin.permissionset-meta.xml)
6. [force-app/main/default/permissionsets/CareOrch_Admissions_Manager.permissionset-meta.xml](force-app/main/default/permissionsets/CareOrch_Admissions_Manager.permissionset-meta.xml)

## 7. Recent Enhancements Included

### 7.1 Operational Alert Chart Accuracy

The manager chart was corrected so bar widths are rendered by valid CSS width declarations and now scale to actual counts.

Reference:
1. [force-app/main/default/lwc/careOrchManagerCockpit/careOrchManagerCockpit.js](force-app/main/default/lwc/careOrchManagerCockpit/careOrchManagerCockpit.js)

### 7.2 Critical Event Taxonomy Expansion

Taxonomy now includes:
1. Fall
2. Medication Error
3. Serious Injury
4. Elopement / Missing Resident
5. Resident-to-Resident Altercation
6. Choking Incident
7. Unresponsive / Loss of Consciousness
8. Sudden Clinical Deterioration
9. Skin Integrity Failure (Severe Pressure Ulcer)
10. Unexplained Injury

The incident logger option list and server-side category mapping were updated accordingly.

References:
1. [force-app/main/default/objects/Critical_Event__c/fields/Critical_Event_Taxonomy__c.field-meta.xml](force-app/main/default/objects/Critical_Event__c/fields/Critical_Event_Taxonomy__c.field-meta.xml)
2. [force-app/main/default/lwc/careOrchIncidentLogger/careOrchIncidentLogger.js](force-app/main/default/lwc/careOrchIncidentLogger/careOrchIncidentLogger.js)
3. [force-app/main/default/classes/CareOrchCriticalIncidentController.cls](force-app/main/default/classes/CareOrchCriticalIncidentController.cls)

## 8. UAT and Evidence Model

UAT is persona-based and mapped to acceptance criteria.

References:
1. [docs/careorch-uat-persona-map.md](docs/careorch-uat-persona-map.md)
2. [scripts/uat_execution_log_seed.csv](scripts/uat_execution_log_seed.csv)
3. [scripts/uat_execution_log_seed_persona_users.csv](scripts/uat_execution_log_seed_persona_users.csv)
4. [scripts/careorch_go_live_gate.ps1](scripts/careorch_go_live_gate.ps1)

Evidence expectations:
1. Record IDs and screenshots per journey step.
2. Explicit pass/fail code per run.
3. Hard-stop controls validated for release gate.

Latest in-org validation snapshot (careorchdev):
1. E11 documentation-aligned deploy IDs:
	- 0AfQ100000RcvKIKAZ (E11 metadata and workspace updates)
	- 0AfQ100000Rcw6fKAB (required ObservationStatus update)
2. Focused regression test execution:
	- Test Run Id: 707Q100000o2qFq
	- Class: CareOrchResidentProfileTest
	- Result: 7/7 passed (includes nutritional immutability check)

## 9. Runtime Data Seeding Notes

Runtime UAT records were seeded for:
1. Accounts (residents)
2. Shift Tasks
3. Shift Lifecycle
4. Critical Events
5. Communication Logs
6. Operational Alert Cases

CareObservation seeding may be access-dependent in some contexts and should be executed with a user/profile that has confirmed create permissions on CareObservation.

Seed script reference:
1. [scripts/seed_careorch_uat_runtime_records.apex](scripts/seed_careorch_uat_runtime_records.apex)

## 10. Deployment and Environment Considerations

careorchdev currently holds the full baseline used for validation.

careorchuat is connected, but full-package deployment from the entire repository fails due to non-CareOrch dependencies and missing foundation metadata in that target org.

Recommended Salesforce handoff strategy:
1. Deploy a CareOrch-scoped package set only.
2. Validate required custom objects and field dependencies first.
3. Deploy LWC and Apex bundles after object baseline exists.
4. Seed runtime data.
5. Execute persona UAT and gate scripts.

## 11. Suggested Salesforce Walkthrough Agenda (60-90 min)

1. Business context and safety goals (5 min)
2. Architecture and module map (10 min)
3. Shift reliability flow live demo (10 min)
4. Incident closed-loop controls live demo (15 min)
5. Translation and reviewer governance demo (10 min)
6. Manager cockpit intervention and chart interpretation (10 min)
7. Security model and role boundaries (10 min)
8. UAT evidence and release gate method (10 min)
9. Open Q and A and deployment next steps (10 min)

## 12. Sign-off Checklist for Salesforce Review

1. Confirm all required objects/fields exist in target org.
2. Confirm persona permission sets are assigned to active users.
3. Confirm incident logger and manager cockpit render and invoke Apex successfully.
4. Confirm critical-event close hard-stop validation is active.
5. Confirm SLA thresholds are present for Death and DEFAULT.
6. Confirm operational alert chart reflects live case priorities.
7. Confirm UAT execution logs and evidence pack structure are in place.
8. Confirm release gate script inputs and thresholds are agreed.

## 13. Technical Workflows by Scenario

This section describes runtime execution logic in concrete scenarios so admins, architects, and QA can trace exactly what should happen.

### Scenario 1: Shift Assignment Accepted on First Contact

Goal: A shift is assigned and accepted immediately, with metrics captured.

Preconditions:
1. Task shift exists with valid start and end fields.
2. Assigned user has Floor Carer permissions.

Workflow:
1. Task is inserted or updated into assignment-ready state.
2. Shift assignment trigger calls service layer.
3. Service sets assignment metadata and sends email with accept and reject links.
4. Carer clicks accept endpoint.
5. REST handler validates token context and marks shift accepted.
6. Service updates:
	- CareOrch_Shift_Status__c
	- CareOrch_Time_to_First_Response_Minutes__c
	- CareOrch_Time_to_Fill_Minutes__c
	- CareOrch_Contacted_Count__c
7. Optional manager notification is sent per policy.

Expected outcome:
1. Shift status is Accepted.
2. At-risk flag remains false.
3. Lifecycle log reflects assignment and response timestamps.

### Scenario 2: Shift Rejected and Re-Routed

Goal: A rejected shift is re-routed while preserving auditability.

Preconditions:
1. Shift is in offered or pending response state.
2. Alternate eligible carers are available.

Workflow:
1. Carer clicks reject endpoint.
2. REST handler records rejection reason and timestamp.
3. Service increments CareOrch_Rejected_Count__c.
4. Assignment logic selects next eligible carer.
5. New assignment notification is sent.
6. If retries exceed threshold, service sets:
	- CareOrch_At_Risk__c = true
	- CareOrch_At_Risk_Reason__c with explanation
7. Manager cockpit surfaces this shift in exception view.

Expected outcome:
1. Rejection and reroute are traceable.
2. At-risk visibility is immediate for Operations Lead.

### Scenario 3: Critical Event Logged and Acknowledged Within SLA

Goal: Incident is logged and communication is acknowledged before escalation.

Preconditions:
1. User has incident logging permission.
2. Active shift and resident context are resolvable.

Workflow:
1. User submits incident in logger LWC.
2. Controller maps taxonomy and category, then creates Critical_Event__c.
3. Trigger invokes dispatch service.
4. Service creates initial Communication_Log__c and sends outbound communication.
5. Family or responsible party acknowledges communication.
6. Acknowledged_Communication_Count__c rollup becomes greater than zero.
7. Event can proceed to closure when mandatory clinical fields are complete.

Expected outcome:
1. Escalation path is not executed.
2. Closed-loop validation passes.

### Scenario 4: Critical Event Not Acknowledged and Escalated

Goal: Enforce escalation and prevent premature closure.

Preconditions:
1. Critical event exists in open state.
2. No acknowledgement before SLA deadline.

Workflow:
1. Escalation job runs on schedule.
2. Job checks event age against CareOrch_SLA_Threshold__c.
3. If acknowledgement count is zero:
	- escalation status is updated
	- backup dispatch is sent
	- additional Communication_Log__c entries are created
4. Attempt to close event without acknowledgement is blocked by validation rule.
5. After acknowledgement and required documentation, close operation succeeds.

Expected outcome:
1. No silent incident closure.
2. Audit trail shows escalation and communication retries.

### Scenario 5: Observation Auto-Translation with Reviewer Governance

Goal: Translation runs automatically, but final approval is role-controlled.

Preconditions:
1. Observation record meets flow entry criteria.
2. Translation target context is available.

Workflow:
1. Before-save flow sets translation preparation flags.
2. After-save flow invokes auto-translate action.
3. Action writes translated output and status updates.
4. Non-reviewer user attempts Reviewed status.
5. Validation rule blocks transition.
6. Clinical Reviewer completes review and sets final status.

Expected outcome:
1. Translation throughput is automated.
2. Clinical sign-off integrity is preserved.

### Scenario 6: Manager Reassignment and Phone Override

Goal: Operations Lead resolves staffing exceptions through cockpit actions.

Preconditions:
1. User has CareOrch_Operations_Lead permission set.
2. Shift is at-risk or requires reassignment.

Workflow:
1. Manager cockpit loads KPI and exception datasets.
2. Operations Lead selects shift and target carer.
3. reassignShift server action validates authority and eligibility.
4. Shift ownership and lifecycle state update.
5. Manager logs phone override communication entry where required.
6. Cockpit refreshes metrics and exception lists.

Expected outcome:
1. Reassignment is completed by authorized role only.
2. Manual interventions are captured for audit.

### Scenario 7: Operational Alert Case Priority Visualization

Goal: Priority chart reflects true case distribution.

Preconditions:
1. Operational_Alert cases exist with populated Priority.
2. Cockpit chart component receives aggregate data.

Workflow:
1. Controller queries grouped case counts by Priority.
2. LWC computes normalized percentage widths.
3. normalizeCasePriorityWidth returns full CSS style width value.
4. Bars render proportionally to count.
5. Any new case changes are reflected after data refresh.

Expected outcome:
1. High-priority bars are visually larger only when counts are larger.
2. Chart is reliable for manager triage.

### Scenario 8: Admissions Lead Intake and Assignment

Goal: Lead intake follows Care_Enquiry controls and routing.

Preconditions:
1. Lead record type is Care_Enquiry.
2. User has Admissions permission set.

Workflow:
1. Lead is created with intake details.
2. Validation rules enforce required funding and care-type fields.
3. Lead assignment trigger calls assignment service.
4. Lead is routed to admissions owner or queue.
5. Conversion proceeds only when data quality criteria are met.

Expected outcome:
1. Admissions pipeline is governed and measurable.
2. Ownership is deterministic and role-aligned.

## 14. Scenario-to-Component Traceability Matrix

1. Scenario 1 and 2:
	- CareOrchShiftAssignmentTrigger
	- CareOrchShiftAssignmentService
	- CareOrchShiftResponseRest
	- Shift_Lifecycle__c
2. Scenario 3 and 4:
	- careOrchIncidentLogger
	- CareOrchCriticalIncidentController
	- CareOrchCriticalEventTrigger
	- CareOrchCriticalEventDispatchService
	- CareOrchCriticalEventEscalationJob
	- Critical_Event__c validation rules
3. Scenario 5:
	- CareOrch_Observation_Translation_Prep flow
	- CareOrch_Observation_Auto_Translate flow
	- CareOrchObservationAutoTranslateAction
	- Reviewed status validation rule
4. Scenario 6 and 7:
	- careOrchManagerCockpit LWC
	- CareOrchManagerCockpitController
	- CareOrchSlaThresholdService
5. Scenario 8:
	- CareOrchLeadAssignmentTrigger
	- CareOrchLeadAssignmentService
	- Lead.Care_Enquiry metadata
	- Admissions permission sets

## 15. UAT Execution Pattern by Scenario

For each scenario execution, capture:
1. Test actor persona and user id.
2. Input record ids.
3. Timestamped action sequence.
4. Expected versus actual outcome.
5. Evidence links: screenshots, SOQL result snippets, and record history.
6. Final verdict: Pass, Fail, or Blocked.

Recommended run order:
1. Scenario 1
2. Scenario 2
3. Scenario 3
4. Scenario 4
5. Scenario 5
6. Scenario 6
7. Scenario 7
8. Scenario 8

This order minimizes test dependency conflicts and mirrors live operational progression from staffing to incident response to governance reporting.

## 16. Full Process Playbook (Every Process Explained)

This section expands each operational process into implementation-level detail using a standard format.

Template used for every process:
1. Purpose
2. Trigger
3. Actors and permissions
4. Required inputs and data contracts
5. Step-by-step runtime flow
6. Decision logic
7. Data writes and side effects
8. Notifications and user experience
9. Failure modes and controls
10. Evidence and QA checks

### 16.1 Process P01: Shift Record Creation (Source Entry)

1. Purpose:
	- Create a Task record that qualifies as a CareOrch shift.
2. Trigger:
	- User, integration, or process inserts a Task with shift datetime fields.
3. Actors and permissions:
	- Operations actors or system integrations with Task create access.
4. Required inputs and data contracts:
	- Task.Subject
	- Task.OwnerId
	- Task.WhatId (recommended for resident or location linkage)
	- CareOrch_Shift_Start__c
	- CareOrch_Shift_End__c
5. Step-by-step runtime flow:
	- Insert Task.
	- Shift trigger fires after insert.
	- Assignment service inspects Task for shift qualification.
6. Decision logic:
	- Record is shift-eligible only when start and end are both present.
7. Data writes and side effects:
	- Initial record insert only.
	- Additional normalization happens in P02.
8. Notifications and user experience:
	- None at creation itself until initialization determines pending assignment.
9. Failure modes and controls:
	- Missing shift fields means no shift lifecycle initialization.
10. Evidence and QA checks:
	- SOQL confirms new Task with shift fields populated.

### 16.2 Process P02: Shift Initialization and Assignment Email Dispatch

1. Purpose:
	- Initialize shift control fields and notify assigned caregiver.
2. Trigger:
	- Task after insert or after update where owner changes or status moves to Pending.
3. Actors and permissions:
	- Trigger context execution.
4. Required inputs and data contracts:
	- Qualified shift Task record.
	- Owner must be active user with email.
5. Step-by-step runtime flow:
	- Trigger calls assignment service handleAfter.
	- Service computes initialization set.
	- Service updates default fields: status, counters, risk flags, contacted list.
	- Service re-queries refreshed tasks.
	- Service sends accept and reject email links.
6. Decision logic:
	- Process runs for insert, owner change, or explicit shift status transition to Pending.
7. Data writes and side effects:
	- CareOrch_Shift_Status__c default to Pending if blank.
	- CareOrch_Contacted_Caregiver_Ids__c updated.
	- CareOrch_Contacted_Count__c, CareOrch_Rejected_Count__c, CareOrch_At_Risk__c initialized.
8. Notifications and user experience:
	- Caregiver receives email with accept and reject endpoint links.
9. Failure modes and controls:
	- Owner missing email prevents dispatch.
	- Recursion guard prevents trigger self-loop.
10. Evidence and QA checks:
	- Verify Task fields initialized.
	- Verify email activity and unique links generated.

### 16.3 Process P03: Shift Acceptance Flow

1. Purpose:
	- Mark shift accepted and finalize response metrics.
2. Trigger:
	- Caregiver clicks accept endpoint.
3. Actors and permissions:
	- Floor Carer user, REST endpoint handler, assignment service.
4. Required inputs and data contracts:
	- Task Id from endpoint.
	- Acting user identity.
5. Step-by-step runtime flow:
	- REST endpoint validates request.
	- Service loads target shift.
	- Service stamps first response and fill timestamps.
	- Service sets Accepted status.
	- Service optionally emails manager.
6. Decision logic:
	- First response timestamp set if absent, preserved if already present.
7. Data writes and side effects:
	- CareOrch_Shift_Status__c = Accepted.
	- CareOrch_First_Response_At__c and CareOrch_Filled_At__c written.
	- Time-to-response and time-to-fill recomputed.
8. Notifications and user experience:
	- Manager gets acceptance update when manager email is resolvable.
9. Failure modes and controls:
	- Missing task or invalid state blocks update.
10. Evidence and QA checks:
	- Confirm status and timing fields after acceptance.

### 16.4 Process P04: Shift Rejection and Auto-Reroute

1. Purpose:
	- Handle caregiver rejection and route to next eligible caregiver.
2. Trigger:
	- Caregiver clicks reject endpoint.
3. Actors and permissions:
	- Floor Carer user, REST endpoint handler, assignment service.
4. Required inputs and data contracts:
	- Task Id.
	- Rejecting user Id.
5. Step-by-step runtime flow:
	- Endpoint invokes rejectAndRouteToNextCaregiver.
	- Service locks task with FOR UPDATE.
	- Service increments rejected count and updates contacted list.
	- Service resolves next caregiver from CareOrch_Floor_Carer permission set members.
	- If found, owner set to next caregiver and status reset to Pending.
	- If not found, task marked Unfilled.
6. Decision logic:
	- Branch A: next caregiver available.
	- Branch B: no caregiver available.
7. Data writes and side effects:
	- Contacted and rejected counters updated.
	- Risk flags updated based on risk evaluation.
	- Manager notification sent for reassignment or escalation.
8. Notifications and user experience:
	- Manager receives rejection/reassignment updates.
9. Failure modes and controls:
	- No eligible caregivers leads to Unfilled terminal state.
10. Evidence and QA checks:
	- Confirm owner change or Unfilled status path.
	- Confirm counters and risk reason updates.

### 16.5 Process P05: At-Risk Evaluation and Alerting

1. Purpose:
	- Flag staffing risk before or at unfilled outcome.
2. Trigger:
	- Rejection cycle processing.
3. Actors and permissions:
	- Assignment service.
4. Required inputs and data contracts:
	- Current rejection count.
	- Historical unfilled pattern for same linked context.
5. Step-by-step runtime flow:
	- Evaluate high rejection threshold.
	- Evaluate repeated unfilled shifts in lookback window and time band.
	- Construct consolidated risk reason.
6. Decision logic:
	- At risk when any configured risk condition is met.
7. Data writes and side effects:
	- CareOrch_At_Risk__c and CareOrch_At_Risk_Reason__c updated.
	- Alert sent once if not already sent.
8. Notifications and user experience:
	- Operations Lead sees at-risk signals in cockpit and can intervene.
9. Failure modes and controls:
	- Prevent duplicate alert spam via alert-sent flag.
10. Evidence and QA checks:
	- Confirm risk reason includes trigger condition text.

### 16.6 Process P06: Operations Lead Manual Reassignment

1. Purpose:
	- Allow controlled intervention by Operations Lead.
2. Trigger:
	- Reassign action from Manager Cockpit.
3. Actors and permissions:
	- CareOrch_Operations_Lead only.
4. Required inputs and data contracts:
	- Task Id.
	- Target caregiver Id.
	- Manager note.
5. Step-by-step runtime flow:
	- LWC calls reassignShift controller action.
	- Controller validates authority and payload.
	- Task owner updated and shift status set to Pending.
	- Handover or manager context updated.
	- Assignment lifecycle re-enters notification path.
6. Decision logic:
	- Unauthorized persona blocked.
7. Data writes and side effects:
	- OwnerId and status update.
8. Notifications and user experience:
	- Updated shift appears in relevant inbox and cockpit views.
9. Failure modes and controls:
	- Invalid caregiver or permission mismatch rejected.
10. Evidence and QA checks:
	- Confirm owner history and status transition.

### 16.7 Process P07: Shift Inbox and Calendar Read Models

1. Purpose:
	- Present current user shifts in operational UI views.
2. Trigger:
	- LWC page load or manual refresh.
3. Actors and permissions:
	- Floor Carer and permitted clinical users.
4. Required inputs and data contracts:
	- Current user context.
	- Window start and end for calendar view.
5. Step-by-step runtime flow:
	- Apex controller queries Task where owner is current user and shift fields exist.
	- Data mapped to view DTOs.
6. Decision logic:
	- Status fallback applied if blank.
7. Data writes and side effects:
	- Read-only operation.
8. Notifications and user experience:
	- Inbox and calendar drive caregiver daily execution.
9. Failure modes and controls:
	- Missing field permissions produce empty or partial datasets.
10. Evidence and QA checks:
	- Compare query results with rendered rows.

### 16.8 Process P08: Incident Logging with Active Shift Resolution

1. Purpose:
	- Capture critical incident tied to active care context.
2. Trigger:
	- Submit from incident logger LWC.
3. Actors and permissions:
	- Floor Carer and authorized users.
4. Required inputs and data contracts:
	- Event taxonomy.
	- Resident or contextual linkage.
	- Optional geolocation and narrative details.
5. Step-by-step runtime flow:
	- Controller resolves active shift candidate.
	- Controller maps event category from taxonomy.
	- Critical_Event__c inserted with shift and context fields.
	- Critical event trigger fires for dispatch workflow.
6. Decision logic:
	- Category mapping may collapse multiple severe taxonomies into serious concern category.
7. Data writes and side effects:
	- New Critical_Event__c record.
8. Notifications and user experience:
	- Incident appears in manager and escalation pipelines.
9. Failure modes and controls:
	- Missing required fields blocked by object validations.
10. Evidence and QA checks:
	- Confirm event created with expected taxonomy and mapped category.

### 16.9 Process P09: Critical Event Dispatch and Initial Communication Log

1. Purpose:
	- Ensure immediate outreach and auditable communication baseline.
2. Trigger:
	- Critical event insert or qualifying update.
3. Actors and permissions:
	- Critical event trigger and dispatch service.
4. Required inputs and data contracts:
	- Critical event details.
	- Contact channel details.
5. Step-by-step runtime flow:
	- Trigger invokes dispatch service.
	- Service creates initial Communication_Log__c.
	- Service sends outbound communication.
	- Service schedules escalation path using SLA threshold context.
6. Decision logic:
	- Threshold uses event category-specific minutes with fallback.
7. Data writes and side effects:
	- Communication log records.
	- Escalation schedule entries.
8. Notifications and user experience:
	- Family and operations channels receive notifications.
9. Failure modes and controls:
	- Missing routing metadata may force fallback behavior.
10. Evidence and QA checks:
	- Confirm log count and schedule timestamps.

### 16.10 Process P10: Escalation Job and No-Acknowledgement Path

1. Purpose:
	- Prevent unresolved incidents from stalling.
2. Trigger:
	- Scheduled job execution.
3. Actors and permissions:
	- Scheduled Apex job context.
4. Required inputs and data contracts:
	- Open critical events.
	- Acknowledgement count and SLA threshold records.
5. Step-by-step runtime flow:
	- Job evaluates each open event against SLA.
	- If acknowledgement missing, escalation actions execute.
	- Backup communication generated and logged.
6. Decision logic:
	- Escalate only when threshold breached and acknowledgement count remains zero.
7. Data writes and side effects:
	- Event escalation fields updated.
	- Additional communication logs inserted.
8. Notifications and user experience:
	- Escalation visibility appears in cockpit and communication records.
9. Failure modes and controls:
	- Job retries on next schedule for unresolved events.
10. Evidence and QA checks:
	- Confirm escalation status and additional log entries.

### 16.11 Process P11: Closed-Loop and Clinical Documentation Validation

1. Purpose:
	- Block closure until communication and documentation obligations are met.
2. Trigger:
	- Update attempting closure state.
3. Actors and permissions:
	- Any user attempting status transition.
4. Required inputs and data contracts:
	- Acknowledged_Communication_Count__c greater than zero.
	- Mandatory clinical fields complete.
5. Step-by-step runtime flow:
	- Validation rules evaluate record at save.
	- If constraints fail, DML blocked with validation message.
6. Decision logic:
	- All mandatory closure criteria must pass.
7. Data writes and side effects:
	- No write if blocked.
8. Notifications and user experience:
	- User sees explicit validation feedback.
9. Failure modes and controls:
	- Prevents premature or non-compliant closure.
10. Evidence and QA checks:
	- Attempt closure without acknowledgement and confirm block.

### 16.12 Process P12: Observation Translation Preparation

1. Purpose:
	- Set translation preconditions before persistence.
2. Trigger:
	- CareObservation before-save flow entry.
3. Actors and permissions:
	- Flow runtime under record context.
4. Required inputs and data contracts:
	- Observation language and translation status fields.
5. Step-by-step runtime flow:
	- Flow evaluates whether translation should run.
	- Flow writes preparation flags and status values.
6. Decision logic:
	- Branches by source language, status, and field completeness.
7. Data writes and side effects:
	- Prep field values updated inline.
8. Notifications and user experience:
	- User sees status progression after save.
9. Failure modes and controls:
	- Flow entry conditions prevent unnecessary translation calls.
10. Evidence and QA checks:
	- Confirm prep fields update on qualifying records.

### 16.13 Process P13: Observation Auto-Translate Invocation

1. Purpose:
	- Produce draft translation output post-save.
2. Trigger:
	- CareObservation after-save flow path.
3. Actors and permissions:
	- Flow and invocable Apex action.
4. Required inputs and data contracts:
	- Observation Id.
	- Source text fields.
5. Step-by-step runtime flow:
	- Flow invokes auto-translate action.
	- Action resolves source payload and writes translated content.
	- Translation status moved to translated or equivalent state.
6. Decision logic:
	- Skip path for non-qualifying records.
7. Data writes and side effects:
	- Draft translated fields and status fields updated.
8. Notifications and user experience:
	- Observation displays generated translation text.
9. Failure modes and controls:
	- Action error handling keeps record consistent and auditable.
10. Evidence and QA checks:
	- Confirm translated fields and status transition after save.

### 16.14 Process P14: Reviewer-Only Final Translation Approval

1. Purpose:
	- Enforce clinical governance on final Reviewed status.
2. Trigger:
	- Update attempt to Reviewed.
3. Actors and permissions:
	- Clinical Reviewer or non-reviewer user.
4. Required inputs and data contracts:
	- Reviewer permission and record eligibility.
5. Step-by-step runtime flow:
	- Validation checks persona capability.
	- Unauthorized update blocked.
	- Authorized reviewer update accepted.
6. Decision logic:
	- Role-based gate at save time.
7. Data writes and side effects:
	- Reviewed status written only for authorized users.
8. Notifications and user experience:
	- Non-reviewer receives immediate validation error.
9. Failure modes and controls:
	- Prevents accidental clinical approval by operational users.
10. Evidence and QA checks:
	- Test with non-reviewer and reviewer accounts.

### 16.15 Process P15: Manager Cockpit KPI Aggregation and Exception Panels

1. Purpose:
	- Provide operations command center visibility.
2. Trigger:
	- Cockpit load or refresh.
3. Actors and permissions:
	- Operations Lead.
4. Required inputs and data contracts:
	- Shift, incident, translation, and case datasets.
5. Step-by-step runtime flow:
	- Apex aggregates KPI counts.
	- Apex fetches exception records.
	- LWC renders widgets and drill-down tables.
6. Decision logic:
	- Filters by pending or unfilled shift status and breach conditions.
7. Data writes and side effects:
	- Read-heavy path with optional edits handled by separate actions.
8. Notifications and user experience:
	- Real-time triage dashboard for daily command operations.
9. Failure modes and controls:
	- Missing object access causes partial dashboard load.
10. Evidence and QA checks:
	- Compare widget counts with direct SOQL control totals.

### 16.16 Process P16: Manager Cockpit In-Line Save

1. Purpose:
	- Allow fast operational edits without page navigation.
2. Trigger:
	- User edits row and submits save.
3. Actors and permissions:
	- Operations Lead.
4. Required inputs and data contracts:
	- Row Id and editable field payload.
5. Step-by-step runtime flow:
	- LWC sends draft values to Apex.
	- Apex validates allowed fields and applies updates.
	- LWC refreshes data and surfaces save result toast.
6. Decision logic:
	- Invalid or unauthorized field edits rejected.
7. Data writes and side effects:
	- DML update on target object rows.
8. Notifications and user experience:
	- Success or failure feedback is immediate.
9. Failure modes and controls:
	- Field-level security or validation rules can block save.
10. Evidence and QA checks:
	- Confirm persisted values after reload.

### 16.17 Process P17: Phone Override Communication Logging

1. Purpose:
	- Record manual communication interventions for audit.
2. Trigger:
	- Manager selects phone override action.
3. Actors and permissions:
	- Operations Lead.
4. Required inputs and data contracts:
	- Critical event reference.
	- Override note and optional call metadata.
5. Step-by-step runtime flow:
	- Action invokes Apex endpoint.
	- Communication_Log__c created and linked to incident.
6. Decision logic:
	- Required fields validated before insert.
7. Data writes and side effects:
	- New communication log row.
8. Notifications and user experience:
	- Log is visible in incident history.
9. Failure modes and controls:
	- Missing incident reference blocks insert.
10. Evidence and QA checks:
	- Confirm linked log record and timestamp.

### 16.18 Process P18: Operational Alert Case Priority Chart Computation

1. Purpose:
	- Visualize case priority distribution accurately.
2. Trigger:
	- Cockpit case panel load or refresh.
3. Actors and permissions:
	- Operations Lead and authorized users.
4. Required inputs and data contracts:
	- Grouped case counts by Priority for Operational_Alert record type.
5. Step-by-step runtime flow:
	- Apex returns grouped counts.
	- LWC computes normalized widths against max or total strategy.
	- Style string built as valid CSS width declaration.
	- Bars rendered.
6. Decision logic:
	- Empty dataset path renders no bars.
7. Data writes and side effects:
	- Read-only path.
8. Notifications and user experience:
	- Visual triage support for manager decisioning.
9. Failure modes and controls:
	- Incorrect style string leads to uniform full-width bars.
10. Evidence and QA checks:
	- Validate bar percentages against raw grouped counts.

### 16.19 Process P19: Admissions Lead Intake Validation and Routing

1. Purpose:
	- Govern pre-admission lead quality and ownership.
2. Trigger:
	- Lead create or update for Care_Enquiry record type.
3. Actors and permissions:
	- Admissions users and lead assignment automation.
4. Required inputs and data contracts:
	- Funding and care-type required fields.
	- Routing context fields.
5. Step-by-step runtime flow:
	- Validation rules check mandatory data.
	- Trigger invokes assignment service.
	- Service applies owner or queue.
6. Decision logic:
	- Missing mandatory values block save.
7. Data writes and side effects:
	- Lead ownership updates.
8. Notifications and user experience:
	- Admissions users see routed enquiry in assigned queue or owner list.
9. Failure modes and controls:
	- Misconfigured routing inputs may cause fallback owner path.
10. Evidence and QA checks:
	- Confirm owner assignment and validation enforcement.

### 16.20 Process P20: UAT Evidence Capture and Go-Live Gate Execution

1. Purpose:
	- Standardize acceptance proof before release sign-off.
2. Trigger:
	- UAT execution cycle.
3. Actors and permissions:
	- Floor Carer, Clinical Reviewer, Operations Lead, Release Lead.
4. Required inputs and data contracts:
	- Persona test matrix.
	- Seed datasets.
	- Gate script thresholds.
5. Step-by-step runtime flow:
	- Execute scenario steps in recommended order.
	- Capture record ids, screenshots, and outcome codes.
	- Run release gate checks.
	- Resolve fail or blocked outcomes.
	- Collect sign-offs.
6. Decision logic:
	- Release readiness only when gate criteria are all passed or approved exceptions are documented.
7. Data writes and side effects:
	- UAT evidence artifacts and logs.
8. Notifications and user experience:
	- Stakeholder readiness summary for go-live review.
9. Failure modes and controls:
	- Missing evidence or failed hard-stop scenarios block sign-off.
10. Evidence and QA checks:
	- Complete matrix with pass or fail status and linked proof per case.

## 17. End-to-End Control Points and Ownership

1. Shift creation source control:
	- Owner: Operations process owner.
	- Control: Ensure shift fields always provided on Task create.
2. Assignment lifecycle control:
	- Owner: Operations Lead.
	- Control: Pending to Accepted or Unfilled transitions monitored daily.
3. Critical event closure control:
	- Owner: Clinical and operations governance.
	- Control: Closed-loop acknowledgement and mandatory clinical validation rules.
4. Translation approval control:
	- Owner: Clinical Reviewer.
	- Control: Reviewer-only final status gate.
5. Dashboard integrity control:
	- Owner: Operations Lead.
	- Control: KPI and chart count reconciliation against SOQL spot checks.
6. Release control:
	- Owner: Release Lead.
	- Control: Persona UAT matrix and go-live gate pass.

## 18. Recommended Operations Cadence

1. Start of day:
	- Review Pending and Unfilled shifts.
	- Review active critical events and acknowledgement lag.
2. Mid-day:
	- Review at-risk flags and reassignment queue.
	- Confirm translation backlog status.
3. End of day:
	- Reconcile unresolved incidents.
	- Validate communication logs for all severe incidents.
	- Capture unresolved blockers into next-day action list.

## 19. Minimal Troubleshooting Tree

1. Shift not visible:
	- Check Task owner, shift start and end fields, and status.
	- Check user permission set assignment.
2. Assignment email not sent:
	- Check owner has active email.
	- Check trigger path conditions were met.
3. Rejection did not reroute:
	- Check eligible CareOrch_Floor_Carer assignees.
	- Check contacted list and rejection count on task.
4. Incident cannot close:
	- Check acknowledgement count and mandatory clinical fields.
5. Translation status stuck:
	- Check flow entry criteria and invocable action outcome.
6. Cockpit chart looks wrong:
	- Compare grouped counts to normalized width output.

## 20. Epic 9-11 Architectural Alignment

For the approved architecture direction and corrected backlog slices for Admissions Intake, Safeguarding Ratios, and Regulatory and Experience Cloud delivery, use:

1. [docs/careorch-epic9-11-architectural-alignment.md](docs/careorch-epic9-11-architectural-alignment.md)

This document is the source of truth for:
1. Locked design decisions.
2. Corrected slice definitions and dependencies.
3. Build sequence and acceptance tests.


## 17. Addendum: Pending Scope Completion (10.1, 10.2, 11.2)

Date completed: 2026-06-03
Deploy Id: 0AfQ100000RcxcDKAR

### 17.1 Resident Risk Banner (10.1)

Delivered behavior:
1. CareOrch Workspace now renders a resident risk warning banner when either resident risk flag is true:
- Account.CareOrch_Hyper_Aggressive_Behavior__c
- Account.CareOrch_Mobility_Assistance_Required__c
2. Banner content is severity-aware and prioritizes hyper-aggressive behavior messaging.

Implementation references:
1. [force-app/main/default/lwc/careOrchResidentAlertBanner/careOrchResidentAlertBanner.html](force-app/main/default/lwc/careOrchResidentAlertBanner/careOrchResidentAlertBanner.html)
2. [force-app/main/default/lwc/careOrchResidentAlertBanner/careOrchResidentAlertBanner.js](force-app/main/default/lwc/careOrchResidentAlertBanner/careOrchResidentAlertBanner.js)
3. [force-app/main/default/lwc/careOrchCarerWorkspace/careOrchCarerWorkspace.js](force-app/main/default/lwc/careOrchCarerWorkspace/careOrchCarerWorkspace.js)
4. [force-app/main/default/lwc/careOrchCarerWorkspace/careOrchCarerWorkspace.html](force-app/main/default/lwc/careOrchCarerWorkspace/careOrchCarerWorkspace.html)

### 17.2 Dietary Broadcast to Resident Account (10.2)

Delivered behavior:
1. Added resident-side dietary field on Account:
- Account.CareOrch_Dietary_Needs__c
2. On care enquiry conversion transition, dietary details are synchronized from Lead to converted Account in trigger-service runtime.

Implementation references:
1. [force-app/main/default/objects/Account/fields/CareOrch_Dietary_Needs__c.field-meta.xml](force-app/main/default/objects/Account/fields/CareOrch_Dietary_Needs__c.field-meta.xml)
2. [force-app/main/default/triggers/CareOrchLeadAssignmentTrigger.trigger](force-app/main/default/triggers/CareOrchLeadAssignmentTrigger.trigger)
3. [force-app/main/default/classes/CareOrchLeadAssignmentService.cls](force-app/main/default/classes/CareOrchLeadAssignmentService.cls)
4. [force-app/main/default/classes/CareOrchLeadAssignmentServiceTest.cls](force-app/main/default/classes/CareOrchLeadAssignmentServiceTest.cls)

### 17.3 Activity Log Foundation (11.2 Baseline)

Delivered behavior:
1. New object deployed: CareOrch_Activity_Log__c (ControlledByParent to resident Account via master-detail).
2. Core fields deployed for activity type, timestamp, notes, and visibility partition marker.
3. Tab deployed and surfaced in CareOrch permission sets.

Implementation references:
1. [force-app/main/default/objects/CareOrch_Activity_Log__c/CareOrch_Activity_Log__c.object-meta.xml](force-app/main/default/objects/CareOrch_Activity_Log__c/CareOrch_Activity_Log__c.object-meta.xml)
2. [force-app/main/default/objects/CareOrch_Activity_Log__c/fields/Resident_Account__c.field-meta.xml](force-app/main/default/objects/CareOrch_Activity_Log__c/fields/Resident_Account__c.field-meta.xml)
3. [force-app/main/default/objects/CareOrch_Activity_Log__c/fields/CareOrch_Activity_Type__c.field-meta.xml](force-app/main/default/objects/CareOrch_Activity_Log__c/fields/CareOrch_Activity_Type__c.field-meta.xml)
4. [force-app/main/default/objects/CareOrch_Activity_Log__c/fields/CareOrch_Activity_Date_Time__c.field-meta.xml](force-app/main/default/objects/CareOrch_Activity_Log__c/fields/CareOrch_Activity_Date_Time__c.field-meta.xml)
5. [force-app/main/default/objects/CareOrch_Activity_Log__c/fields/CareOrch_Activity_Notes__c.field-meta.xml](force-app/main/default/objects/CareOrch_Activity_Log__c/fields/CareOrch_Activity_Notes__c.field-meta.xml)
6. [force-app/main/default/objects/CareOrch_Activity_Log__c/fields/CareOrch_Visibility_Scope__c.field-meta.xml](force-app/main/default/objects/CareOrch_Activity_Log__c/fields/CareOrch_Visibility_Scope__c.field-meta.xml)
7. [force-app/main/default/tabs/CareOrch_Activity_Log__c.tab-meta.xml](force-app/main/default/tabs/CareOrch_Activity_Log__c.tab-meta.xml)

### 17.4 Validation Snapshot

1. Deploy success:
- 0AfQ100000RcxcDKAR
2. Focused regression tests:
- Test Run Id: 707Q100000o345a
- Result: 10/10 passed
- Classes: CareOrchLeadAssignmentServiceTest, CareOrchResidentProfileTest

### 17.5 Remaining Platform Scaffold Items

1. Experience Cloud audience partitioning metadata is not yet committed in this repository because no existing experiences baseline is present under force-app/main/default/experiences.
2. Report and dashboard folder metadata is also not yet established in this repository baseline and should be introduced as a dedicated metadata slice once report folder conventions are approved.
