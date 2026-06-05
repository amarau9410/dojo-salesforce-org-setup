# CareOrch Epic 9-11 Architectural Alignment Baseline

Date: 2026-06-03
Status: Approved Architecture Direction
Scope: Epic 9 (Pre-Admission), Epic 10 (Safeguarding and Ratios), Epic 11 (Regulatory Logging and Family Portal)

## 1. Locked Architectural Decisions

### 1.1 Lead Status Model
Decision:
1. The Care Enquiry Lead process uses the following controlled status path:
   - Inquiry
   - Assessment Scheduled
   - Tour Scheduled
   - Tour Completed
   - Funding Verified
   - Contract Pending
   - Ready to Convert
   - Closed - Not Admitted

Rationale:
1. Conversion gating must be explicitly tied to business progression and cannot rely on ad-hoc status use.
2. This aligns conversion controls with the existing guardrail model and prevents premature conversion.
3. Tour milestones create a formal checkpoint before contract negotiation stages.

### 1.2 Clinical Logging Object Standard
Decision:
1. Standardize nutritional and refusal logging on CareObservation.
2. Update backlog wording that references HealthCloudGA__EHR_Observation__c for this slice.

Rationale:
1. CareObservation is already used by translation and observation flows in this implementation.
2. Avoiding mixed object patterns reduces automation duplication and governance drift.

### 1.3 Staffing Capacity Model
Decision:
1. Implement multi-resident staffing via declarative-first junction modeling.
2. Use a new junction object CareOrch_Resident_Assignment__c between Shift Task and Resident Account.

Rationale:
1. Supports one caregiver to many residents in a shift.
2. Keeps capacity checks declarative and maintainable.

## 2. Corrected Backlog Slices

## Phase G: Pre-Admission Clinical Intake and Assessment (Epic 9)

### E9-A1: Care_Enquiry Lead Schema Expansion
Type: Metadata
Dependencies: None

Build Scope:
1. Add Lead fields:
   - CareOrch_Enquiry_Source__c (Picklist: Hospital, Agency, Private)
   - CareOrch_Medical_Conditions__c (Long Text Area)
   - CareOrch_Care_Needs__c (Long Text Area)
   - CareOrch_Dietary_Needs__c (Long Text Area)
   - CareOrch_Contact_Information__c (Long Text Area)
   - CareOrch_Check_In_Date__c (Date)
2. Add controlled Lead Status values in the Care Enquiry process:
   - Inquiry
   - Assessment Scheduled
   - Tour Scheduled
   - Tour Completed
   - Funding Verified
   - Contract Pending
   - Ready to Convert
   - Closed - Not Admitted
3. Expose the above fields on the Care Enquiry Lead layout.
4. Grant field-level permissions to Admissions personas.

Done Criteria:
1. Admissions users can create and edit all baseline profiling fields.
2. Status path reflects pre-admission progression.

### E9-A3: Facility Tour Milestone and Layout Adjustments
Type: Metadata
Dependencies: E9-A1

Build Scope:
1. Ensure Tour Scheduled and Tour Completed are available and ordered in the Care Enquiry status path.
2. Add Lead fields:
   - CareOrch_Tour_Feedback_Satisfactory__c (Checkbox)
   - CareOrch_Tour_Notes__c (Long Text Area)
3. Expose tour feedback fields on the Care Enquiry layout.
4. Add validation rule preventing transition to Contract Pending unless CareOrch_Tour_Feedback_Satisfactory__c is true.

Validation Rule Formula (recommended):
1. AND(
ISCHANGED(Status),
ISPICKVAL(Status, "Contract Pending"),
NOT(CareOrch_Tour_Feedback_Satisfactory__c)
)

Validation Error Message (recommended):
1. Tour feedback must be marked satisfactory before moving to Contract Pending.

Done Criteria:
1. Admissions users cannot move lead to Contract Pending without satisfactory tour confirmation.
2. Tour notes are captured as part of admission qualification evidence.

### E9-A2: Contract Verification and Conversion Gate
Type: Metadata, Apex, and Flow
Dependencies: E9-A1

Build Scope:
1. Implement conversion guardrail logic that blocks conversion unless:
   - Lead status is Ready to Convert
   - CareOrch_Check_In_Date__c is populated
   - Contract state is Activated (per final data model decision)
2. Enforce conversion readiness in Lead trigger/service before update logic.
3. On qualifying conversion, auto-create Task assigned to Facility Manager queue:
   - Subject: Prepare Room and Kitchen Logistics for Incoming Resident
   - Due date aligned to check-in preparation window
4. Implement post-conversion task creation in record-triggered flow:
   - Flow: CareOrch_Lead_Post_Conversion_Preparation_Task
   - Queue fallback: if facility manager queue is not task-enabled, assign to lead owner

Done Criteria:
1. Conversion is blocked for missing readiness controls.
2. Preparation task is generated on successful conversion.

## Phase H: Floor Staff Safeguarding and Ratios (Epic 10)

### E10-M1: Multi-Resident Junction Assignment Model
Type: Metadata
Dependencies: None

Build Scope:
1. Create CareOrch_Resident_Assignment__c.
2. Add lookups:
   - Shift_Task__c (Shift_Lifecycle__c shift context)
   - Resident_Account__c (Account)
3. Add safeguards and assignment attributes as needed (active flag, role in shift, note).
4. Add Account fields:
   - CareOrch_Mobility_Assistance_Required__c (Checkbox)
   - CareOrch_Hyper_Aggressive_Behavior__c (Checkbox)

Done Criteria:
1. One shift can contain multiple residents through related records.
2. Resident risk signals are explicitly modeled.

### E10-M2: Capacity Tier and Lone Worker Enforcement
Type: Metadata and Apex
Dependencies: E10-M1

Build Scope:
1. Aggregate assignment/risk counts to shift context using shift lifecycle counter fields maintained by assignment guardrail logic.
2. Enforce capacity tiers (5 low-needs max, 2 high-needs max) on resident assignment save.
3. Enforce lone-worker safeguard for hyper-aggressive residents unless second caregiver coverage is confirmed.
4. Surface warning on Shift_Lifecycle__c and block save on violations.

Done Criteria:
1. Unsafe staffing combinations cannot be saved.
2. Operations Lead sees clear capacity and risk warnings.

## Phase I: Regulatory Logging and Experience Cloud (Epic 11)

### E11-R1: CareObservation Nutritional and Refusal Logging
Type: Metadata and LWC
Dependencies: None

Build Scope:
1. Add CareObservation record type Nutritional_Log.
2. Add fields:
   - CareOrch_Meal_Type__c (Picklist: Breakfast, Lunch, Dinner, Snack)
   - CareOrch_Consumption_Level__c (Picklist: All, Most, Half, Little, None)
   - CareOrch_Food_Fruit_Refused__c (Long Text Area)
3. Add a compact input panel in careOrchCarerWorkspace for mobile-first capture.
4. Apply write-lock strategy after creation for compliance.

Done Criteria:
1. Carer can submit nutritional log in three clicks or less.
2. Audit-compliant immutability controls are in place.

### E11-R2: Activity Logs and Experience Cloud Data Partitioning
Type: Metadata, Experience Cloud, Sharing
Dependencies: None

Build Scope:
1. Create CareOrch_Activity_Log__c (master-detail to resident Account).
2. Add fields:
   - CareOrch_Activity_Name__c (Text)
   - CareOrch_Activity_Details__c (Long Text or Rich Text)
   - Photo capture support via Files
3. Build Experience Cloud NoK timeline component.
4. Configure strict record partitioning so NoK sees only activity for linked resident.

Done Criteria:
1. Caregiver-posted activity and photos are visible to authorized NoK only.
2. Cross-account data leakage is blocked.

## 3. Implementation Sequence

1. E9-A1
2. E9-A3
3. E9-A2
4. E10-M1
5. E10-M2
6. E11-R1
7. E11-R2

Reasoning:
1. Admission and conversion controls must stabilize before downstream staffing and portal exposure.
2. Junction assignment model must exist before safeguard enforcement logic.

## 4. Guardrails for Build Team

1. Declarative first; Apex only when platform constraints require it.
2. No profile edits; use permission sets.
3. Keep naming consistent with CareOrch prefix and existing conventions.
4. Keep deployment slices source-dir compatible for targeted promotion.
5. Provide test evidence per slice with record ids, screenshots, and pass/fail outcome.

## 5. Acceptance Test Matrix

| Slice | Test Case | Expected Result |
|---|---|---|
| E9-A1 | Create Care Enquiry lead with full baseline fields | Lead saves and fields persist |
| E9-A1 | Move status to Assessment Scheduled | Status transition allowed |
| E9-A3 | Attempt move to Contract Pending without satisfactory tour flag | Save blocked with validation error |
| E9-A3 | Complete Tour feedback and move to Contract Pending | Status transition allowed |
| E9-A2 | Attempt conversion without Ready to Convert or check-in date | Conversion blocked |
| E9-A2 | Convert qualifying lead | Preparation task auto-created |
| E10-M1 | Assign multiple residents to one shift via junction | Multiple linked rows saved |
| E10-M2 | Assign lone worker to hyper-aggressive resident | Save blocked with warning |
| E11-R1 | Capture Nutritional_Log in mobile flow | Record created in under three clicks |
| E11-R1 | Attempt post-create edit on locked fields | Edit blocked per compliance control |
| E11-R2 | NoK user opens portal timeline | User sees only linked resident records |
| E11-R2 | NoK tries accessing another resident activity | Access denied |

## 6. Immediate Repo Alignment Notes

1. Existing Care Enquiry business process and conversion guardrails must be updated to include Ready to Convert alignment.
2. Tour milestones and tour quality checkpoint must be added before Contract Pending can be used.
3. Existing CareObservation architecture is retained and extended, not replaced.
4. Existing shift assignment engine remains, with junction and capacity enforcement added as a new layer.
