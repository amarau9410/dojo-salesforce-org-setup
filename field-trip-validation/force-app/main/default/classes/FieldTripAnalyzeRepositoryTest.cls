@isTest
private class FieldTripAnalyzeRepositoryTest {
    @isTest
    static void shouldReturnNoRuns_WhenQueueIsEmpty() {
        User operatorUser = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Analyze_Operator' }
        );
        System.runAs(operatorUser) {
            Test.startTest();
            List<Field_Trip_Run__c> runs =
                FieldTripAnalyzeRepository.selectActiveAnalyzeRuns(
                    UserInfo.getOrganizationId(),
                    10
                );
            List<Field_Trip_Run_Item__c> items =
                FieldTripAnalyzeRepository.selectAnalyzeItems(new Set<Id>());
            List<AsyncApexJob> jobs = FieldTripAnalyzeRepository.selectJobs(new Set<Id>());
            Test.stopTest();

            Assert.areEqual(0, runs.size(), 'An empty test org should have no Analyze runs');
            Assert.areEqual(0, items.size(), 'An empty run ID set should return no items');
            Assert.areEqual(0, jobs.size(), 'An empty job ID set should return no jobs');
        }
    }

    @isTest
    static void shouldPersistRunAndItemChanges_WhenAuthorized() {
        User operatorUser = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Analyze_Operator' }
        );
        System.runAs(operatorUser) {
            Field_Trip_Run__c run = new Field_Trip_Run__c(
                Operation__c = 'Analyze',
                Status__c = 'Processing',
                Start_Date__c = Date.today().addMonths(-1),
                End_Date_Exclusive__c = Date.today(),
                Target_Org__c = 'warthog',
                Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
                Idempotency_Key__c = 'repository-test',
                Confirmed_Production__c = false,
                Requested_By__c = UserInfo.getUserId()
            );
            Database.insert(run, AccessLevel.SYSTEM_MODE);
            Field_Trip_Run_Item__c item = new Field_Trip_Run_Item__c(
                Field_Trip_Run__c = run.Id,
                Item_Type__c = 'Analyze Job',
                Status__c = 'Queued',
                Object_Analysis_Id__c = 'a0B000000000001',
                Object_API_Name__c = 'Account'
            );
            Database.insert(item, AccessLevel.SYSTEM_MODE);
            run.Status__c = 'Completed';
            item.Status__c = 'Failed';

            Test.startTest();
            FieldTripAnalyzeRepository.updateItems(
                new List<Field_Trip_Run_Item__c>{ item }
            );
            FieldTripAnalyzeRepository.updateRuns(
                new List<Field_Trip_Run__c>{ run }
            );
            Test.stopTest();

            Assert.areEqual('Completed', [
                SELECT Status__c FROM Field_Trip_Run__c WHERE Id = :run.Id
            ].Status__c, 'The repository should persist the parent terminal status');
            Assert.areEqual('Failed', [
                SELECT Status__c FROM Field_Trip_Run_Item__c WHERE Id = :item.Id
            ].Status__c, 'The repository should persist the item terminal status');
        }
    }
}
