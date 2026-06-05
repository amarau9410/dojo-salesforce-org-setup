# CareOrch Epics 6-8 Corrected Implementation Blueprint

Date: 2026-06-01
Target Org: careorchdev
Scope: Enquiry-to-placement, operational support cases, and resident finance lifecycle

## 1. Architecture Guardrails

1. Critical clinical incidents remain on Critical_Event__c as the system of record.
2. Case is used for operational support and integration-alert workflows, not to replace Critical_Event__c.
3. Lead is used only for pre-admission commercial pipeline.
4. Do not implement hard delete cascades for financial audit objects as a business process requirement.
5. Use Flow-first automation; only use Apex where Flow is insufficient.
6. Keep naming consistent with current org pattern, for example CareOrch_Funding_Type__c, not namespaced-style field API names.

## 2. Final Object Model

## 2.1 Core Lifecycle Objects

1. Lead
- Record Type: Care_Enquiry
- Purpose: pre-admission commercial pipeline

2. Account (Person Account)
- Record Type: Resident
- Purpose: post-conversion active resident profile

3. Critical_Event__c
- Purpose: clinical incident lifecycle, communication closed loop, escalation
- Existing behavior must remain unchanged

4. Case
- Record Type: Operational_Alert
- Purpose: operational support and integration issues for active residents
- Optional lookup to Critical_Event__c for cross-reference only

## 2.2 Financial and Funding Objects

1. Contract (standard)
- Related to Resident Person Account
- Stores fee and legal status lifecycle

2. CareOrch_Funding_Check__c (custom)
- Relationship: Master-Detail to Account
- Purpose: track public funding eligibility reviews

3. CareOrch_Invoice__c (custom)
- Relationship: Master-Detail to Account
- Purpose: monthly billing header

4. CareOrch_Invoice_Line__c (custom)
- Relationship: Master-Detail to CareOrch_Invoice__c
- Purpose: itemized charges

5. CareOrch_Patient_Account_Ledger__c (custom)
- Relationship: Lookup to Account
- Purpose: resident comfort-funds transactions

## 2.3 Key Relationships

1. Lead Care_Enquiry converts to Account Resident Person Account.
2. Case Operational_Alert links to Account and may link to Critical_Event__c when alert source is clinical/integration-related.
3. Funding_Check, Invoice, and Ledger objects roll up to Account.
4. Invoice_Line rolls up to Invoice.

## 3. Record Types and Validation Rules

## 3.1 Lead Care_Enquiry

Record type:
1. Care_Enquiry on Lead.

Fields:
1. CareOrch_Funding_Type__c picklist: Private, Local Authority, NHS Continuing Healthcare, Split-Funded.
2. CareOrch_Requested_Care_Type__c picklist: Residential, Nursing, Dementia, Respite.
3. CareOrch_Target_Admission_Date__c date.

Validation rules:
1. Require CareOrch_Funding_Type__c when RecordType is Care_Enquiry.
2. Require CareOrch_Requested_Care_Type__c when RecordType is Care_Enquiry.
3. Require CareOrch_Target_Admission_Date__c at or after TODAY for net-new enquiries.

Pipeline statuses for Care_Enquiry:
1. Inquiry
2. Assessment Scheduled
3. Funding Verified
4. Contract Pending
5. Ready to Convert
6. Closed - Not Admitted

## 3.2 Lead Conversion to Resident

Configuration:
1. Map Lead funding and care preference fields to Account Resident fields.
2. Use duplicate rules to prevent duplicate Person Accounts.
3. Restrict conversion permission to Admissions personas.

Validation and controls:
1. Conversion allowed only when status is Ready to Convert.
2. Funding type must be populated prior to conversion.
3. Conversion target must be Person Account record type Resident.

## 3.3 Case Operational_Alert

Record type:
1. Operational_Alert on Case.

Fields:
1. CareOrch_Alert_Source__c picklist: EHR Sync, eMAR Integration, Device Telemetry, Manual Ops Alert.
2. CareOrch_Severity__c picklist: High, Medium, Low.
3. CareOrch_Resident_Impact__c checkbox.
4. CareOrch_Critical_Event__c lookup to Critical_Event__c optional.

Validation rules:
1. Require AccountId for Operational_Alert.
2. Require Alert Source for Operational_Alert.
3. Require Severity for Operational_Alert.
4. If Critical_Event lookup is populated, Account on Case must equal Client_Account on Critical_Event.

## 3.4 Contract

Fields:
1. CareOrch_Core_Weekly_Fee__c currency.
2. CareOrch_Fee_Payer_Type__c picklist: Self-Funder, Local Authority, Corporate Guarantor.

Validation rules:
1. Block status change to Activated unless CareOrch_Core_Weekly_Fee__c > 0.
2. Require Fee Payer Type when status is Activated.

## 3.5 Funding Check

Fields:
1. CareOrch_Eligibility_Status__c picklist: Pending Assessment, Approved, Denied, Under Appeal.
2. CareOrch_Approved_Weekly_Contribution__c currency.
3. CareOrch_Review_Date__c date.

Validation rules:
1. If status is Approved, contribution must be greater than 0.
2. Review Date required for Approved and Under Appeal.

Rollups:
1. Account rollup for active approved public contribution total.

Retention policy correction:
1. Do not require resident hard delete to satisfy acceptance.
2. Use archival/retention policy for financial compliance.

## 3.6 Invoice and Invoice Line

Invoice fields:
1. Billing_Period_Start__c date.
2. Billing_Period_End__c date.
3. Total_Amount_Due__c rollup summary.
4. Payment_Status__c picklist.

Invoice line fields:
1. Line_Item_Description__c text.
2. Quantity__c number.
3. Unit_Price__c currency.
4. Line_Total__c formula = Quantity * Unit_Price.

Validation rules:
1. Quantity must be greater than 0.
2. Unit price must be greater than or equal to 0.
3. Billing period end must be on or after billing period start.

## 3.7 Comfort Funds Ledger

Fields:
1. CareOrch_Transaction_Type__c picklist: Deposit, Charge.
2. CareOrch_Amount__c currency.
3. CareOrch_Merchant_Description__c text.
4. CareOrch_Transaction_Date__c date.

Validation rules:
1. Amount must be greater than 0.
2. Merchant description required for Charge.

Balance behavior:
1. Running balance on Account updated by Flow.
2. Charges subtract and Deposits add.

## 4. Flow-First Automation Map

## 4.1 Lead Intake and Routing

1. Before-save Lead flow Care_Enquiry_Validation
- Entry: Lead created or updated, record type Care_Enquiry
- Actions: enforce required data quality flags and normalize values

2. After-save Lead flow Care_Enquiry_Assignment
- Entry: new Care_Enquiry lead
- Actions: route to Admissions Queue via assignment conditions

3. Scheduled path Care_Enquiry_Aging
- Entry: inquiry older than SLA without progression
- Actions: create reminder task for Admissions Manager

## 4.2 Lead-to-Resident Conversion Guardrail Flow

1. Screen flow Admissions_Convert_Care_Enquiry
- Entry: quick action on Lead
- Checks: status Ready to Convert, required fields complete, duplicate check
- Action: invoke standard conversion with Resident Person Account target
- Post-action: create onboarding task set

## 4.3 Operational Alert Case Creation

1. After-save flow on HealthCloudGA__EHR_Observation__c
- Entry: critical integration or medication refusal flag conditions
- Actions:
- create Case with RecordType Operational_Alert
- set Priority High, Status New, AccountId from resident mapping
- create custom notification to Duty Nurse recipients
- optionally link to existing Critical_Event__c when applicable

Conflict prevention:
1. Do not auto-create Critical_Event__c from this flow if the event already exists.
2. If clinical event already tracked on Critical_Event__c, create only supporting Case and cross-link.

## 4.4 Funding and Finance Automations

1. After-save Funding_Check flow
- update Account rollup indicators and next-review reminder task

2. After-save Invoice_Line flow
- validate and recompute invoice aggregates when needed

3. After-save Ledger flow
- update Account comfort-fund balance using signed amount logic

## 5. Rewritten Acceptance Criteria

## 5.1 Story 6.1 Care Enquiry Capture

1. Creating a Lead with Record Type Care_Enquiry requires CareOrch_Funding_Type__c.
2. Care_Enquiry statuses are limited to inquiry pipeline values.
3. New Care_Enquiry leads are routed to Admissions Queue by assignment rule/flow.
4. Clinical directory objects are not created during enquiry stage.

## 5.2 Story 6.2 Lead Conversion

1. Admissions conversion creates a Resident Person Account with Resident record type.
2. CareOrch_Funding_Type__c and related mapped values persist on resident profile.
3. Duplicate controls prevent unintended extra person records.
4. Lead timeline notes are preserved through conversion history.

## 5.3 Story 7.1 Operational Alert Cases

1. Critical integration or medication refusal alert creates Case Record Type Operational_Alert.
2. Case is created with Priority High, Status New, and resident AccountId.
3. Duty Nurse receives custom notification.
4. Existing Critical_Event lifecycle remains authoritative for incident closure and communication controls.
5. Where relevant, Case links to existing Critical_Event__c instead of duplicating incident source of truth.

## 5.4 Story 8.1 Contract Management

1. Contract related list is visible on Resident Person Account.
2. Activating Contract is blocked unless weekly fee is greater than 0.
3. Multiple contract amendments can be tracked historically.

## 5.5 Story 8.2 Funding Eligibility

1. Funding checks can be created and reviewed against Resident account.
2. Approved contributions roll up to Account total.
3. Data retention follows archive/compliance policy; acceptance does not depend on hard delete cascade.

## 5.6 Story 8.3 Invoice Engine

1. Invoice line totals roll up to invoice total due.
2. Example check: 10 units at 20 recalculates parent by 200.
3. Billing period and line-item validations prevent invalid charges.

## 5.7 Story 8.4 Comfort Funds Ledger

1. Deposit increases resident comfort-fund balance.
2. Charge decreases resident comfort-fund balance.
3. Balance updates immediately after transaction save.
4. Merchant description captured for charge transactions.

## 6. Security and Access Model

1. No profile edits; use permission sets only.
2. Create dedicated permission sets:
- CareOrch_Admissions_Manager
- CareOrch_Admissions_Admin
- CareOrch_Operations_Support
- CareOrch_Finance_Controller
- CareOrch_Billing_Clerk
3. Apply CRUD/FLS least privilege per object.
4. Restrict conversion and financial activation actions to approved personas.

## 7. Delivery Sequence

1. Phase A: Lead Care_Enquiry model, statuses, routing, conversion mapping.
2. Phase B: Operational_Alert Case model and alert flow with notifications.
3. Phase C: Contract and Funding_Check model with rollups.
4. Phase D: Invoice and Ledger model with automation and reconciliation tests.
5. Phase E: UAT and cutover with role-based scripts.

## 8. Minimum Test Pack

1. Lead required fields and assignment route tests.
2. Lead conversion to Resident Person Account with duplicate prevention tests.
3. Operational_Alert case creation and notification tests.
4. Non-regression tests confirming Critical_Event close controls still hold.
5. Contract activation validation tests.
6. Funding rollup tests.
7. Invoice rollup math tests.
8. Ledger running balance tests.

## 9. Open Decisions Required Before Build

1. Final admissions queue name and owner model.
2. Exact duplicate rule strategy for person accounts.
3. Duty Nurse recipient resolution logic for notifications.
4. Data retention policy for financial objects and resident offboarding.
5. Whether any finance automations need Apex for volume/complexity.
