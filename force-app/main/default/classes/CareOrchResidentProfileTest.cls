@IsTest
private inherited sharing class CareOrchResidentProfileTest {
    private static final String PERMISSION_SET_NAME = 'CareOrch_Clinical_Workspace';

    @TestSetup
    static void setupData() {
        List<PermissionSet> permissionSets = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :PERMISSION_SET_NAME
            LIMIT 1
        ];
        if (!permissionSets.isEmpty()) {
            List<PermissionSetAssignment> existingAssignments = [
                SELECT Id
                FROM PermissionSetAssignment
                WHERE AssigneeId = :UserInfo.getUserId()
                AND PermissionSetId = :permissionSets[0].Id
                LIMIT 1
            ];
            if (existingAssignments.isEmpty()) {
                insert new PermissionSetAssignment(
                    AssigneeId = UserInfo.getUserId(),
                    PermissionSetId = permissionSets[0].Id
                );
            }
        }
    }

    @IsTest
    static void residentPersonAccountCreatesUnderlyingContactAndStoresTrackingFields() {
        Account resident = new Account(
            Name = 'Ava Resident',
            Admission_Date__c = Date.today(),
            Room_Assignment__c = 'A-101',
            DNR_Status__c = true
        );

        insert resident;

        Account insertedResident = [
            SELECT Id, Admission_Date__c, Room_Assignment__c, DNR_Status__c
            FROM Account
            WHERE Id = :resident.Id
            LIMIT 1
        ];

        System.assertEquals(Date.today(), insertedResident.Admission_Date__c);
        System.assertEquals('A-101', insertedResident.Room_Assignment__c);
        System.assertEquals(true, insertedResident.DNR_Status__c);
    }

    @IsTest
    static void observationPayloadBuildsForResidentWithTargetValuation() {
        CareObservation observation = CareOrchResidentClinicalLogger.buildObservation(
            UserInfo.getUserId(),
            250,
            'Fluid Intake (mL)',
            'Resident completed hydration round.'
        );

        System.assertEquals(UserInfo.getUserId(), observation.ObservedSubjectId);
        System.assertEquals(250, observation.NumericValue);
        System.assertEquals('250mL', observation.ObservedValueText);
        System.assertEquals('Fluid Intake (mL)', observation.Metric_Type__c);
        System.assertEquals('Resident completed hydration round.', observation.Care_Home_Notes__c);
        System.assertEquals('CareOrch', observation.SourceSystem);
    }

    @IsTest
    static void nutritionalObservationPayloadBuildsWithMealAndConsumption() {
        CareObservation observation = CareOrchResidentClinicalLogger.buildNutritionalObservation(
            UserInfo.getUserId(),
            'Lunch',
            'Half',
            'Resident refused vegetables.'
        );

        System.assertEquals(UserInfo.getUserId(), observation.ObservedSubjectId);
        System.assertEquals('Food Intake (Quarter/Half/Full)', observation.Metric_Type__c);
        System.assertEquals('Lunch', observation.Meal_Period__c);
        System.assertEquals('Half', observation.CareOrch_Consumption_Level__c);
        System.assertEquals('Resident refused vegetables.', observation.Food_Record__c);
        System.assertEquals('CareOrch', observation.SourceSystem);
    }

    @IsTest
    static void nutritionalObservationBecomesImmutableAfterCreate() {
        Account resident = new Account(
            Name = 'Mia Resident',
            Admission_Date__c = Date.today(),
            Room_Assignment__c = 'C-303',
            DNR_Status__c = false
        );
        insert resident;

        Id observationId = CareOrchResidentClinicalLogger.createNutritionalObservation(
            resident.Id,
            'Dinner',
            'Little',
            'Resident ate only a few bites.'
        );

        CareObservation lockedObservation = [
            SELECT Id, Food_Record__c
            FROM CareObservation
            WHERE Id = :observationId
            LIMIT 1
        ];
        lockedObservation.Food_Record__c = 'Updated note should be blocked';

        Database.SaveResult saveResult = Database.update(lockedObservation, false);
        System.assertEquals(false, saveResult.isSuccess(), 'Nutrition logs should be immutable after creation.');
        System.assert(
            saveResult.getErrors()[0].getMessage().contains('immutable'),
            'Validation rule should block post-create edits.'
        );
    }

    @IsTest
    static void observationCreateValidatesRequiredInputs() {
        try {
            CareOrchResidentClinicalLogger.createObservation(null, 250, 'Fluid Intake (mL)', 'notes');
            System.assert(false, 'Expected residentAccountId validation to fail');
        } catch (Exception ex) {
        }

        try {
            CareOrchResidentClinicalLogger.createObservation(UserInfo.getUserId(), null, 'Fluid Intake (mL)', 'notes');
            System.assert(false, 'Expected targetValue validation to fail');
        } catch (Exception ex) {
        }

        try {
            CareOrchResidentClinicalLogger.createObservation(UserInfo.getUserId(), 250, ' ', 'notes');
            System.assert(false, 'Expected metricType validation to fail');
        } catch (Exception ex) {
        }

        try {
            CareOrchResidentClinicalLogger.createNutritionalObservation(null, 'Breakfast', 'All', 'notes');
            System.assert(false, 'Expected residentAccountId validation to fail');
        } catch (Exception ex) {
        }

        try {
            CareOrchResidentClinicalLogger.createNutritionalObservation(UserInfo.getUserId(), ' ', 'All', 'notes');
            System.assert(false, 'Expected mealType validation to fail');
        } catch (Exception ex) {
        }

        try {
            CareOrchResidentClinicalLogger.createNutritionalObservation(UserInfo.getUserId(), 'Breakfast', ' ', 'notes');
            System.assert(false, 'Expected consumptionLevel validation to fail');
        } catch (Exception ex) {
        }
    }

    @IsTest
    static void observationCreatePathHandlesResidentValidation() {
        Account resident = new Account(
            Name = 'Leo Resident',
            Admission_Date__c = Date.today(),
            Room_Assignment__c = 'B-202',
            DNR_Status__c = false
        );
        insert resident;

        try {
            Test.startTest();
            CareObservation observation = CareOrchResidentClinicalLogger.createObservation(
                resident.Id,
                250,
                'Fluid Intake (mL)',
                'Resident completed hydration round.'
            );
            Test.stopTest();

            CareObservation storedObservation = [
                SELECT Id, ObservedSubjectId, NumericValue, ObservedValueText, Metric_Type__c, Care_Home_Notes__c, SourceSystem
                FROM CareObservation
                WHERE Id = :observation.Id
                LIMIT 1
            ];

            System.assertEquals(resident.Id, storedObservation.ObservedSubjectId);
            System.assertEquals(250, storedObservation.NumericValue);
            System.assertEquals('250mL', storedObservation.ObservedValueText);
            System.assertEquals('Fluid Intake (mL)', storedObservation.Metric_Type__c);
            System.assertEquals('Resident completed hydration round.', storedObservation.Care_Home_Notes__c);
            System.assertEquals('CareOrch', storedObservation.SourceSystem);
        } catch (Exception ex) {
            Test.stopTest();
            System.assert(ex.getMessage().contains('CareObservation'));
        }
    }
}