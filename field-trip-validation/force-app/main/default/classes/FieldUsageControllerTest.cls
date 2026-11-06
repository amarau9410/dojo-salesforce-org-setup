@isTest
private class FieldUsageControllerTest {
    @TestSetup
    static void setupTestData() {
        User scopedReader = DataDictionaryTestDataFactory.createDictionaryReader(
            'ddscope',
            new Set<String>{ 'CMSL' },
            false
        );
        DataDictionaryTestDataFactory.createDictionaryReader(
            'ddmulti',
            new Set<String>{ 'CMSL', 'FDMS' },
            false
        );
        DataDictionaryTestDataFactory.createDictionaryReader('ddnone', new Set<String>(), false);
        DataDictionaryTestDataFactory.createDictionaryReader('ddadmin', new Set<String>(), true);
        DataDictionaryTestDataFactory.createSystemAdministrator('ddsysadm');
        System.runAs(scopedReader) {
            Data_Dictionary_Object__c accountCatalog =
                DataDictionaryTestDataFactory.createCatalogObject('Account', true);
            List<Data_Dictionary_Field__c> catalogFields =
                DataDictionaryTestDataFactory.createCatalogFields(accountCatalog.Id, 3, true);
            DataDictionaryTestDataFactory.createFieldUsage(catalogFields, true);
        }
    }

    @isTest
    static void shouldReturnFilterOptions_WhenEvidenceExists() {
        FieldUsageController.FilterOptions options;
        System.runAs(getDictionaryReader('ddmulti')) {
            Test.startTest();
            options = FieldUsageController.getFilterOptions();
            Test.stopTest();
        }

        Assert.areEqual(new List<String>{ 'CMSL', 'FDMS' }, options.alliances, 'Segments should be ordered');
        Assert.areEqual(new List<String>{ 'Account' }, options.objectApiNames, 'Object options should be distinct');
    }

    @isTest
    static void shouldSeparateUsageSignals_WhenSegmentIsSelected() {
        FieldUsageController.UsageResponse response;
        System.runAs(getDictionaryReader('ddscope')) {
            Test.startTest();
            response = getUsageWithRows('CMSL', null, 'Used', 'Field 0');
            Test.stopTest();
        }

        Assert.areEqual(1, response.rows.size(), 'Table filters should limit the displayed CMSL evidence');
        Assert.areEqual(1, response.summary.evidenceCount, 'Metrics should match the visible filtered evidence');
        Assert.areEqual(1, response.summary.usedCount, 'Populated evidence should be counted as used');
        Assert.areEqual(0, response.summary.unusedCount, 'Filtered-out unused evidence should not be counted');
        Assert.areEqual(0, response.summary.noRecordsCount, 'CMSL has an analyzed sample');
        Assert.areEqual(0, response.rows[0].dependencyCount, 'Dependency evidence should remain separate');
    }

    @isTest
    static void shouldReturnNoRecordsEvidence_WhenAnalysisSampleIsEmpty() {
        FieldUsageController.UsageResponse response;
        System.runAs(getDictionaryReader('ddmulti')) {
            Test.startTest();
            response = getUsageWithRows('FDMS', 'Account', 'No Records', 'Field 2');
            Test.stopTest();
        }

        Assert.areEqual(1, response.rows.size(), 'All supplied filters should be applied');
        Assert.areEqual('No Records', response.rows[0].usageStatus, 'Empty samples must remain inconclusive');
        Assert.areEqual(1, response.summary.noRecordsCount, 'No-record evidence should be counted separately');
    }

    @isTest
    static void shouldReturnAuthorizedTotals_WhenSegmentIsNotSelected() {
        FieldUsageController.UsageResponse response;
        System.runAs(getDictionaryReader('ddscope')) {
            Test.startTest();
            response = getUsageWithRows(null, null, null, null);
            Test.stopTest();
        }

        Assert.areEqual(2, response.rows.size(), 'Only the reader authorized CMSL evidence should be returned');
        Assert.areEqual(2, response.summary.evidenceCount, 'Totals should include only authorized evidence');
        Assert.areEqual(1, response.segments.size(), 'Only one authorized segment summary should be returned');
        Assert.areEqual('CMSL', response.segments[0].reportingGroup, 'The summary must not expose FDMS');
        Assert.areEqual(1, response.segments[0].previousUsedCount, 'Previous used fields should be counted');
        Assert.areEqual(1, response.segments[0].previousUnusedCount, 'Previous unused fields should be counted');
        Assert.areEqual(12.5, response.segments[0].previousAveragePopulationPercent, 'Previous population should be averaged');
        Assert.areEqual(200, response.segments[0].previousRecordsAnalyzed, 'Previous samples should be counted once per analysis');
        Assert.areEqual(
            Datetime.newInstance(2026, 7, 1, 12, 0, 0),
            response.segments[0].previousAnalyzedAt,
            'Previous analysis date should be returned'
        );
        for (FieldUsageController.UsageRow row : response.rows) {
            Assert.areEqual('CMSL', row.reportingGroup, 'FDMS evidence must not leak into authorized totals');
        }
    }

    @isTest
    static void shouldReturnAllAuthorizedTotals_WhenReaderHasMultipleAlliances() {
        FieldUsageController.UsageResponse response;
        System.runAs(getDictionaryReader('ddmulti')) {
            Test.startTest();
            response = getUsageWithRows(null, 'Account', null, null);
            Test.stopTest();
        }

        Assert.areEqual(3, response.rows.size(), 'Both authorized reporting segments should be returned');
        Assert.areEqual(3, response.summary.evidenceCount, 'The summary should match both authorized segments');
        Assert.areEqual(1, response.summary.noRecordsCount, 'No-record evidence should remain explicit');
        Assert.areEqual(2, response.segments.size(), 'Each authorized reporting segment should be summarized');
    }

    @isTest
    static void shouldOnlyReturnAuthorizedFilterOptions_WhenReaderHasOneAlliance() {
        FieldUsageController.FilterOptions options;
        System.runAs(getDictionaryReader('ddscope')) {
            Test.startTest();
            options = FieldUsageController.getFilterOptions();
            Test.stopTest();
        }

        Assert.areEqual(new List<String>{ 'CMSL' }, options.alliances, 'Only authorized segments should be listed');
        Assert.areEqual(new List<String>{ 'Account' }, options.objectApiNames, 'Authorized object options should be listed');
    }

    @isTest
    static void shouldReturnNoFilterOptions_WhenReaderHasNoAlliance() {
        FieldUsageController.FilterOptions options;
        System.runAs(getDictionaryReader('ddnone')) {
            Test.startTest();
            options = FieldUsageController.getFilterOptions();
            Test.stopTest();
        }

        Assert.areEqual(0, options.alliances.size(), 'Readers without alliance access should see no segments');
        Assert.areEqual(0, options.objectApiNames.size(), 'Readers without alliance access should see no objects');
    }

    @isTest
    static void shouldRejectUsageRequest_WhenAllianceIsNotAuthorized() {
        System.runAs(getDictionaryReader('ddscope')) {
            Test.startTest();
            try {
                FieldUsageController.getUsage('FDMS', null, null, null);
                Assert.fail('An unauthorized reporting segment should be rejected');
            } catch (AuraHandledException exceptionValue) {
                Assert.isNotNull(exceptionValue, 'The controller should reject the unauthorized segment');
            }
            Test.stopTest();
        }
    }

    @isTest
    static void shouldNotGrantAllAllianceAccess_WhenUserHasLegacyPermission() {
        FieldUsageController.FilterOptions options;
        System.runAs(getDictionaryReader('ddadmin')) {
            Test.startTest();
            options = FieldUsageController.getFilterOptions();
            Test.stopTest();
        }

        Assert.areEqual(0, options.alliances.size(), 'A non-admin permission must not grant alliance visibility');
        Assert.isFalse(options.canViewAllAlliances, 'Only Modify All Data should grant all-alliance visibility');
    }

    @isTest
    static void shouldRejectDirectAllianceRequest_WhenLegacyPermissionHasNoEntitlement() {
        System.runAs(getDictionaryReader('ddadmin')) {
            Test.startTest();
            try {
                FieldUsageController.getUsage('CMSL', null, null, null);
                Assert.fail('The legacy permission must not bypass alliance entitlements');
            } catch (AuraHandledException exceptionValue) {
                Assert.isNotNull(exceptionValue, 'The controller should reject the direct request');
            }
            Test.stopTest();
        }
    }

    @isTest
    static void shouldReturnAllReportingGroups_WhenProfileHasModifyAllData() {
        FieldUsageController.FilterOptions options;
        System.runAs(getDictionaryReader('ddsysadm')) {
            Test.startTest();
            options = FieldUsageController.getFilterOptions();
            Test.stopTest();
        }

        Assert.areEqual(
            new List<String>{ 'CMSL', 'FDMS' },
            options.alliances,
            'Administrators should see every segment without an override assignment'
        );
        Assert.isTrue(options.canViewAllAlliances, 'Modify All Data should grant all-alliance visibility');
    }

    private static User getDictionaryReader(String aliasValue) {
        return [SELECT Id FROM User WHERE Alias = :aliasValue LIMIT 1];
    }

    @isTest
    static void shouldScanEvidenceOnce_WhenAdministratorLoadsMetrics() {
        DataDictionaryTestDataFactory.createUsageBudgetRows(9000);
        User administrator = getDictionaryReader('ddsysadm');
        FieldUsageController.UsageResponse response;
        Integer queryRows;
        System.runAs(administrator) {
            Test.startTest();
            response = FieldUsageController.getUsage(null, null, null, null);
            queryRows = Limits.getQueryRows();
            Test.stopTest();
        }
        Assert.areEqual(9003, response.summary.evidenceCount, 'Metrics must include all evidence');
        Assert.areEqual(9004, queryRows, 'Metrics should scan evidence once plus the profile record');
        Assert.areEqual(0, response.rows.size(), 'Details must not consume the metrics transaction budget');
        Assert.areEqual(2, response.segments.size(), 'Both reporting segments should remain visible');
        FieldUsageController.SegmentSummary cmsl;
        for (FieldUsageController.SegmentSummary segment : response.segments) {
            if (segment.reportingGroup == 'CMSL') {
                cmsl = segment;
            }
        }
        Assert.isNotNull(cmsl, 'The CMSL summary should exist');
        Assert.areEqual(250, cmsl.recordsAnalyzed, 'Analysis samples must not be double-counted across statuses');
        Assert.areEqual(200, cmsl.previousRecordsAnalyzed, 'Previous samples must be counted once');
        Assert.areEqual(12.5, cmsl.previousAveragePopulationPercent,
            'Rows without previous analysis dates must not dilute previous averages');
    }

    @isTest
    static void shouldCountOnlyGroups_WhenAdministratorLoadsFilters() {
        DataDictionaryTestDataFactory.createUsageBudgetRows(251);
        User administrator = getDictionaryReader('ddsysadm');
        Integer queryRows;
        FieldUsageController.FilterOptions options;
        System.runAs(administrator) {
            Test.startTest();
            options = FieldUsageController.getFilterOptions();
            queryRows = Limits.getQueryRows();
            Test.stopTest();
        }
        Assert.areEqual(5, queryRows, 'Filter queries should count groups plus two profile checks, not evidence rows');
        Assert.areEqual(new List<String>{ 'CMSL', 'FDMS' }, options.alliances,
            'Optimized filters must preserve all authorized groups');
    }

    @isTest
    static void shouldRejectDetailRequest_WhenAllianceIsNotAuthorized() {
        System.runAs(getDictionaryReader('ddscope')) {
            Test.startTest();
            try {
                FieldUsageController.getUsageRows('FDMS', null, null, null);
                Assert.fail('The detail endpoint must independently enforce alliance restrictions');
            } catch (AuraHandledException exceptionValue) {
                Assert.isNotNull(exceptionValue, 'Unauthorized detail requests should be rejected');
            }
            Test.stopTest();
        }
    }

    @isTest
    static void shouldReturnNoDetails_WhenReaderHasNoAlliance() {
        FieldUsageController.UsageResponse response;
        System.runAs(getDictionaryReader('ddnone')) {
            Test.startTest();
            response = FieldUsageController.getUsageRows(null, null, null, null);
            Test.stopTest();
        }
        Assert.areEqual(0, response.rows.size(), 'Unentitled readers must see no details');
        Assert.isFalse(response.isTruncated, 'An empty authorized scope is not truncation');
    }

    private static FieldUsageController.UsageResponse getUsageWithRows(
        String alliance, String objectApiName, String usageStatus, String searchTerm
    ) {
        FieldUsageController.UsageResponse response =
            FieldUsageController.getUsage(alliance, objectApiName, usageStatus, searchTerm);
        response.rows =
            FieldUsageController.getUsageRows(alliance, objectApiName, usageStatus, searchTerm).rows;
        return response;
    }
}