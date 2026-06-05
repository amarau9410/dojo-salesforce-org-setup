public with sharing class CareOrchManagerCockpitController {
    private static final Integer DEFAULT_LIMIT = 50;
    private static final Integer TREND_DAYS = 7;
    private static final String FLOOR_CARER_PERMISSION_SET = 'CareOrch_Floor_Carer';

    public class Snapshot {
        @AuraEnabled public Integer criticalSlaBreaches;
        @AuraEnabled public Integer atRiskShifts;
        @AuraEnabled public Integer pendingTranslationReviews;
        @AuraEnabled public Integer deathSlaMinutes;
        @AuraEnabled public Integer defaultSlaMinutes;
        @AuraEnabled public List<TrendPoint> trend;
        @AuraEnabled public List<CasePriorityPoint> casePriority;
    }

    public class CasePriorityPoint {
        @AuraEnabled public String priority;
        @AuraEnabled public Integer count;
    }

    public class TrendPoint {
        @AuraEnabled public String dayLabel;
        @AuraEnabled public Decimal averageOpenAgeHours;
        @AuraEnabled public Decimal averageResolutionHours;
        @AuraEnabled public Integer openCount;
        @AuraEnabled public Integer resolvedCount;
    }

    public class CaregiverOption {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
    }

    @AuraEnabled(cacheable=true)
    public static Snapshot getSnapshot() {
        Snapshot result = new Snapshot();
        List<Critical_Event__c> breachRows = getCriticalSlaBreachRows(DEFAULT_LIMIT);
        result.criticalSlaBreaches = breachRows.size();
        result.atRiskShifts = [
            SELECT COUNT()
            FROM Task
            WHERE CareOrch_Shift_Start__c != null
              AND Likely_To_Fail__c = true
              AND CareOrch_Shift_Status__c IN ('Pending', 'Unfilled')
        ];
        try {
            result.pendingTranslationReviews = [
                SELECT COUNT()
                FROM CareObservation
                WHERE Translation_Status__c = 'Auto-translated'
            ];
        } catch (Exception ex) {
            result.pendingTranslationReviews = 0;
        }
        result.deathSlaMinutes = CareOrchSlaThresholdService.getThresholdMinutes('Death');
        result.defaultSlaMinutes = CareOrchSlaThresholdService.getThresholdMinutes('DEFAULT');
        result.trend = buildTrend();
        result.casePriority = buildOperationalAlertPriorityChart();
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<Critical_Event__c> getCriticalSlaBreachRows(Integer limitSize) {
        Integer effectiveLimit = normalizeLimit(limitSize);
        Datetime nowStamp = System.now();

        List<Critical_Event__c> rows = new List<Critical_Event__c>();
        for (Critical_Event__c eventRecord : [
            SELECT Id, Name, Event_Category__c, Status__c, CreatedDate,
                   Acknowledged_Communication_Count__c, Assigned_To__c, Assigned_To__r.Name,
                   Client_Account__r.Name
            FROM Critical_Event__c
            WHERE Status__c != 'Closed'
              AND Acknowledged_Communication_Count__c = 0
            ORDER BY CreatedDate ASC
            LIMIT :Math.max(200, effectiveLimit)
        ]) {
            Integer slaMinutes = CareOrchSlaThresholdService.getThresholdMinutes(eventRecord.Event_Category__c);
            Decimal ageMinutes = Math.abs((nowStamp.getTime() - eventRecord.CreatedDate.getTime()) / 60000.0);
            if (ageMinutes <= slaMinutes) {
                continue;
            }
            rows.add(eventRecord);

            if (rows.size() >= effectiveLimit) {
                break;
            }
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<Task> getAtRiskShiftRows(Integer limitSize) {
        Integer effectiveLimit = normalizeLimit(limitSize);
        return [
            SELECT Id, Subject, CareOrch_Shift_Status__c, CareOrch_Shift_Start__c,
                   CareOrch_Contacted_Count__c, CareOrch_Rejected_Count__c,
                                     CareOrch_At_Risk__c, Likely_To_Fail__c, CareOrch_At_Risk_Reason__c,
                   OwnerId, Owner.Name, What.Name
            FROM Task
            WHERE CareOrch_Shift_Start__c != null
                            AND Likely_To_Fail__c = true
              AND CareOrch_Shift_Status__c IN ('Pending', 'Unfilled')
            ORDER BY CareOrch_Shift_Start__c ASC
            LIMIT :effectiveLimit
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<CareObservation> getPendingTranslationRows(Integer limitSize) {
        Integer effectiveLimit = normalizeLimit(limitSize);
        try {
            return [
                SELECT Id, Name, Translation_Status__c, Original_Observation__c,
                       Auto_Translated_Notes__c, Draft_Unverified_Translation__c,
                       LastModifiedDate
                FROM CareObservation
                WHERE Translation_Status__c = 'Auto-translated'
                ORDER BY LastModifiedDate ASC
                LIMIT :effectiveLimit
            ];
        } catch (Exception ex) {
            return new List<CareObservation>();
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Critical_Event__c> getOpenRiskAgingRows(Integer limitSize, String dayKey, String segment) {
        Integer effectiveLimit = normalizeLimit(limitSize);

        if (String.isBlank(dayKey) || String.isBlank(segment)) {
            return getCriticalSlaBreachRows(effectiveLimit);
        }

        Date selectedDay;
        try {
            selectedDay = Date.valueOf(dayKey);
        } catch (Exception ex) {
            return getCriticalSlaBreachRows(effectiveLimit);
        }

        Datetime startStamp = Datetime.newInstance(selectedDay, Time.newInstance(0, 0, 0, 0));
        Datetime endStamp = startStamp.addDays(1);

        if (segment == 'resolved') {
            return [
                SELECT Id, Name, Event_Category__c, Status__c, CreatedDate,
                       Acknowledged_Communication_Count__c, Assigned_To__c, Assigned_To__r.Name,
                       Client_Account__r.Name, LastModifiedDate
                FROM Critical_Event__c
                WHERE Status__c = 'Closed'
                  AND LastModifiedDate >= :startStamp
                  AND LastModifiedDate < :endStamp
                ORDER BY LastModifiedDate DESC
                LIMIT :effectiveLimit
            ];
        }

        return [
            SELECT Id, Name, Event_Category__c, Status__c, CreatedDate,
                   Acknowledged_Communication_Count__c, Assigned_To__c, Assigned_To__r.Name,
                   Client_Account__r.Name, LastModifiedDate
            FROM Critical_Event__c
            WHERE Status__c != 'Closed'
              AND CreatedDate >= :startStamp
              AND CreatedDate < :endStamp
            ORDER BY CreatedDate DESC
            LIMIT :effectiveLimit
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<CaregiverOption> getAssignableCaregivers(Id taskId) {
        Id currentOwnerId;
        if (taskId != null) {
            List<Task> tasks = [
                SELECT Id, OwnerId
                FROM Task
                WHERE Id = :taskId
                LIMIT 1
            ];
            if (!tasks.isEmpty()) {
                currentOwnerId = tasks[0].OwnerId;
            }
        }

        List<CaregiverOption> options = new List<CaregiverOption>();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId, Assignee.Name, Assignee.Email
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name = :FLOOR_CARER_PERMISSION_SET
              AND Assignee.IsActive = true
              AND Assignee.Email != null
            ORDER BY Assignee.LastName, Assignee.FirstName
        ]) {
            if (currentOwnerId != null && psa.AssigneeId == currentOwnerId) {
                continue;
            }

            CaregiverOption option = new CaregiverOption();
            option.userId = psa.AssigneeId;
            option.name = psa.Assignee.Name;
            option.email = psa.Assignee.Email;
            options.add(option);
        }
        return options;
    }

    @AuraEnabled
    public static void reassignShift(Id taskId, Id caregiverId, String managerNote) {
        if (taskId == null || caregiverId == null) {
            throw new AuraHandledException('taskId and caregiverId are required');
        }

        Integer eligible = [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name = :FLOOR_CARER_PERMISSION_SET
              AND AssigneeId = :caregiverId
        ];
        if (eligible == 0) {
            throw new AuraHandledException('Selected caregiver does not have CareOrch floor carer access');
        }

        Task taskRecord = [
            SELECT Id, CareOrch_Handover_Comment__c
            FROM Task
            WHERE Id = :taskId
            LIMIT 1
            FOR UPDATE
        ];

        String existingComment = taskRecord.CareOrch_Handover_Comment__c;
        String noteLine = 'Manager reassigned on ' + String.valueOf(System.now()) +
            (String.isBlank(managerNote) ? '' : ': ' + managerNote);

        update new Task(
            Id = taskRecord.Id,
            OwnerId = caregiverId,
            CareOrch_Shift_Status__c = 'Pending',
            CareOrch_Handover_Comment__c = String.isBlank(existingComment)
                ? noteLine
                : existingComment + '\n' + noteLine
        );
    }

    @AuraEnabled
    public static void saveRows(String panelKey, String draftValuesJson) {
        if (String.isBlank(panelKey) || String.isBlank(draftValuesJson)) {
            return;
        }

        List<Object> rawDrafts = (List<Object>) JSON.deserializeUntyped(draftValuesJson);
        if (rawDrafts == null || rawDrafts.isEmpty()) {
            return;
        }

        if (panelKey == 'critical' || panelKey == 'aging') {
            List<Critical_Event__c> updates = new List<Critical_Event__c>();
            for (Object raw : rawDrafts) {
                Map<String, Object> values = (Map<String, Object>) raw;
                if (!values.containsKey('Id')) {
                    continue;
                }
                Critical_Event__c updateRow = new Critical_Event__c(Id = (Id) values.get('Id'));
                if (values.containsKey('Status__c')) {
                    updateRow.Status__c = (String) values.get('Status__c');
                }
                if (values.containsKey('Assigned_To__c')) {
                    updateRow.Assigned_To__c = (Id) values.get('Assigned_To__c');
                }
                updates.add(updateRow);
            }
            if (!updates.isEmpty()) {
                update updates;
            }
            return;
        }

        if (panelKey == 'shifts') {
            List<Task> updates = new List<Task>();
            for (Object raw : rawDrafts) {
                Map<String, Object> values = (Map<String, Object>) raw;
                if (!values.containsKey('Id')) {
                    continue;
                }
                Task updateRow = new Task(Id = (Id) values.get('Id'));
                if (values.containsKey('CareOrch_At_Risk__c')) {
                    updateRow.CareOrch_At_Risk__c = (Boolean) values.get('CareOrch_At_Risk__c');
                }
                if (values.containsKey('CareOrch_At_Risk_Reason__c')) {
                    updateRow.CareOrch_At_Risk_Reason__c = (String) values.get('CareOrch_At_Risk_Reason__c');
                }
                updates.add(updateRow);
            }
            if (!updates.isEmpty()) {
                update updates;
            }
            return;
        }

        if (panelKey == 'translations') {
            List<CareObservation> updates = new List<CareObservation>();
            for (Object raw : rawDrafts) {
                Map<String, Object> values = (Map<String, Object>) raw;
                if (!values.containsKey('Id')) {
                    continue;
                }
                CareObservation updateRow = new CareObservation(Id = (Id) values.get('Id'));
                if (values.containsKey('Translation_Status__c')) {
                    updateRow.Translation_Status__c = (String) values.get('Translation_Status__c');
                }
                if (values.containsKey('Auto_Translated_Notes__c')) {
                    updateRow.Auto_Translated_Notes__c = (String) values.get('Auto_Translated_Notes__c');
                }
                updates.add(updateRow);
            }
            if (!updates.isEmpty()) {
                update updates;
            }
        }
    }

    @AuraEnabled
    public static Id logPhoneOverride(Id criticalEventId) {
        if (criticalEventId == null) {
            throw new AuraHandledException('criticalEventId is required');
        }

        Critical_Event__c eventRecord = [
            SELECT Id, Assigned_To__c, Client_Account__c
            FROM Critical_Event__c
            WHERE Id = :criticalEventId
            LIMIT 1
        ];

        List<Contact> contacts = [
            SELECT Id, Relationship_Type__c
            FROM Contact
            WHERE AccountId = :eventRecord.Client_Account__c
              AND Emergency_Opt_In__c = true
              AND Relationship_Type__c IN ('Primary Contact', 'Secondary Backup')
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        Communication_Log__c overrideLog = new Communication_Log__c(
            Critical_Event__c = eventRecord.Id,
            Contact__c = contacts.isEmpty() ? null : contacts[0].Id,
            Assigned_To__c = eventRecord.Assigned_To__c,
            Channel__c = 'Voice',
            Status__c = 'Sent',
            Acknowledged__c = false,
            Dispatched_Timestamp__c = System.now()
        );
        insert overrideLog;
        return overrideLog.Id;
    }

    private static List<TrendPoint> buildTrend() {
        Date startDate = Date.today().addDays(-1 * (TREND_DAYS - 1));
        Datetime startStamp = Datetime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));

        Map<Date, Decimal> openAgeSumByDay = new Map<Date, Decimal>();
        Map<Date, Integer> openCountByDay = new Map<Date, Integer>();
        for (Critical_Event__c openEvent : [
            SELECT Id, CreatedDate
            FROM Critical_Event__c
            WHERE Status__c != 'Closed'
              AND CreatedDate >= :startStamp
        ]) {
            Date dayKey = openEvent.CreatedDate.date();
            Decimal ageHours = Math.abs((System.now().getTime() - openEvent.CreatedDate.getTime()) / 3600000.0);
            openAgeSumByDay.put(dayKey, (openAgeSumByDay.containsKey(dayKey) ? openAgeSumByDay.get(dayKey) : 0) + ageHours);
            openCountByDay.put(dayKey, (openCountByDay.containsKey(dayKey) ? openCountByDay.get(dayKey) : 0) + 1);
        }

        Map<Date, Decimal> resolvedSumByDay = new Map<Date, Decimal>();
        Map<Date, Integer> resolvedCountByDay = new Map<Date, Integer>();
        for (Critical_Event__c resolvedEvent : [
            SELECT Id, CreatedDate, LastModifiedDate
            FROM Critical_Event__c
            WHERE Status__c = 'Closed'
              AND LastModifiedDate >= :startStamp
        ]) {
            Date dayKey = resolvedEvent.LastModifiedDate.date();
            Decimal resolutionHours = Math.abs((resolvedEvent.LastModifiedDate.getTime() - resolvedEvent.CreatedDate.getTime()) / 3600000.0);
            resolvedSumByDay.put(dayKey, (resolvedSumByDay.containsKey(dayKey) ? resolvedSumByDay.get(dayKey) : 0) + resolutionHours);
            resolvedCountByDay.put(dayKey, (resolvedCountByDay.containsKey(dayKey) ? resolvedCountByDay.get(dayKey) : 0) + 1);
        }

        List<TrendPoint> rows = new List<TrendPoint>();
        for (Integer i = 0; i < TREND_DAYS; i++) {
            Date day = startDate.addDays(i);
            Integer openCount = openCountByDay.containsKey(day) ? openCountByDay.get(day) : 0;
            Integer resolvedCount = resolvedCountByDay.containsKey(day) ? resolvedCountByDay.get(day) : 0;

            TrendPoint row = new TrendPoint();
            row.dayLabel = String.valueOf(day);
            row.openCount = openCount;
            row.resolvedCount = resolvedCount;
            row.averageOpenAgeHours = openCount == 0
                ? 0
                : (openAgeSumByDay.get(day) / openCount).setScale(2);
            row.averageResolutionHours = resolvedCount == 0
                ? 0
                : (resolvedSumByDay.get(day) / resolvedCount).setScale(2);
            rows.add(row);
        }

        return rows;
    }

    private static List<CasePriorityPoint> buildOperationalAlertPriorityChart() {
        Map<String, Integer> countsByPriority = new Map<String, Integer>{
            'Critical' => 0,
            'High' => 0,
            'Medium' => 0,
            'Low' => 0,
            'Unspecified' => 0
        };

        for (AggregateResult row : [
            SELECT Priority priorityValue, COUNT(Id) rowCount
            FROM Case
            WHERE RecordType.DeveloperName = 'Operational_Alert'
              AND Status != 'Closed'
            GROUP BY Priority
        ]) {
            String priority = (String) row.get('priorityValue');
            Integer total = (Integer) row.get('rowCount');
            String key = String.isBlank(priority) ? 'Unspecified' : priority;
            countsByPriority.put(key, total);
        }

        List<String> order = new List<String>{ 'Critical', 'High', 'Medium', 'Low', 'Unspecified' };
        List<CasePriorityPoint> chartRows = new List<CasePriorityPoint>();
        for (String key : order) {
            CasePriorityPoint point = new CasePriorityPoint();
            point.priority = key;
            point.count = countsByPriority.containsKey(key) ? countsByPriority.get(key) : 0;
            chartRows.add(point);
        }
        return chartRows;
    }

    private static Integer normalizeLimit(Integer limitSize) {
        if (limitSize == null || limitSize <= 0) {
            return DEFAULT_LIMIT;
        }
        return Math.min(limitSize, 200);
    }

}
