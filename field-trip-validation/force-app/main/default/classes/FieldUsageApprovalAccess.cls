/**
 * Resolves approval candidates from setup records that alliance users cannot query directly.
 */
public without sharing class FieldUsageApprovalAccess {
    private static final String APPROVER_PERMISSION_SET = 'Field_Usage_Report_Approver';
    private static final String ALL_ALLIANCES_PERMISSION_SET = 'Field_Usage_All_Alliances';
    private static final String SUBMIT_APPROVAL_PERMISSION =
        'Submit_Field_Usage_Reports_For_Approval';

    /**
     * Returns active approvers who hold the dedicated permission set and share the alliance.
     * @param alliance Reporting alliance being submitted.
     * @return Eligible approver users ordered by name.
     */
    public static List<User> getEligibleApprovers(String alliance) {
        if (!FeatureManagement.checkPermission(SUBMIT_APPROVAL_PERMISSION)) {
            return new List<User>();
        }

        Set<Id> candidateIds = getApproverCandidateIds();
        if (candidateIds.isEmpty()) {
            return new List<User>();
        }

        Set<Id> allAllianceUserIds = new Set<Id>();
        for (PermissionSetAssignment assignment : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name = :ALL_ALLIANCES_PERMISSION_SET
                AND AssigneeId IN :candidateIds
        ]) {
            allAllianceUserIds.add(assignment.AssigneeId);
        }

        Map<String, Object> queryBinds = new Map<String, Object>{
            'candidateIds' => candidateIds
        };
        List<User> candidates = Database.queryWithBinds(
            'SELECT Id, Name, Email, Profile.PermissionsModifyAllData, '
                + 'Visible_Alliance_ADCB__c, Visible_Alliance_AIBMS__c, '
                + 'Visible_Alliance_CMSL__c, Visible_Alliance_EMS__c, '
                + 'Visible_Alliance_FDMS__c, Visible_Alliance_FDMSSA__c, '
                + 'Visible_Alliance_UCBA__c, Visible_Alliance_Unicaja__c, '
                + 'Visible_Alliance_VERT__c FROM User '
                + 'WHERE Id IN :candidateIds AND IsActive = true ORDER BY Name LIMIT 500',
            queryBinds,
            AccessLevel.SYSTEM_MODE
        );
        List<User> eligibleApprovers = new List<User>();
        for (User candidate : candidates) {
            if (candidate.Profile.PermissionsModifyAllData
                || allAllianceUserIds.contains(candidate.Id)
                || userHasAlliance(candidate, alliance)) {
                eligibleApprovers.add(candidate);
            }
        }
        return eligibleApprovers;
    }

    @TestVisible
    private static Set<Id> getApproverCandidateIds() {
        Set<Id> candidateIds = new Set<Id>();
        for (PermissionSetAssignment assignment : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name = :APPROVER_PERMISSION_SET
        ]) {
            candidateIds.add(assignment.AssigneeId);
        }
        return candidateIds;
    }

    @TestVisible
    private static Boolean userHasAlliance(User candidate, String alliance) {
        return (alliance == 'ADCB' && candidate.Visible_Alliance_ADCB__c == true)
            || (alliance == 'AIBMS' && candidate.Visible_Alliance_AIBMS__c == true)
            || (alliance == 'Bidvest' && candidate.Visible_Alliance_FDMSSA__c == true)
            || (alliance == 'CMSL' && candidate.Visible_Alliance_CMSL__c == true)
            || (alliance == 'EMS' && candidate.Visible_Alliance_EMS__c == true)
            || (alliance == 'FDMS' && candidate.Visible_Alliance_FDMS__c == true)
            || (alliance == 'UCBA' && candidate.Visible_Alliance_UCBA__c == true)
            || (alliance == 'Unicaja' && candidate.Visible_Alliance_Unicaja__c == true)
            || (alliance == 'Vert' && candidate.Visible_Alliance_VERT__c == true);
    }
}