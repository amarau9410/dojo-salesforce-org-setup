# CareOrch Caregiver and Lead Training Guide

Date: 2026-06-03
Target Org: careorchdev
Audience: Floor Carer, Operations Lead, and Release Lead users

## 1. Purpose

This guide teaches caregivers how to use CareOrch end to end during a real shift lifecycle.

It is based on the UAT persona map and focuses on:
- what a caregiver does directly
- what handoffs happen to other personas
- what to do when controls block progression

## 2. Roles and Handoffs

Primary caregiver role in app:
- Floor Carer (CareOrch_Floor_Carer)

Related persona handoffs:
- Clinical Reviewer: handles translation quality and reviewed-status controls.
- Operations Lead: handles shift risk intervention, communication override, and governance decisions.
- Release Lead/Admin: handles policy controls and hard-stop verification.

Role authority note:
- Shift assignment and reassignment is an Operations Lead responsibility via Manager Cockpit.
- Floor Carers respond to assigned shifts (accept or reject) but do not perform assignment.
- Clinical Reviewers do not assign shifts.

## 3. Access Checklist Before Training

1. Confirm user is Active.
2. Confirm permission set CareOrch_Floor_Carer is assigned.
3. Open App Launcher and launch CareOrch Console.
4. Confirm these tabs are available:
- CareOrch Workspace
- CareOrch Shift Inbox
- CareOrch My Calendar
- CareOrch Incident Logger
- Critical Event
- Communication Log

If any tab is missing, use nav personalization (pencil icon) to add it.

## 3.1 Lead Access Segregation Control

Policy:
1. Caregiver personas must not process or convert leads.
2. Lead access is restricted to admissions permission sets only:
- CareOrch_Admissions_Admin
- CareOrch_Admissions_Manager

Do not assign admissions permission sets to users holding caregiver personas:
1. CareOrch_Floor_Carer
2. CareOrch_Clinical_Workspace
3. CareOrch_Operations_Lead

Verification command:
1. Run `scripts/careorch_verify_lead_access.ps1`.
2. Expected result is `PASS: No caregiver persona user has admissions lead-processing permission sets.`

## 4. Caregiver End-to-End Lifecycle

## 4.1 Start of Shift

Goal:
- Confirm assigned work and readiness.

Steps:
1. Open CareOrch Console.
2. Open CareOrch Shift Inbox.
3. Click Refresh.
4. Validate your assigned shift rows:
- Shift
- Patient
- Status
- Start
- End
- Contacted / Rejected counts
- At Risk and Risk Reason

Expected outcome:
- You can see your current shifts and their status context.

If something is wrong:
- No shifts shown: contact Operations Lead to validate assignment.
- Wrong patient or timing: do not proceed; raise to Operations Lead.

## 4.2 Shift Response (Accept or Reject)

Goal:
- Confirm assignment response is recorded promptly.

Accept path:
1. Open assignment email.
2. Click Accept link.
3. Return to Shift Inbox and Refresh.
4. Verify shift status is Accepted.

Reject path:
1. Open assignment email.
2. Click Reject link.
3. Return to Shift Inbox and Refresh.
4. Verify owner/status/counters changed based on routing.

Expected outcome:
- Accept updates shift progression metrics.
- Reject triggers rerouting logic and updates counters.

Caregiver rule:
- Only reject when genuinely unavailable; repeated rejection can mark shift as At Risk.

## 4.3 Monitor At-Risk Signals

Goal:
- Identify when staffing reliability risk is rising.

Steps:
1. In Shift Inbox, monitor At Risk and Risk Reason columns.
2. If At Risk becomes true, immediately notify Operations Lead.

Expected outcome:
- At-risk shifts are visible and escalated early.

Caregiver handoff:
- Operations Lead decides corrective reassignment and mitigation actions.

## 4.4 Log a Critical Incident

Goal:
- Capture incident with enough context for closed-loop response.

Steps:
1. Open CareOrch Incident Logger tab.
2. Wait for context load (active shift and location capture).
3. Select incident taxonomy:
- Fall
- Medication Error
- Serious Injury
4. Submit incident.

Expected outcome:
- A Critical Event record is created with:
- resident context
- active shift context
- incident location (when available)

Important controls:
- Incident logging requires active shift + resident context.
- If no active shift is found, start/verify shift context first.

What happens next automatically:
- Communication dispatch and escalation workflow starts in background.

## 4.5 Document Observations (Clinical Notes)

Goal:
- Record observations clearly and support translation quality.

Steps:
1. Open CareObservation workflow entry point.
2. Create observation with required fields.
3. If not English, populate Original Language and Original Observation.
4. Save.

Expected outcome:
- Translation lifecycle progresses (Pending or Auto-translated based on flow logic).

Caregiver boundaries:
- Enter accurate clinical content.
- Do not force reviewer-only outcomes.

Handoff:
- Clinical Reviewer validates and finalizes translation quality.

## 4.5.1 Log Nutritional Intake (E11-R1)

Goal:
- Capture meal completion and refusal context in under three clicks from workspace.

Steps:
1. Open CareOrch Workspace.
2. Click Log Nutritional Intake.
3. Enter:
- Resident Account Id
- Meal Period
- Consumption Level
- Refusal or food record notes (optional)
4. Click Save Nutritional Log.

Expected outcome:
- Nutritional CareObservation is created with food-intake metric and nutritional fields.
- Entry is immutable after create for audit consistency.

If blocked:
1. Validate Resident Account Id is correct.
2. Confirm caregiver has required permission set assignment.
3. Escalate to Operations Lead if save errors persist.

## 4.6 During Shift: Track Communication and Follow-up

Goal:
- Ensure incident follow-up has an auditable trail.

Steps:
1. Open Communication Log tab for incident-related entries.
2. Verify communication attempts exist for critical incidents you logged.
3. If you detect missing communication evidence for active critical incidents, notify Operations Lead immediately.

Expected outcome:
- Communication trail exists and is reviewable.

## 4.7 End of Shift Handover

Goal:
- Leave clear and actionable status for next caregiver/manager.

Steps:
1. Return to CareOrch Workspace and Shift Inbox.
2. Ensure in-flight tasks are completed or clearly left with correct status.
3. Confirm critical incidents are logged and linked context is correct.
4. Confirm observations entered during shift are saved.
5. Add handover comments where required by workflow.

Expected outcome:
- Next shift can continue safely with complete operational context.

## 5. Console Usage Guidance (Tabs and Subtabs)

Use CareOrch Console for training and live operations.

Tips:
1. Keep Shift Inbox pinned as your main workspace tab.
2. Open each resident/task/incident record from the list; it opens as a subtab.
3. Keep Incident Logger and Communication Log open as adjacent workspace tabs for faster response.

## 6. Common Errors and What to Do

No active shift found in incident logger:
1. Verify you are on an active shift.
2. Refresh Shift Inbox.
3. If still blocked, contact Operations Lead.

Cannot set reviewed translation state:
1. This is expected for caregiver persona.
2. Route to Clinical Reviewer.

Cannot close incident due to communication rule:
1. This is expected control behavior.
2. Ensure communication acknowledgement evidence exists.
3. Coordinate with Operations Lead.

App tab missing:
1. Use app nav pencil icon to add tab.
2. If unavailable in list, request permission/tab visibility review.

## 7. Daily Caregiver Checklist

At shift start:
1. Open CareOrch Console.
2. Refresh Shift Inbox.
3. Confirm assignment and patient context.

During shift:
1. Update tasks.
2. Log incidents immediately when they happen.
3. Capture observations with complete detail.
4. Watch At Risk indicators and escalate quickly.

At shift end:
1. Confirm all key updates saved.
2. Confirm incidents and communication trail are present.
3. Leave clear handover status.

## 8. Caregiver Trainer Validation Script (Classroom Use)

Use this quick script in supervised training:
1. Trainee opens Shift Inbox and identifies one active shift.
2. Trainee logs one incident using Incident Logger.
3. Trainer validates Critical Event created with shift context.
4. Trainee creates one non-English observation.
5. Trainer validates translation lifecycle progression.
6. Trainee reviews communication logs for the incident.
7. Trainee summarizes handover actions.

Pass criteria:
- Trainee can complete all steps without policy violations.
- Required records are created with expected context.
- Handoffs to Clinical Reviewer and Operations Lead are correctly identified.

## 8.1 Mobile Test Day (iPhone and Android)

Use this section to validate caregiver readiness on real mobile devices.

Mobile app note:
- For caregiver mobile testing, use the CareOrch app experience in Salesforce mobile.
- Use CareOrch Console primarily for desktop console/subtab workflows.

Pre-test setup:
1. Confirm caregiver test user has CareOrch_Floor_Carer.
2. Confirm mobile device has Salesforce app installed and updated.
3. Log in to careorchdev with caregiver test user.
4. Ensure test data exists for FC-01 to FC-08 scenarios.

### iPhone Steps (Salesforce iOS App)

1. Open Salesforce app.
2. Tap menu icon and select CareOrch app.
3. Tap Edit Navigation.
4. Add and order tabs:
- CareOrch Shift Inbox
- CareOrch Incident Logger
- CareOrch Workspace
- CareOrch My Calendar
- Critical Event
- Communication Log
5. Tap Done.
6. Run FC-01 to FC-08 in order:
- FC-01: refresh Shift Inbox and verify assigned rows.
- FC-02: use Accept link from assignment email and verify status in app.
- FC-03: use Reject link and verify reroute counters/status.
- FC-04: verify At Risk indicator behavior when threshold conditions are met.
- FC-05: log incident via Incident Logger and verify Critical Event creation.
- FC-06: create non-English observation and verify translation lifecycle progression.
- FC-07: create nutritional log from workspace modal and verify CareObservation fields.
- FC-08: attempt post-create edit on nutritional fields and verify immutability block.

### Android Steps (Salesforce Android App)

1. Open Salesforce app.
2. Open app switcher and select CareOrch.
3. Open Navigation Menu and tap Edit.
4. Add and order tabs:
- CareOrch Shift Inbox
- CareOrch Incident Logger
- CareOrch Workspace
- CareOrch My Calendar
- Critical Event
- Communication Log
5. Save navigation changes.
6. Run FC-01 to FC-08 in order using same validation points as iPhone.

### Mobile Connectivity and Offline Check

1. Start with device online.
2. In CareOrch Workspace, complete one task action.
3. Switch device to airplane mode.
4. Perform one more caregiver action allowed by UI flow.
5. Re-enable network.
6. Verify queued updates sync and final record state is correct.

Expected outcome:
- No data loss.
- Queued actions reconcile when network returns.

### Mobile Test Pass Criteria

1. Caregiver can find all required tabs on both iPhone and Android.
2. FC-01 to FC-08 complete with expected outcomes.
3. Incident logging succeeds with correct context.
4. Observation flow works and translation lifecycle transitions are visible.
5. Nutritional entries save successfully and reject post-create edits.
6. Offline/online transition does not break caregiver task completion flow.

### Mobile Evidence Checklist

Capture for each device type and each FC scenario:
1. Device type and OS version.
2. App version.
3. Screenshot of tab navigation setup.
4. Screenshot/video of each scenario result.
5. Record IDs created/updated.
6. Timestamp and tester username.
7. Result code: Pass, Fail, Blocked, Not Run.

## 8.2 Nutritional Logging Trainer Script Add-On

Use this mini script after standard caregiver walkthrough:
1. Trainee opens CareOrch Workspace.
2. Trainee creates one nutritional log (meal + consumption + note).
3. Trainer verifies created CareObservation fields are populated.
4. Trainee attempts to edit nutritional fields on created record.
5. Trainer verifies immutability validation block appears.

Pass criteria:
- Trainee can create nutritional entry correctly.
- Trainee understands immutability control and when to escalate corrections.

## 9. Operations Lead Training (Manager Track)

## 9.1 Access Checklist

1. Confirm permission set CareOrch_Operations_Lead is assigned.
2. Open App Launcher and launch CareOrch Console.
3. Confirm these tabs are visible:
- careOrchManagerCockpit
- standard-Case
- Critical_Event__c
- Communication_Log__c
- Shift_Lifecycle__c
- CareOrch_SLA_Threshold__c
- standard-Report and standard-Dashboard

## 9.1.1 Operational Alert Case Visibility Check

1. Open Case tab.
2. Change list view to Recent.
3. Open one case and verify Record Type is Operational Alert.
4. Confirm these fields are visible on layout:
- CareOrch Alert Source
- CareOrch Severity
- CareOrch Resident Impact
- CareOrch Critical Event

Expected outcome:
- Operations Lead can view and edit Operational Alert records directly from Case tab.

## 9.2 Start-of-Day Monitoring

Goal:
- Identify risk early and prioritize interventions.

Steps:
1. Open Manager Cockpit.
2. Review widgets in this order:
- Critical SLA Breaches
- At-Risk Shifts
- Pending Translation Reviews
- Operational Alert Cases by Priority chart
- Open Risk Aging trend
3. Click into any non-zero widget and open top-priority records.

Expected outcome:
- Manager has a prioritized queue for immediate action.

Chart usage note:
1. Use the Cases by Priority chart to confirm whether Critical or High Operational Alert volume is increasing.
2. If Critical or High bars rise, pivot to Case tab and triage Operational Alert records first.

## 9.3 Shift Risk Intervention

Goal:
- Reduce shift failure risk quickly.

Steps:
1. In cockpit, open at-risk shift rows.
2. Use Reassign action for unstable coverage.
3. Enter manager note with reason and expected next step.
4. Confirm reassignment.
5. Reopen Task record and verify owner and status updates.

Expected outcome:
- Shift ownership and status are corrected and auditable.

## 9.4 Incident Communication Oversight

Goal:
- Ensure critical incidents maintain communication evidence.

Steps:
1. Open critical incident rows from cockpit.
2. Verify linked Communication_Log__c entries exist.
3. Use Log Phone Override where needed.
4. Re-check communication status and acknowledgements.

Expected outcome:
- Communication evidence exists before incident closure attempts.

## 9.5 Operational Alert Triage (New)

Goal:
- Triage and action resident-impacting alerts created from observations or incident escalations.

Steps:
1. Open Case tab and filter to Record Type = Operational Alert.
2. Prioritize cases with Priority High and Status New.
3. Validate required fields:
- Account
- CareOrch Alert Source
- CareOrch Severity
4. If Alert Source = Critical Event, verify CareOrch Critical Event is linked.
5. Assign case owner and update status based on operating procedure.
6. Add summary notes in Description for handoff.

Expected outcome:
- Operational alerts are triaged with complete context and clear ownership.

## 9.6 SLA Threshold Governance

Goal:
- Keep escalation timings aligned with operational policy.

Steps:
1. Open CareOrch_SLA_Threshold__c tab.
2. Review active rows for Death and DEFAULT categories.
3. Update Threshold_Minutes__c only with approved change request.
4. Save and document change reason.
5. Refresh cockpit and verify breach logic reflects new thresholds.

Expected outcome:
- SLA behavior and cockpit breach calculations match governance decisions.

## 9.7 End-of-Day Operations Lead Checklist

1. No unreviewed high-priority breaches without owner.
2. At-risk shifts have mitigation notes or reassignment.
3. Critical incidents have communication logs.
4. Translation backlog is handed off to Clinical Reviewer.
5. Any blockers are escalated to Release Lead/Admin.
6. Operational Alert queue has no unowned High severity cases.

## 10. Release Lead / Admin Training (Control Track)

## 10.1 Access Checklist

1. Confirm System Administrator (or equivalent) access.
2. Confirm visibility to Setup, validation rules, flows, scripts, and reports.
3. Open CareOrch Console and Manager Cockpit for runtime checks.

## 10.2 Control Verification Flow

Goal:
- Validate hard-stop controls before go-live approval.

Steps:
1. Execute RL-01 negative test:
- Attempt closing a critical event with zero acknowledged communication logs.
- Confirm validation block appears.
2. Execute RL-02 negative test:
- Attempt Pending Review or Closed status without required clinical documentation.
- Confirm validation block appears.
3. Execute RL-03 escalation check:
- Validate secondary dispatch and manager notification when no acknowledgement exists past SLA.

Expected outcome:
- Golden Rule and clinical controls cannot be bypassed.

## 10.3 Go-Live Gate Execution

Goal:
- Make evidence-based release decision.

Steps:
1. Prepare required CSVs:
- journey summary
- activation audit
- defect export
2. Run scripts/careorch_go_live_gate.ps1 with all inputs.
3. Capture exit code and terminal output.
4. Store evidence in release folder with timestamp.

Expected outcome:
- Exit code 0 only when quality/adoption/defect thresholds are satisfied.

## 10.4 Release Decision Checklist

1. RL-01 and RL-02 both pass.
2. No open High/Critical defects in protected areas.
3. Critical-path pass rate meets target.
4. Required sign-offs collected from Operations Lead and Clinical Lead.
5. Evidence pack complete and archived.

## 11. Related Documents

1. docs/careorch-uat-persona-map.md
2. docs/careorch-solution-design-deep-dive.md
3. scripts/uat_execution_log_seed.csv
4. scripts/careorch_go_live_gate.ps1
5. scripts/careorch_go_live_gate_README.md

## 10. Addendum: Pending Scope Completion (10.1, 10.2, 11.2)

### 10.1 Resident Risk Banner in Workspace

What caregivers now see:
1. A warning banner at the top of resident-scoped workspace when either risk flag is true.
2. Hyper-aggressive behavior message is prioritized when both flags are true.
3. Mobility assistance message appears when only mobility flag is true.

Caregiver expectation:
1. Read banner before executing care actions.
2. Follow two-carer and de-escalation protocol when aggressive risk is shown.
3. Confirm transfer support checks when mobility assistance warning is shown.

### 10.2 Dietary Information Continuity

What changed:
1. Dietary needs from care enquiry lead conversion now copy to resident account profile.
2. Caregivers and operations can review dietary context directly from resident account context.

Training note:
1. If dietary text appears outdated, escalate to admissions and operations lead for source correction.

### 10.3 Activity Log Baseline (CareOrch Activity Log)

What changed:
1. New CareOrch Activity Log object and tab are available for care activity journaling.
2. Core fields include activity type, activity date-time, notes, and visibility scope.

How to use in training:
1. Create activity log entries linked to the resident account.
2. Keep notes concise and operational.
3. Set visibility scope correctly for internal versus family-facing intent.

### 10.4 Validation Snapshot

1. Deploy Id: 0AfQ100000RcxcDKAR
2. Test Run Id: 707Q100000o345a
3. Result: 10/10 passed
