@isTest
private class FieldTripWorkerApiTest {
    @isTest
    static void shouldClaimOnceAndRequireTokenForCompletion() {
        User worker = FieldTripRunTestDataFactory.createOperator(
            new List<String>{ 'Field_Trip_Automation_Worker' }
        );
        Field_Trip_Run__c run = createRequestedRun(worker.Id, 'worker-api-claim');

        System.runAs(worker) {
            Database.insert(run, AccessLevel.SYSTEM_MODE);
            FieldTripWorkerApi.WorkerResponse claimResponse = invoke(
                'claim',
                new Map<String, Object>{
                    'runId' => run.Id,
                    'allowedOperations' => new List<String>{ 'Generate Reports' }
                }
            );
            Assert.isTrue(claimResponse.success, 'The eligible run should be claimed');
            Assert.isTrue(claimResponse.claimed, 'The response should confirm ownership');
            Assert.isFalse(String.isBlank(claimResponse.claimToken),
                'A cryptographic ownership token should be returned');

            FieldTripWorkerApi.WorkerResponse duplicateResponse = invoke(
                'claim',
                new Map<String, Object>{
                    'runId' => run.Id,
                    'allowedOperations' => new List<String>{ 'Generate Reports' }
                }
            );
            Assert.areEqual(409, RestContext.response.statusCode,
                'A second worker must not claim a Processing run');
            Assert.isFalse(duplicateResponse.success, 'The duplicate claim should fail');

            FieldTripWorkerApi.WorkerResponse staleResponse = invoke(
                'complete',
                new Map<String, Object>{
                    'runId' => run.Id,
                    'claimToken' => 'not-the-issued-token',
                    'status' => 'Completed'
                }
            );
            Assert.areEqual(409, RestContext.response.statusCode,
                'A stale worker must not complete the run');
            Assert.isFalse(staleResponse.success, 'The stale completion should fail');

            FieldTripWorkerApi.WorkerResponse completeResponse = invoke(
                'complete',
                new Map<String, Object>{
                    'runId' => run.Id,
                    'claimToken' => claimResponse.claimToken,
                    'status' => 'Completed',
                    'outputFolderUrl' => 'https://example.com/field-trip/run'
                }
            );
            Assert.isTrue(completeResponse.success, 'The owning worker should complete the run');
        }

        Id completedRunId = run.Id;
        Field_Trip_Run__c completedRun = (Field_Trip_Run__c) Database.query(
            'SELECT Status__c, Completed_At__c, Output_Folder_URL__c, '
                + 'Idempotency_Key__c FROM Field_Trip_Run__c WHERE Id = :completedRunId',
            AccessLevel.SYSTEM_MODE
        );
        Assert.areEqual('Completed', completedRun.Status__c, 'The run should be terminal');
        Assert.isNotNull(completedRun.Completed_At__c, 'Completion time should be audited');
        Assert.isTrue(completedRun.Idempotency_Key__c.endsWith(':' + run.Id),
            'Completion should release the active idempotency key');
    }

    @isTest
    static void shouldEnforceEnvironmentGate_WhenRunIsNotProductionConfirmed() {
        User worker = FieldTripRunTestDataFactory.createOperator(
            new List<String>{ 'Field_Trip_Automation_Worker' }
        );
        Field_Trip_Run__c run = createRequestedRun(worker.Id, 'worker-unconfirmed');
        run.Confirmed_Production__c = false;
        Boolean isSandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
        FieldTripWorkerApi.WorkerResponse response;
        System.runAs(worker) {
            Database.insert(run, AccessLevel.SYSTEM_MODE);
            Test.startTest();
            response = invoke('claim', new Map<String, Object>{
                'runId' => run.Id,
                'allowedOperations' => new List<String>{ 'Generate Reports' }
            });
            Test.stopTest();
        }
        Assert.areEqual(isSandbox, response.success,
            'The worker must reject unconfirmed Production runs');
        Assert.areEqual(isSandbox, response.claimed,
            'Only a sandbox run may be claimed without Production confirmation');
        Field_Trip_Run__c storedRun = [
            SELECT Status__c, Claim_Token__c FROM Field_Trip_Run__c WHERE Id = :run.Id
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(isSandbox ? 'Processing' : 'Requested', storedRun.Status__c,
            'Rejection must leave the Production run unclaimed');
        if (!isSandbox) {
            Assert.areEqual(409, RestContext.response.statusCode,
                'Unconfirmed Production claims must return a conflict');
            Assert.areEqual('The production run is not explicitly confirmed.', response.message,
                'The rejection must identify missing Production confirmation');
            Assert.isNull(storedRun.Claim_Token__c,
                'A rejected Production claim must not issue an ownership token');
        }
    }

    @isTest
    static void shouldRejectCallerWithoutWorkerPermission() {
        User operatorUser = FieldTripRunTestDataFactory.createOperator(new List<String>());
        System.runAs(operatorUser) {
            FieldTripWorkerApi.WorkerResponse response = invoke(
                'claim',
                new Map<String, Object>{
                    'allowedOperations' => new List<String>{ 'Generate Reports' }
                }
            );
            Assert.areEqual(403, RestContext.response.statusCode,
                'The API must require its dedicated Custom Permission');
            Assert.isFalse(response.success, 'Unauthorized callers should be rejected');
        }
    }

    @isTest
    static void shouldRejectAnalyzeOperation_WhenWorkerClaimsRuns() {
        User worker = FieldTripRunTestDataFactory.createOperator(
            new List<String>{ 'Field_Trip_Automation_Worker' }
        );
        Field_Trip_Run__c run = createRequestedRun(worker.Id, 'worker-analyze-is-disabled');
        run.Operation__c = 'Analyze';
        System.runAs(worker) {
            Database.insert(run, AccessLevel.SYSTEM_MODE);
            FieldTripWorkerApi.WorkerResponse response = invoke(
                'claim',
                new Map<String, Object>{
                    'runId' => run.Id,
                    'allowedOperations' => new List<String>{ 'Analyze' }
                }
            );
            Assert.areEqual(400, RestContext.response.statusCode,
                'The Windows worker must not claim Salesforce-native Analyze runs');
            Assert.isFalse(response.success,
                'Analyze-only worker claims should be rejected');
        }
    }

    private static FieldTripWorkerApi.WorkerResponse invoke(
        String action,
        Map<String, Object> body
    ) {
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/field-trip-worker/v1/' + action;
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(JSON.serialize(body));
        RestContext.request = request;
        RestContext.response = new RestResponse();
        return FieldTripWorkerApi.post();
    }

    private static Field_Trip_Run__c createRequestedRun(
        Id requestedBy,
        String idempotencyKey
    ) {
        return new Field_Trip_Run__c(
            Operation__c = 'Generate Reports',
            Status__c = 'Requested',
            Start_Date__c = Date.today().addMonths(-1),
            End_Date_Exclusive__c = Date.today(),
            Target_Org__c = FieldTripRunController.resolveTargetOrg(
                [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox,
                URL.getOrgDomainUrl().getHost()
            ),
            Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
            Idempotency_Key__c = idempotencyKey,
            Confirmed_Production__c = true,
            Requested_By__c = requestedBy
        );
    }
}