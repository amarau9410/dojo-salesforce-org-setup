# CareOrch UAT Persona Map

Date: 2026-06-03
Target Org: careorchdev

## 1. Purpose

This UAT map defines persona-based journeys, permission requirements, exact tester actions, option selections, pass/fail rules, and release sign-off requirements for CareOrch.

## 2. Personas

1. Floor Carer
- Primary focus: shift execution, incident logging, and observation capture.
- Main access: Workspace, Shift Inbox, My Calendar, incident logger entry points.

2. Clinical Reviewer
- Primary focus: translation validation and observation quality outcomes.
- Main access: CareObservation workflows and translation review actions.

3. Operations Lead
- Primary focus: manager cockpit intervention, SLA governance, trend/report checks.
- Main access: Manager Cockpit, dashboards/reports, SLA threshold governance object.

4. Salesforce Admin / Release Lead
- Primary focus: control verification, deployment safety, go-live gate evidence.
- Main access: setup, validation rules, flow status, script execution, test run results.

## 3. Permission and Access Matrix

Use named users per persona and assign permission sets exactly as below before running UAT.

| Persona | Required Permission Sets | Key Tabs to Verify | Key Object Access Needed |
|---|---|---|---|
| Floor Carer | CareOrch_Floor_Carer | CareOrch Workspace, CareOrch Shift Inbox, CareOrch My Calendar | Task (read/edit own shift records), Critical_Event__c (create/edit), Communication_Log__c (create), CareObservation (create/edit) |
| Clinical Reviewer | CareOrch_Clinical_Workspace | CareObservation views, optional cockpit access if enabled as Available | CareObservation (read/edit), Critical_Event__c (read/edit as reviewer scope), Communication_Log__c (read/edit) |
| Operations Lead | CareOrch_Operations_Lead | Manager Cockpit, Reports, Dashboards | Critical_Event__c, Task, CareObservation, Communication_Log__c, CareOrch_SLA_Threshold__c (full governance CRUD) |
| Release Lead (Admin) | System Administrator profile or equivalent + optional CareOrch_Operations_Lead | Setup, Manager Cockpit, Reports, Dashboards | Full validation/flow visibility, test execution, script execution |

### 3.1 Permission Assignment Checklist

1. Confirm persona users are Active.
2. Assign permission sets in Setup -> Permission Set Assignments.
3. Verify tab visibility in App Launcher (Visible or Available).
4. Run smoke checks:
- Floor Carer can open Shift Inbox.
- Clinical Reviewer can edit translation-related fields except restricted reviewed status where applicable.
- Operations Lead can open Manager Cockpit and edit SLA threshold records.
- Release Lead can access validation rules and run scripts/tests.

## 4. UAT Execution Rules

1. Use fresh test data for each run or reset records between runs.
2. Capture evidence for every test case:
- screenshot or export
- record Ids
- timestamp
- actor user
3. Record the exact selected values/options used in each step.
4. Log failures with severity and impacted area.
5. A failed hard-stop control is a release blocker.

### 4.1 Pass/Fail Decision Rules (Per Test Case)

Mark a test case Pass only when all are true:

1. Preconditions were satisfied.
2. Tester executed required option selections exactly.
3. Expected data state is present on the record.
4. Required evidence artifacts are attached.

Mark a test case Fail if any are true:

1. Expected status/field values did not update.
2. Expected validation block did not trigger.
3. Unexpected error occurred for a valid scenario.
4. Evidence is missing or does not prove behavior.

### 4.2 Defect Severity Rules

1. Critical: hard-stop control broken (example: RL-01, RL-02 bypassed).
2. High: critical-path persona journey blocked.
3. Medium: non-blocking functional defect with workaround.
4. Low: cosmetic or minor wording/format issue.

### 4.3 UAT Result Codes

1. Pass
2. Fail
3. Blocked (environment/data dependency)
4. Not Run

Use these exact codes in the execution log.

## 5. Persona Test Map (Detailed Execution)

Each case below includes exact selections and verification points.

## 5.1 Floor Carer Cases

| UAT ID | Journey | Preconditions | Exact Steps and Selections | Expected Result | Pass/Fail Checks | Evidence |
|---|---|---|---|---|---|---|
| FC-01 | View assigned shifts | Carer has CareOrch_Floor_Carer and >=1 shift task | Open App "CareOrch" -> select tab "CareOrch Shift Inbox" -> click Refresh | Assigned rows visible with Start/End/Patient/Status | Pass if at least 1 expected shift appears and fields match source Task; Fail if no data with valid preconditions | Grid screenshot, task Id list |
| FC-02 | Accept shift from email link | Pending shift assigned to carer and assignment email sent | Open assignment email -> click Accept link (action=accept) | Shift status becomes Accepted and manager notification path is triggered | Pass if Task.CareOrch_Shift_Status__c = Accepted and filled timestamps/metrics updated; Fail if status unchanged | Email screenshot, before/after task fields |
| FC-03 | Reject shift and auto-reroute | Pending shift assigned to carer | Open assignment email -> click Reject link (action=reject) | Shift rerouted to next eligible caregiver and counters increment | Pass if owner changes and contacted/rejected counters increase; Fail if no reroute despite eligible caregiver | Before/after owner, counters, status |
| FC-04 | At-risk detection visibility | Shift has repeated rejections/high streak | Repeat reject flow to cross threshold | At-risk flag and reason are populated | Pass if CareOrch_At_Risk__c=true and reason not blank; Fail if threshold crossed without at-risk update | Task field screenshot with reason |
| FC-05 | Incident logging with context | Active shift linked to resident account exists | Open incident logger -> select taxonomy "Serious Injury" or supported value -> submit with geo coordinates | Critical event created with resident, shift context, location | Pass if Critical_Event__c has Active_Shift_Context__c and Incident_Location fields populated; Fail if record missing context | New critical event screenshot + field dump |
| FC-06 | Observation authoring | Carer can create CareObservation | Create CareObservation with Original_Language non-English and Original_Observation populated | Translation path moves to Pending/Auto-translated per flow timing | Pass if translation lifecycle fields move as designed; Fail if no status progression | CareObservation before/after values |
| FC-07 | Nutritional intake logging | Carer has access to CareOrch Workspace and resident context | Open CareOrch Workspace -> click Log Nutritional Intake -> enter Resident Account Id, Meal Period, Consumption Level and notes -> click Save Nutritional Log | CareObservation is created with food-intake metric and nutritional fields populated | Pass if record is created and includes Metric_Type__c, Meal_Period__c, CareOrch_Consumption_Level__c, Food_Record__c; Fail if create fails or fields are blank | Modal screenshot + created CareObservation Id and field dump |
| FC-08 | Nutritional immutability enforcement | Nutritional log created in FC-07 | Open created CareObservation -> attempt edit of Meal_Period__c, CareOrch_Consumption_Level__c, or Food_Record__c -> Save | Save is blocked by immutability validation rule | Pass if save is blocked with nutritional immutability error; Fail if update succeeds | Error screenshot + attempted field values |

## 5.2 Clinical Reviewer Cases

| UAT ID | Journey | Preconditions | Exact Steps and Selections | Expected Result | Pass/Fail Checks | Evidence |
|---|---|---|---|---|---|---|
| CR-01 | Pending translation queue | Observation has Translation_Status__c=Pending and no English translation | Wait for after-save automation or trigger update to rerun flow | Record transitions to Auto-translated and draft flag true | Pass if Translation_Status__c=Auto-translated and Draft_Unverified_Translation__c=true; Fail otherwise | Before/after observation screenshots |
| CR-02 | Translation edit and handoff | Auto-translated record exists | Edit Auto_Translated_Notes__c and allowed status fields | Permitted edits save successfully | Pass if update commits and field history shows change; Fail on valid edit error | Field history screenshot |
| CR-03 | Reviewed-status gate | Reviewer is non-admin | Attempt set Translation_Status__c = Reviewed | Validation block appears | Pass if save is blocked with expected validation message; Fail if reviewer can set Reviewed | Error dialog screenshot |
| CR-04 | Medication refused follow-up | eMAR signal payload with signalType=Medication Refused ingested | Verify resulting CareObservation and linked follow-up records | ActionPlan and ActionPlanItem records are created | Pass if ActionPlan + items + tasks exist; Fail if any chain object missing | ActionPlan Id, item/task list screenshot |
| CR-05 | Nutritional log review visibility | Nutritional logs exist from FC-07 | Open created nutritional CareObservation records in reviewer context | Reviewer can view nutritional details while immutable fields remain protected from post-create edits | Pass if reviewer can read nutritional fields and edit attempt is blocked consistently; Fail if record not visible or immutability inconsistent | Reviewer screenshot + field-level evidence |

## 5.3 Operations Lead Cases

| UAT ID | Journey | Preconditions | Exact Steps and Selections | Expected Result | Pass/Fail Checks | Evidence |
|---|---|---|---|---|---|---|
| OL-01 | Cockpit KPI snapshot | Data exists for critical/shifts/translations | Open "Manager Cockpit" tab | 4 widgets and trend render in one page | Pass if all widgets load and no error toast; Fail on broken load | Cockpit screenshot |
| OL-02 | Critical breach drill-down | Breach data present | Click widget "Critical SLA Breaches" -> click Open on row | Panel shows actionable breach rows and detail nav works | Pass if row list appears and record opens; Fail if panel empty with known breaches | Panel + record screenshot |
| OL-03 | Shift corrective action | At-risk shift exists | In shifts panel click Reassign -> select caregiver option -> enter manager note -> Confirm Reassignment | Owner changes, status set Pending, note appended | Pass if owner/status/comment updated; Fail if action toasts success but data unchanged | Before/after task fields |
| OL-04 | In-line save | Editable rows present | Edit status/risk/translation fields directly in grid -> Save | Updates persist and refresh shows committed values | Pass if values persist after refresh; Fail if rollback/no persistence | Save toast + refreshed values |
| OL-05 | Phone override logging | Critical event row exists | Click "Log Phone Override" | Communication_Log__c created for event | Pass if new communication log linked to event exists; Fail if no log | Log record screenshot |
| OL-06 | SLA threshold governance | Operations lead has object access | Open CareOrch_SLA_Threshold__c records -> set Event_Category__c values Death and DEFAULT -> set Threshold_Minutes__c to test values -> Save | Threshold changes influence breach computation and cockpit SLA minutes | Pass if cockpit shows updated SLA minute logic after refresh; Fail if unchanged | Threshold records + cockpit values |

## 5.4 Release Lead Cases

| UAT ID | Journey | Preconditions | Exact Steps and Selections | Expected Result | Pass/Fail Checks | Evidence |
|---|---|---|---|---|---|---|
| RL-01 | Golden Rule enforcement | Critical event with zero acknowledged communication logs | Edit event -> set Status__c = Closed -> Save | Save blocked by closed-loop validation rule | Pass if blocked with validation error; Fail if close is allowed | Error screenshot + event Id |
| RL-02 | Clinical close gate | Death/Serious category event missing required clinical fields | Set Status__c = Pending Review or Closed -> Save | Save blocked by mandatory clinical doc validation | Pass if blocked; Fail if status change succeeds | Error screenshot + event Id |
| RL-03 | Escalation automation | Event remains unacknowledged beyond SLA | Invoke/await escalation job window | Secondary dispatch logged and manager notified | Pass if comm log count increments and status/routing behavior occurs; Fail otherwise | Comm log timeline + manager mail evidence |
| RL-04 | Go-live gate automation | Prepare journey, activation, defect CSV files | Run script scripts/careorch_go_live_gate.ps1 with all 3 inputs | Exit code 0 only when thresholds met | Pass if output and exit code align with input data; Fail if incorrect pass/fail decision | Terminal output + archived CSVs |

## 6. Coverage Matrix (Plan AC to UAT)

| Delivery Plan Area | Acceptance Criterion | UAT IDs |
|---|---|---|
| Week 2 Critical Event Workflow | Critical incident creates communication audit entries | FC-05, RL-03 |
| Week 2 Critical Event Workflow | Acknowledgement state and escalation behavior | RL-03 |
| Week 2 Critical Event Workflow | Hard-stop close without acknowledged comms is blocked | RL-01 |
| Week 3 Shift Reliability | Shift metrics and routing are tracked | FC-01, FC-02, FC-03, FC-04 |
| Week 4 Translation Quality | Translation queue/review lifecycle works | FC-06, CR-01, CR-02, CR-03 |
| Epic 11 Nutritional Logging | Mobile nutritional capture and immutable audit behavior | FC-07, FC-08, CR-05 |
| Week 5 Cockpit | Cockpit widgets and drill-down actions function | OL-01, OL-02, OL-03, OL-04, OL-05 |
| Week 6 UAT/Hardening | Go-live checks enforce quality/adoption/defect gates | RL-04 |

## 7. Entry and Exit Criteria

### Entry

1. Required permission sets assigned and verified per Section 3.
2. Test dataset loaded for shifts, incidents, observations.
3. Translation queue and action plan template active.
4. Flows and validation rules active in target org.
5. UAT execution log template prepared with result codes.

### Exit

1. Critical-path pass rate >= 95%.
2. Zero open High/Critical defects in protected areas.
3. No failures in RL-01 and RL-02 hard-stop controls.
4. Go-live gate script passes with evidence.
5. Sign-off by operations lead and clinical lead.

## 8. How Testers Record Pass and Fail

For every UAT ID, log these fields:

1. UAT ID
2. Tester persona and username
3. Build/version timestamp
4. Selected options/values used
5. Actual result summary
6. Result code: Pass, Fail, Blocked, Not Run
7. Defect Id if Fail
8. Evidence link(s)

Use one row per test execution attempt. If a failed case is re-run after fix, create a new row and keep both records.

## 9. UAT Evidence Pack Structure

Store evidence under a timestamped release folder with:

1. Test execution log by UAT ID.
2. Screenshot folder grouped by persona.
3. CSV exports used by go-live gate:
- journey summary
- activation audit
- defect export
4. Summary memo with blockers, waivers (if any), and approval decisions.

## 10. Suggested Test Users

1. One Floor Carer user.
2. One Clinical Reviewer user.
3. One Operations Lead user.
4. One System Administrator user for control verification and negative tests.

## 11. Related Artifacts

1. [docs/careorch-standout-6-week-delivery-plan.md](docs/careorch-standout-6-week-delivery-plan.md)
2. [docs/careorch-solution-design-deep-dive.md](docs/careorch-solution-design-deep-dive.md)
3. [scripts/careorch_go_live_gate.ps1](scripts/careorch_go_live_gate.ps1)
4. [scripts/careorch_go_live_gate_README.md](scripts/careorch_go_live_gate_README.md)

## 12. Latest Validation Snapshot (careorchdev)

1. Deployment references for latest nutritional logging slice:
	- 0AfQ100000RcvKIKAZ
	- 0AfQ100000Rcw6fKAB
2. Focused regression test run:
	- Class: CareOrchResidentProfileTest
	- Test Run Id: 707Q100000o2qFq
	- Result: 7/7 passed

## 13. Addendum: Pending Scope Completion (10.1, 10.2, 11.2)

Date completed: 2026-06-03
Deploy Id: 0AfQ100000RcxcDKAR

### 13.1 New UAT Cases Added

Floor Carer:
1. FC-09 Resident risk banner visibility
- Open resident-scoped CareOrch Workspace with risk flags.
- Verify warning banner appears for hyper-aggressive or mobility assistance flags.
- Pass when banner appears only when a flag is true and message matches risk context.

Operations Lead:
1. OL-07 Dietary copy verification after care enquiry conversion
- Convert Care_Enquiry lead with dietary details.
- Verify Account.CareOrch_Dietary_Needs__c equals lead dietary text.
- Pass when copy occurs on conversion transition.

2. OL-08 Activity log object baseline validation
- Open CareOrch Activity Log tab.
- Create one activity log linked to a resident account.
- Verify required fields enforce type/date-time/visibility and record persists.
- Pass when create/read/edit works with assigned permission set.

### 13.2 Updated Access Validation Points

1. CareOrch_Floor_Carer now includes object access to CareOrch_Activity_Log__c and tab availability.
2. CareOrch_Clinical_Workspace now includes object access to CareOrch_Activity_Log__c and tab availability.
3. CareOrch_Operations_Lead now includes full access to CareOrch_Activity_Log__c and tab visibility.
4. Account dietary field visibility added in all three CareOrch role permission sets.

### 13.3 Verification Snapshot

1. Focused test run id: 707Q100000o345a
2. Result: 10/10 passed
3. Classes: CareOrchLeadAssignmentServiceTest, CareOrchResidentProfileTest
