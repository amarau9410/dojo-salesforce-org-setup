# CareOrch Admissions Duplicate Exception Path

Date: 2026-06-01
Target Org: careorchdev

## Purpose

This runbook defines the admissions-team process when person-account duplicate blocking is triggered during Care Enquiry conversion.

## Trigger Condition

1. User attempts to convert a Care Enquiry lead.
2. Person Account duplicate rule blocks creation of a new resident account.

## Admissions Operator Steps

1. Review duplicate suggestions shown by Salesforce.
2. Open each suggested resident account in a new tab.
3. Compare identity and placement details:
- Full name
- Phone/email
- Target admission date
- Funding type
- Requested care type
4. If record is the same resident, do not create new resident:
- Cancel conversion.
- Update existing resident account if needed.
- Re-parent follow-up activities/cases to existing resident account.
5. If record is not the same resident (false positive), escalate to admissions admin.

## Admissions Admin Exception Steps

1. Validate false-positive evidence from operator.
2. Create resident account via approved admin path with documented reason.
3. Link the originating lead and note exception reason in lead/account description.
4. Notify operations lead of exception for weekly duplicate-review audit.

## Audit Requirements

1. Every exception must include:
- Lead ID
- Candidate duplicate account ID
- Reason false positive was approved
- Admin approver name and date
2. Store evidence in release/UAT defect tracker for traceability.
