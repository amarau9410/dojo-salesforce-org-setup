public without sharing class CareOrchShiftAssignmentService {
    private static Boolean suppressTriggerWork = false;
    private static final Integer HIGH_REJECTION_THRESHOLD = 2;
    private static final Integer REPEATED_UNFILLED_THRESHOLD = 2;
    private static final Integer LOOKBACK_DAYS_FOR_UNFILLED = 30;

    public static void handleAfter(List<Task> newRecords, Map<Id, Task> oldMap) {
        if (suppressTriggerWork || newRecords == null || newRecords.isEmpty()) {
            return;
        }

        Set<Id> ownerIds = new Set<Id>();
        List<Task> tasksToInitialize = new List<Task>();

        for (Task t : newRecords) {
            if (!isShiftTask(t)) {
                continue;
            }

            Task oldRecord = oldMap == null ? null : oldMap.get(t.Id);
            Boolean isInsert = oldRecord == null;
            Boolean ownerChanged = !isInsert && oldRecord.OwnerId != t.OwnerId;
            Boolean statusMovedToPending =
                !isInsert &&
                oldRecord.CareOrch_Shift_Status__c != 'Pending' &&
                t.CareOrch_Shift_Status__c == 'Pending';

            if (isInsert || ownerChanged || statusMovedToPending) {
                tasksToInitialize.add(t);
                if (isUserId(t.OwnerId)) {
                    ownerIds.add(t.OwnerId);
                }
            }
        }

        if (tasksToInitialize.isEmpty()) {
            return;
        }

        Map<Id, User> ownersById = new Map<Id, User>();
        if (!ownerIds.isEmpty()) {
            ownersById = new Map<Id, User>([
                SELECT Id, Name, Email
                FROM User
                WHERE Id IN :ownerIds AND IsActive = true
            ]);
        }

        List<Task> updates = new List<Task>();
        for (Task t : tasksToInitialize) {
            Set<String> contacted = parseContacted(t.CareOrch_Contacted_Caregiver_Ids__c);
            String ownerIdStr = String.valueOf(t.OwnerId);
            if (isUserId(t.OwnerId)) {
                contacted.add(ownerIdStr);
            }

            Task u = new Task(Id = t.Id);
            if (String.isBlank(t.CareOrch_Shift_Status__c)) {
                u.CareOrch_Shift_Status__c = 'Pending';
            }
            u.CareOrch_Contacted_Caregiver_Ids__c = serializeContacted(contacted);
            u.CareOrch_Contacted_Count__c = contacted.size();
            if (t.CareOrch_Rejected_Count__c == null) {
                u.CareOrch_Rejected_Count__c = 0;
            }
            if (t.CareOrch_At_Risk__c == null) {
                u.CareOrch_At_Risk__c = false;
            }
            if (t.CareOrch_At_Risk_Alert_Sent__c == null) {
                u.CareOrch_At_Risk_Alert_Sent__c = false;
            }
            updates.add(u);
        }

        if (!updates.isEmpty()) {
            suppressTriggerWork = true;
            try {
                update updates;
            } finally {
                suppressTriggerWork = false;
            }
        }

        Set<Id> refreshedIds = new Set<Id>();
        for (Task t : tasksToInitialize) {
            refreshedIds.add(t.Id);
        }

        Map<Id, Task> refreshedTasks = new Map<Id, Task>([
            SELECT Id, Subject, OwnerId, WhatId, What.Name,
                   CareOrch_Shift_Start__c, CareOrch_Shift_End__c,
                   CareOrch_Handover_Comment__c,
                   CareOrch_Contacted_Count__c,
                   CareOrch_Rejected_Count__c,
                   CareOrch_Shift_Status__c,
                   CareOrch_At_Risk__c,
                   CareOrch_At_Risk_Reason__c,
                   CareOrch_At_Risk_Alert_Sent__c
            FROM Task
            WHERE Id IN :refreshedIds
        ]);

        for (Task t : tasksToInitialize) {
            Task current = refreshedTasks.get(t.Id);
            if (current == null || current.CareOrch_Shift_Status__c != 'Pending') {
                continue;
            }

            User caregiver = ownersById.get(current.OwnerId);
            if (caregiver == null || String.isBlank(caregiver.Email)) {
                continue;
            }

            sendShiftAssignmentEmail(current, caregiver);
        }
    }

    public static void rejectAndRouteToNextCaregiver(Id taskId, Id rejectingUserId) {
        Datetime nowDt = System.now();
        Task taskRecord = [
            SELECT Id, Subject, OwnerId, WhatId, What.Name,
                   CareOrch_Shift_Start__c, CareOrch_Shift_End__c,
                   CareOrch_Handover_Comment__c,
                   CareOrch_Shift_Status__c,
                   CareOrch_Shift_Manager__c,
                   CareOrch_Contacted_Caregiver_Ids__c,
                   CareOrch_Contacted_Count__c,
                   CareOrch_Rejected_Count__c,
                   CareOrch_First_Response_At__c,
                   CareOrch_Time_to_First_Response_Minutes__c,
                   CareOrch_At_Risk__c,
                   CareOrch_At_Risk_Reason__c,
                   CareOrch_At_Risk_Alert_Sent__c
            FROM Task
            WHERE Id = :taskId
            LIMIT 1
            FOR UPDATE
        ];

        Set<String> contacted = parseContacted(taskRecord.CareOrch_Contacted_Caregiver_Ids__c);
        contacted.add(String.valueOf(rejectingUserId));

        Integer rejected = taskRecord.CareOrch_Rejected_Count__c == null
            ? 0
            : Integer.valueOf(taskRecord.CareOrch_Rejected_Count__c);
        rejected += 1;

        Id nextCaregiverId = findNextCaregiverId(contacted);
        String managerEmail = resolveManagerEmail(taskRecord, rejectingUserId);

        RiskEvaluation risk = evaluateRisk(taskRecord, rejected);
        Datetime firstResponseAt = taskRecord.CareOrch_First_Response_At__c == null
            ? nowDt
            : taskRecord.CareOrch_First_Response_At__c;
        Decimal timeToFirstResponse = taskRecord.CareOrch_Time_to_First_Response_Minutes__c == null
            ? computeElapsedMinutes(taskRecord.CareOrch_Shift_Start__c, firstResponseAt)
            : taskRecord.CareOrch_Time_to_First_Response_Minutes__c;

        if (nextCaregiverId != null) {
            contacted.add(String.valueOf(nextCaregiverId));

            Task updateTask = new Task(
                Id = taskRecord.Id,
                OwnerId = nextCaregiverId,
                CareOrch_Shift_Status__c = 'Pending',
                CareOrch_Rejected_Count__c = rejected,
                CareOrch_Contacted_Caregiver_Ids__c = serializeContacted(contacted),
                CareOrch_Contacted_Count__c = contacted.size(),
                CareOrch_First_Response_At__c = firstResponseAt,
                CareOrch_Time_to_First_Response_Minutes__c = timeToFirstResponse,
                CareOrch_At_Risk__c = risk.atRisk,
                CareOrch_At_Risk_Reason__c = risk.reason,
                CareOrch_At_Risk_Alert_Sent__c = risk.atRisk
                    ? (taskRecord.CareOrch_At_Risk_Alert_Sent__c == true ? true : false)
                    : false
            );

            suppressTriggerWork = false;
            update updateTask;

            if (risk.atRisk && !String.isBlank(managerEmail) && taskRecord.CareOrch_At_Risk_Alert_Sent__c != true) {
                sendManagerEmail(
                    managerEmail,
                    'CareOrch Shift At-Risk Alert',
                    buildManagerBody(
                        taskRecord,
                        'At-risk shift flagged before unfilled. Reason: ' + risk.reason,
                        contacted.size(),
                        rejected
                    )
                );
                update new Task(Id = taskRecord.Id, CareOrch_At_Risk_Alert_Sent__c = true);
            }

            if (!String.isBlank(managerEmail)) {
                sendManagerEmail(
                    managerEmail,
                    'CareOrch Shift Rejected - Reassigned',
                    buildManagerBody(taskRecord, 'Rejected and reassigned to the next available caregiver.', contacted.size(), rejected)
                );
            }
            return;
        }

        Task closeOut = new Task(
            Id = taskRecord.Id,
            CareOrch_Shift_Status__c = 'Unfilled',
            CareOrch_Rejected_Count__c = rejected,
            CareOrch_Contacted_Caregiver_Ids__c = serializeContacted(contacted),
            CareOrch_Contacted_Count__c = contacted.size(),
            CareOrch_First_Response_At__c = firstResponseAt,
            CareOrch_Time_to_First_Response_Minutes__c = timeToFirstResponse,
            CareOrch_At_Risk__c = true,
            CareOrch_At_Risk_Reason__c = String.isBlank(risk.reason)
                ? 'No remaining caregiver available'
                : risk.reason + '; no remaining caregiver available',
            CareOrch_Time_to_Fill_Minutes__c = computeElapsedMinutes(taskRecord.CareOrch_Shift_Start__c, nowDt)
        );
        update closeOut;

        if (!String.isBlank(managerEmail)) {
            sendManagerEmail(
                managerEmail,
                'CareOrch Shift Escalation - No Caregiver Accepted',
                buildManagerBody(taskRecord, 'No available caregiver accepted the shift.', contacted.size(), rejected)
            );
        }
    }

    public static void notifyManagerForAcceptance(Id taskId, Id acceptingUserId) {
        Datetime nowDt = System.now();
        Task taskRecord = [
            SELECT Id, Subject, OwnerId, WhatId, What.Name,
                   CareOrch_Shift_Start__c, CareOrch_Shift_End__c,
                   CareOrch_Shift_Manager__c,
                   CareOrch_Contacted_Count__c,
                   CareOrch_Rejected_Count__c,
                   CareOrch_First_Response_At__c,
                   CareOrch_Time_to_First_Response_Minutes__c
            FROM Task
            WHERE Id = :taskId
            LIMIT 1
        ];

        Datetime firstResponseAt = taskRecord.CareOrch_First_Response_At__c == null
            ? nowDt
            : taskRecord.CareOrch_First_Response_At__c;
        Decimal firstResponseMinutes = taskRecord.CareOrch_Time_to_First_Response_Minutes__c == null
            ? computeElapsedMinutes(taskRecord.CareOrch_Shift_Start__c, firstResponseAt)
            : taskRecord.CareOrch_Time_to_First_Response_Minutes__c;

        update new Task(
            Id = taskRecord.Id,
            CareOrch_Shift_Status__c = 'Accepted',
            CareOrch_First_Response_At__c = firstResponseAt,
            CareOrch_Filled_At__c = nowDt,
            CareOrch_Time_to_First_Response_Minutes__c = firstResponseMinutes,
            CareOrch_Time_to_Fill_Minutes__c = computeElapsedMinutes(taskRecord.CareOrch_Shift_Start__c, nowDt)
        );

        String managerEmail = resolveManagerEmail(taskRecord, acceptingUserId);
        if (String.isBlank(managerEmail)) {
            return;
        }

        Integer contacted = taskRecord.CareOrch_Contacted_Count__c == null
            ? 0
            : Integer.valueOf(taskRecord.CareOrch_Contacted_Count__c);
        Integer rejected = taskRecord.CareOrch_Rejected_Count__c == null
            ? 0
            : Integer.valueOf(taskRecord.CareOrch_Rejected_Count__c);

        sendManagerEmail(
            managerEmail,
            'CareOrch Shift Accepted',
            buildManagerBody(taskRecord, 'Shift accepted by caregiver.', contacted, rejected)
        );
    }

    private static Id findNextCaregiverId(Set<String> excludedUserIds) {
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId, Assignee.Email
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name = 'CareOrch_Floor_Carer'
              AND Assignee.IsActive = true
              AND Assignee.Email != null
            ORDER BY Assignee.LastName, Assignee.FirstName
        ]) {
            if (!excludedUserIds.contains(String.valueOf(psa.AssigneeId))) {
                return psa.AssigneeId;
            }
        }
        return null;
    }

    private static String resolveManagerEmail(Task taskRecord, Id fallbackUserId) {
        if (taskRecord.CareOrch_Shift_Manager__c != null) {
            List<User> managers = [
                SELECT Id, Email
                FROM User
                WHERE Id = :taskRecord.CareOrch_Shift_Manager__c
                LIMIT 1
            ];
            if (!managers.isEmpty() && !String.isBlank(managers[0].Email)) {
                return managers[0].Email;
            }
        }

        List<User> fallbackUsers = [
            SELECT Id, Manager.Email
            FROM User
            WHERE Id = :fallbackUserId
            LIMIT 1
        ];
        if (fallbackUsers.isEmpty() || fallbackUsers[0].Manager == null) {
            return null;
        }

        return fallbackUsers[0].Manager.Email;
    }

    private static void sendShiftAssignmentEmail(Task taskRecord, User caregiver) {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        String taskId = EncodingUtil.urlEncode(String.valueOf(taskRecord.Id), 'UTF-8');

        String acceptLink = baseUrl + '/services/apexrest/careorch/shift-response?action=accept&taskId=' + taskId;
        String rejectLink = baseUrl + '/services/apexrest/careorch/shift-response?action=reject&taskId=' + taskId;

        String patientName = taskRecord.WhatId == null ? 'Not specified' : String.valueOf(taskRecord.getSObject('What').get('Name'));
        String handover = String.isBlank(taskRecord.CareOrch_Handover_Comment__c)
            ? 'No handover details provided.'
            : taskRecord.CareOrch_Handover_Comment__c;

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { caregiver.Email });
        mail.setSubject('Shift Assigned: ' + safe(taskRecord.Subject));
        mail.setPlainTextBody(
            'Hello ' + safe(caregiver.Name) + ',\n\n' +
            'A shift has been assigned to you.\n\n' +
            'Shift Start: ' + formatDateTime(taskRecord.CareOrch_Shift_Start__c) + '\n' +
            'Shift End: ' + formatDateTime(taskRecord.CareOrch_Shift_End__c) + '\n' +
            'Patient: ' + patientName + '\n' +
            'Handover: ' + handover + '\n\n' +
            'Accept Shift: ' + acceptLink + '\n' +
            'Reject Shift: ' + rejectLink + '\n\n' +
            'If you reject, CareOrch will contact the next available caregiver automatically.'
        );
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }

    private static void sendManagerEmail(String managerEmail, String subject, String body) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { managerEmail });
        mail.setSubject(subject);
        mail.setPlainTextBody(body);
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }

    private static String buildManagerBody(Task taskRecord, String eventLine, Integer contactedCount, Integer rejectedCount) {
        String patientName = taskRecord.WhatId == null ? 'Not specified' : String.valueOf(taskRecord.getSObject('What').get('Name'));

        return
            'CareOrch Shift Update\n\n' +
            'Shift: ' + safe(taskRecord.Subject) + '\n' +
            'Patient: ' + patientName + '\n' +
            'Shift Start: ' + formatDateTime(taskRecord.CareOrch_Shift_Start__c) + '\n' +
            'Shift End: ' + formatDateTime(taskRecord.CareOrch_Shift_End__c) + '\n\n' +
            'Event: ' + eventLine + '\n' +
            'Caregivers Contacted: ' + String.valueOf(contactedCount) + '\n' +
            'Caregivers Rejected: ' + String.valueOf(rejectedCount) + '\n';
    }

    private class RiskEvaluation {
        private Boolean atRisk;
        private String reason;

        private RiskEvaluation(Boolean atRisk, String reason) {
            this.atRisk = atRisk;
            this.reason = reason;
        }
    }

    private static RiskEvaluation evaluateRisk(Task taskRecord, Integer rejectedCount) {
        List<String> reasons = new List<String>();
        if (rejectedCount >= HIGH_REJECTION_THRESHOLD) {
            reasons.add('High rejection streak');
        }

        if (taskRecord.WhatId != null && getRepeatedUnfilledCount(taskRecord.WhatId, taskRecord.CareOrch_Shift_Start__c) >= REPEATED_UNFILLED_THRESHOLD) {
            reasons.add('Repeated unfilled shifts for location/time band');
        }

        if (reasons.isEmpty()) {
            return new RiskEvaluation(false, null);
        }

        return new RiskEvaluation(true, String.join(reasons, '; '));
    }

    private static Integer getRepeatedUnfilledCount(Id whatId, Datetime shiftStart) {
        if (whatId == null || shiftStart == null) {
            return 0;
        }

        String currentBand = getTimeBand(shiftStart);
        Integer countMatches = 0;
        for (Task historical : [
            SELECT CareOrch_Shift_Start__c
            FROM Task
            WHERE WhatId = :whatId
              AND CareOrch_Shift_Status__c = 'Unfilled'
              AND CareOrch_Shift_Start__c >= :System.now().addDays(-LOOKBACK_DAYS_FOR_UNFILLED)
            LIMIT 200
        ]) {
            if (currentBand == getTimeBand(historical.CareOrch_Shift_Start__c)) {
                countMatches += 1;
            }
        }
        return countMatches;
    }

    private static String getTimeBand(Datetime dt) {
        if (dt == null) {
            return 'Unknown';
        }
        Integer hour = Integer.valueOf(dt.format('H'));
        if (hour >= 6 && hour < 14) {
            return 'Morning';
        }
        if (hour >= 14 && hour < 22) {
            return 'Afternoon';
        }
        return 'Night';
    }

    private static Decimal computeElapsedMinutes(Datetime startDt, Datetime endDt) {
        if (startDt == null || endDt == null) {
            return null;
        }
        Long diffMillis = endDt.getTime() - startDt.getTime();
        if (diffMillis < 0) {
            diffMillis = 0;
        }
        return Decimal.valueOf(diffMillis) / Decimal.valueOf(60000);
    }

    private static Boolean isShiftTask(Task t) {
        return t != null && t.CareOrch_Shift_Start__c != null && t.CareOrch_Shift_End__c != null;
    }

    private static Boolean isUserId(Id ownerId) {
        return ownerId != null && String.valueOf(ownerId).startsWith('005');
    }

    private static Set<String> parseContacted(String raw) {
        Set<String> values = new Set<String>();
        if (String.isBlank(raw)) {
            return values;
        }

        for (String item : raw.split(';')) {
            String trimmed = item == null ? null : item.trim();
            if (!String.isBlank(trimmed)) {
                values.add(trimmed);
            }
        }
        return values;
    }

    private static String serializeContacted(Set<String> ids) {
        if (ids == null || ids.isEmpty()) {
            return null;
        }

        List<String> out = new List<String>();
        out.addAll(ids);
        out.sort();
        return String.join(out, ';');
    }

    private static String formatDateTime(Datetime dt) {
        return dt == null ? 'Not specified' : dt.format('yyyy-MM-dd HH:mm');
    }

    private static String safe(String value) {
        return value == null ? '' : value;
    }
}
