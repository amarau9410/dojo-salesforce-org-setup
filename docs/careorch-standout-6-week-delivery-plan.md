# CareOrch 6-Week Standout Delivery Plan

Date: 2026-05-28
Target Org: careorchdev
Delivery Model: Permission-set-led, mobile-first, declarative-first

## 1) Objective

Make CareOrch stand out by improving safety, family trust, operational reliability, and measurable oversight.

## 2) Scope Outcomes

- Critical events are communicated to family contacts within agreed SLAs with full audit evidence.
- Shift assignment and escalation are measurable, predictable, and manager-visible.
- Clinical documentation quality is consistent and reviewable.
- Managers get a live oversight cockpit with actionable KPIs.

## 3) Six-Week Plan

### Week 1 - Baseline and Control Design

Goals:
- Establish governance, KPI baseline, and data model finalization for family communication and oversight.

Stories:
- As a manager, I need agreed response SLAs for death and serious health concerns so teams execute consistently.
- As an implementation lead, I need baseline metrics so I can show measurable improvement at Week 6.

Build:
- Confirm policy SLAs:
  - Death notification SLA (for example: 15 minutes)
  - Serious concern notification SLA (for example: 30 minutes)
- Finalize Account model usage:
  - Resident and Family Contact record types
  - Primary family link
  - Notification preferences
- Define KPI dictionary and owners.

Acceptance Criteria:
- SLA policy document signed off by care operations manager.
- KPI dictionary created with formulas and data source fields.
- Data model mappings confirmed for all critical communication fields.

KPIs Baseline Captured:
- Median time-to-notify family
- % notifications within SLA
- Shift fill rate
- Unfilled shift rate
- Observation completeness rate

---

### Week 2 - Critical Event Communication Workflow

Goals:
- Deliver closed-loop communication for death and serious concern incidents.

Stories:
- As a caregiver, I need guided prompts to contact the right family person quickly.
- As a manager, I need proof of who was contacted, when, by channel, and outcome.

Build:
- Add incident communication flow:
  - Trigger from critical event status/flag
  - Resolve primary family contact and fallback contact
  - Capture channel used, attempt time, outcome, and acknowledgement
- Add manager escalation if acknowledgement not received within SLA threshold.
- Add communication templates for phone script/email/SMS summary notes.

Acceptance Criteria:
- Creating a critical incident creates communication tasks/audit entries.
- Acknowledgement state changes are logged with timestamp and actor.
- Escalation task is auto-created when SLA threshold breaches.
- Hard-stop enforcement: incident status cannot move to Closed unless at least one communication log is acknowledged (system blocks save with validation error).

KPIs:
- SLA compliance % by event type
- Acknowledgement turnaround time
- Escalation rate

---

### Week 3 - Shift Reliability and Escalation Intelligence

Goals:
- Harden shift routing and make failure patterns visible.

Stories:
- As a manager, I need to see which shifts are at risk of not being filled.
- As a caregiver, I need clear assignment context and clean accept/reject outcomes.

Build:
- Extend shift workflow analytics fields and reports:
  - time_to_first_response
  - time_to_fill
  - contact_attempt_count
  - rejection_count
- Add risk indicator rules:
  - high rejection streak
  - repeated unfilled shifts by location/time band
- Add manager alerts for at-risk shifts before unfilled state.

Acceptance Criteria:
- Each shift tracks first response, fill time, attempts, and rejections.
- At-risk shifts appear on manager view before final failure.
- Email escalation includes clear counts and timeline.

KPIs:
- Shift fill rate
- Median time-to-fill
- Rejection rate
- Proactive save rate (at-risk flagged then filled)

---

### Week 4 - Clinical Documentation Quality and Translation Review

Goals:
- Improve care data quality and confidence in multilingual notes.

Stories:
- As a clinical reviewer, I need translation outputs queued for review when required.
- As a manager, I need to measure documentation completeness by team.

Build:
- Add quality gates:
  - Required fields by metric/event type
  - Blocking validation for missing critical values
- Add translation review lifecycle and queue:
  - Pending Translation -> Auto Translated -> Reviewed
- Add reviewer queue list/report with aging.

Acceptance Criteria:
- Required fields enforce on save for defined event types.
- Translation review queue lists all records needing human validation.
- Reviewer action updates status and reviewer timestamp.

KPIs:
- Observation completeness %
- Translation review turnaround time
- % translated records reviewed

---

### Week 5 - Oversight Cockpit and Executive Reporting

Goals:
- Give managers live operational control and leadership-ready reporting.

Stories:
- As an operations manager, I need one cockpit to spot and resolve risk quickly.
- As leadership, I need trend reporting to evidence quality improvement.

Build:
- Manager cockpit page/tab with core widgets:
  - unfilled shifts
  - critical notification SLA breaches
  - pending translation reviews
  - action plans overdue
  - high-risk residents/events
- Weekly trend dashboard and export-ready summary.

Acceptance Criteria:
- Cockpit loads all widgets in one navigation context.
- All widgets drill down to actionable records.
- Weekly trend report can be generated without manual data stitching.

KPIs:
- Breach count trend (week over week)
- Open high-risk items aging
- Mean time to manager intervention

---

### Week 6 - UAT, Adoption, and Hardening

Goals:
- Validate in real workflows, train users, and lock in operating rhythm.

Stories:
- As a caregiver, I need role-specific, low-noise UX so I can execute quickly.
- As a manager, I need confidence that all critical controls are working in production-like use.

Build:
- Role-based UAT scripts:
  - caregiver shift acceptance/rejection
  - family notification with acknowledgement
  - translation review process
  - manager escalation and cockpit actions
- Adoption toolkit:
  - 30-minute role training decks
  - quick-reference guides
  - manager daily checklist
- Production readiness checks and cutover checklist.

Acceptance Criteria:
- UAT pass rate >= 95% on critical-path scenarios.
- Training delivered to all target roles.
- Go-live checklist signed by clinical and operations leads.

KPIs:
- UAT defect density
- First-week adoption (% active users per role)
- Critical incident process compliance %

## 4) KPI Definitions (Operational)

- Time to Notify Family:
  - Event critical timestamp -> first communication attempt timestamp.
- Notification SLA Compliance:
  - count(events within SLA) / count(total critical events).
- Time to Acknowledgement:
  - first communication attempt -> family acknowledgement timestamp.
- Shift Fill Rate:
  - count(filled shifts) / count(total shifts).
- Unfilled Shift Rate:
  - count(unfilled shifts) / count(total shifts).
- Observation Completeness:
  - count(observations meeting required-field set) / count(total observations).
- Translation Review Throughput:
  - count(reviewed translations in period) / count(total translated in period).

## 5) Suggested Artifacts to Add to Repo

- docs/careorch-kpi-dictionary.md
- docs/careorch-critical-event-sla.md
- docs/careorch-manager-cockpit-runbook.md
- docs/careorch-uat-role-scripts.md

## 6) Risks and Mitigations

- Risk: Permission model drift from baseline profile strategy.
  - Mitigation: enforce persona access through permission sets only; monthly access review.
- Risk: Alert fatigue for managers.
  - Mitigation: prioritize severity tiers and suppression windows.
- Risk: Inconsistent family contact data quality.
  - Mitigation: required fields + validation + weekly data hygiene report.
- Risk: Translation trust gap.
  - Mitigation: reviewer queue and explicit reviewed status before downstream reliance.

## 7) Definition of Standout (Success State)

- 90%+ critical notifications within SLA.
- 30% reduction in unfilled shifts.
- 95%+ observation completeness.
- Manager intervention time reduced week over week.
- Family communication audit trail complete for all critical events.
