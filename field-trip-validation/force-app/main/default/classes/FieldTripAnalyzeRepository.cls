/**
 * Reads and persists the Salesforce records used by the Analyze orchestrator.
 */
public without sharing class FieldTripAnalyzeRepository {
    private static final String REQUIRED_PERMISSION = 'Launch_Field_Trip_Analyze';
    private static final String SCHEDULER_NAME = 'Field Trip Analyze Orchestrator';
    private static final Set<String> ACTIVE_JOB_STATUSES = new Set<String>{
        'Holding', 'Queued', 'Preparing', 'Processing'
    };
    private static final Set<String> ACTIVE_SCHEDULE_STATES = new Set<String>{
        'WAITING', 'ACQUIRED', 'EXECUTING', 'PAUSED', 'BLOCKED', 'PAUSED-BLOCKED'
    };

    /**
     * Selects requested and processing Analyze runs owned by this Salesforce org.
     * @param organizationId Salesforce org ID used to scope the queue.
     * @param rowLimit Maximum number of runs to lock for one pass.
     * @return Eligible Analyze runs, locked for this transaction.
     */
    public static List<Field_Trip_Run__c> selectActiveAnalyzeRuns(
        String organizationId,
        Integer rowLimit
    ) {
        requirePermission();
        if (String.isBlank(organizationId) || rowLimit == null || rowLimit < 1) {
            throw new RepositoryException('A Salesforce org ID and positive row limit are required.');
        }
        String queryText =
            'SELECT Id, Name, Status__c, Operation__c, Claim_Token__c, '
            + 'Salesforce_Org_Id__c, Requested_By__c, Requested_By__r.Email, '
            + 'Started_At__c, Completed_At__c, Idempotency_Key__c, Failure_Summary__c '
            + 'FROM Field_Trip_Run__c '
            + 'WHERE Operation__c = \'Analyze\' '
            + 'AND Status__c IN (\'Requested\', \'Processing\') '
            + 'AND Claim_Token__c = null '
            + 'AND Salesforce_Org_Id__c = :organizationId '
            + 'LIMIT :rowLimit FOR UPDATE';
        Map<String, Object> queryBinds = new Map<String, Object>{
            'organizationId' => organizationId,
            'rowLimit' => rowLimit
        };
        return (List<Field_Trip_Run__c>) Database.queryWithBinds(
            queryText,
            queryBinds,
            AccessLevel.SYSTEM_MODE
        );
    }

    /**
     * Selects Analyze job items belonging to the supplied parent runs.
     * @param runIds Parent run IDs.
     * @return Analyze job items ordered by creation time.
     */
    public static List<Field_Trip_Run_Item__c> selectAnalyzeItems(Set<Id> runIds) {
        requirePermission();
        if (runIds == null || runIds.isEmpty()) {
            return new List<Field_Trip_Run_Item__c>();
        }
        return [
            SELECT Id, Field_Trip_Run__c, Item_Type__c, Status__c,
                Object_Analysis_Id__c, Object_API_Name__c, Apex_Job_Id__c,
                Error_Count__c, Failure_Summary__c
            FROM Field_Trip_Run_Item__c
            WHERE Field_Trip_Run__c IN :runIds
                AND Item_Type__c = 'Analyze Job'
            ORDER BY CreatedDate ASC
        ];
    }

    /**
     * Counts active Batch Apex jobs across the org.
     * @return Count of jobs consuming the shared Batch Apex capacity.
     */
    public static Integer countActiveBatchJobs() {
        requirePermission();
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
                AND Status IN :ACTIVE_JOB_STATUSES
        ];
    }

    /**
     * Loads the persisted state of submitted Analyze jobs.
     * @param jobIds Apex job IDs.
     * @return Matching asynchronous Apex job records.
     */
    public static List<AsyncApexJob> selectJobs(Set<Id> jobIds) {
        requirePermission();
        if (jobIds == null || jobIds.isEmpty()) {
            return new List<AsyncApexJob>();
        }
        return [
            SELECT Id, Status, NumberOfErrors, ExtendedStatus
            FROM AsyncApexJob
            WHERE Id IN :jobIds
        ];
    }

    /**
     * Checks whether an orchestration Queueable is already queued or running.
     * @return True when another pass is active.
     */
    public static Boolean hasActiveQueueable() {
        requirePermission();
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
                AND ApexClass.Name = 'FieldTripAnalyzeOrchestrator'
                AND Status IN :ACTIVE_JOB_STATUSES
        ] > 0;
    }

    /**
     * Finds an existing active recurring scheduler by its stable job name.
     * @return The newest active schedule, or an empty list.
     */
    public static List<CronTrigger> findActiveSchedules() {
        requirePermission();
        return [
            SELECT Id, State
            FROM CronTrigger
            WHERE CronJobDetail.Name = :SCHEDULER_NAME
                AND State IN :ACTIVE_SCHEDULE_STATES
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    /**
     * Persists item state changes atomically.
     * @param items Changed Analyze items.
     */
    public static void updateItems(List<Field_Trip_Run_Item__c> items) {
        requirePermission();
        if (items == null || items.isEmpty()) {
            return;
        }
        Database.update(items, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Persists run state changes atomically.
     * @param runs Changed Analyze runs.
     */
    public static void updateRuns(List<Field_Trip_Run__c> runs) {
        requirePermission();
        if (runs == null || runs.isEmpty()) {
            return;
        }
        Database.update(runs, AccessLevel.SYSTEM_MODE);
    }

    private static void requirePermission() {
        if (!FeatureManagement.checkPermission(REQUIRED_PERMISSION)) {
            throw new RepositoryException(
                'The Field Trip Analyze Operator permission is required for queue processing.'
            );
        }
    }

    private class RepositoryException extends Exception {}
}
