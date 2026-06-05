# Epic 5 Validation - AppExchange Compliance and Listing Architecture

Date: 2026-05-27
Org: careorchdev

## 1) Security Audit and USER_MODE Compliance

### Implemented changes
- Added `WITH USER_MODE` and `insert as user`/`delete as user` enforcement in:
  - `force-app/main/default/classes/ManageGroupMemberAction.cls`
  - `force-app/main/default/classes/CareOrchEmarSignalActionPlanService.cls`
  - `force-app/main/default/classes/CareOrchEmarSignalsRest.cls`
- Removed dynamic SOQL field-concatenation in `CareOrchEmarSignalsRest.resolveResident` and replaced it with a fixed query template.

### Analyzer run
- Command:
  - `sf scanner run --target "force-app/main/default/classes" --format json --outfile "tmp/epic5-scanner-all.json"`
- Result summary:
  - PMD findings exist (documentation/design/style), but no Security-category findings.
- Security acceptance check:
  - Search run against report for `"category":"Security"|ApexSOQLInjection|ApexCRUDViolation|ApexXSSFromURLParam`
  - Result: no matches.

## 2) Regression Validation

### Deployment
- Updated classes deployed to careorchdev successfully.

### Tests
- Command:
  - `sf apex run test --target-org careorchdev --class-names CareOrchEmarSignalsRestTest --result-format json --wait 60`
- Result:
  - Passing: 8
  - Failing: 0

## 3) Commercial Listing and Contact Architecture

Updated website artifacts under `tmp/wilfredandkaizer-website`:
- `services.html`
  - Added CareOrch product profile overview.
  - Added service matrix table.
  - Added AppExchange + Stripe licensing section with tiered checkout CTAs.
- `contact.html`
  - Added Salesforce Web-to-Case form posting to org `00DQ100000BxUbdMAF`.
  - Form fields route operational inquiries into Salesforce case tracking records.
- `assets/site.css`
  - Added styles for matrix table, pricing cards, and form controls.
- `assets/site.js`
  - Added Stripe CTA handler.
  - Added query-param-based form submission confirmation.

## 4) Packaging Note

- Full 2GP package version creation was not executed in this run.
- Prerequisite for final board submission remains:
  - Run `sf package version create` against the configured Dev Hub with production-ready package settings.
  - Validate resulting subscriber package with install and smoke test checks.
