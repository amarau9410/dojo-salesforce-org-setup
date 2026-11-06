/**
 * Atomically claims and terminalizes Field Trip runs for the dedicated automation identity.
 */
@RestResource(urlMapping='/field-trip-worker/v1/*')
global without sharing class FieldTripWorkerApi {
    private static final String PROCESS_PERMISSION = 'Process_Field_Trip_Automation';
    private static final Set<String> OPERATIONS = new Set<String>{ 'Generate Reports' };

    @HttpPost
    global static WorkerResponse post() {
        WorkerResponse response = new WorkerResponse();
        try {
            requireWorkerPermission();
            String action = RestContext.request.requestURI.substringAfterLast('/').toLowerCase();
            WorkerRequest request = String.isBlank(RestContext.request.requestBody?.toString())
                ? new WorkerRequest()
                : (WorkerRequest) JSON.deserialize(
                    RestContext.request.requestBody.toString(),
                    WorkerRequest.class
                );
            if (action == 'claim') {
                return claim(request);
            }
            if (action == 'complete') {
                return complete(request);
            }
            return fail(response, 404, 'Unsupported worker API action.');
        } catch (WorkerApiException exceptionValue) {
            return fail(response, exceptionValue.statusCode, exceptionValue.getMessage());
        } catch (Exception exceptionValue) {
            return fail(response, 500, 'The Field Trip worker request could not be completed.');
        }
    }

    private static WorkerResponse claim(WorkerRequest request) {
        Set<String> allowedOperations = new Set<String>();
        for (String operation : request.allowedOperations == null
            ? new List<String>()
            : request.allowedOperations) {
            if (OPERATIONS.contains(operation)) {
                allowedOperations.add(operation);
            }
        }
        if (allowedOperations.isEmpty()) {
            throw new WorkerApiException(400, 'At least one supported operation is required.');
        }

        List<Field_Trip_Run__c> candidates;
        if (request.runId == null) {
            String organizationId = UserInfo.getOrganizationId();
            candidates = [
                SELECT Id, Status__c, Operation__c, Salesforce_Org_Id__c,
                    Confirmed_Production__c, Requested_By__r.Email
                FROM Field_Trip_Run__c
                WHERE Status__c = 'Requested'
                    AND Salesforce_Org_Id__c = :organizationId
                    AND Operation__c IN :allowedOperations
                LIMIT 1
                FOR UPDATE
            ];
        } else {
            candidates = [
                SELECT Id, Status__c, Operation__c, Salesforce_Org_Id__c,
                    Confirmed_Production__c, Requested_By__r.Email
                FROM Field_Trip_Run__c
                WHERE Id = :request.runId
                LIMIT 1
                FOR UPDATE
            ];
        }
        if (candidates.isEmpty()) {
            WorkerResponse emptyResponse = new WorkerResponse();
            emptyResponse.success = true;
            emptyResponse.claimed = false;
            return emptyResponse;
        }

        Field_Trip_Run__c run = candidates[0];
        if (run.Status__c != 'Requested') {
            throw new WorkerApiException(409, 'The selected run is not in Requested status.');
        }
        if (run.Salesforce_Org_Id__c != UserInfo.getOrganizationId()) {
            throw new WorkerApiException(409, 'The selected run belongs to another Salesforce org.');
        }
        if (!allowedOperations.contains(run.Operation__c)) {
            throw new WorkerApiException(409, 'The selected operation is not enabled for this worker.');
        }
        Organization organization = [SELECT IsSandbox FROM Organization LIMIT 1];
        if (!organization.IsSandbox && !run.Confirmed_Production__c) {
            throw new WorkerApiException(409, 'The production run is not explicitly confirmed.');
        }
        if (String.isBlank(run.Requested_By__r?.Email)) {
            throw new WorkerApiException(409, 'The requesting user does not have an email address.');
        }

        String claimToken = EncodingUtil.convertToHex(Crypto.generateDigest(
            'SHA-256',
            Blob.valueOf(run.Id + '|' + System.now().getTime() + '|' + Crypto.getRandomLong())
        ));
        run.Status__c = 'Processing';
        run.Started_At__c = System.now();
        run.Claimed_At__c = System.now();
        run.Claimed_By__c = UserInfo.getUserId();
        run.Claim_Token__c = claimToken;
        Database.update(run, AccessLevel.SYSTEM_MODE);

        WorkerResponse claimedResponse = new WorkerResponse();
        claimedResponse.success = true;
        claimedResponse.claimed = true;
        claimedResponse.runId = run.Id;
        claimedResponse.claimToken = claimToken;
        return claimedResponse;
    }

    private static WorkerResponse complete(WorkerRequest request) {
        if (request.runId == null || String.isBlank(request.claimToken)) {
            throw new WorkerApiException(400, 'Run ID and claim token are required.');
        }
        if (request.status != 'Completed' && request.status != 'Failed') {
            throw new WorkerApiException(400, 'Terminal status must be Completed or Failed.');
        }
        List<Field_Trip_Run__c> runs = [
            SELECT Id, Status__c, Claim_Token__c, Idempotency_Key__c
            FROM Field_Trip_Run__c
            WHERE Id = :request.runId
            LIMIT 1
            FOR UPDATE
        ];
        if (runs.isEmpty()) {
            throw new WorkerApiException(404, 'The selected run is unavailable.');
        }
        Field_Trip_Run__c run = runs[0];
        if (run.Status__c != 'Processing' || run.Claim_Token__c != request.claimToken) {
            throw new WorkerApiException(409, 'The worker no longer owns this run.');
        }

        run.Status__c = request.status;
        run.Completed_At__c = System.now();
        run.Idempotency_Key__c = terminalKey(run.Idempotency_Key__c, run.Id);
        if (!String.isBlank(request.failureSummary)) {
            run.Failure_Summary__c = request.failureSummary.left(32000);
        }
        if (!String.isBlank(request.outputFolderUrl)) {
            run.Output_Folder_URL__c = request.outputFolderUrl.left(255);
        }
        Database.update(run, AccessLevel.SYSTEM_MODE);

        WorkerResponse completedResponse = new WorkerResponse();
        completedResponse.success = true;
        completedResponse.claimed = true;
        completedResponse.runId = run.Id;
        return completedResponse;
    }

    private static String terminalKey(String idempotencyKey, Id runId) {
        String suffix = ':' + runId;
        return idempotencyKey.endsWith(suffix) ? idempotencyKey : idempotencyKey + suffix;
    }

    private static void requireWorkerPermission() {
        if (!FeatureManagement.checkPermission(PROCESS_PERMISSION)) {
            throw new WorkerApiException(403, 'Field Trip automation permission is required.');
        }
    }

    private static WorkerResponse fail(
        WorkerResponse response,
        Integer statusCode,
        String message
    ) {
        RestContext.response.statusCode = statusCode;
        response.success = false;
        response.claimed = false;
        response.message = message;
        return response;
    }

    global class WorkerRequest {
        global Id runId;
        global List<String> allowedOperations;
        global String claimToken;
        global String status;
        global String failureSummary;
        global String outputFolderUrl;
    }

    global class WorkerResponse {
        global Boolean success;
        global Boolean claimed;
        global Id runId;
        global String claimToken;
        global String message;
    }

    private class WorkerApiException extends Exception {
        private Integer statusCode;

        private WorkerApiException(Integer statusCode, String message) {
            this.statusCode = statusCode;
            this.setMessage(message);
        }
    }
}