/**
 * Dispatches and reconciles Field Trip Analyze batch jobs independently of the Windows worker.
 */
public without sharing class FieldTripAnalyzeOrchestrator
    implements Queueable {
    private static final String REQUIRED_PERMISSION = 'Launch_Field_Trip_Analyze';
    private static final Integer MAX_ACTIVE_BATCH_JOBS = 3;
    private static final Integer MAX_RUNS_PER_PASS = 10;
    private static final Set<String> ACTIVE_JOB_STATUSES = new Set<String>{
        'Holding', 'Queued', 'Preparing', 'Processing'
    };

    /** Submits one managed-package Analyze job. */
    public interface BatchSubmitter {
        Id submit(String analysisId);
    }

    /** A terminal or active snapshot of an asynchronous Apex job. */
    public class JobStatusSnapshot {
        public String status;
        public Integer numberOfErrors;
        public String extendedStatus;

        public JobStatusSnapshot(String status, Integer numberOfErrors, String extendedStatus) {
            this.status = status;
            this.numberOfErrors = numberOfErrors;
            this.extendedStatus = extendedStatus;
        }
    }

    @TestVisible private static BatchSubmitter batchSubmitter;
    @TestVisible private static Integer activeBatchCountOverride;
    @TestVisible private static Map<Id, JobStatusSnapshot> jobStatusOverrides;
    @TestVisible private static Boolean suppressNotifications = false;

    /**
     * Processes queued Analyze runs and reconciles submitted batch jobs.
     * @param context Queueable execution context.
     */
    public void execute(QueueableContext context) {
        if (processPendingRuns() && !Test.isRunningTest()) {
            AsyncOptions options = new AsyncOptions();
            options.MinimumQueueableDelayInMinutes = 1;
            System.enqueueJob(new FieldTripAnalyzeOrchestrator(), options);
        }
    }

    /**
     * Dispatches up to three active Analyze batches and persists their outcomes.
     */
    public static Boolean processPendingRuns() {
        requirePermission();
        List<Field_Trip_Run__c> runs = FieldTripAnalyzeRepository.selectActiveAnalyzeRuns(
            UserInfo.getOrganizationId(),
            MAX_RUNS_PER_PASS
        );
        if (runs.isEmpty()) {
            return false;
        }

        Set<Id> runIds = new Map<Id, Field_Trip_Run__c>(runs).keySet();
        List<Field_Trip_Run_Item__c> items = FieldTripAnalyzeRepository.selectAnalyzeItems(runIds);
        Map<Id, List<Field_Trip_Run_Item__c>> itemsByRunId =
            new Map<Id, List<Field_Trip_Run_Item__c>>();
        Set<Id> apexJobIds = new Set<Id>();
        List<Field_Trip_Run_Item__c> changedItems = new List<Field_Trip_Run_Item__c>();
        List<Field_Trip_Run__c> changedRuns = new List<Field_Trip_Run__c>();
        List<Field_Trip_Run__c> completedRuns = new List<Field_Trip_Run__c>();
        for (Field_Trip_Run_Item__c item : items) {
            if (!itemsByRunId.containsKey(item.Field_Trip_Run__c)) {
                itemsByRunId.put(
                    item.Field_Trip_Run__c,
                    new List<Field_Trip_Run_Item__c>()
                );
            }
            itemsByRunId.get(item.Field_Trip_Run__c).add(item);
            if (!String.isBlank(item.Apex_Job_Id__c)) {
                try {
                    apexJobIds.add(Id.valueOf(item.Apex_Job_Id__c));
                } catch (Exception exceptionValue) {
                    markFailed(item, 'The stored Apex job ID is invalid; the job was not resubmitted.');
                    changedItems.add(item);
                }
            }
        }

        Map<Id, JobStatusSnapshot> jobStatuses = getJobStatuses(apexJobIds);
        Integer activeBatchJobs = activeBatchCountOverride == null
            ? FieldTripAnalyzeRepository.countActiveBatchJobs()
            : activeBatchCountOverride;
        BatchSubmitter submitter = batchSubmitter == null
            ? new ManagedPackageBatchSubmitter()
            : batchSubmitter;
        Boolean continueProcessing = runs.size() == MAX_RUNS_PER_PASS;

        for (Field_Trip_Run__c run : runs) {
            Boolean runChanged = false;
            if (run.Status__c == 'Requested') {
                run.Status__c = 'Processing';
                run.Started_At__c = System.now();
                runChanged = true;
            }
            List<Field_Trip_Run_Item__c> runItems = itemsByRunId.get(run.Id);
            if (runItems == null || runItems.isEmpty()) {
                run.Status__c = 'Failed';
                run.Completed_At__c = System.now();
                run.Failure_Summary__c = 'The Analyze run contains no job items.';
                releaseIdempotencyKey(run);
                changedRuns.add(run);
                completedRuns.add(run);
                continue;
            }

            for (Field_Trip_Run_Item__c item : runItems) {
                if (item.Status__c == 'Processing') {
                    reconcileProcessingItem(item, jobStatuses);
                    changedItems.add(item);
                } else if (item.Status__c == 'Queued') {
                    if (!String.isBlank(item.Apex_Job_Id__c)) {
                        item.Status__c = 'Processing';
                        reconcileProcessingItem(item, jobStatuses);
                        changedItems.add(item);
                    } else if (activeBatchJobs < MAX_ACTIVE_BATCH_JOBS) {
                        try {
                            Id jobId = submitter.submit(item.Object_Analysis_Id__c);
                            if (jobId == null) {
                                throw new OrchestrationException(
                                    'Salesforce did not return an Apex job ID.'
                                );
                            }
                            item.Apex_Job_Id__c = String.valueOf(jobId);
                            item.Status__c = 'Processing';
                            activeBatchJobs++;
                            changedItems.add(item);
                        } catch (Exception exceptionValue) {
                            markFailed(
                                item,
                                ('Analyze submission failed: ' + exceptionValue.getMessage()).left(32000)
                            );
                            changedItems.add(item);
                        }
                    }
                }
            }

            if (isRunTerminal(runItems)) {
                run.Status__c = hasFailedItem(runItems) ? 'Failed' : 'Completed';
                run.Completed_At__c = System.now();
                run.Failure_Summary__c = buildFailureSummary(runItems);
                releaseIdempotencyKey(run);
                changedRuns.add(run);
                completedRuns.add(run);
            } else if (run.Status__c != 'Processing' || run.Started_At__c == null) {
                run.Status__c = 'Processing';
                run.Started_At__c = run.Started_At__c == null
                    ? System.now()
                    : run.Started_At__c;
                runChanged = true;
            } else if (runsWereUpdatedByThisPass(run, changedItems)) {
                runChanged = true;
            }
            if (run.Status__c == 'Processing') {
                continueProcessing = true;
            }
            if (runChanged) {
                changedRuns.add(run);
            }
        }

        if (!changedItems.isEmpty()) {
            FieldTripAnalyzeRepository.updateItems(changedItems);
        }
        if (!suppressNotifications && !completedRuns.isEmpty()) {
            addNotificationWarnings(completedRuns);
        }
        if (!changedRuns.isEmpty()) {
            FieldTripAnalyzeRepository.updateRuns(changedRuns);
        }
        return continueProcessing;
    }

    private static Map<Id, JobStatusSnapshot> getJobStatuses(Set<Id> apexJobIds) {
        if (jobStatusOverrides != null) {
            return jobStatusOverrides;
        }
        Map<Id, JobStatusSnapshot> statusesById = new Map<Id, JobStatusSnapshot>();
        for (AsyncApexJob job : FieldTripAnalyzeRepository.selectJobs(apexJobIds)) {
            statusesById.put(
                job.Id,
                new JobStatusSnapshot(job.Status, job.NumberOfErrors, job.ExtendedStatus)
            );
        }
        return statusesById;
    }

    private static void reconcileProcessingItem(
        Field_Trip_Run_Item__c item,
        Map<Id, JobStatusSnapshot> jobStatuses
    ) {
        if (String.isBlank(item.Apex_Job_Id__c)) {
            markFailed(item, 'The processing Analyze item has no persisted Apex job ID.');
            return;
        }
        Id jobId;
        try {
            jobId = Id.valueOf(item.Apex_Job_Id__c);
        } catch (Exception exceptionValue) {
            markFailed(item, 'The stored Apex job ID is invalid; the job was not resubmitted.');
            return;
        }

        JobStatusSnapshot job = jobStatuses.get(jobId);
        if (job == null) {
            markFailed(item, 'The recorded Apex job could not be found; it was not resubmitted.');
            return;
        }
        if (ACTIVE_JOB_STATUSES.contains(job.status)) {
            return;
        }
        Integer errorCount = job.numberOfErrors == null ? 0 : job.numberOfErrors;
        item.Error_Count__c = errorCount;
        if (job.status == 'Completed' && errorCount == 0) {
            item.Status__c = 'Completed';
            item.Failure_Summary__c = null;
        } else {
            String failure = 'Apex job ended with status ' + job.status
                + ' and ' + errorCount + ' error(s).';
            if (!String.isBlank(job.extendedStatus)) {
                failure += ' ' + job.extendedStatus;
            }
            markFailed(item, failure.left(32000));
            item.Error_Count__c = errorCount;
        }
    }

    private static void markFailed(Field_Trip_Run_Item__c item, String reason) {
        item.Status__c = 'Failed';
        item.Error_Count__c = 1;
        item.Failure_Summary__c = reason.left(32000);
    }

    private static Boolean isRunTerminal(List<Field_Trip_Run_Item__c> runItems) {
        for (Field_Trip_Run_Item__c item : runItems) {
            if (item.Status__c != 'Completed' && item.Status__c != 'Failed') {
                return false;
            }
        }
        return true;
    }

    private static Boolean hasFailedItem(List<Field_Trip_Run_Item__c> runItems) {
        for (Field_Trip_Run_Item__c item : runItems) {
            if (item.Status__c == 'Failed') {
                return true;
            }
        }
        return false;
    }

    private static String buildFailureSummary(List<Field_Trip_Run_Item__c> runItems) {
        List<String> failures = new List<String>();
        for (Field_Trip_Run_Item__c item : runItems) {
            if (item.Status__c == 'Failed') {
                failures.add(
                    item.Object_API_Name__c + ' (' + item.Object_Analysis_Id__c + '): '
                    + item.Failure_Summary__c
                );
            }
        }
        return failures.isEmpty()
            ? null
            : String.join(failures, '\n').left(32000);
    }

    private static void releaseIdempotencyKey(Field_Trip_Run__c run) {
        String terminalSuffix = ':' + run.Id;
        if (!String.isBlank(run.Idempotency_Key__c)
            && !run.Idempotency_Key__c.endsWith(terminalSuffix)) {
            run.Idempotency_Key__c += terminalSuffix;
        }
    }

    private static Boolean runsWereUpdatedByThisPass(
        Field_Trip_Run__c run,
        List<Field_Trip_Run_Item__c> changedItems
    ) {
        for (Field_Trip_Run_Item__c item : changedItems) {
            if (item.Field_Trip_Run__c == run.Id) {
                return true;
            }
        }
        return false;
    }

    private static void addNotificationWarnings(List<Field_Trip_Run__c> runs) {
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<Field_Trip_Run__c> runsByMessageIndex = new List<Field_Trip_Run__c>();
        for (Field_Trip_Run__c run : runs) {
            if (run.Requested_By__c == null) {
                appendNotificationWarning(run, 'No requesting user was recorded for the completion email.');
                continue;
            }
            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            message.setTargetObjectId(run.Requested_By__c);
            message.setSaveAsActivity(false);
            message.setSubject('Field Trip Analyze run ' + run.Name + ' ' + run.Status__c);
            message.setPlainTextBody(
                'Your Field Trip Analyze run ' + run.Name + ' finished with status '
                + run.Status__c + '. Review the run and its job items in the Field Trip Quarterly console.'
            );
            messages.add(message);
            runsByMessageIndex.add(run);
        }
        if (messages.isEmpty()) {
            return;
        }
        try {
            Messaging.SendEmailResult[] results = Messaging.sendEmail(messages, false);
            for (Integer index = 0; index < results.size(); index++) {
                if (!results[index].isSuccess()) {
                    String details = results[index].getErrors().isEmpty()
                        ? 'Salesforce rejected the completion email.'
                        : results[index].getErrors()[0].getMessage();
                    appendNotificationWarning(
                        runsByMessageIndex[index],
                        ('Completion email could not be sent: ' + details).left(32000)
                    );
                }
            }
        } catch (Exception exceptionValue) {
            for (Field_Trip_Run__c run : runsByMessageIndex) {
                appendNotificationWarning(
                    run,
                    ('Completion email could not be sent: ' + exceptionValue.getMessage()).left(32000)
                );
            }
        }
    }

    private static void appendNotificationWarning(Field_Trip_Run__c run, String warning) {
        String currentSummary = run.Failure_Summary__c;
        run.Failure_Summary__c = String.isBlank(currentSummary)
            ? warning.left(32000)
            : (currentSummary + '\n' + warning).left(32000);
    }

    private static void requirePermission() {
        if (!FeatureManagement.checkPermission(REQUIRED_PERMISSION)) {
            throw new OrchestrationException(
                'The scheduled Analyze orchestrator requires the Field Trip Analyze Operator permission.'
            );
        }
    }

    private class ManagedPackageBatchSubmitter implements BatchSubmitter {
        public Id submit(String analysisId) {
            if (Test.isRunningTest()) {
                return (Id) (
                    AsyncApexJob.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix()
                    + '000000000001'
                );
            }
            Field_Trip.analyzeObject batch = new Field_Trip.analyzeObject(
                Id.valueOf(analysisId),
                '',
                ''
            );
            return Database.executeBatch(batch);
        }
    }

    private class OrchestrationException extends Exception {}

}
