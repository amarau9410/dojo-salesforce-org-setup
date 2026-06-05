public with sharing class CareOrchLeadAssignmentService {
    @TestVisible
    private static String queueDeveloperName = 'CareOrch_Admissions';

    public static void routeCareEnquiries(List<Lead> leads) {
        if (leads == null || leads.isEmpty()) {
            return;
        }

        Id careEnquiryRecordTypeId = getCareEnquiryRecordTypeId();
        if (careEnquiryRecordTypeId == null) {
            return;
        }

        Id admissionsQueueId = getAdmissionsQueueId();
        if (admissionsQueueId == null) {
            return;
        }

        for (Lead leadRow : leads) {
            if (leadRow.RecordTypeId == careEnquiryRecordTypeId) {
                leadRow.OwnerId = admissionsQueueId;
            }
        }
    }

    public static void enforceConversionReadiness(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        if (newLeads == null || newLeads.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        Id careEnquiryRecordTypeId = getCareEnquiryRecordTypeId();
        if (careEnquiryRecordTypeId == null) {
            return;
        }

        List<Lead> convertingLeads = new List<Lead>();
        Set<Id> convertedAccountIds = new Set<Id>();

        for (Lead leadRow : newLeads) {
            Lead oldRow = oldMap.get(leadRow.Id);
            if (oldRow == null) {
                continue;
            }

            if (leadRow.RecordTypeId != careEnquiryRecordTypeId) {
                continue;
            }

            if (oldRow.IsConverted == false && leadRow.IsConverted == true) {
                convertingLeads.add(leadRow);
                if (leadRow.ConvertedAccountId != null) {
                    convertedAccountIds.add(leadRow.ConvertedAccountId);
                }
            }
        }

        if (convertingLeads.isEmpty()) {
            return;
        }

        Set<Id> activatedContractAccountIds = new Set<Id>();
        if (!convertedAccountIds.isEmpty()) {
            for (Contract contractRow : [
                SELECT Id, AccountId
                FROM Contract
                WHERE AccountId IN :convertedAccountIds
                  AND Status = 'Activated'
            ]) {
                activatedContractAccountIds.add(contractRow.AccountId);
            }
        }

        for (Lead leadRow : convertingLeads) {
            if (leadRow.CareOrch_Check_In_Date__c == null) {
                leadRow.CareOrch_Check_In_Date__c.addError('CareOrch Check-In Date is required before conversion.');
            }

            if (leadRow.ConvertedAccountId == null || !activatedContractAccountIds.contains(leadRow.ConvertedAccountId)) {
                leadRow.addError('Conversion requires an associated Activated Contract.');
            }
        }
    }

    public static void syncDietaryNeedsToConvertedAccount(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        if (newLeads == null || newLeads.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        Map<Id, String> dietaryByAccountId = new Map<Id, String>();
        for (Lead leadRow : newLeads) {
            Lead oldRow = oldMap.get(leadRow.Id);
            if (oldRow == null) {
                continue;
            }

            if (!(oldRow.IsConverted == false && leadRow.IsConverted == true)) {
                continue;
            }

            if (leadRow.ConvertedAccountId == null || String.isBlank(leadRow.CareOrch_Dietary_Needs__c)) {
                continue;
            }

            dietaryByAccountId.put(leadRow.ConvertedAccountId, leadRow.CareOrch_Dietary_Needs__c);
        }

        if (dietaryByAccountId.isEmpty()) {
            return;
        }

        List<Account> updates = new List<Account>();
        for (Account accountRow : [
            SELECT Id, CareOrch_Dietary_Needs__c
            FROM Account
            WHERE Id IN :dietaryByAccountId.keySet()
        ]) {
            accountRow.CareOrch_Dietary_Needs__c = dietaryByAccountId.get(accountRow.Id);
            updates.add(accountRow);
        }

        if (!updates.isEmpty()) {
            Database.update(updates, false);
        }
    }

    @TestVisible
    private static Id getCareEnquiryRecordTypeId() {
        Schema.RecordTypeInfo rtInfo = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('Care_Enquiry');
        return rtInfo == null ? null : rtInfo.getRecordTypeId();
    }

    @TestVisible
    private static Id getAdmissionsQueueId() {
        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue'
              AND DeveloperName = :queueDeveloperName
            LIMIT 1
        ];
        return queues.isEmpty() ? null : queues[0].Id;
    }

}
