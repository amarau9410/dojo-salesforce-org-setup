@isTest
private class DataDictionaryControllerTest {
    @TestSetup
    static void setupTestData() {
        User dictionaryReader = DataDictionaryTestDataFactory.createDictionaryReader();
        System.runAs(dictionaryReader) {
            Data_Dictionary_Object__c accountCatalog =
                DataDictionaryTestDataFactory.createCatalogObject('Account', true);
            DataDictionaryTestDataFactory.createCatalogObject('Risk_Assessment__c', true);
            DataDictionaryTestDataFactory.createCatalogFields(accountCatalog.Id, 251, true);
        }
    }

    @isTest
    static void shouldReturnGlobalMetrics_WhenCatalogIsLoaded() {
        User dictionaryReader = getDictionaryReader();
        DataDictionaryController.CatalogResponse response;
        System.runAs(dictionaryReader) {
            Test.startTest();
            response = DataDictionaryController.getCatalog(null, null, null, null);
            Test.stopTest();
        }

        Assert.areEqual(2, response.summary.objectCount, 'Both active objects should be counted');
        Assert.areEqual(502, response.summary.fieldCount, 'Field totals should be aggregated');
        Assert.areEqual(400, response.summary.documentedFieldCount, 'Documented fields should be aggregated');
        Assert.areEqual(2, response.objects.size(), 'Both active objects should be returned');
        Assert.areEqual(79.700, response.summary.documentationCoverage, 'Coverage should be calculated');
    }

    @isTest
    static void shouldFilterObjects_WhenGovernanceFiltersAreProvided() {
        User dictionaryReader = getDictionaryReader();
        DataDictionaryController.CatalogResponse response;
        System.runAs(dictionaryReader) {
            Test.startTest();
            response = DataDictionaryController.getCatalog(
                'risk',
                'Approved',
                'Internal',
                'Custom'
            );
            Test.stopTest();
        }

        Assert.areEqual(1, response.objects.size(), 'Only the matching custom object should be returned');
        Assert.areEqual(
            'Risk_Assessment__c',
            response.objects[0].apiName,
            'Search should match API names without case sensitivity'
        );
    }

    @isTest
    static void shouldReturnAllFields_WhenObjectIsSelected() {
        User dictionaryReader = getDictionaryReader();
        List<DataDictionaryController.FieldRow> fieldRows;
        System.runAs(dictionaryReader) {
            Data_Dictionary_Object__c accountCatalog = [
                SELECT Id FROM Data_Dictionary_Object__c WHERE Qualified_API_Name__c = 'Account' LIMIT 1
            ];
            Test.startTest();
            fieldRows = DataDictionaryController.getFields(accountCatalog.Id);
            Test.stopTest();
        }

        Assert.areEqual(251, fieldRows.size(), 'The controller should return records across a 200-row boundary');
        Assert.areEqual('Field_0__c', fieldRows[0].apiName, 'Fields should be ordered by label');
        Assert.isTrue(fieldRows[0].required, 'Technical field flags should be projected');
    }

    @isTest
    static void shouldReturnEmptyList_WhenNoObjectIsSelected() {
        User dictionaryReader = getDictionaryReader();
        List<DataDictionaryController.FieldRow> fieldRows;
        System.runAs(dictionaryReader) {
            Test.startTest();
            fieldRows = DataDictionaryController.getFields(null);
            Test.stopTest();
        }

        Assert.areEqual(0, fieldRows.size(), 'No fields should be queried without a selected object');
    }

    @isTest
    static void shouldReturnChangeMetricsAndFilteredRows() {
        Data_Dictionary_Scan__c scan = new Data_Dictionary_Scan__c(
            Scan_Key__c = 'test-scan', Source_Org_Id__c = UserInfo.getOrganizationId(),
            Scope__c = 'Custom and Core', Status__c = 'Completed', Started_At__c = System.now(),
            Completed_At__c = System.now(), Object_Count__c = 2, Field_Count__c = 502,
            Change_Count__c = 2, Retention_Until__c = Date.today().addYears(10),
            Notification_Status__c = 'Pending'
        );
        Database.insert(scan, AccessLevel.SYSTEM_MODE);
        Database.insert(new List<Data_Dictionary_Change__c>{
            new Data_Dictionary_Change__c(
                Dictionary_Scan__c = scan.Id, Change_Key__c = 'change-1', Catalog_Key__c = 'Account|One__c',
                Entity_Type__c = 'Field', Change_Type__c = 'Added', Object_API_Name__c = 'Account',
                Qualified_API_Name__c = 'Account.One__c', Metadata_Label__c = 'One',
                Detected_At__c = System.now(), Review_Status__c = 'New',
                Retention_Until__c = Date.today().addYears(10)
            ),
            new Data_Dictionary_Change__c(
                Dictionary_Scan__c = scan.Id, Change_Key__c = 'change-2', Catalog_Key__c = 'Account|Two__c',
                Entity_Type__c = 'Field', Change_Type__c = 'Changed', Object_API_Name__c = 'Account',
                Qualified_API_Name__c = 'Account.Two__c', Metadata_Label__c = 'Two',
                Detected_At__c = System.now(), Review_Status__c = 'Resolved',
                Retention_Until__c = Date.today().addYears(10)
            )
        }, AccessLevel.SYSTEM_MODE);

        DataDictionaryController.ChangeInventoryResponse response;
        System.runAs(getDictionaryReader()) {
            response = DataDictionaryController.getChangeInventory('one', 'Added', 'New');
        }

        Assert.areEqual(1, response.changes.size(), 'Filters should narrow displayed change rows');
        Assert.areEqual(1, response.summary.addedCount, 'Summary should include all added changes');
        Assert.areEqual(1, response.summary.changedCount, 'Summary should include all changed changes');
        Assert.areEqual('Pending', response.summary.notificationStatus, 'Latest scan notification state should be shown');
    }

    @isTest
    static void shouldReturnDuplicateMetricsBeforeApplyingFilters() {
        Data_Dictionary_Scan__c scan = new Data_Dictionary_Scan__c(
            Scan_Key__c = 'duplicate-scan', Source_Org_Id__c = UserInfo.getOrganizationId(),
            Scope__c = 'Custom and Core', Status__c = 'Completed', Started_At__c = System.now(),
            Retention_Until__c = Date.today().addYears(10), Notification_Status__c = 'Not Required'
        );
        Database.insert(scan, AccessLevel.SYSTEM_MODE);
        Database.insert(new List<Data_Dictionary_Duplicate__c>{
            duplicateCandidate(scan.Id, 'candidate-1', 'Account', 'Name_One__c', 'Name_Two__c', 91, 'New'),
            duplicateCandidate(scan.Id, 'candidate-2', 'Contact', 'Risk_One__c', 'Risk_Two__c', 82, 'Confirmed Duplicate')
        }, AccessLevel.SYSTEM_MODE);

        DataDictionaryController.DuplicateInventoryResponse response;
        System.runAs(getDictionaryReader()) {
            response = DataDictionaryController.getDuplicateCandidates('name', 'New', 80);
        }

        Assert.areEqual(1, response.candidates.size(), 'Filters should narrow displayed candidates');
        Assert.areEqual(2, response.summary.candidateCount, 'Summary should include every active candidate');
        Assert.areEqual(86.50, response.summary.averageConfidence, 'Average confidence should use all candidates');
        Assert.areEqual(1, response.summary.confirmedCount, 'Confirmed decisions should be summarized');
    }

    private static Data_Dictionary_Duplicate__c duplicateCandidate(
        Id scanId,
        String candidateKey,
        String objectApiName,
        String fieldA,
        String fieldB,
        Decimal confidence,
        String reviewStatus
    ) {
        return new Data_Dictionary_Duplicate__c(
            Dictionary_Scan__c = scanId, Candidate_Key__c = candidateKey,
            Object_API_Name__c = objectApiName, Field_A_API_Name__c = fieldA,
            Field_A_Label__c = fieldA, Field_B_API_Name__c = fieldB, Field_B_Label__c = fieldB,
            Data_Type__c = 'string', Confidence__c = confidence,
            Review_Status__c = reviewStatus, Detected_At__c = System.now(),
            Last_Evaluated_At__c = System.now(), Active__c = true,
            Retention_Until__c = Date.today().addYears(10)
        );
    }

    private static User getDictionaryReader() {
        return [SELECT Id FROM User WHERE Alias = 'ddread' LIMIT 1];
    }
}