public with sharing class CareOrchCriticalIncidentController {
    public class IncidentContext {
        @AuraEnabled public Id shiftTaskId;
        @AuraEnabled public String shiftSummary;
        @AuraEnabled public Id residentAccountId;
        @AuraEnabled public String residentName;
        @AuraEnabled public Datetime initiatedAt;
    }

    public class IncidentResult {
        @AuraEnabled public Id criticalEventId;
        @AuraEnabled public String message;
    }

    @AuraEnabled(cacheable=true)
    public static IncidentContext getIncidentContext() {
        IncidentContext context = new IncidentContext();
        context.initiatedAt = System.now();

        Task activeShift = findActiveShiftTask(UserInfo.getUserId());
        if (activeShift == null) {
            return context;
        }

        context.shiftTaskId = activeShift.Id;
        if (activeShift.WhatId != null && String.valueOf(activeShift.WhatId).startsWith('001')) {
            context.residentAccountId = activeShift.WhatId;
            context.residentName = activeShift.What == null ? null : String.valueOf(activeShift.What.get('Name'));
        }
        context.shiftSummary =
            safe(activeShift.Subject) +
            ' | ' +
            formatDateTime(activeShift.CareOrch_Shift_Start__c) +
            ' to ' +
            formatDateTime(activeShift.CareOrch_Shift_End__c);

        return context;
    }

    @AuraEnabled
    public static IncidentResult createIncident(String taxonomy, Decimal latitude, Decimal longitude) {
        IncidentContext context = getIncidentContext();
        if (context.residentAccountId == null) {
            throw new AuraHandledException('No active shift with a resident account is available for incident logging.');
        }

        String sanitizedTaxonomy = String.isBlank(taxonomy) ? null : taxonomy.trim();
        if (String.isBlank(sanitizedTaxonomy)) {
            throw new AuraHandledException('Incident taxonomy is required.');
        }

        Critical_Event__c eventRecord = new Critical_Event__c(
            Client_Account__c = context.residentAccountId,
            Event_Category__c = mapEventCategory(sanitizedTaxonomy),
            Status__c = 'Open',
            Assigned_To__c = UserInfo.getUserId(),
            Critical_Event_Taxonomy__c = sanitizedTaxonomy,
            Active_Shift_Context__c = context.shiftSummary,
            Active_Shift_Task_Id__c = context.shiftTaskId == null ? null : String.valueOf(context.shiftTaskId),
            Incident_Location__Latitude__s = latitude,
            Incident_Location__Longitude__s = longitude
        );

        insert as user eventRecord;

        IncidentResult result = new IncidentResult();
        result.criticalEventId = eventRecord.Id;
        result.message = 'Critical incident logged successfully.';
        return result;
    }

    private static Task findActiveShiftTask(Id userId) {
        List<Task> shifts = [
            SELECT Id, Subject, WhatId, What.Name, CareOrch_Shift_Start__c, CareOrch_Shift_End__c
            FROM Task
            WHERE OwnerId = :userId
              AND CareOrch_Shift_Start__c != null
              AND CareOrch_Shift_End__c != null
              AND CareOrch_Shift_Start__c <= :System.now()
              AND CareOrch_Shift_End__c >= :System.now()
            ORDER BY CareOrch_Shift_Start__c DESC
            LIMIT 1
        ];

        return shifts.isEmpty() ? null : shifts[0];
    }

    private static String mapEventCategory(String taxonomy) {
        Set<String> seriousConcernTaxonomies = new Set<String>{
            'Serious Injury',
            'Elopement / Missing Resident',
            'Resident-to-Resident Altercation',
            'Choking Incident',
            'Unresponsive / Loss of Consciousness',
            'Sudden Clinical Deterioration',
            'Skin Integrity Failure (Severe Pressure Ulcer)',
            'Unexplained Injury'
        };

        if (seriousConcernTaxonomies.contains(taxonomy)) {
            return 'Serious Health Concern';
        }
        return 'Other';
    }

    private static String formatDateTime(Datetime value) {
        return value == null ? 'n/a' : value.format('yyyy-MM-dd HH:mm');
    }

    private static String safe(String value) {
        return value == null ? '' : value;
    }
}
