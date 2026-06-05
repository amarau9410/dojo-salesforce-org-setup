public with sharing class CareOrchShiftInboxController {
    public class ShiftTaskRow {
        @AuraEnabled public Id taskId;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime shiftStart;
        @AuraEnabled public Datetime shiftEnd;
        @AuraEnabled public String patientName;
        @AuraEnabled public Decimal contactedCount;
        @AuraEnabled public Decimal rejectedCount;
        @AuraEnabled public Boolean atRisk;
        @AuraEnabled public String atRiskReason;
        @AuraEnabled public Decimal timeToFirstResponseMinutes;
        @AuraEnabled public Decimal timeToFillMinutes;
    }

    @AuraEnabled(cacheable=true)
    public static List<ShiftTaskRow> getMyShiftTasks() {
        List<ShiftTaskRow> rows = new List<ShiftTaskRow>();

        for (Task taskRecord : [
            SELECT Id,
                   Subject,
                   CareOrch_Shift_Status__c,
                   CareOrch_Shift_Start__c,
                   CareOrch_Shift_End__c,
                   What.Name,
                   CareOrch_Contacted_Count__c,
                     CareOrch_Rejected_Count__c,
                     CareOrch_At_Risk__c,
                     CareOrch_At_Risk_Reason__c,
                     CareOrch_Time_to_First_Response_Minutes__c,
                     CareOrch_Time_to_Fill_Minutes__c
            FROM Task
            WHERE OwnerId = :UserInfo.getUserId()
              AND CareOrch_Shift_Start__c != null
            WITH USER_MODE
            ORDER BY CareOrch_Shift_Start__c ASC, LastModifiedDate DESC
            LIMIT 100
        ]) {
            ShiftTaskRow row = new ShiftTaskRow();
            row.taskId = taskRecord.Id;
            row.subject = taskRecord.Subject;
            row.status = taskRecord.CareOrch_Shift_Status__c;
            row.shiftStart = taskRecord.CareOrch_Shift_Start__c;
            row.shiftEnd = taskRecord.CareOrch_Shift_End__c;
            row.patientName = taskRecord.What != null ? taskRecord.What.Name : null;
            row.contactedCount = taskRecord.CareOrch_Contacted_Count__c;
            row.rejectedCount = taskRecord.CareOrch_Rejected_Count__c;
            row.atRisk = taskRecord.CareOrch_At_Risk__c;
            row.atRiskReason = taskRecord.CareOrch_At_Risk_Reason__c;
            row.timeToFirstResponseMinutes = taskRecord.CareOrch_Time_to_First_Response_Minutes__c;
            row.timeToFillMinutes = taskRecord.CareOrch_Time_to_Fill_Minutes__c;
            rows.add(row);
        }

        return rows;
    }
}
