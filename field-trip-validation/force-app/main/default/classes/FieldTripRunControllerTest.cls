@isTest
private class FieldTripRunControllerTest {
    @isTest
    static void shouldRemoveNonProcessingRunAndItems_WhenAdministratorIsAuthorized() {
        User administrator = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Report_Generator' }
        );
        Id runId;
        System.runAs(administrator) {
            runId = FieldTripRunController.requestReports(
                Date.newInstance(2026, 6, 1), Date.newInstance(2026, 7, 1),
                new List<String>{ 'CMSL' }, true
            );
            FieldTripRunTestDataFactory.createCompletedWorkbook(runId, 'CMSL');

            Test.startTest();
            FieldTripRunController.removeRun(runId);
            Test.stopTest();
        }

        Assert.areEqual(0, [SELECT COUNT() FROM Field_Trip_Run__c WHERE Id = :runId],
            'The selected run should be removed');
        Assert.areEqual(0, [
            SELECT COUNT() FROM Field_Trip_Run_Item__c WHERE Field_Trip_Run__c = :runId
            WITH SYSTEM_MODE
        ], 'Cascade deletion should remove the run items');
    }

    @isTest
    static void shouldRejectRemoval_WhenRunIsProcessing() {
        User administrator = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>()
        );
        Field_Trip_Run__c run = new Field_Trip_Run__c(
            Operation__c = 'Analyze', Status__c = 'Processing',
            Start_Date__c = Date.today().addMonths(-1), End_Date_Exclusive__c = Date.today(),
            Target_Org__c = 'warthog', Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
            Idempotency_Key__c = 'processing-removal-test', Confirmed_Production__c = false,
            Requested_By__c = administrator.Id
        );
        Boolean wasRejected = false;

        System.runAs(administrator) {
            Database.insert(run, AccessLevel.SYSTEM_MODE);
            Test.startTest();
            try {
                FieldTripRunController.removeRun(run.Id);
                Assert.fail('A Processing run must not be removed');
            } catch (AuraHandledException exceptionValue) {
                wasRejected = true;
            }
            Test.stopTest();
        }

        Assert.isTrue(wasRejected, 'Processing runs should use governed recovery');
        Assert.areEqual(1, [SELECT COUNT() FROM Field_Trip_Run__c WHERE Id = :run.Id],
            'A rejected removal must retain the run');
    }

    @isTest
    static void shouldRejectRemoval_WhenRunItemIsProcessing() {
        User administrator = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Report_Generator' }
        );
        Id runId;
        System.runAs(administrator) {
            runId = FieldTripRunController.requestReports(
                Date.newInstance(2026, 6, 1), Date.newInstance(2026, 7, 1),
                new List<String>{ 'CMSL' }, true
            );
            Database.insert(new Field_Trip_Run_Item__c(
                Field_Trip_Run__c = runId,
                Item_Type__c = 'Workbook',
                Status__c = 'Processing',
                Report_Group__c = 'CMSL'
            ), AccessLevel.SYSTEM_MODE);

            Test.startTest();
            try {
                FieldTripRunController.removeRun(runId);
                Assert.fail('A run with a Processing item must not be removed');
            } catch (AuraHandledException exceptionValue) {
                Assert.isNotNull(exceptionValue, 'The rejection should be surfaced to the console');
            }
            Test.stopTest();
        }

        Assert.areEqual(1, [SELECT COUNT() FROM Field_Trip_Run__c WHERE Id = :runId],
            'A run with active child work must be retained');
    }

    @isTest
    static void shouldRejectRemoval_WhenUserIsNotAdministrator() {
        User administrator = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Report_Generator' }
        );
        User operatorUser = FieldTripRunTestDataFactory.createOperator(new List<String>());
        Id runId;
        System.runAs(administrator) {
            runId = FieldTripRunController.requestReports(
                Date.newInstance(2026, 6, 1), Date.newInstance(2026, 7, 1),
                new List<String>{ 'CMSL' }, true
            );
        }
        Boolean wasRejected = false;

        System.runAs(operatorUser) {
            Test.startTest();
            try {
                FieldTripRunController.removeRun(runId);
                Assert.fail('A non-administrator must not remove runs');
            } catch (AuraHandledException exceptionValue) {
                wasRejected = true;
            }
            Test.stopTest();
        }

        Assert.isTrue(wasRejected, 'Run removal should require Modify All Data');
        Assert.areEqual(1, [SELECT COUNT() FROM Field_Trip_Run__c WHERE Id = :runId],
            'An unauthorized attempt must retain the run');
    }

    @isTest
    static void shouldRecoverOnlyStaleProcessingRun_WhenAdministratorIsAuthorized() {
        assertStaleRunRecovery(false);
    }

    @isTest
    static void shouldAuditMalformedJobIds_WhenRecoveringStaleRun() {
        assertStaleRunRecovery(true);
    }

    private static void assertStaleRunRecovery(Boolean hasMalformedJobId) {
        User administrator = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Run_Recovery' }
        );
        Field_Trip_Run__c run = new Field_Trip_Run__c(
            Operation__c = 'Generate Reports',
            Status__c = 'Processing',
            Start_Date__c = Date.today().addMonths(-1),
            End_Date_Exclusive__c = Date.today(),
            Target_Org__c = 'warthog',
            Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
            Idempotency_Key__c = 'recovery-test',
            Confirmed_Production__c = false,
            Requested_By__c = administrator.Id,
            Claimed_At__c = System.now().addMinutes(-31),
            Started_At__c = System.now().addMinutes(-31)
        );
        System.runAs(administrator) {
            Database.insert(run, AccessLevel.SYSTEM_MODE);
            FieldTripRunController.recoveryMinimumAgeMinutes = -1;
            FieldTripRunController.recoveryItemsTestRecords =
                new List<Field_Trip_Run_Item__c>();
            if (hasMalformedJobId) {
                FieldTripRunController.recoveryItemsTestRecords.add(
                    new Field_Trip_Run_Item__c(Apex_Job_Id__c = 'malformed')
                );
            }
            Test.startTest();
            FieldTripRunController.recoverRun(
                run.Id,
                'Worker host and Apex job evidence were reconciled before recovery.'
            );
            Test.stopTest();
        }

        Id recoveredRunId = run.Id;
        Field_Trip_Run__c recoveredRun = (Field_Trip_Run__c) Database.query(
            'SELECT Status__c, Idempotency_Key__c, Recovery_Reason__c FROM Field_Trip_Run__c '
                + 'WHERE Id = :recoveredRunId',
            AccessLevel.SYSTEM_MODE
        );
        Assert.areEqual('Failed', recoveredRun.Status__c,
            'Recovery should terminalize the stuck run as Failed');
        Assert.isTrue(recoveredRun.Idempotency_Key__c.endsWith(':' + run.Id),
            'Recovery should release the active request key');
        String expectedReason =
            'Worker host and Apex job evidence were reconciled before recovery.';
        if (hasMalformedJobId) {
            expectedReason += ' Historical malformed Apex job IDs skipped: 1.';
        }
        Assert.areEqual(expectedReason, recoveredRun.Recovery_Reason__c,
            'Recovery must retain the operator evidence and audit skipped malformed IDs');
    }

    @isTest
    static void shouldRejectRecovery_WhenProcessingRunIsNotStale() {
        User administrator = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Run_Recovery' }
        );
        Field_Trip_Run__c run = new Field_Trip_Run__c(
            Operation__c = 'Generate Reports', Status__c = 'Processing',
            Start_Date__c = Date.today().addMonths(-1), End_Date_Exclusive__c = Date.today(),
            Target_Org__c = 'warthog', Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
            Idempotency_Key__c = 'recent-recovery-test', Confirmed_Production__c = false,
            Requested_By__c = administrator.Id, Claimed_At__c = System.now()
        );
        Boolean wasRejected = false;

        System.runAs(administrator) {
            Database.insert(run, AccessLevel.SYSTEM_MODE);
            try {
                FieldTripRunController.recoverRun(
                    run.Id,
                    'This recent run should not be eligible for administrator recovery.'
                );
                Assert.fail('A recent Processing run must not be recovered');
            } catch (AuraHandledException exceptionValue) {
                wasRejected = true;
            }
        }

        Assert.isTrue(wasRejected, 'The minimum recovery age should be enforced');
        Assert.areEqual('Processing', [
            SELECT Status__c FROM Field_Trip_Run__c WHERE Id = :run.Id
        ].Status__c, 'A rejected recovery must not mutate the run');
    }

    @isTest
    static void shouldCreateReportRequest_WhenOperatorIsAuthorized() {
        User operatorUser = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Report_Generator', 'Field_Trip_Report_Downloader' }
        );
        Id runId;
        System.runAs(operatorUser) {
            Test.startTest();
            runId = FieldTripRunController.requestReports(
                Date.newInstance(2026, 6, 1),
                Date.newInstance(2026, 7, 1),
                new List<String>{ 'FDMS', 'CMSL' },
                true
            );
            Test.stopTest();
        }

        Assert.isNotNull(runId, 'The request should return its governed run ID');
        Assert.areEqual(1, [SELECT COUNT() FROM Field_Trip_Run__c], 'One report run should be created');
        Field_Trip_Run__c run = [
            SELECT Confirmed_Production__c, Salesforce_Org_Id__c, Target_Org__c
            FROM Field_Trip_Run__c WHERE Id = :runId
            WITH SYSTEM_MODE
        ];
        Boolean isSandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
        Assert.areEqual(!isSandbox, run.Confirmed_Production__c,
            'Only Production requests should record Production confirmation');
        Assert.areEqual(UserInfo.getOrganizationId(), run.Salesforce_Org_Id__c,
            'The request must belong to the executing org');
        Assert.areEqual(
            FieldTripRunController.resolveTargetOrg(isSandbox, URL.getOrgDomainUrl().getHost()),
            run.Target_Org__c,
            'The request must target the executing environment'
        );
    }

    @isTest
    static void shouldEnforceEnvironmentGate_WhenProductionConfirmationIsFalse() {
        assertEnvironmentConfirmationGate(false);
    }

    @isTest
    static void shouldEnforceEnvironmentGate_WhenProductionConfirmationIsNull() {
        assertEnvironmentConfirmationGate(null);
    }

    private static void assertEnvironmentConfirmationGate(Boolean confirmedProduction) {
        User operatorUser = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Report_Generator' }
        );
        Boolean isSandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
        Boolean rejected = false;
        Id runId;
        System.runAs(operatorUser) {
            Test.startTest();
            try {
                runId = FieldTripRunController.requestReports(
                    Date.newInstance(2026, 6, 1), Date.newInstance(2026, 7, 1),
                    new List<String>{ 'FDMS' }, confirmedProduction
                );
            } catch (AuraHandledException exceptionValue) {
                rejected = true;
            }
            Test.stopTest();
        }
        Assert.areEqual(!isSandbox, rejected,
            'Unconfirmed requests must be rejected only in Production');
        Assert.areEqual(isSandbox ? 1 : 0, [SELECT COUNT() FROM Field_Trip_Run__c],
            'A rejected Production request must not persist a run');
        if (isSandbox) {
            Assert.isNotNull(runId, 'Sandbox requests do not require Production confirmation');
            Assert.isFalse([
                SELECT Confirmed_Production__c FROM Field_Trip_Run__c WHERE Id = :runId
            ].Confirmed_Production__c, 'Sandbox requests must not be marked as Production');
        }
    }

    @isTest
    static void shouldCreateAnalyzeItemsAndLoadConsole_WhenOperatorIsAuthorized() {
        User operatorUser = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{
                'Field_Trip_Analyze_Operator',
                'Field_Trip_Report_Generator',
                'Field_Trip_Report_Downloader'
            }
        );
        Id runId;
        FieldTripRunController.ConsoleState state;
        System.runAs(operatorUser) {
            Field_Trip__Object_Analysis__c analysis =
                FieldTripRunTestDataFactory.createAnalysis();
            FieldTripRunController.analysisTestRecords =
                new List<Field_Trip__Object_Analysis__c>{ analysis };
            Test.startTest();
            runId = FieldTripRunController.requestAnalyze(
                Date.newInstance(2026, 6, 1),
                Date.newInstance(2026, 7, 1),
                new List<Id>{ analysis.Id },
                true
            );
            state = FieldTripRunController.getConsoleState();
            Test.stopTest();
        }

        Assert.isNotNull(runId, 'Analyze should create a governed run');
        Field_Trip_Run__c requestedRun = [
            SELECT Status__c, Started_At__c, Claim_Token__c
            FROM Field_Trip_Run__c
            WHERE Id = :runId
            WITH SYSTEM_MODE
        ];
        Assert.areEqual('Processing', requestedRun.Status__c,
            'Analyze requests should be reserved for Salesforce-native processing');
        Assert.isNotNull(requestedRun.Started_At__c,
            'The Salesforce-native run should record when processing began');
        Assert.isNull(requestedRun.Claim_Token__c,
            'The Windows report worker must not own native Analyze runs');
        Assert.areEqual(1, [SELECT COUNT() FROM Field_Trip_Run_Item__c],
            'One Analyze item should be created per selected analysis');
        Assert.isTrue(state.canLaunchAnalyze, 'The operator should have Analyze permission');
        Assert.isTrue(state.canGenerateReports, 'The operator should have report permission');
        Assert.isTrue(state.canDownloadReports, 'The operator should have download permission');
        Assert.isFalse(String.isBlank(state.targetOrg),
            'The console should derive the current sandbox name');
        Assert.areEqual(1, state.runs.size(), 'The created run should appear in recent activity');
        Assert.areEqual(1, state.runs[0].items.size(), 'The Analyze item should appear beneath the run');
    }

    @isTest
    static void shouldResolveCurrentEnvironment_FromOrgDomain() {
        Assert.areEqual(
            'admin',
            FieldTripRunController.resolveTargetOrg(
                true,
                'firstforce--admin.sandbox.my.salesforce.com'
            ),
            'The Admin sandbox should use its own environment name'
        );
        Assert.areEqual(
            'warthog',
            FieldTripRunController.resolveTargetOrg(
                true,
                'firstforce--warthog.sandbox.my.salesforce.com'
            ),
            'The Warthog sandbox should use its own environment name'
        );
        Assert.areEqual(
            'Prod',
            FieldTripRunController.resolveTargetOrg(false, 'firstforce.my.salesforce.com'),
            'Production should retain the explicit production label'
        );
    }

    @isTest
    static void shouldRejectAnalyze_WhenAllianceUserHasLaunchPermission() {
        User allianceUser = FieldTripRunTestDataFactory.createOperator(
            new List<String>{
                'Field_Trip_Analyze_Operator',
                'Field_Trip_Report_Generator',
                'Field_Trip_Report_Downloader'
            },
            new Set<String>{ 'CMSL' }
        );
        Boolean wasRejected = false;
        FieldTripRunController.ConsoleState state;
        System.runAs(allianceUser) {
            Field_Trip__Object_Analysis__c analysis =
                FieldTripRunTestDataFactory.createAnalysis();
            FieldTripRunController.analysisTestRecords =
                new List<Field_Trip__Object_Analysis__c>{ analysis };
            Test.startTest();
            state = FieldTripRunController.getConsoleState();
            try {
                FieldTripRunController.requestAnalyze(
                    Date.newInstance(2026, 6, 1), Date.newInstance(2026, 7, 1),
                    new List<Id>{ analysis.Id }, true
                );
                Assert.fail('An alliance user must not launch Analyze');
            } catch (AuraHandledException exceptionValue) {
                wasRejected = true;
            }
            Test.stopTest();
        }

        Assert.isTrue(wasRejected, 'Administrator status must be enforced server-side');
        Assert.isFalse(state.canLaunchAnalyze,
            'The console must not expose Analyze to alliance users');
        Assert.isFalse(state.canGenerateReports,
            'The console must not expose workbook generation to alliance users');
        Assert.areEqual(0, [SELECT COUNT() FROM Field_Trip_Run__c],
            'Rejected Analyze requests must not create a run');
    }

    @isTest
    static void shouldReturnExistingRun_WhenRequestIsDuplicated() {
        User operatorUser = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Report_Generator' }
        );
        Id firstRunId;
        Id secondRunId;
        System.runAs(operatorUser) {
            Test.startTest();
            firstRunId = FieldTripRunController.requestReports(
                Date.newInstance(2026, 6, 1), Date.newInstance(2026, 7, 1),
                new List<String>{ 'FDMS' }, true
            );
            secondRunId = FieldTripRunController.requestReports(
                Date.newInstance(2026, 6, 1), Date.newInstance(2026, 7, 1),
                new List<String>{ 'FDMS' }, true
            );
            Test.stopTest();
        }

        Assert.areEqual(firstRunId, secondRunId, 'Equivalent active requests should be idempotent');
        Assert.areEqual(1, [SELECT COUNT() FROM Field_Trip_Run__c], 'Only one request should be stored');
    }

    @isTest
    static void shouldRejectReportRequest_WhenGroupIsUnsupported() {
        User operatorUser = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Report_Generator' }
        );
        Boolean wasRejected = false;
        System.runAs(operatorUser) {
            Test.startTest();
            try {
                FieldTripRunController.requestReports(
                    Date.newInstance(2026, 6, 1), Date.newInstance(2026, 7, 1),
                    new List<String>{ 'Not Approved' }, true
                );
                Assert.fail('An unsupported group should be rejected');
            } catch (AuraHandledException exceptionValue) {
                wasRejected = true;
            }
            Test.stopTest();
        }
        Assert.isTrue(wasRejected, 'An unsupported report group should be rejected');
    }

    @isTest
    static void shouldRejectReportRequest_WhenAllianceUserHasGeneratorPermission() {
        User operatorUser = FieldTripRunTestDataFactory.createOperator(
            new List<String>{ 'Field_Trip_Report_Generator' },
            new Set<String>{ 'CMSL' }
        );
        Boolean wasRejected = false;
        System.runAs(operatorUser) {
            Test.startTest();
            try {
                FieldTripRunController.requestReports(
                    Date.newInstance(2026, 6, 1), Date.newInstance(2026, 7, 1),
                    new List<String>{ 'FDMS' }, true
                );
                Assert.fail('A report for another alliance should be rejected');
            } catch (AuraHandledException exceptionValue) {
                wasRejected = true;
            }
            Test.stopTest();
        }
        Assert.isTrue(wasRejected, 'Alliance users must not generate workbooks');
        Assert.areEqual(0, [SELECT COUNT() FROM Field_Trip_Run__c],
            'An unauthorized report request should not create a run');
    }

    @isTest
    static void shouldRejectReportRequest_WhenUserLacksPermission() {
        User operatorUser = FieldTripRunTestDataFactory.createOperator(new List<String>());
        Boolean wasRejected = false;
        System.runAs(operatorUser) {
            Test.startTest();
            try {
                FieldTripRunController.requestReports(
                    Date.newInstance(2026, 6, 1), Date.newInstance(2026, 7, 1),
                    new List<String>{ 'FDMS' }, true
                );
                Assert.fail('A user without the custom permission should be rejected');
            } catch (AuraHandledException exceptionValue) {
                wasRejected = true;
            }
            Test.stopTest();
        }
        Assert.isTrue(wasRejected, 'A user without the custom permission should be rejected');
    }

    @isTest
    static void shouldReturnOnlyAuthorizedArtifacts_WhenAllianceIsSelected() {
        User operatorUser = FieldTripRunTestDataFactory.createOperator(
            new List<String>{
                'Field_Trip_Report_Downloader',
                'Field_Usage_Report_Submitter'
            },
            new Set<String>{ 'CMSL' }
        );
        User administrator = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Report_Generator' }
        );
        Id cmslRunId;
        Field_Trip_Run_Item__c workbook;
        System.runAs(administrator) {
            cmslRunId = FieldTripRunController.requestReports(
                Date.newInstance(2026, 6, 1), Date.newInstance(2026, 7, 1),
                new List<String>{ 'CMSL' }, true
            );
            workbook = FieldTripRunTestDataFactory.createCompletedWorkbook(cmslRunId, 'CMSL');
        }

        FieldTripRunController.AllianceReportState state;
        Boolean rejectedOtherAlliance = false;
        System.runAs(operatorUser) {
            Test.startTest();
            state = FieldTripRunController.getAllianceReportState('CMSL');
            try {
                FieldTripRunController.getAllianceReportState('FDMS');
                Assert.fail('Another alliance report state should be rejected');
            } catch (AuraHandledException exceptionValue) {
                rejectedOtherAlliance = true;
            }
            Test.stopTest();
        }

        Assert.areEqual(1, state.artifacts.size(), 'The authorized workbook should be returned');
        Assert.areEqual('CMSL', state.artifacts[0].reportGroup,
            'Only the selected authorized alliance should be returned');
        Assert.isTrue(rejectedOtherAlliance, 'Cross-alliance report state must be rejected');
    }

    @isTest
    static void shouldHideOtherAllianceRuns_WhenConsoleLoads() {
        User cmslOperator = FieldTripRunTestDataFactory.createOperator(
            new List<String>{ 'Field_Trip_Report_Downloader' },
            new Set<String>{ 'CMSL' }
        );
        User administrator = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Report_Generator' }
        );
        System.runAs(administrator) {
            FieldTripRunController.requestReports(
                Date.newInstance(2026, 6, 1), Date.newInstance(2026, 7, 1),
                new List<String>{ 'CMSL' }, true
            );
        }
        System.runAs(administrator) {
            FieldTripRunController.requestReports(
                Date.newInstance(2026, 6, 1), Date.newInstance(2026, 7, 1),
                new List<String>{ 'FDMS' }, true
            );
        }

        List<Field_Trip_Run__c> runs = [
            SELECT Id, Operation__c, Report_Groups__c, Requested_By__c
            FROM Field_Trip_Run__c
            WITH SYSTEM_MODE
        ];
        Integer visibleRunCount = 0;
        System.runAs(cmslOperator) {
            Test.startTest();
            for (Field_Trip_Run__c run : runs) {
                if (FieldTripRunController.isRunVisible(run, new Set<String>{ 'CMSL' })) {
                    visibleRunCount++;
                    Assert.areEqual('CMSL', run.Report_Groups__c,
                        'Only the CMSL report run should be visible');
                }
            }
            Test.stopTest();
        }

        Assert.areEqual(1, visibleRunCount,
            'The console should omit report runs for other alliances');
    }

    @isTest
    static void shouldRejectApproval_WhenApproverHasDifferentAlliance() {
        User submitter = FieldTripRunTestDataFactory.createOperator(
            new List<String>{ 'Field_Usage_Report_Submitter' },
            new Set<String>{ 'CMSL' }
        );
        User fdmsApprover = FieldTripRunTestDataFactory.createOperator(
            new List<String>{ 'Field_Usage_Report_Approver' },
            new Set<String>{ 'FDMS' }
        );
        User administrator = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Report_Generator' }
        );
        Id runId;
        Field_Trip_Run_Item__c workbook;
        System.runAs(administrator) {
            runId = FieldTripRunController.requestReports(
                Date.newInstance(2026, 6, 1), Date.newInstance(2026, 7, 1),
                new List<String>{ 'CMSL' }, true
            );
            workbook = FieldTripRunTestDataFactory.createCompletedWorkbook(runId, 'CMSL');
        }

        Boolean wasRejected = false;
        System.runAs(submitter) {
            Test.startTest();
            try {
                FieldTripRunController.submitReportForApproval(
                    workbook.Id,
                    fdmsApprover.Id,
                    'Please review.'
                );
                Assert.fail('A different-alliance approver should be rejected');
            } catch (AuraHandledException exceptionValue) {
                wasRejected = true;
            }
            Test.stopTest();
        }

        Assert.isTrue(wasRejected, 'The selected approver must share the report alliance');
        Assert.areEqual(0, [SELECT COUNT() FROM ProcessInstance],
            'Rejected routing must not create an approval process');
    }

    @isTest
    static void shouldCreateApprovalAudit_WhenApproverIsEligible() {
        User submitter = FieldTripRunTestDataFactory.createOperator(
            new List<String>{ 'Field_Usage_Report_Submitter' },
            new Set<String>{ 'CMSL' }
        );
        User cmslApprover = FieldTripRunTestDataFactory.createOperator(
            new List<String>{ 'Field_Usage_Report_Approver' },
            new Set<String>{ 'CMSL' }
        );
        User administrator = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Report_Generator' }
        );
        Id runId;
        Field_Trip_Run_Item__c workbook;
        System.runAs(administrator) {
            runId = FieldTripRunController.requestReports(
                Date.newInstance(2026, 6, 1), Date.newInstance(2026, 7, 1),
                new List<String>{ 'CMSL' }, true
            );
            workbook = FieldTripRunTestDataFactory.createCompletedWorkbook(runId, 'CMSL');
        }

        Assert.areEqual(1, [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :cmslApprover.Id
                AND PermissionSet.Name = 'Field_Usage_Report_Approver'
        ], 'The selected approver should hold the dedicated permission set');
        Assert.isTrue([
            SELECT Visible_Alliance_CMSL__c
            FROM User
            WHERE Id = :cmslApprover.Id
        ].Visible_Alliance_CMSL__c, 'The selected approver should have CMSL visibility');
        User approverWithAlliance = [
            SELECT Visible_Alliance_CMSL__c
            FROM User
            WHERE Id = :cmslApprover.Id
        ];
        Assert.isTrue(
            FieldUsageApprovalAccess.userHasAlliance(approverWithAlliance, 'CMSL'),
            'The approval helper should recognize the approver CMSL flag'
        );

        Id processInstanceId;
        System.runAs(submitter) {
            Assert.isTrue(
                FieldUsageApprovalAccess.getApproverCandidateIds().contains(cmslApprover.Id),
                'The setup-access helper should resolve the dedicated approver assignment'
            );
            FieldTripRunController.AllianceReportState state =
                FieldTripRunController.getAllianceReportState('CMSL');
            Assert.isTrue(state.canSubmitForApproval,
                'The requester should hold the submit-for-approval custom permission');
            Set<Id> eligibleApproverIds = new Set<Id>();
            for (FieldTripRunController.ApproverOption option : state.approvers) {
                eligibleApproverIds.add(option.id);
            }
            Assert.isTrue(eligibleApproverIds.contains(cmslApprover.Id),
                'The eligible approver options should include the selected same-alliance user');
            Test.startTest();
            processInstanceId = FieldTripRunController.submitReportForApproval(
                workbook.Id,
                cmslApprover.Id,
                'Please validate the CMSL workbook.'
            );
            Test.stopTest();
        }

        ProcessInstance instanceValue = [
            SELECT Id, TargetObjectId, Status, SubmittedById
            FROM ProcessInstance
            WHERE Id = :processInstanceId
        ];
        ProcessInstanceWorkitem workItem = [
            SELECT Id, ActorId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstanceId = :processInstanceId
        ];
        Assert.areEqual(workbook.Id, instanceValue.TargetObjectId,
            'The approval must be bound to the exact workbook item');
        Assert.areEqual('Pending', instanceValue.Status,
            'The submitted workbook should await a decision');
        Assert.areEqual(submitter.Id, instanceValue.SubmittedById,
            'Salesforce should retain the submitting user');
        Assert.areEqual(cmslApprover.Id, workItem.ActorId,
            'The work item should be assigned to the selected same-alliance approver');

        System.runAs(submitter) {
            FieldTripRunController.AllianceReportState submittedState =
                FieldTripRunController.getAllianceReportState('CMSL');
            Assert.areEqual('Pending', submittedState.artifacts[0].approvalStatus,
                'The authorized artifact projection should include pending approval history');
        }

        Boolean removalRejected = false;
        System.runAs(administrator) {
            try {
                FieldTripRunController.removeRun(runId);
                Assert.fail('A run with approval evidence must not be removed');
            } catch (AuraHandledException exceptionValue) {
                removalRejected = true;
            }
        }
        Assert.isTrue(removalRejected, 'Approval-bound workbook evidence must be retained');
        Assert.areEqual(1, [SELECT COUNT() FROM Field_Trip_Run__c WHERE Id = :runId],
            'Rejected approval-evidence removal must retain the run');
    }

    @isTest
    static void shouldRejectNativeApprovalSubmission_WhenControllerGateIsClosed() {
        User submitter = FieldTripRunTestDataFactory.createOperator(
            new List<String>{ 'Field_Usage_Report_Submitter' },
            new Set<String>{ 'CMSL' }
        );
        User approver = FieldTripRunTestDataFactory.createOperator(
            new List<String>{ 'Field_Usage_Report_Approver' },
            new Set<String>{ 'CMSL' }
        );
        User administrator = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Report_Generator' }
        );
        Field_Trip_Run_Item__c workbook;
        System.runAs(administrator) {
            Id runId = FieldTripRunController.requestReports(
                Date.newInstance(2026, 6, 1), Date.newInstance(2026, 7, 1),
                new List<String>{ 'CMSL' }, true
            );
            workbook = FieldTripRunTestDataFactory.createCompletedWorkbook(runId, 'CMSL');
        }

        Boolean nativeSubmissionRejected = false;
        System.runAs(submitter) {
            Approval.ProcessSubmitRequest request = new Approval.ProcessSubmitRequest();
            request.setObjectId(workbook.Id);
            request.setProcessDefinitionNameOrId('Field_Usage_Report_Approval');
            request.setSkipEntryCriteria(false);
            request.setSubmitterId(submitter.Id);
            request.setNextApproverIds(new List<Id>{ approver.Id });
            try {
                Approval.ProcessResult result = Approval.process(request);
                nativeSubmissionRejected = !result.isSuccess();
            } catch (DmlException exceptionValue) {
                nativeSubmissionRejected = true;
            }
        }

        Assert.isTrue(nativeSubmissionRejected,
            'Native submission must fail without the one-time controller gate');
        Assert.areEqual(0, [
            SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId = :workbook.Id
        ], 'A bypass attempt must not create approval audit records');
    }

    @isTest
    static void shouldReturnEmptyElevatedCollections_WhenNoIdsAreProvided() {
        User operatorUser = FieldTripRunTestDataFactory.createOperator(new List<String>());
        System.runAs(operatorUser) {
            Test.startTest();
            Assert.areEqual(0, FieldTripRunDataAccess.getRunItems(new Set<Id>()).size(),
                'No run IDs should return no child items');
            Assert.areEqual(0, FieldTripRunDataAccess.getProcessInstances(new Set<Id>()).size(),
                'No item IDs should return no approval processes');
            Assert.areEqual(0, FieldTripRunDataAccess.getProcessSteps(new Set<Id>()).size(),
                'No process IDs should return no approval steps');
            Test.stopTest();
        }
    }

    @isTest
    static void shouldRejectSecondSubmission_WhenApprovalIsPending() {
        User submitter = FieldTripRunTestDataFactory.createOperator(
            new List<String>{ 'Field_Usage_Report_Submitter' },
            new Set<String>{ 'CMSL' }
        );
        User approver = FieldTripRunTestDataFactory.createOperator(
            new List<String>{ 'Field_Usage_Report_Approver' },
            new Set<String>{ 'CMSL' }
        );
        User administrator = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Report_Generator' }
        );
        Id runId;
        Field_Trip_Run_Item__c workbook;
        System.runAs(administrator) {
            runId = FieldTripRunController.requestReports(
                Date.newInstance(2026, 6, 1), Date.newInstance(2026, 7, 1),
                new List<String>{ 'CMSL' }, true
            );
            workbook = FieldTripRunTestDataFactory.createCompletedWorkbook(runId, 'CMSL');
        }

        Boolean secondSubmissionRejected = false;
        System.runAs(submitter) {
            FieldTripRunController.submitReportForApproval(
                workbook.Id,
                approver.Id,
                'Initial submission.'
            );
            Test.startTest();
            try {
                FieldTripRunController.submitReportForApproval(
                    workbook.Id,
                    approver.Id,
                    'Duplicate submission.'
                );
                Assert.fail('A workbook with a pending approval must not be resubmitted');
            } catch (AuraHandledException exceptionValue) {
                secondSubmissionRejected = true;
            }
            Test.stopTest();
        }

        Assert.isTrue(secondSubmissionRejected,
            'The second submission should be rejected while approval is pending');
        Assert.areEqual(1, [
            SELECT COUNT()
            FROM ProcessInstance
            WHERE TargetObjectId = :workbook.Id
        ], 'Only one approval process should exist for the workbook');
    }

    @isTest
    static void shouldRejectReportRequest_WhenWindowIsInvalid() {
        User operatorUser = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Report_Generator' }
        );
        Boolean wasRejected = false;
        System.runAs(operatorUser) {
            Test.startTest();
            try {
                FieldTripRunController.requestReports(
                    Date.newInstance(2026, 7, 1), Date.newInstance(2026, 6, 1),
                    new List<String>{ 'FDMS' }, true
                );
                Assert.fail('An inverted reporting window should be rejected');
            } catch (AuraHandledException exceptionValue) {
                wasRejected = true;
            }
            Test.stopTest();
        }
        Assert.isTrue(wasRejected, 'An inverted reporting window should be rejected');
    }
}