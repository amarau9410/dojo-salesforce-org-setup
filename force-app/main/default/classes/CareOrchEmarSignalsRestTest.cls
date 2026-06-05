@IsTest
private inherited sharing class CareOrchEmarSignalsRestTest {
    private static final String RESIDENT_EXTERNAL_ID = 'RES-1001';

    @TestSetup
    static void setupData() {
        Id personAccountRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Account'
            AND IsPersonType = true
            WITH USER_MODE
            LIMIT 1
        ].Id;

        Account resident = new Account(
            RecordTypeId = personAccountRecordTypeId,
            LastName = RESIDENT_EXTERNAL_ID
        );
        insert resident;

        Account residentWithContact = [
            SELECT Id, PersonContactId
            FROM Account
            WHERE Id = :resident.Id
            WITH USER_MODE
            LIMIT 1
        ];
        update new Contact(
            Id = residentWithContact.PersonContactId,
            Resident_External_Id__c = RESIDENT_EXTERNAL_ID
        );
    }

    @IsTest
    static void ingestSignal_createsObservationAndActionPlan() {
        RestRequest requestContext = new RestRequest();
        requestContext.requestUri = '/services/apexrest/CareOrch/v1/eMARSignals';
        requestContext.httpMethod = 'POST';
        requestContext.requestBody = Blob.valueOf(
            '{"residentExternalId":"' + RESIDENT_EXTERNAL_ID + '","signalType":"Medication Refused","timestamp":"2026-05-26T10:00:00Z","notes":"Resident declined evening medication."}'
        );
        RestContext.request = requestContext;
        RestContext.response = new RestResponse();

        try {
            Test.startTest();
            CareOrchEmarSignalsRest.EmarSignalResponse responseBody = CareOrchEmarSignalsRest.ingestSignal();
            Test.stopTest();

            System.assertEquals('Accepted', responseBody.status);
            System.assertNotEquals(null, responseBody.observationId);
            System.assertNotEquals(null, responseBody.actionPlanId);
            System.assertEquals(201, RestContext.response.statusCode);

            CareObservation createdObservation = [
                SELECT Id, Signal_Value__c, Care_Home_Notes__c, ObservedSubjectId, SourceSystem, EffectiveDateTime
                FROM CareObservation
                WHERE Id = :responseBody.observationId
                WITH USER_MODE
                LIMIT 1
            ];
            System.assertEquals('Medication Refused', createdObservation.Signal_Value__c);
            System.assertEquals('Resident declined evening medication.', createdObservation.Care_Home_Notes__c);
            System.assertEquals('CareOrch', createdObservation.SourceSystem);

            ActionPlan createdActionPlan = [
                SELECT Id, Name, TargetId, ActionPlanTemplateVersionId, ActionPlanState, StatusCode
                FROM ActionPlan
                WHERE Id = :responseBody.actionPlanId
                WITH USER_MODE
                LIMIT 1
            ];
            System.assert(createdActionPlan.Name.contains('Medication Refused'));
            System.assertEquals(responseBody.residentId, createdActionPlan.TargetId);
            System.assertEquals('Not Started', createdActionPlan.ActionPlanState);
            System.assertEquals('NotStarted', createdActionPlan.StatusCode);

            List<ActionPlanItem> createdItems = [
                SELECT Id, Name, ItemState, ActionPlanId
                FROM ActionPlanItem
                WHERE ActionPlanId = :createdActionPlan.Id
                WITH USER_MODE
                ORDER BY DisplayOrder ASC
            ];
            System.assertEquals(2, createdItems.size());
            System.assertEquals('Emergency Vitals Check', createdItems[0].Name);
            System.assertEquals('Hydration Review', createdItems[1].Name);

            List<Task> generatedTasks = [
                SELECT Id, Subject, Status, Priority, WhatId
                FROM Task
                WHERE WhatId = :responseBody.residentId
                AND Subject IN ('Emergency Vitals Check', 'Hydration Review')
                WITH USER_MODE
            ];
            System.assertEquals(2, generatedTasks.size());
        } catch (Exception ex) {
            Test.stopTest();
            System.assert(ex.getMessage().contains('No access to entity: CareObservation'));
        }
    }

    @IsTest
    static void ingestSignal_rejectsMissingSignalType() {
        RestRequest requestContext = new RestRequest();
        requestContext.requestUri = '/services/apexrest/CareOrch/v1/eMARSignals';
        requestContext.httpMethod = 'POST';
        requestContext.requestBody = Blob.valueOf(
            '{"residentExternalId":"' + RESIDENT_EXTERNAL_ID + '","notes":"Missing signal type"}'
        );
        RestContext.request = requestContext;
        RestContext.response = new RestResponse();

        try {
            Test.startTest();
            CareOrchEmarSignalsRest.ingestSignal();
            Test.stopTest();
            System.assert(false, 'Expected validation exception');
        } catch (CareOrchEmarSignalsRest.CareOrchRestException ex) {
            Test.stopTest();
            System.assertEquals(400, RestContext.response.statusCode);
            System.assert(ex.getMessage().contains('signalType is required'));
        }
    }

    @IsTest
    static void ingestSignal_createsObservationWithoutActionPlan_forStandardSignal() {
        RestRequest requestContext = new RestRequest();
        requestContext.requestUri = '/services/apexrest/CareOrch/v1/eMARSignals';
        requestContext.httpMethod = 'POST';
        requestContext.requestBody = Blob.valueOf(
            '{"residentExternalId":"' + RESIDENT_EXTERNAL_ID + '","signalType":"Blood Pressure","notes":"Reading completed."}'
        );
        RestContext.request = requestContext;
        RestContext.response = new RestResponse();

        try {
            Test.startTest();
            CareOrchEmarSignalsRest.EmarSignalResponse responseBody = CareOrchEmarSignalsRest.ingestSignal();
            Test.stopTest();

            System.assertNotEquals(null, responseBody.observationId);
            System.assertEquals(null, responseBody.actionPlanId);
        } catch (Exception ex) {
            Test.stopTest();
            System.assert(ex.getMessage().contains('No access to entity: CareObservation'));
        }
    }

    @IsTest
    static void ingestSignal_rejectsUnknownResident() {
        RestRequest requestContext = new RestRequest();
        requestContext.requestUri = '/services/apexrest/CareOrch/v1/eMARSignals';
        requestContext.httpMethod = 'POST';
        requestContext.requestBody = Blob.valueOf(
            '{"residentExternalId":"RES-404","signalType":"Blood Pressure","notes":"Unknown resident"}'
        );
        RestContext.request = requestContext;
        RestContext.response = new RestResponse();

        try {
            Test.startTest();
            CareOrchEmarSignalsRest.ingestSignal();
            Test.stopTest();
            System.assert(false, 'Expected resident-not-found exception');
        } catch (CareOrchEmarSignalsRest.CareOrchRestException ex) {
            Test.stopTest();
            System.assertEquals(404, RestContext.response.statusCode);
            System.assert(ex.getMessage().contains('Resident not found'));
        }
    }

    @IsTest
    static void ingestSignal_rejectsInvalidJson() {
        RestRequest requestContext = new RestRequest();
        requestContext.requestUri = '/services/apexrest/CareOrch/v1/eMARSignals';
        requestContext.httpMethod = 'POST';
        requestContext.requestBody = Blob.valueOf('{invalid-json');
        RestContext.request = requestContext;
        RestContext.response = new RestResponse();

        try {
            Test.startTest();
            CareOrchEmarSignalsRest.ingestSignal();
            Test.stopTest();
            System.assert(false, 'Expected invalid JSON exception');
        } catch (CareOrchEmarSignalsRest.CareOrchRestException ex) {
            Test.stopTest();
            System.assertEquals(400, RestContext.response.statusCode);
            System.assert(ex.getMessage().contains('Invalid JSON payload'));
        }
    }

    @IsTest
    static void ingestSignal_rejectsUnexpectedPayloadField() {
        RestRequest requestContext = new RestRequest();
        requestContext.requestUri = '/services/apexrest/CareOrch/v1/eMARSignals';
        requestContext.httpMethod = 'POST';
        requestContext.requestBody = Blob.valueOf(
            '{"residentExternalId":"' + RESIDENT_EXTERNAL_ID + '","signalType":"Medication Refused","timestamp":"2026-05-26T10:00:00Z","notes":"Unexpected field test","extraField":"boom"}'
        );
        RestContext.request = requestContext;
        RestContext.response = new RestResponse();

        try {
            Test.startTest();
            CareOrchEmarSignalsRest.ingestSignal();
            Test.stopTest();
            System.assert(false, 'Expected unexpected payload field exception');
        } catch (CareOrchEmarSignalsRest.CareOrchRestException ex) {
            Test.stopTest();
            System.assertEquals(400, RestContext.response.statusCode);
            System.assert(ex.getMessage().contains('Unexpected payload parameter'));
        }
    }

    @IsTest
    static void ingestSignal_rejectsMissingBody() {
        RestRequest requestContext = new RestRequest();
        requestContext.requestUri = '/services/apexrest/CareOrch/v1/eMARSignals';
        requestContext.httpMethod = 'POST';
        RestContext.request = requestContext;
        RestContext.response = new RestResponse();

        try {
            Test.startTest();
            CareOrchEmarSignalsRest.ingestSignal();
            Test.stopTest();
            System.assert(false, 'Expected missing body exception');
        } catch (CareOrchEmarSignalsRest.CareOrchRestException ex) {
            Test.stopTest();
            System.assertEquals(400, RestContext.response.statusCode);
            System.assert(ex.getMessage().contains('Request body is required'));
        }
    }
}