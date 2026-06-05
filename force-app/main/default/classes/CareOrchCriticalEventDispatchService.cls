public without sharing class CareOrchCriticalEventDispatchService {
    private static Boolean suppressWork = false;

    public static void handleAfterInsert(List<Critical_Event__c> newRecords) {
        if (suppressWork || newRecords == null || newRecords.isEmpty()) {
            return;
        }

        Set<Id> eventIds = new Set<Id>();
        Set<Id> residentAccountIds = new Set<Id>();
        for (Critical_Event__c eventRecord : newRecords) {
            if (eventRecord == null || eventRecord.Client_Account__c == null) {
                continue;
            }
            eventIds.add(eventRecord.Id);
            residentAccountIds.add(eventRecord.Client_Account__c);
        }

        if (eventIds.isEmpty()) {
            return;
        }

        Map<Id, Critical_Event__c> eventById = new Map<Id, Critical_Event__c>([
            SELECT Id, Name, Client_Account__c, Client_Account__r.Name,
                   Client_Account__r.CareOrch_Preferred_Notification_Method__c,
                   Event_Category__c, Assigned_To__c, Assigned_To__r.ManagerId, Assigned_To__r.Manager.Email
            FROM Critical_Event__c
            WHERE Id IN :eventIds
        ]);

        Map<Id, List<Contact>> contactsByAccount = new Map<Id, List<Contact>>();
        for (Contact familyContact : [
            SELECT Id, Name, Email, AccountId, Relationship_Type__c, Emergency_Opt_In__c
            FROM Contact
            WHERE AccountId IN :residentAccountIds
              AND Emergency_Opt_In__c = true
              AND Relationship_Type__c IN ('Primary Contact', 'Secondary Backup')
            ORDER BY CreatedDate ASC
        ]) {
            if (!contactsByAccount.containsKey(familyContact.AccountId)) {
                contactsByAccount.put(familyContact.AccountId, new List<Contact>());
            }
            contactsByAccount.get(familyContact.AccountId).add(familyContact);
        }

        List<Communication_Log__c> logsToInsert = new List<Communication_Log__c>();
        for (Critical_Event__c eventRecord : eventById.values()) {
            Contact primaryContact = resolveContact(contactsByAccount.get(eventRecord.Client_Account__c), 'Primary Contact');
            if (primaryContact == null) {
                continue;
            }

            String channel = resolveChannel(eventRecord.Client_Account__r.CareOrch_Preferred_Notification_Method__c);
            logsToInsert.add(buildLog(eventRecord, primaryContact, channel, eventRecord.Assigned_To__c));
            sendDispatchMessage(eventRecord, primaryContact, channel, false);

            Datetime escalateAt = System.now().addMinutes(CareOrchSlaThresholdService.getThresholdMinutes(eventRecord.Event_Category__c));
            System.schedule(
                buildScheduleName(eventRecord.Id),
                buildOneTimeCron(escalateAt),
                new CareOrchCriticalEventEscalationJob(eventRecord.Id)
            );
        }

        if (!logsToInsert.isEmpty()) {
            insert logsToInsert;
        }
    }

    public static void processEscalation(Id criticalEventId) {
        if (criticalEventId == null) {
            return;
        }

        List<AggregateResult> ackCounts = [
            SELECT COUNT(Id) total
            FROM Communication_Log__c
            WHERE Critical_Event__c = :criticalEventId
              AND Acknowledged__c = true
        ];
        Integer acknowledged = ackCounts.isEmpty() ? 0 : Integer.valueOf(ackCounts[0].get('total'));
        if (acknowledged > 0) {
            return;
        }

        Critical_Event__c eventRecord = [
            SELECT Id, Name, Status__c, Client_Account__c, Client_Account__r.Name,
                   Client_Account__r.CareOrch_Preferred_Notification_Method__c,
                   Assigned_To__c, Assigned_To__r.ManagerId, Assigned_To__r.Manager.Email
            FROM Critical_Event__c
            WHERE Id = :criticalEventId
            LIMIT 1
        ];

        if (eventRecord.Status__c == 'Closed') {
            return;
        }

        List<Contact> eligibleContacts = [
            SELECT Id, Name, Email, Relationship_Type__c
            FROM Contact
            WHERE AccountId = :eventRecord.Client_Account__c
              AND Emergency_Opt_In__c = true
              AND Relationship_Type__c IN ('Primary Contact', 'Secondary Backup')
            ORDER BY CreatedDate ASC
        ];

        Contact secondaryContact = resolveContact(eligibleContacts, 'Secondary Backup');
        String channel = resolveChannel(eventRecord.Client_Account__r.CareOrch_Preferred_Notification_Method__c);
        List<Communication_Log__c> escalationLogs = new List<Communication_Log__c>();

        if (secondaryContact != null) {
            escalationLogs.add(buildLog(eventRecord, secondaryContact, channel, eventRecord.Assigned_To__c));
            sendDispatchMessage(eventRecord, secondaryContact, channel, true);
        }

        String managerEmail = eventRecord.Assigned_To__r == null || eventRecord.Assigned_To__r.Manager == null
            ? null
            : eventRecord.Assigned_To__r.Manager.Email;
        if (!String.isBlank(managerEmail)) {
            Messaging.SingleEmailMessage managerAlert = new Messaging.SingleEmailMessage();
            managerAlert.setToAddresses(new String[] { managerEmail });
            managerAlert.setSubject('Critical Event Escalation - SLA Breach Risk');
            managerAlert.setPlainTextBody(
                'Critical event ' + eventRecord.Name + ' for resident ' + eventRecord.Client_Account__r.Name +
                ' has no acknowledgement within SLA. Secondary dispatch has been triggered.'
            );
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { managerAlert });
        }

        if (!escalationLogs.isEmpty()) {
            insert escalationLogs;
        }

        update new Critical_Event__c(Id = eventRecord.Id, Status__c = 'Pending Review');
    }

    private static Communication_Log__c buildLog(
        Critical_Event__c eventRecord,
        Contact dispatchContact,
        String channel,
        Id assignedTo
    ) {
        return new Communication_Log__c(
            Critical_Event__c = eventRecord.Id,
            Contact__c = dispatchContact.Id,
            Assigned_To__c = assignedTo,
            Channel__c = channel,
            Dispatched_Timestamp__c = System.now(),
            Acknowledged__c = false,
            Status__c = 'Sent'
        );
    }

    private static Contact resolveContact(List<Contact> contacts, String relationshipType) {
        if (contacts == null) {
            return null;
        }

        for (Contact contactRecord : contacts) {
            if (contactRecord.Relationship_Type__c == relationshipType) {
                return contactRecord;
            }
        }
        return null;
    }

    private static void sendDispatchMessage(
        Critical_Event__c eventRecord,
        Contact familyContact,
        String channel,
        Boolean isEscalation
    ) {
        if (String.isBlank(familyContact.Email)) {
            return;
        }

        String subjectPrefix = isEscalation ? '[Escalated]' : '[Initial Dispatch]';
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setToAddresses(new String[] { familyContact.Email });
        message.setSubject(subjectPrefix + ' Critical Event Notification');
        message.setPlainTextBody(
            'Hello ' + familyContact.Name + ',\n\n' +
            'A critical event was logged for ' + eventRecord.Client_Account__r.Name + '.\n' +
            'Dispatch channel preference: ' + channel + '\n' +
            'Event reference: ' + eventRecord.Name + '\n\n' +
            'Please acknowledge this message with the care team.'
        );
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { message });
    }

    private static String resolveChannel(String preferredChannel) {
        if (preferredChannel == 'SMS' || preferredChannel == 'Voice' || preferredChannel == 'Email') {
            return preferredChannel;
        }
        return 'Voice';
    }

    private static String buildScheduleName(Id eventId) {
        String base = 'CareOrchCriticalEventEscalation_' + String.valueOf(eventId);
        if (base.length() > 80) {
            return base.substring(0, 80);
        }
        return base;
    }

    private static String buildOneTimeCron(Datetime executeAt) {
        return String.format(
            '{0} {1} {2} {3} {4} ? {5}',
            new List<String>{
                String.valueOf(executeAt.second()),
                String.valueOf(executeAt.minute()),
                String.valueOf(executeAt.hour()),
                String.valueOf(executeAt.day()),
                String.valueOf(executeAt.month()),
                String.valueOf(executeAt.year())
            }
        );
    }
}
