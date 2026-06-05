@IsTest
private inherited sharing class CareOrchManagerCockpitControllerTest {
    @TestSetup
    static void setupData() {
        Account resident = new Account(
            Name = 'Cockpit Resident',
            CareOrch_Preferred_Notification_Method__c = 'Voice'
        );
        insert resident;

        insert new Contact(
            LastName = 'Cockpit Primary',
            AccountId = resident.Id,
            Relationship_Type__c = 'Primary Contact',
            Emergency_Opt_In__c = true,
            Email = 'cockpit.primary@example.com'
        );

        Task atRiskShift = new Task(
            OwnerId = UserInfo.getUserId(),
            Subject = 'At risk shift',
            Status = 'Not Started',
            Priority = 'Normal',
            ActivityDate = Date.today(),
            WhatId = resident.Id,
            CareOrch_Shift_Start__c = System.now().addMinutes(-50),
            CareOrch_Shift_End__c = System.now().addMinutes(20),
            CareOrch_Shift_Status__c = 'Pending',
            CareOrch_At_Risk__c = true,
            CareOrch_At_Risk_Reason__c = 'High rejection streak'
        );
        insert atRiskShift;

        Critical_Event__c breachEvent = new Critical_Event__c(
            Client_Account__c = resident.Id,
            Event_Category__c = 'Death',
            Status__c = 'Open',
            Assigned_To__c = UserInfo.getUserId(),
            Critical_Event_Taxonomy__c = 'Fall',
            Observation_Type__c = 'Behavioral',
            Behavioral_Notes__c = 'Initial manager cockpit test note'
        );
        insert breachEvent;
        Test.setCreatedDate(breachEvent.Id, System.now().addMinutes(-25));

        insert new Communication_Log__c(
            Critical_Event__c = breachEvent.Id,
            Contact__c = [SELECT Id FROM Contact WHERE AccountId = :resident.Id LIMIT 1].Id,
            Assigned_To__c = UserInfo.getUserId(),
            Channel__c = 'Voice',
            Status__c = 'Sent',
            Acknowledged__c = false,
            Dispatched_Timestamp__c = System.now().addMinutes(-25)
        );

    }

    @IsTest
    static void snapshotReturnsCountsAndTrend() {
        Test.startTest();
        CareOrchManagerCockpitController.Snapshot snapshot = CareOrchManagerCockpitController.getSnapshot();
        List<Critical_Event__c> criticalRows =
            CareOrchManagerCockpitController.getCriticalSlaBreachRows(20);
        List<Task> shiftRows =
            CareOrchManagerCockpitController.getAtRiskShiftRows(20);
        List<CareObservation> translationRows =
            CareOrchManagerCockpitController.getPendingTranslationRows(20);
        Test.stopTest();

        System.assert(snapshot.criticalSlaBreaches > 0, 'Expected at least one critical SLA breach.');
        System.assert(snapshot.atRiskShifts > 0, 'Expected at least one at-risk shift.');
        System.assert(snapshot.pendingTranslationReviews >= 0, 'Expected non-negative translation review count.');
        System.assertEquals(7, snapshot.trend.size(), 'Expected seven trend points.');
        System.assertEquals(5, snapshot.casePriority.size(), 'Expected five chart buckets for case priority.');
        System.assert(!criticalRows.isEmpty());
        System.assert(!shiftRows.isEmpty());
        System.assertNotEquals(null, translationRows);
    }

    @IsTest
    static void saveRowsPersistsInlineOverrides() {
        Task shiftTask = [
            SELECT Id, CareOrch_At_Risk__c, CareOrch_At_Risk_Reason__c
            FROM Task
            WHERE Subject = 'At risk shift'
            LIMIT 1
        ];

        String shiftDraft = JSON.serialize(new List<Map<String, Object>>{
            new Map<String, Object>{
                'Id' => shiftTask.Id,
                'CareOrch_At_Risk__c' => false,
                'CareOrch_At_Risk_Reason__c' => 'Manager override'
            }
        });

        Test.startTest();
        CareOrchManagerCockpitController.saveRows('shifts', shiftDraft);
        Test.stopTest();

        Task refreshedShift = [
            SELECT CareOrch_At_Risk__c, CareOrch_At_Risk_Reason__c
            FROM Task
            WHERE Id = :shiftTask.Id
            LIMIT 1
        ];
        System.assertEquals(false, refreshedShift.CareOrch_At_Risk__c);
        System.assertEquals('Manager override', refreshedShift.CareOrch_At_Risk_Reason__c);

    }

    @IsTest
    static void logPhoneOverrideCreatesCommunicationEntry() {
        Critical_Event__c eventRecord = [
            SELECT Id
            FROM Critical_Event__c
            WHERE Critical_Event_Taxonomy__c = 'Fall'
            LIMIT 1
        ];

        Integer beforeCount = [
            SELECT COUNT()
            FROM Communication_Log__c
            WHERE Critical_Event__c = :eventRecord.Id
        ];

        Test.startTest();
        Id createdLogId = CareOrchManagerCockpitController.logPhoneOverride(eventRecord.Id);
        Test.stopTest();

        Integer afterCount = [
            SELECT COUNT()
            FROM Communication_Log__c
            WHERE Critical_Event__c = :eventRecord.Id
        ];
        System.assertNotEquals(null, createdLogId);
        System.assert(afterCount > beforeCount, 'Expected override action to add a communication log.');
    }
}
