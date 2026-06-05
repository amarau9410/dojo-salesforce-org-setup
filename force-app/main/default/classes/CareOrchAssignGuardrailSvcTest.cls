@IsTest
private class CareOrchAssignGuardrailSvcTest {
    private static Shift_Lifecycle__c createShift(Boolean secondCoverage) {
        Shift_Lifecycle__c shiftRow = new Shift_Lifecycle__c(
            Status__c = 'Pending',
            CareOrch_Second_Caregiver_Coverage__c = secondCoverage
        );
        insert shiftRow;
        return shiftRow;
    }

    private static Account createResident(String name, Boolean mobility, Boolean aggressive) {
        Account resident = new Account(
            Name = name,
            CareOrch_Mobility_Assistance_Required__c = mobility,
            CareOrch_Hyper_Aggressive_Behavior__c = aggressive
        );
        insert resident;
        return resident;
    }

    @IsTest
    static void blocksAggressiveResidentWithoutSecondCoverage() {
        Shift_Lifecycle__c shiftRow = createShift(false);
        Account aggressiveResident = createResident('Resident Aggressive', false, true);

        CareOrch_Resident_Assignment__c assignment = new CareOrch_Resident_Assignment__c(
            Shift_Task__c = shiftRow.Id,
            Resident_Account__c = aggressiveResident.Id,
            CareOrch_Assignment_Active__c = true
        );

        Test.startTest();
        Database.SaveResult saveResult = Database.insert(assignment, false);
        Test.stopTest();

        System.assertEquals(false, saveResult.isSuccess(), 'Insert should be blocked by lone-worker safeguard.');
        System.assert(saveResult.getErrors()[0].getMessage().contains('second caregiver coverage'));
    }

    @IsTest
    static void blocksWhenHighNeedsExceedsTwo() {
        Shift_Lifecycle__c shiftRow = createShift(true);

        List<CareOrch_Resident_Assignment__c> assignments = new List<CareOrch_Resident_Assignment__c>();
        for (Integer i = 0; i < 3; i++) {
            Account highNeedsResident = createResident('High Needs ' + i, true, false);
            assignments.add(new CareOrch_Resident_Assignment__c(
                Shift_Task__c = shiftRow.Id,
                Resident_Account__c = highNeedsResident.Id,
                CareOrch_Assignment_Active__c = true
            ));
        }

        Test.startTest();
        Database.SaveResult[] results = Database.insert(assignments, false);
        Test.stopTest();

        Integer successCount = 0;
        Integer failureCount = 0;
        for (Database.SaveResult result : results) {
            if (result.isSuccess()) {
                successCount++;
            } else {
                failureCount++;
                System.assert(result.getErrors()[0].getMessage().contains('maximum 2 high-needs'));
            }
        }

        System.assertEquals(2, successCount, 'Only two high-needs assignments should be accepted.');
        System.assertEquals(1, failureCount, 'Third high-needs assignment should be blocked.');
    }

    @IsTest
    static void rollupsAndWarningRefreshAfterSuccessfulAssignment() {
        Shift_Lifecycle__c shiftRow = createShift(true);
        Account resident = createResident('Resident Low Needs', false, false);

        insert new CareOrch_Resident_Assignment__c(
            Shift_Task__c = shiftRow.Id,
            Resident_Account__c = resident.Id,
            CareOrch_Assignment_Active__c = true
        );

        Shift_Lifecycle__c refreshed = [
            SELECT CareOrch_Assignment_Count__c, CareOrch_High_Needs_Count__c, CareOrch_Capacity_Risk_Warning__c
            FROM Shift_Lifecycle__c
            WHERE Id = :shiftRow.Id
            LIMIT 1
        ];

        System.assertEquals(1, Integer.valueOf(refreshed.CareOrch_Assignment_Count__c));
        System.assertEquals(0, Integer.valueOf(refreshed.CareOrch_High_Needs_Count__c));
        System.assertEquals(null, refreshed.CareOrch_Capacity_Risk_Warning__c);
    }
}
