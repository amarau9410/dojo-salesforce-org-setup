# Epic 3 Implementation and Validation Guide

This repo now contains the mobile-first LWC and permission model updates for Epic 3.

## User Story 3.1: Mobile "Next Best Action" LWC Engine

Implemented in:
- force-app/main/default/lwc/careOrchCarerWorkspace/careOrchCarerWorkspace.js
- force-app/main/default/lwc/careOrchCarerWorkspace/careOrchCarerWorkspace.html
- force-app/main/default/lwc/careOrchCarerWorkspace/careOrchCarerWorkspace.css
- force-app/main/default/lwc/careOrchCarerWorkspace/careOrchCarerWorkspace.js-meta.xml

What is implemented:
- Mobile-optimized SLDS card grid for floor carers.
- Caching pattern with `@wire(getRecord)` from `lightning/uiRecordApi`.
- Instant optimistic state transition on tap to show `Task Completed` before server sync.
- Offline queue behavior using local storage for completion retries once connectivity returns.
- Mobile first-paint diagnostics emitted to console as:
  - `[CareOrch] Mobile layout paint: <n>ms`

### Mobile performance check (AC target < 1.2s)
1. Open Salesforce Mobile app or desktop mobile emulation.
2. Open the CareOrch Carer Workspace tab.
3. Open browser/device logs.
4. Confirm paint log line appears and the measured value is under 1200ms.

## User Story 3.2: Briefcase Builder Cache Layer Configuration

Salesforce does not expose Briefcase Builder rules as normal source metadata files in this workspace, so this section is configured in Setup UI.

### Setup steps (careorchdev)
1. Go to Setup -> Briefcase Builder.
2. Create a briefcase:
   - Label: `CareOrch_Floor_Cache`
3. Add object rule for `Task`:
   - Filter logic:
     - `OwnerId = $User.Id`
     - `Status = 'Open'`
     - `ActivityDate = TODAY`
4. Add object rule for `Account` (Person):
   - Include records related through scheduled floor tasks assigned to current user.
5. Assign briefcase to Permission Set:
   - `CareOrch Floor Carer`

### Verification checklist
- With network ON, open workspace and confirm assigned tasks and residents are visible.
- Turn on Airplane Mode / disable network.
- Confirm cached resident roster and tasks are still visible.
- Complete a task while offline and confirm UI immediately shows completion status.
- Re-enable network and confirm completion syncs back.

## Supporting permission set in source
- force-app/main/default/permissionsets/CareOrch_Floor_Carer.permissionset-meta.xml

This permission set is the target container for floor carer access and Briefcase assignment.
