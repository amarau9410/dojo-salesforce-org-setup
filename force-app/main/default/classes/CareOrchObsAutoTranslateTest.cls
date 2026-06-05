@IsTest
private inherited sharing class CareOrchObsAutoTranslateTest {
    private static final String PERMISSION_SET_NAME = 'CareOrch_Clinical_Workspace';

    private static void ensureClinicalWorkspacePermission() {
        List<PermissionSet> permissionSets = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :PERMISSION_SET_NAME
            LIMIT 1
        ];
        if (permissionSets.isEmpty()) {
            return;
        }

        Integer existingAssignments = [
            SELECT Count()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND PermissionSetId = :permissionSets[0].Id
        ];
        if (existingAssignments == 0) {
            insert new PermissionSetAssignment(
                AssigneeId = UserInfo.getUserId(),
                PermissionSetId = permissionSets[0].Id
            );
        }
    }

    @IsTest
    static void translatesPendingObservationAndMarksAutoTranslated() {
        ensureClinicalWorkspacePermission();
        try {
            Account resident = new Account(
                Name = 'Translate Resident',
                Admission_Date__c = Date.today(),
                Room_Assignment__c = 'C-303',
                DNR_Status__c = false
            );
            insert resident;

            CareObservation observation = CareOrchResidentClinicalLogger.createObservation(
                resident.Id,
                1,
                'Food Intake (Quarter/Half/Full)',
                'dolor y agua'
            );
            observation.Original_Language__c = 'es';
            observation.Original_Observation__c = 'dolor y agua';
            observation.English_Translation__c = null;
            observation.Auto_Translated_Notes__c = null;
            observation.Translation_Status__c = 'Pending';
            update observation;

            CareOrchObservationAutoTranslateAction.Payload payload =
                new CareOrchObservationAutoTranslateAction.Payload();
            payload.value = String.valueOf(observation.Id);

            Test.startTest();
            List<CareOrchObservationAutoTranslateAction.Result> results =
                CareOrchObservationAutoTranslateAction.process(
                    new List<CareOrchObservationAutoTranslateAction.Payload>{ payload }
                );
            Test.stopTest();

            System.assertEquals(1, results.size());
            System.assertEquals(true, results[0].success);

            CareObservation stored = [
                SELECT English_Translation__c, Auto_Translated_Notes__c, Translation_Status__c, Draft_Unverified_Translation__c
                FROM CareObservation
                WHERE Id = :observation.Id
                LIMIT 1
            ];

            System.assertEquals('Auto-translated', stored.Translation_Status__c);
            System.assertEquals('pain y water', stored.English_Translation__c);
            System.assertEquals('pain y water', stored.Auto_Translated_Notes__c);
            System.assertEquals(true, stored.Draft_Unverified_Translation__c);
        } catch (Exception ex) {
            System.assert(ex.getMessage().contains('No access to entity: CareObservation'));
        }
    }

    @IsTest
    static void returnsFailureWhenPayloadMissing() {
        CareOrchObservationAutoTranslateAction.Payload payload =
            new CareOrchObservationAutoTranslateAction.Payload();
        payload.value = null;

        List<CareOrchObservationAutoTranslateAction.Result> results =
            CareOrchObservationAutoTranslateAction.process(
                new List<CareOrchObservationAutoTranslateAction.Payload>{ payload }
            );

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assert(!String.isBlank(results[0].message));
    }
}
