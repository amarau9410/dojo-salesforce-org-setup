@IsTest
private inherited sharing class CareOrchCriticalEventWorkflowTest {
    @TestSetup
    static void setupData() {
        Account resident = new Account(
            Name = 'Critical Event Resident',
            CareOrch_Preferred_Notification_Method__c = 'Voice'
        );
        insert resident;

        insert new List<Contact>{
            new Contact(
                LastName = 'Primary Family',
                AccountId = resident.Id,
                Email = 'primary.family@example.com',
                Relationship_Type__c = 'Primary Contact',
                Emergency_Opt_In__c = true
            ),
            new Contact(
                LastName = 'Secondary Family',
                AccountId = resident.Id,
                Email = 'secondary.family@example.com',
                Relationship_Type__c = 'Secondary Backup',
                Emergency_Opt_In__c = true
            )
        };

        insert new Task(
            OwnerId = UserInfo.getUserId(),
            Subject = 'Active Shift Context',
            Status = 'Not Started',
            Priority = 'Normal',
            ActivityDate = Date.today(),
            WhatId = resident.Id,
            CareOrch_Shift_Start__c = System.now().addMinutes(-15),
            CareOrch_Shift_End__c = System.now().addMinutes(45)
        );
    }

    @IsTest
    static void incidentControllerCreatesEventWithShiftContext() {
        Account resident = [
            SELECT Id
            FROM Account
            WHERE Name = 'Critical Event Resident'
            LIMIT 1
        ];

        Test.startTest();
        CareOrchCriticalIncidentController.IncidentContext context =
            CareOrchCriticalIncidentController.getIncidentContext();
        CareOrchCriticalIncidentController.IncidentResult result =
            CareOrchCriticalIncidentController.createIncident('Fall', 51.501, -0.141);
        Test.stopTest();

        System.assertNotEquals(null, context.shiftTaskId);
        System.assertEquals(resident.Id, context.residentAccountId);
        System.assertNotEquals(null, result.criticalEventId);

        Critical_Event__c createdEvent = [
            SELECT Client_Account__c, Event_Category__c, Status__c, Assigned_To__c,
                   Critical_Event_Taxonomy__c, Active_Shift_Task_Id__c,
                   Incident_Location__Latitude__s, Incident_Location__Longitude__s
            FROM Critical_Event__c
            WHERE Id = :result.criticalEventId
            LIMIT 1
        ];

        System.assertEquals(resident.Id, createdEvent.Client_Account__c);
        System.assertEquals('Other', createdEvent.Event_Category__c);
        System.assert(
            new Set<String>{ 'Open', 'Pending Review' }.contains(createdEvent.Status__c),
            'Expected status to remain Open or move to Pending Review after scheduled escalation.'
        );
        System.assertEquals(UserInfo.getUserId(), createdEvent.Assigned_To__c);
        System.assertEquals('Fall', createdEvent.Critical_Event_Taxonomy__c);
        System.assertNotEquals(null, createdEvent.Active_Shift_Task_Id__c);
        System.assertNotEquals(null, createdEvent.Incident_Location__Latitude__s);
        System.assertNotEquals(null, createdEvent.Incident_Location__Longitude__s);
    }

    @IsTest
    static void triggerCreatesInitialCommunicationLog() {
        Account resident = [
            SELECT Id
            FROM Account
            WHERE Name = 'Critical Event Resident'
            LIMIT 1
        ];

        Test.startTest();
        insert new Critical_Event__c(
            Client_Account__c = resident.Id,
            Event_Category__c = 'Other',
            Status__c = 'Open',
            Assigned_To__c = UserInfo.getUserId(),
            Critical_Event_Taxonomy__c = 'Medication Error'
        );
        Test.stopTest();

        Integer logCount = [
            SELECT COUNT()
            FROM Communication_Log__c
            WHERE Critical_Event__r.Client_Account__c = :resident.Id
        ];
        System.assert(logCount > 0, 'Expected at least one communication log for critical event dispatch.');
    }

    @IsTest
    static void escalationAddsSecondaryDispatchWhenUnacknowledged() {
        Account resident = [
            SELECT Id
            FROM Account
            WHERE Name = 'Critical Event Resident'
            LIMIT 1
        ];

        Critical_Event__c eventRecord = new Critical_Event__c(
            Client_Account__c = resident.Id,
            Event_Category__c = 'Other',
            Status__c = 'Open',
            Assigned_To__c = UserInfo.getUserId(),
            Critical_Event_Taxonomy__c = 'Serious Injury'
        );
        insert eventRecord;

        Integer beforeCount = [
            SELECT COUNT()
            FROM Communication_Log__c
            WHERE Critical_Event__c = :eventRecord.Id
        ];

        Test.startTest();
        CareOrchCriticalEventDispatchService.processEscalation(eventRecord.Id);
        Test.stopTest();

        Integer afterCount = [
            SELECT COUNT()
            FROM Communication_Log__c
            WHERE Critical_Event__c = :eventRecord.Id
        ];
        System.assert(afterCount > beforeCount, 'Expected escalation to add another communication log.');

        Critical_Event__c updatedEvent = [
            SELECT Status__c
            FROM Critical_Event__c
            WHERE Id = :eventRecord.Id
            LIMIT 1
        ];
        System.assertEquals('Pending Review', updatedEvent.Status__c);
    }

    @IsTest
    static void escalationSkipsWhenAlreadyAcknowledged() {
        Account resident = [
            SELECT Id
            FROM Account
            WHERE Name = 'Critical Event Resident'
            LIMIT 1
        ];

        Critical_Event__c eventRecord = new Critical_Event__c(
            Client_Account__c = resident.Id,
            Event_Category__c = 'Other',
            Status__c = 'Open',
            Assigned_To__c = UserInfo.getUserId(),
            Critical_Event_Taxonomy__c = 'Fall'
        );
        insert eventRecord;

        Communication_Log__c initialLog = [
            SELECT Id, Status__c, Acknowledged__c
            FROM Communication_Log__c
            WHERE Critical_Event__c = :eventRecord.Id
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        initialLog.Acknowledged__c = true;
        initialLog.Status__c = 'Acknowledged';
        update initialLog;

        Integer beforeCount = [
            SELECT COUNT()
            FROM Communication_Log__c
            WHERE Critical_Event__c = :eventRecord.Id
        ];

        Test.startTest();
        CareOrchCriticalEventDispatchService.processEscalation(eventRecord.Id);
        Test.stopTest();

        Integer afterCount = [
            SELECT COUNT()
            FROM Communication_Log__c
            WHERE Critical_Event__c = :eventRecord.Id
        ];
        System.assertEquals(beforeCount, afterCount);

        Critical_Event__c refreshedEvent = [
            SELECT Status__c
            FROM Critical_Event__c
            WHERE Id = :eventRecord.Id
            LIMIT 1
        ];
        System.assertEquals('Open', refreshedEvent.Status__c);
    }

    @IsTest
    static void closingIncidentWithoutAcknowledgementIsBlocked() {
        Account resident = [
            SELECT Id
            FROM Account
            WHERE Name = 'Critical Event Resident'
            LIMIT 1
        ];

        Critical_Event__c eventRecord = new Critical_Event__c(
            Client_Account__c = resident.Id,
            Event_Category__c = 'Other',
            Status__c = 'Open',
            Assigned_To__c = UserInfo.getUserId(),
            Critical_Event_Taxonomy__c = 'Fall'
        );
        insert eventRecord;

        eventRecord.Status__c = 'Closed';
        try {
            update eventRecord;
            System.assert(false, 'Expected close operation to be blocked without acknowledged communication evidence.');
        } catch (DmlException ex) {
            System.assert(
                ex.getMessage().contains('cannot be closed until an outbound communication log has been marked as Acknowledged'),
                'Expected closed-loop acknowledgement validation error but got: ' + ex.getMessage()
            );
        }
    }
}
