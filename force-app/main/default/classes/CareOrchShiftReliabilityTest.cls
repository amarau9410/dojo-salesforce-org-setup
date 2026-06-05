@IsTest
private inherited sharing class CareOrchShiftReliabilityTest {
    @TestSetup
    static void setupData() {
        Account contextAccount = new Account(Name = 'Shift Reliability Resident');
        insert contextAccount;
    }

    @IsTest
    static void acceptanceCapturesResponseAndFillMetrics() {
        Account contextAccount = [
            SELECT Id
            FROM Account
            WHERE Name = 'Shift Reliability Resident'
            LIMIT 1
        ];

        Task shiftTask = new Task(
            OwnerId = UserInfo.getUserId(),
            Subject = 'Reliability acceptance test',
            Status = 'Not Started',
            Priority = 'Normal',
            ActivityDate = Date.today(),
            WhatId = contextAccount.Id,
            CareOrch_Shift_Start__c = System.now().addMinutes(-90),
            CareOrch_Shift_End__c = System.now().addMinutes(30),
            CareOrch_Shift_Status__c = 'Pending'
        );
        insert shiftTask;

        Test.startTest();
        CareOrchShiftAssignmentService.notifyManagerForAcceptance(shiftTask.Id, UserInfo.getUserId());
        Test.stopTest();

        Task stored = [
            SELECT CareOrch_Shift_Status__c,
                   CareOrch_First_Response_At__c,
                   CareOrch_Filled_At__c,
                   CareOrch_Time_to_First_Response_Minutes__c,
                   CareOrch_Time_to_Fill_Minutes__c
            FROM Task
            WHERE Id = :shiftTask.Id
            LIMIT 1
        ];

        System.assertEquals('Accepted', stored.CareOrch_Shift_Status__c);
        System.assertNotEquals(null, stored.CareOrch_First_Response_At__c);
        System.assertNotEquals(null, stored.CareOrch_Filled_At__c);
        System.assertNotEquals(null, stored.CareOrch_Time_to_First_Response_Minutes__c);
        System.assertNotEquals(null, stored.CareOrch_Time_to_Fill_Minutes__c);
        System.assert(stored.CareOrch_Time_to_Fill_Minutes__c >= stored.CareOrch_Time_to_First_Response_Minutes__c);
    }

    @IsTest
    static void repeatedRejectionsFlagShiftAsAtRisk() {
        Account contextAccount = [
            SELECT Id
            FROM Account
            WHERE Name = 'Shift Reliability Resident'
            LIMIT 1
        ];

        Task shiftTask = new Task(
            OwnerId = UserInfo.getUserId(),
            Subject = 'Reliability rejection test',
            Status = 'Not Started',
            Priority = 'Normal',
            ActivityDate = Date.today(),
            WhatId = contextAccount.Id,
            CareOrch_Shift_Start__c = System.now().addMinutes(-45),
            CareOrch_Shift_End__c = System.now().addMinutes(60),
            CareOrch_Shift_Status__c = 'Pending',
            CareOrch_Contacted_Caregiver_Ids__c = String.valueOf(UserInfo.getUserId()),
            CareOrch_Contacted_Count__c = 1,
            CareOrch_Rejected_Count__c = 1
        );
        insert shiftTask;

        Test.startTest();
        CareOrchShiftAssignmentService.rejectAndRouteToNextCaregiver(shiftTask.Id, UserInfo.getUserId());
        Test.stopTest();

        Task stored = [
            SELECT CareOrch_Shift_Status__c,
                   CareOrch_Rejected_Count__c,
                   CareOrch_At_Risk__c,
                   CareOrch_At_Risk_Reason__c,
                   CareOrch_First_Response_At__c,
                   CareOrch_Time_to_First_Response_Minutes__c
            FROM Task
            WHERE Id = :shiftTask.Id
            LIMIT 1
        ];

        System.assertEquals('Unfilled', stored.CareOrch_Shift_Status__c);
        System.assertEquals(2, Integer.valueOf(stored.CareOrch_Rejected_Count__c));
        System.assertEquals(true, stored.CareOrch_At_Risk__c);
        System.assert(stored.CareOrch_At_Risk_Reason__c != null && stored.CareOrch_At_Risk_Reason__c.contains('High rejection streak'));
        System.assertNotEquals(null, stored.CareOrch_First_Response_At__c);
        System.assertNotEquals(null, stored.CareOrch_Time_to_First_Response_Minutes__c);
    }
}
