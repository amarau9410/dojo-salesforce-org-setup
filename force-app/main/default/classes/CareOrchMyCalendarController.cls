public with sharing class CareOrchMyCalendarController {
    public class CalendarItem {
        @AuraEnabled public Id taskId;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime startDateTime;
        @AuraEnabled public Datetime endDateTime;
        @AuraEnabled public String patientName;
    }

    @AuraEnabled(cacheable=true)
    public static List<CalendarItem> getUpcomingShiftAgenda() {
        List<CalendarItem> items = new List<CalendarItem>();
        Datetime windowStart = System.now().addDays(-1);
        Datetime windowEnd = System.now().addDays(14);

        for (Task taskRecord : [
            SELECT Id,
                   Subject,
                   CareOrch_Shift_Status__c,
                   CareOrch_Shift_Start__c,
                   CareOrch_Shift_End__c,
                   What.Name
            FROM Task
            WHERE OwnerId = :UserInfo.getUserId()
              AND CareOrch_Shift_Start__c != null
              AND CareOrch_Shift_Start__c >= :windowStart
              AND CareOrch_Shift_Start__c <= :windowEnd
            WITH USER_MODE
            ORDER BY CareOrch_Shift_Start__c ASC
            LIMIT 200
        ]) {
            CalendarItem item = new CalendarItem();
            item.taskId = taskRecord.Id;
            item.subject = taskRecord.Subject;
            item.status = String.isBlank(taskRecord.CareOrch_Shift_Status__c)
                ? 'Pending'
                : taskRecord.CareOrch_Shift_Status__c;
            item.startDateTime = taskRecord.CareOrch_Shift_Start__c;
            item.endDateTime = taskRecord.CareOrch_Shift_End__c;
            item.patientName = taskRecord.What != null ? taskRecord.What.Name : null;
            items.add(item);
        }

        return items;
    }
}
