@isTest
private class FieldTripAnalyzeOrchestratorTest {
    @isTest
    static void shouldPersistSubmittedJobIdsAndRespectActiveCapacity() {
        User operatorUser = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Analyze_Operator' }
        );
        System.runAs(operatorUser) {
            Field_Trip_Run__c run = createRun('dispatch-capacity');
            insertItems(run.Id, 3, 'Queued', null);
            FieldTripAnalyzeOrchestrator.batchSubmitter = new FakeBatchSubmitter();
            FieldTripAnalyzeOrchestrator.activeBatchCountOverride = 1;
            FieldTripAnalyzeOrchestrator.suppressNotifications = true;

            Test.startTest();
            FieldTripAnalyzeOrchestrator.processPendingRuns();
            Test.stopTest();

            List<Field_Trip_Run_Item__c> items = [
                SELECT Status__c, Apex_Job_Id__c
                FROM Field_Trip_Run_Item__c
                WHERE Field_Trip_Run__c = :run.Id
            ];
            Integer submittedCount = 0;
            Integer queuedCount = 0;
            for (Field_Trip_Run_Item__c item : items) {
                if (item.Status__c == 'Processing' && !String.isBlank(item.Apex_Job_Id__c)) {
                    submittedCount++;
                } else if (item.Status__c == 'Queued') {
                    queuedCount++;
                }
            }
            Assert.areEqual(2, submittedCount,
                'Only the two available batch slots should be submitted');
            Assert.areEqual(1, queuedCount,
                'The remaining analysis should stay queued for the next monitor pass');
        }
    }

    @isTest
    static void shouldCompleteRun_WhenRecordedBatchJobSucceeded() {
        User operatorUser = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Analyze_Operator' }
        );
        System.runAs(operatorUser) {
            Id jobId = fakeJobId(1);
            Field_Trip_Run__c run = createRun('terminal-success');
            insertItems(run.Id, 1, 'Processing', String.valueOf(jobId));
            FieldTripAnalyzeOrchestrator.jobStatusOverrides =
                new Map<Id, FieldTripAnalyzeOrchestrator.JobStatusSnapshot>{
                    jobId => new FieldTripAnalyzeOrchestrator.JobStatusSnapshot(
                        'Completed', 0, null
                    )
                };
            FieldTripAnalyzeOrchestrator.suppressNotifications = true;

            Test.startTest();
            FieldTripAnalyzeOrchestrator.processPendingRuns();
            Test.stopTest();

            Field_Trip_Run__c completedRun = [
                SELECT Status__c, Completed_At__c, Idempotency_Key__c
                FROM Field_Trip_Run__c
                WHERE Id = :run.Id
            ];
            Field_Trip_Run_Item__c completedItem = [
                SELECT Status__c, Error_Count__c
                FROM Field_Trip_Run_Item__c
                WHERE Field_Trip_Run__c = :run.Id
                LIMIT 1
            ];
            Assert.areEqual('Completed', completedRun.Status__c,
                'A successful batch should complete the parent run');
            Assert.isNotNull(completedRun.Completed_At__c,
                'The terminal run should have a completion timestamp');
            Assert.isTrue(completedRun.Idempotency_Key__c.endsWith(':' + run.Id),
                'The terminal run should release its active idempotency key');
            Assert.areEqual('Completed', completedItem.Status__c,
                'The successful batch item should be completed');
            Assert.areEqual(0, completedItem.Error_Count__c,
                'A successful job should persist a zero error count');
        }
    }

    @isTest
    static void shouldFailRun_WhenRecordedBatchJobHasErrors() {
        User operatorUser = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Analyze_Operator' }
        );
        System.runAs(operatorUser) {
            Id jobId = fakeJobId(2);
            Field_Trip_Run__c run = createRun('terminal-failure');
            insertItems(run.Id, 1, 'Processing', String.valueOf(jobId));
            FieldTripAnalyzeOrchestrator.jobStatusOverrides =
                new Map<Id, FieldTripAnalyzeOrchestrator.JobStatusSnapshot>{
                    jobId => new FieldTripAnalyzeOrchestrator.JobStatusSnapshot(
                        'Completed', 2, 'Two scope errors'
                    )
                };
            FieldTripAnalyzeOrchestrator.suppressNotifications = true;

            Test.startTest();
            FieldTripAnalyzeOrchestrator.processPendingRuns();
            Test.stopTest();

            Field_Trip_Run__c failedRun = [
                SELECT Status__c, Failure_Summary__c
                FROM Field_Trip_Run__c
                WHERE Id = :run.Id
            ];
            Field_Trip_Run_Item__c failedItem = [
                SELECT Status__c, Error_Count__c, Failure_Summary__c
                FROM Field_Trip_Run_Item__c
                WHERE Field_Trip_Run__c = :run.Id
                LIMIT 1
            ];
            Assert.areEqual('Failed', failedRun.Status__c,
                'A batch that reports errors should fail the run');
            Assert.areEqual('Failed', failedItem.Status__c,
                'A batch that reports errors should fail its item');
            Assert.areEqual(2, failedItem.Error_Count__c,
                'The managed batch error count should be retained');
            Assert.isTrue(failedRun.Failure_Summary__c.contains('Two scope errors'),
                'The managed batch status should be included in the run summary');
        }
    }

    @isTest
    static void shouldFailWithoutResubmitting_WhenRecordedJobIsMissing() {
        User operatorUser = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Analyze_Operator' }
        );
        System.runAs(operatorUser) {
            Id jobId = fakeJobId(3);
            Field_Trip_Run__c run = createRun('missing-job');
            insertItems(run.Id, 1, 'Processing', String.valueOf(jobId));
            FieldTripAnalyzeOrchestrator.jobStatusOverrides =
                new Map<Id, FieldTripAnalyzeOrchestrator.JobStatusSnapshot>();
            FieldTripAnalyzeOrchestrator.suppressNotifications = true;

            Test.startTest();
            FieldTripAnalyzeOrchestrator.processPendingRuns();
            Test.stopTest();

            Field_Trip_Run_Item__c failedItem = [
                SELECT Status__c, Failure_Summary__c
                FROM Field_Trip_Run_Item__c
                WHERE Field_Trip_Run__c = :run.Id
                LIMIT 1
            ];
            Assert.areEqual('Failed', failedItem.Status__c,
                'A missing job record must fail rather than risk duplicate submission');
            Assert.isTrue(failedItem.Failure_Summary__c.contains('was not resubmitted'),
                'The failure should explain why no replacement job was started');
        }
    }

    @isTest
    static void shouldFailRequestedRun_WhenItContainsNoItems() {
        User operatorUser = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Analyze_Operator' }
        );
        System.runAs(operatorUser) {
            Field_Trip_Run__c run = createRun('empty-run');
            run.Status__c = 'Requested';
            run.Started_At__c = null;
            Database.update(run, AccessLevel.SYSTEM_MODE);
            FieldTripAnalyzeOrchestrator.suppressNotifications = true;

            Test.startTest();
            FieldTripAnalyzeOrchestrator.processPendingRuns();
            Test.stopTest();

            Field_Trip_Run__c failedRun = [
                SELECT Status__c, Started_At__c, Completed_At__c, Failure_Summary__c
                FROM Field_Trip_Run__c
                WHERE Id = :run.Id
            ];
            Assert.areEqual('Failed', failedRun.Status__c,
                'A requested run without items should fail instead of remaining active');
            Assert.isNotNull(failedRun.Started_At__c,
                'The first processing pass should record the start time');
            Assert.isNotNull(failedRun.Completed_At__c,
                'An invalid run should be completed immediately');
            Assert.isTrue(failedRun.Failure_Summary__c.contains('no job items'),
                'The failure should explain why the run could not proceed');
        }
    }

    @isTest
    static void shouldFailRun_WhenBatchSubmissionThrows() {
        User operatorUser = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Analyze_Operator' }
        );
        System.runAs(operatorUser) {
            Field_Trip_Run__c run = createRun('submission-failure');
            insertItems(run.Id, 1, 'Queued', null);
            FieldTripAnalyzeOrchestrator.batchSubmitter = new FailingBatchSubmitter();
            FieldTripAnalyzeOrchestrator.activeBatchCountOverride = 0;
            FieldTripAnalyzeOrchestrator.suppressNotifications = true;

            Test.startTest();
            FieldTripAnalyzeOrchestrator.processPendingRuns();
            Test.stopTest();

            Field_Trip_Run_Item__c failedItem = [
                SELECT Status__c, Error_Count__c, Failure_Summary__c
                FROM Field_Trip_Run_Item__c
                WHERE Field_Trip_Run__c = :run.Id
                LIMIT 1
            ];
            Assert.areEqual('Failed', failedItem.Status__c,
                'A submission exception should fail the item');
            Assert.areEqual(1, failedItem.Error_Count__c,
                'A failed submission should record one error');
            Assert.isTrue(failedItem.Failure_Summary__c.contains('test submission failure'),
                'The item should retain the submission exception details');
        }
    }

    @isTest
    static void shouldRecordWarning_WhenCompletedRunHasNoRequestingUser() {
        User operatorUser = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Analyze_Operator' }
        );
        System.runAs(operatorUser) {
            Id jobId = fakeJobId(4);
            Field_Trip_Run__c run = createRun('missing-requester');
            run.Requested_By__c = null;
            Database.update(run, AccessLevel.SYSTEM_MODE);
            insertItems(run.Id, 1, 'Processing', String.valueOf(jobId));
            FieldTripAnalyzeOrchestrator.jobStatusOverrides =
                new Map<Id, FieldTripAnalyzeOrchestrator.JobStatusSnapshot>{
                    jobId => new FieldTripAnalyzeOrchestrator.JobStatusSnapshot(
                        'Completed', 0, null
                    )
                };

            Test.startTest();
            FieldTripAnalyzeOrchestrator.processPendingRuns();
            Test.stopTest();

            Field_Trip_Run__c completedRun = [
                SELECT Status__c, Failure_Summary__c
                FROM Field_Trip_Run__c
                WHERE Id = :run.Id
            ];
            Assert.areEqual('Completed', completedRun.Status__c,
                'A successful analysis should still complete without a requester');
            Assert.isTrue(completedRun.Failure_Summary__c.contains(
                'No requesting user was recorded'
            ), 'The missing completion email should be visible on the run');
        }
    }

    private static Field_Trip_Run__c createRun(String keySuffix) {
        Field_Trip_Run__c run = new Field_Trip_Run__c(
            Operation__c = 'Analyze',
            Status__c = 'Processing',
            Start_Date__c = Date.today().addMonths(-1),
            End_Date_Exclusive__c = Date.today(),
            Target_Org__c = 'warthog',
            Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
            Idempotency_Key__c = 'test-' + keySuffix,
            Confirmed_Production__c = false,
            Requested_By__c = UserInfo.getUserId(),
            Started_At__c = System.now()
        );
        Database.insert(run, AccessLevel.SYSTEM_MODE);
        return run;
    }

    private static void insertItems(
        Id runId,
        Integer itemCount,
        String status,
        String apexJobId
    ) {
        List<Field_Trip_Run_Item__c> items = new List<Field_Trip_Run_Item__c>();
        for (Integer index = 0; index < itemCount; index++) {
            items.add(new Field_Trip_Run_Item__c(
                Field_Trip_Run__c = runId,
                Item_Type__c = 'Analyze Job',
                Status__c = status,
                Object_Analysis_Id__c = 'a0B00000000000' + String.valueOf(index),
                Object_API_Name__c = 'Account',
                Apex_Job_Id__c = apexJobId
            ));
        }
        Database.insert(items, AccessLevel.SYSTEM_MODE);
    }

    private static Id fakeJobId(Integer sequenceNumber) {
        String suffix = String.valueOf(sequenceNumber).leftPad(12, '0');
        return (Id) (AsyncApexJob.SObjectType.getDescribe().getKeyPrefix() + suffix);
    }

    private class FakeBatchSubmitter implements FieldTripAnalyzeOrchestrator.BatchSubmitter {
        private Integer sequenceNumber = 100;

        public Id submit(String analysisId) {
            sequenceNumber++;
            return fakeJobId(sequenceNumber);
        }
    }

    private class FailingBatchSubmitter implements FieldTripAnalyzeOrchestrator.BatchSubmitter {
        public Id submit(String analysisId) {
            throw new OrchestrationTestException('test submission failure');
        }
    }

    private class OrchestrationTestException extends Exception {}
}
