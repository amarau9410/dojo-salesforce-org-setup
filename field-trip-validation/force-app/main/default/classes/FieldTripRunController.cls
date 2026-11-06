/**
 * Governs Field Trip Analyze and authoritative report requests from Lightning.
 */
public with sharing class FieldTripRunController {
    private static final Integer MAX_ANALYSIS_SELECTION = 200;
    private static final Integer MAX_RECENT_RUNS = 50;
    private static final Integer MAX_REPORT_ARTIFACTS = 20;
    private static final String APPROVAL_PROCESS_NAME = 'Field_Usage_Report_Approval';
    private static final String SUBMIT_APPROVAL_PERMISSION =
        'Submit_Field_Usage_Reports_For_Approval';
    private static final String RECOVER_RUN_PERMISSION = 'Recover_Field_Trip_Runs';
    @TestVisible private static Integer recoveryMinimumAgeMinutes = 30;
    private static final Set<String> REPORT_GROUPS = new Set<String>{
        'ADCB', 'AIBMS', 'Bidvest', 'CMSL', 'EMS', 'FDMS', 'UCBA', 'Unicaja', 'Vert'
    };
    @TestVisible private static List<Field_Trip__Object_Analysis__c> analysisTestRecords;
    @TestVisible private static List<Field_Trip_Run_Item__c> recoveryItemsTestRecords;

    /**
     * Returns environment, permission, available-analysis, and recent-run state.
     * @return State required to render the quarterly console.
     */
    @AuraEnabled(cacheable=true)
    public static ConsoleState getConsoleState() {
        try {
            Organization organization = [
                SELECT Id, Name, IsSandbox
                FROM Organization
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            ConsoleState state = new ConsoleState();
            state.organizationId = organization.Id;
            state.organizationName = organization.Name;
            state.isSandbox = organization.IsSandbox;
            state.targetOrg = resolveTargetOrg(
                organization.IsSandbox,
                URL.getOrgDomainUrl().getHost()
            );
            Boolean isAdministrator = FieldUsageController.isCurrentUserAdministrator();
            state.canLaunchAnalyze = isAdministrator
                && FeatureManagement.checkPermission('Launch_Field_Trip_Analyze');
            state.canGenerateReports = isAdministrator
                && FeatureManagement.checkPermission('Generate_Field_Trip_Reports');
            state.canDownloadReports = FeatureManagement.checkPermission('Download_Field_Trip_Reports');
            state.canManageRuns = isAdministrator;
            state.canRecoverRuns = isAdministrator
                && FeatureManagement.checkPermission(RECOVER_RUN_PERMISSION);
            state.activeBatchJobs = [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE JobType = 'BatchApex'
                    AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
            ];
            state.analyses = getAnalysisOptions();
            state.runs = getRecentRuns(
                state.canDownloadReports,
                FieldUsageController.getAuthorizedReportingGroups()
            );
            return state;
        } catch (Exception exceptionValue) {
            throw new AuraHandledException('The Field Trip quarterly console could not be loaded.');
        }
    }

    /**
     * Creates one governed Analyze request and one item per validated Object Analysis.
     * @param startDate Inclusive reporting-window start.
     * @param endDateExclusive Exclusive reporting-window end.
     * @param selectedAnalysisIds Managed-package Object Analysis IDs selected by the operator.
     * @param confirmedProduction Explicit production confirmation from the operator.
     * @return The created or existing idempotent run ID.
     */
    @AuraEnabled
    public static Id requestAnalyze(
        Date startDate,
        Date endDateExclusive,
        List<Id> selectedAnalysisIds,
        Boolean confirmedProduction
    ) {
        requirePermission('Launch_Field_Trip_Analyze', 'You do not have permission to launch Analyze jobs.');
        requireAdministrator('Only administrators can launch Field Trip Analyze jobs.');
        validateWindow(startDate, endDateExclusive);
        if (selectedAnalysisIds == null || selectedAnalysisIds.isEmpty()) {
            throw new AuraHandledException('Select at least one Object Analysis.');
        }

        Set<Id> uniqueAnalysisIds = new Set<Id>(selectedAnalysisIds);
        if (uniqueAnalysisIds.size() > MAX_ANALYSIS_SELECTION) {
            throw new AuraHandledException('No more than 200 Object Analyses can be submitted in one run.');
        }
        List<Field_Trip__Object_Analysis__c> analyses = getSelectedAnalyses(uniqueAnalysisIds);
        if (analyses.size() != uniqueAnalysisIds.size()) {
            throw new AuraHandledException('One or more selected Object Analyses are unavailable. Refresh and try again.');
        }
        EnvironmentContext environment = getEnvironment(confirmedProduction);
        List<String> orderedIds = new List<String>();
        for (Field_Trip__Object_Analysis__c analysis : analyses) {
            orderedIds.add(analysis.Id);
        }
        String scope = String.join(orderedIds, ',');
        String idempotencyKey = createIdempotencyKey('Analyze', startDate, endDateExclusive, scope);
        Id existingRunId = findExistingRun(idempotencyKey);
        if (existingRunId != null) {
            return existingRunId;
        }

        Field_Trip_Run__c run = createRun(
            'Analyze', startDate, endDateExclusive, environment, idempotencyKey
        );
        run.Status__c = 'Processing';
        run.Started_At__c = System.now();
        run.Analysis_Ids__c = String.join(orderedIds, '\n');
        Database.insert(run, AccessLevel.SYSTEM_MODE);

        List<Field_Trip_Run_Item__c> items = new List<Field_Trip_Run_Item__c>();
        for (Field_Trip__Object_Analysis__c analysis : analyses) {
            items.add(new Field_Trip_Run_Item__c(
                Field_Trip_Run__c = run.Id,
                Item_Type__c = 'Analyze Job',
                Status__c = 'Queued',
                Object_Analysis_Id__c = analysis.Id,
                Object_API_Name__c = analysis.Field_Trip__Object_Name__c
            ));
        }
        Database.insert(items, AccessLevel.SYSTEM_MODE);
        FieldTripAnalyzeScheduler.startProcessingIfIdle();
        return run.Id;
    }

    /**
     * Creates a governed authoritative-template report request.
     * @param startDate Inclusive analysis-result window start.
     * @param endDateExclusive Exclusive analysis-result window end.
     * @param selectedReportGroups Allowlisted report groups to generate.
     * @param confirmedProduction Explicit production confirmation from the operator.
     * @return The created or existing idempotent run ID.
     */
    @AuraEnabled
    public static Id requestReports(
        Date startDate,
        Date endDateExclusive,
        List<String> selectedReportGroups,
        Boolean confirmedProduction
    ) {
        requirePermission('Generate_Field_Trip_Reports', 'You do not have permission to generate reports.');
        requireAdministrator('Only administrators can generate Field Usage workbooks.');
        validateWindow(startDate, endDateExclusive);
        Set<String> uniqueGroups = normalizeReportGroups(selectedReportGroups);
        Set<String> authorizedGroups = FieldUsageController.getAuthorizedReportingGroups();
        if (authorizedGroups != null && !authorizedGroups.containsAll(uniqueGroups)) {
            throw new AuraHandledException(
                'You are not authorized to generate reports for one or more selected alliances.'
            );
        }
        EnvironmentContext environment = getEnvironment(confirmedProduction);
        List<String> orderedGroups = new List<String>(uniqueGroups);
        orderedGroups.sort();
        String scope = String.join(orderedGroups, ',');
        String idempotencyKey = createIdempotencyKey(
            'Generate Reports', startDate, endDateExclusive, scope
        );
        Id existingRunId = findExistingRun(idempotencyKey);
        if (existingRunId != null) {
            return existingRunId;
        }

        Field_Trip_Run__c run = createRun(
            'Generate Reports', startDate, endDateExclusive, environment, idempotencyKey
        );
        run.Report_Groups__c = String.join(orderedGroups, '\n');
        Database.insert(run, AccessLevel.SYSTEM_MODE);
        return run.Id;
    }

    /**
     * Removes one non-processing run and its child items from console history.
     * Approval-bound workbook evidence cannot be removed through this action.
     * @param runId Field Trip Run identifier selected in the console.
     */
    @AuraEnabled
    public static void removeRun(Id runId) {
        requireAdministrator('Only administrators can remove Field Trip runs.');
        if (runId == null) {
            throw new AuraHandledException('Select a Field Trip run to remove.');
        }

        List<Field_Trip_Run__c> runs = [
            SELECT Id, Status__c
            FROM Field_Trip_Run__c
            WHERE Id = :runId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (runs.isEmpty()) {
            throw new AuraHandledException(
                'The selected Field Trip run is unavailable. Refresh and try again.'
            );
        }
        Field_Trip_Run__c run = runs[0];
        if (run.Status__c == 'Processing') {
            throw new AuraHandledException(
                'This run is still processing. Reconcile or recover it before removal.'
            );
        }

        List<Field_Trip_Run_Item__c> items = [
            SELECT Id, Status__c
            FROM Field_Trip_Run_Item__c
            WHERE Field_Trip_Run__c = :run.Id
            WITH SYSTEM_MODE
        ];
        Set<Id> itemIds = new Map<Id, Field_Trip_Run_Item__c>(items).keySet();
        for (Field_Trip_Run_Item__c item : items) {
            if (item.Status__c == 'Processing') {
                throw new AuraHandledException(
                    'One or more run items are still processing. Wait or recover the run first.'
                );
            }
        }
        if (!FieldTripRunDataAccess.getProcessInstances(itemIds).isEmpty()) {
            throw new AuraHandledException(
                'This run contains approval history and must be retained as governance evidence.'
            );
        }

        Database.delete(run, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Returns generated workbook and approval evidence for one authorized alliance.
     * @param alliance Reporting alliance selected in the Field Usage workbench.
     * @return Report artifacts, permissions, approver choices, and approval history.
     */
    @AuraEnabled(cacheable=true)
    public static AllianceReportState getAllianceReportState(String alliance) {
        requireAuthorizedAlliance(alliance);
        AllianceReportState state = new AllianceReportState();
        state.alliance = alliance;
        state.canGenerateReports = FieldUsageController.isCurrentUserAdministrator()
            && FeatureManagement.checkPermission('Generate_Field_Trip_Reports');
        state.canDownloadReports = FeatureManagement.checkPermission(
            'Download_Field_Trip_Reports'
        );
        state.canSubmitForApproval = FeatureManagement.checkPermission(
            SUBMIT_APPROVAL_PERMISSION
        );
        state.approvers = state.canSubmitForApproval
            ? getEligibleApprovers(alliance)
            : new List<ApproverOption>();
        state.artifacts = getReportArtifacts(
            alliance,
            state.canDownloadReports,
            state.canSubmitForApproval
        );
        return state;
    }

    /**
     * Submits one completed, checksummed workbook to an authorized selected approver.
     * @param reportItemId Completed Field Trip workbook item.
     * @param approverId Active eligible approver selected by the requester.
     * @param comments Optional submission comments shown in approval history.
     * @return The Salesforce approval process instance ID.
     */
    @AuraEnabled
    public static Id submitReportForApproval(
        Id reportItemId,
        Id approverId,
        String comments
    ) {
        requirePermission(
            SUBMIT_APPROVAL_PERMISSION,
            'You do not have permission to submit Field Usage reports for approval.'
        );
        if (reportItemId == null || approverId == null) {
            throw new AuraHandledException('Select a completed report and an approver.');
        }

        Field_Trip_Run_Item__c reportItem = FieldTripRunDataAccess.getRunItem(reportItemId);
        if (reportItem == null) {
            throw new AuraHandledException('The selected report is unavailable.');
        }
        requireAuthorizedAlliance(reportItem.Report_Group__c);
        if (reportItem.Item_Type__c != 'Workbook'
            || reportItem.Status__c != 'Completed'
            || String.isBlank(reportItem.Download_URL__c)
            || String.isBlank(reportItem.Checksum_SHA256__c)) {
            throw new AuraHandledException(
                'Only a completed workbook with a download URL and checksum can be submitted.'
            );
        }
        if (FieldTripRunDataAccess.hasPendingApproval(reportItem.Id)) {
            throw new AuraHandledException(
                'This workbook already has a pending approval request.'
            );
        }

        Map<Id, ApproverOption> eligibleApproversById = new Map<Id, ApproverOption>();
        for (ApproverOption option : getEligibleApprovers(reportItem.Report_Group__c)) {
            eligibleApproversById.put(option.id, option);
        }
        if (!eligibleApproversById.containsKey(approverId)) {
            throw new AuraHandledException(
                'The selected user is not an eligible approver for this alliance.'
            );
        }

        FieldTripRunDataAccess.openApprovalSubmissionGate(reportItem.Id);

        Approval.ProcessSubmitRequest request = new Approval.ProcessSubmitRequest();
        request.setObjectId(reportItem.Id);
        request.setProcessDefinitionNameOrId(APPROVAL_PROCESS_NAME);
        request.setSkipEntryCriteria(false);
        request.setSubmitterId(UserInfo.getUserId());
        request.setNextApproverIds(new List<Id>{ approverId });
        if (!String.isBlank(comments)) {
            request.setComments(comments.trim().left(4000));
        }
        Approval.ProcessResult result = FieldTripRunDataAccess.submitForApproval(request);
        if (!result.isSuccess()) {
            throw new AuraHandledException('The report could not be submitted for approval.');
        }
        return result.getInstanceId();
    }

    /**
     * Marks a reconciled stuck Processing run as Failed and releases its idempotency key.
     * @param runId Processing run confirmed to have no active worker or Apex job.
     * @param reason Required operator evidence and recovery rationale.
     */
    @AuraEnabled
    public static void recoverRun(Id runId, String reason) {
        requirePermission(
            RECOVER_RUN_PERMISSION,
            'You do not have permission to recover Field Trip runs.'
        );
        requireAdministrator('Only administrators can recover Field Trip runs.');
        if (runId == null || String.isBlank(reason) || reason.trim().length() < 20) {
            throw new AuraHandledException(
                'Enter a recovery reason of at least 20 characters.'
            );
        }
        List<Field_Trip_Run__c> runs = [
            SELECT Id, Status__c, Idempotency_Key__c, LastModifiedDate
            FROM Field_Trip_Run__c
            WHERE Id = :runId
            WITH SYSTEM_MODE
            LIMIT 1
            FOR UPDATE
        ];
        if (runs.isEmpty() || runs[0].Status__c != 'Processing') {
            throw new AuraHandledException('Only a Processing run can be recovered.');
        }
        Field_Trip_Run__c run = runs[0];
        if (run.LastModifiedDate > System.now().addMinutes(-recoveryMinimumAgeMinutes)) {
            throw new AuraHandledException(
                'The run must be Processing for at least 30 minutes before recovery.'
            );
        }
        Set<Id> apexJobIds = new Set<Id>();
        Integer malformedJobIdCount = 0;
        for (Field_Trip_Run_Item__c item : getRecoveryRunItems(run.Id)) {
            try {
                apexJobIds.add((Id) item.Apex_Job_Id__c);
            } catch (StringException ignoredInvalidJobId) {
                malformedJobIdCount++;
            }
        }
        if (!apexJobIds.isEmpty() && [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE Id IN :apexJobIds
                AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
        ] > 0) {
            throw new AuraHandledException(
                'Recovery is blocked while a recorded Apex job is still active.'
            );
        }
        run.Status__c = 'Failed';
        run.Completed_At__c = System.now();
        run.Recovered_At__c = System.now();
        run.Recovered_By__c = UserInfo.getUserId();
        String recoveryEvidence = malformedJobIdCount == 0
            ? ''
            : ' Historical malformed Apex job IDs skipped: ' + malformedJobIdCount + '.';
        run.Recovery_Reason__c = reason.trim().left(32000 - recoveryEvidence.length())
            + recoveryEvidence;
        run.Failure_Summary__c = ('Recovered as failed: ' + reason.trim()).left(32000);
        String terminalSuffix = ':' + run.Id;
        if (!run.Idempotency_Key__c.endsWith(terminalSuffix)) {
            run.Idempotency_Key__c += terminalSuffix;
        }
        Database.update(run, AccessLevel.SYSTEM_MODE);
    }

    private static List<Field_Trip_Run_Item__c> getRecoveryRunItems(Id runId) {
        if (Test.isRunningTest() && recoveryItemsTestRecords != null) {
            return recoveryItemsTestRecords;
        }
        return [
            SELECT Apex_Job_Id__c
            FROM Field_Trip_Run_Item__c
            WHERE Field_Trip_Run__c = :runId AND Apex_Job_Id__c != null
            WITH SYSTEM_MODE
        ];
    }

    private static void requireAuthorizedAlliance(String alliance) {
        if (String.isBlank(alliance) || !REPORT_GROUPS.contains(alliance)) {
            throw new AuraHandledException('Select a supported reporting alliance.');
        }
        Set<String> authorizedGroups = FieldUsageController.getAuthorizedReportingGroups();
        if (authorizedGroups != null && !authorizedGroups.contains(alliance)) {
            throw new AuraHandledException(
                'You are not authorized to access reports for this alliance.'
            );
        }
    }

    private static void requireAdministrator(String message) {
        if (!FieldUsageController.isCurrentUserAdministrator()) {
            throw new AuraHandledException(message);
        }
    }

    private static List<ApproverOption> getEligibleApprovers(String alliance) {
        List<ApproverOption> options = new List<ApproverOption>();
        for (User candidate : FieldUsageApprovalAccess.getEligibleApprovers(alliance)) {
            options.add(new ApproverOption(candidate));
        }
        return options;
    }

    private static List<ReportArtifactRow> getReportArtifacts(
        String alliance,
        Boolean includeDownloadUrls,
        Boolean canSubmitForApproval
    ) {
        List<Field_Trip_Run_Item__c> items = FieldTripRunDataAccess.getWorkbookItems(
            alliance,
            MAX_REPORT_ARTIFACTS
        );
        Set<Id> itemIds = new Map<Id, Field_Trip_Run_Item__c>(items).keySet();
        Map<Id, ProcessInstance> latestProcessByItemId = new Map<Id, ProcessInstance>();
        Map<Id, ProcessInstanceStep> latestStepByProcessId =
            new Map<Id, ProcessInstanceStep>();
        if (!itemIds.isEmpty()) {
            for (ProcessInstance instanceValue :
                FieldTripRunDataAccess.getProcessInstances(itemIds)) {
                if (!latestProcessByItemId.containsKey(instanceValue.TargetObjectId)) {
                    latestProcessByItemId.put(instanceValue.TargetObjectId, instanceValue);
                }
            }
            Set<Id> processIds = new Map<Id, ProcessInstance>(
                latestProcessByItemId.values()
            ).keySet();
            if (!processIds.isEmpty()) {
                for (ProcessInstanceStep step :
                    FieldTripRunDataAccess.getProcessSteps(processIds)) {
                    if (!latestStepByProcessId.containsKey(step.ProcessInstanceId)) {
                        latestStepByProcessId.put(step.ProcessInstanceId, step);
                    }
                }
            }
        }

        List<ReportArtifactRow> rows = new List<ReportArtifactRow>();
        for (Field_Trip_Run_Item__c item : items) {
            ProcessInstance instanceValue = latestProcessByItemId.get(item.Id);
            ProcessInstanceStep step = instanceValue == null
                ? null
                : latestStepByProcessId.get(instanceValue.Id);
            rows.add(new ReportArtifactRow(
                item,
                instanceValue,
                step,
                includeDownloadUrls,
                canSubmitForApproval
            ));
        }
        return rows;
    }

    private static List<AnalysisOption> getAnalysisOptions() {
        List<AnalysisOption> options = new List<AnalysisOption>();
        List<Field_Trip__Object_Analysis__c> analyses = Test.isRunningTest()
            && analysisTestRecords != null
            ? analysisTestRecords
            : [
            SELECT Id, Name, Field_Trip__Object_Name__c, Field_Trip__Filter__c,
                Field_Trip__Last_Analyzed__c
            FROM Field_Trip__Object_Analysis__c
            WITH USER_MODE
            ORDER BY Field_Trip__Object_Name__c, Name
            LIMIT 1000
        ];
        for (Field_Trip__Object_Analysis__c analysis : analyses) {
            options.add(new AnalysisOption(analysis));
        }
        return options;
    }

    private static List<Field_Trip__Object_Analysis__c> getSelectedAnalyses(Set<Id> analysisIds) {
        if (Test.isRunningTest() && analysisTestRecords != null) {
            List<Field_Trip__Object_Analysis__c> selectedAnalyses =
                new List<Field_Trip__Object_Analysis__c>();
            for (Field_Trip__Object_Analysis__c analysis : analysisTestRecords) {
                if (analysisIds.contains(analysis.Id)) {
                    selectedAnalyses.add(analysis);
                }
            }
            return selectedAnalyses;
        }
        return [
            SELECT Id, Name, Field_Trip__Object_Name__c
            FROM Field_Trip__Object_Analysis__c
            WHERE Id IN :analysisIds
            WITH USER_MODE
            ORDER BY Field_Trip__Object_Name__c, Name
        ];
    }

    private static List<RunRow> getRecentRuns(
        Boolean includeDownloadUrls,
        Set<String> authorizedGroups
    ) {
        List<Field_Trip_Run__c> runs = FieldTripRunDataAccess.getRecentRuns(MAX_RECENT_RUNS);
        List<Field_Trip_Run__c> visibleRuns = new List<Field_Trip_Run__c>();
        for (Field_Trip_Run__c run : runs) {
            if (isRunVisible(run, authorizedGroups)) {
                visibleRuns.add(run);
            }
        }
        runs = visibleRuns;
        Set<Id> runIds = new Map<Id, Field_Trip_Run__c>(runs).keySet();
        Map<Id, List<ItemRow>> itemsByRunId = new Map<Id, List<ItemRow>>();
        if (!runIds.isEmpty()) {
            for (Field_Trip_Run_Item__c item : FieldTripRunDataAccess.getRunItems(runIds)) {
                if (!itemsByRunId.containsKey(item.Field_Trip_Run__c)) {
                    itemsByRunId.put(item.Field_Trip_Run__c, new List<ItemRow>());
                }
                itemsByRunId.get(item.Field_Trip_Run__c).add(
                    new ItemRow(item, includeDownloadUrls)
                );
            }
        }
        List<RunRow> rows = new List<RunRow>();
        for (Field_Trip_Run__c run : runs) {
            rows.add(new RunRow(run, itemsByRunId.get(run.Id), includeDownloadUrls));
        }
        return rows;
    }

    @TestVisible
    private static Boolean isRunVisible(
        Field_Trip_Run__c run,
        Set<String> authorizedGroups
    ) {
        if (authorizedGroups == null) {
            return true;
        }
        if (run.Operation__c != 'Generate Reports') {
            return false;
        }
        if (String.isBlank(run.Report_Groups__c)) {
            return false;
        }
        Set<String> runGroups = new Set<String>();
        for (String groupName : run.Report_Groups__c.split('\n')) {
            if (!String.isBlank(groupName)) {
                runGroups.add(groupName.trim());
            }
        }
        return !runGroups.isEmpty() && authorizedGroups.containsAll(runGroups);
    }

    private static void validateWindow(Date startDate, Date endDateExclusive) {
        if (startDate == null || endDateExclusive == null || endDateExclusive <= startDate) {
            throw new AuraHandledException('Enter a valid reporting window with the end after the start.');
        }
        if (startDate.addYears(2) < endDateExclusive) {
            throw new AuraHandledException('The reporting window cannot exceed two years.');
        }
    }

    private static Set<String> normalizeReportGroups(List<String> selectedReportGroups) {
        if (selectedReportGroups == null || selectedReportGroups.isEmpty()) {
            throw new AuraHandledException('Select at least one report group.');
        }
        Set<String> groups = new Set<String>();
        for (String groupName : selectedReportGroups) {
            if (!REPORT_GROUPS.contains(groupName)) {
                throw new AuraHandledException('An unsupported report group was selected.');
            }
            groups.add(groupName);
        }
        return groups;
    }

    private static void requirePermission(String permissionName, String message) {
        if (!FeatureManagement.checkPermission(permissionName)) {
            throw new AuraHandledException(message);
        }
    }

    private static EnvironmentContext getEnvironment(Boolean confirmedProduction) {
        Organization organization = [
            SELECT Id, Name, IsSandbox FROM Organization WITH SYSTEM_MODE LIMIT 1
        ];
        if (!organization.IsSandbox && confirmedProduction != true) {
            throw new AuraHandledException('Confirm the production operation before submitting.');
        }
        return new EnvironmentContext(
            organization.Id,
            resolveTargetOrg(organization.IsSandbox, URL.getOrgDomainUrl().getHost()),
            !organization.IsSandbox && confirmedProduction == true
        );
    }

    @TestVisible
    private static String resolveTargetOrg(Boolean isSandbox, String orgDomainHost) {
        if (isSandbox != true) {
            return 'Prod';
        }
        String normalizedHost = String.isBlank(orgDomainHost)
            ? ''
            : orgDomainHost.toLowerCase();
        Integer sandboxSeparator = normalizedHost.indexOf('--');
        Integer sandboxSuffix = normalizedHost.indexOf('.sandbox', sandboxSeparator + 2);
        if (sandboxSeparator >= 0 && sandboxSuffix > sandboxSeparator + 2) {
            return normalizedHost.substring(sandboxSeparator + 2, sandboxSuffix);
        }
        return normalizedHost;
    }

    private static Field_Trip_Run__c createRun(
        String operation,
        Date startDate,
        Date endDateExclusive,
        EnvironmentContext environment,
        String idempotencyKey
    ) {
        return new Field_Trip_Run__c(
            Operation__c = operation,
            Status__c = 'Requested',
            Start_Date__c = startDate,
            End_Date_Exclusive__c = endDateExclusive,
            Target_Org__c = environment.targetOrg,
            Salesforce_Org_Id__c = environment.organizationId,
            Idempotency_Key__c = idempotencyKey,
            Confirmed_Production__c = environment.confirmedProduction,
            Requested_By__c = UserInfo.getUserId()
        );
    }

    private static String createIdempotencyKey(
        String operation,
        Date startDate,
        Date endDateExclusive,
        String scope
    ) {
        String source = String.join(new List<String>{
            UserInfo.getOrganizationId(), operation, String.valueOf(startDate),
            String.valueOf(endDateExclusive), scope
        }, '|');
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(source)));
    }

    private static Id findExistingRun(String idempotencyKey) {
        List<Field_Trip_Run__c> existingRuns = [
            SELECT Id
            FROM Field_Trip_Run__c
            WHERE Idempotency_Key__c = :idempotencyKey
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return existingRuns.isEmpty() ? null : existingRuns[0].Id;
    }

    private class EnvironmentContext {
        private String organizationId;
        private String targetOrg;
        private Boolean confirmedProduction;

        private EnvironmentContext(
            String organizationId,
            String targetOrg,
            Boolean confirmedProduction
        ) {
            this.organizationId = organizationId;
            this.targetOrg = targetOrg;
            this.confirmedProduction = confirmedProduction;
        }
    }

    /** State returned to the quarterly Lightning console. */
    public class ConsoleState {
        @AuraEnabled public String organizationId;
        @AuraEnabled public String organizationName;
        @AuraEnabled public Boolean isSandbox;
        @AuraEnabled public String targetOrg;
        @AuraEnabled public Boolean canLaunchAnalyze;
        @AuraEnabled public Boolean canGenerateReports;
        @AuraEnabled public Boolean canDownloadReports;
        @AuraEnabled public Boolean canManageRuns;
        @AuraEnabled public Boolean canRecoverRuns;
        @AuraEnabled public Integer activeBatchJobs;
        @AuraEnabled public List<AnalysisOption> analyses;
        @AuraEnabled public List<RunRow> runs;
    }

    /** Selectable managed-package Object Analysis. */
    public class AnalysisOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String filter;
        @AuraEnabled public Datetime lastAnalyzedAt;

        private AnalysisOption(Field_Trip__Object_Analysis__c source) {
            id = source.Id;
            name = source.Name;
            objectApiName = source.Field_Trip__Object_Name__c;
            filter = source.Field_Trip__Filter__c;
            lastAnalyzedAt = source.Field_Trip__Last_Analyzed__c;
        }
    }

    /** Governed run displayed in recent activity. */
    public class RunRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String operation;
        @AuraEnabled public String status;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDateExclusive;
        @AuraEnabled public String targetOrg;
        @AuraEnabled public String requestedBy;
        @AuraEnabled public Datetime requestedAt;
        @AuraEnabled public Datetime startedAt;
        @AuraEnabled public Datetime completedAt;
        @AuraEnabled public String outputFolderUrl;
        @AuraEnabled public String failureSummary;
        @AuraEnabled public Boolean canDelete;
        @AuraEnabled public List<ItemRow> items;

        private RunRow(
            Field_Trip_Run__c source,
            List<ItemRow> itemRows,
            Boolean includeDownloadUrls
        ) {
            id = source.Id;
            name = source.Name;
            operation = source.Operation__c;
            status = source.Status__c;
            startDate = source.Start_Date__c;
            endDateExclusive = source.End_Date_Exclusive__c;
            targetOrg = source.Target_Org__c;
            requestedBy = source.Requested_By__r?.Name;
            requestedAt = source.CreatedDate;
            startedAt = source.Started_At__c;
            completedAt = source.Completed_At__c;
            outputFolderUrl = includeDownloadUrls ? source.Output_Folder_URL__c : null;
            failureSummary = source.Failure_Summary__c;
            canDelete = source.Status__c != 'Processing';
            items = itemRows ?? new List<ItemRow>();
        }
    }

    /** Analyze job or generated artifact displayed beneath a run. */
    public class ItemRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String itemType;
        @AuraEnabled public String status;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String reportGroup;
        @AuraEnabled public String apexJobId;
        @AuraEnabled public String fileName;
        @AuraEnabled public Decimal fileSize;
        @AuraEnabled public String checksumSha256;
        @AuraEnabled public String downloadUrl;
        @AuraEnabled public Decimal errorCount;
        @AuraEnabled public String failureSummary;

        private ItemRow(Field_Trip_Run_Item__c source, Boolean includeDownloadUrls) {
            id = source.Id;
            itemType = source.Item_Type__c;
            status = source.Status__c;
            objectApiName = source.Object_API_Name__c;
            reportGroup = source.Report_Group__c;
            apexJobId = source.Apex_Job_Id__c;
            fileName = source.File_Name__c;
            fileSize = source.File_Size__c;
            checksumSha256 = source.Checksum_SHA256__c;
            downloadUrl = includeDownloadUrls ? source.Download_URL__c : null;
            errorCount = source.Error_Count__c;
            failureSummary = source.Failure_Summary__c;
        }
    }

    /** Alliance-scoped report and approval state for the Field Usage workbench. */
    public class AllianceReportState {
        @AuraEnabled public String alliance;
        @AuraEnabled public Boolean canGenerateReports;
        @AuraEnabled public Boolean canDownloadReports;
        @AuraEnabled public Boolean canSubmitForApproval;
        @AuraEnabled public List<ApproverOption> approvers;
        @AuraEnabled public List<ReportArtifactRow> artifacts;
    }

    /** Eligible active approver for the selected alliance. */
    public class ApproverOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public String email;

        private ApproverOption(User candidate) {
            id = candidate.Id;
            email = candidate.Email;
            label = String.isBlank(candidate.Email)
                ? candidate.Name
                : candidate.Name + ' (' + candidate.Email + ')';
        }
    }

    /** Generated workbook and its latest native approval audit evidence. */
    public class ReportArtifactRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String runName;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDateExclusive;
        @AuraEnabled public String reportGroup;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fileName;
        @AuraEnabled public Decimal fileSize;
        @AuraEnabled public String checksumSha256;
        @AuraEnabled public String downloadUrl;
        @AuraEnabled public Datetime generatedAt;
        @AuraEnabled public String approvalStatus;
        @AuraEnabled public String submittedBy;
        @AuraEnabled public Datetime submittedAt;
        @AuraEnabled public String decidedBy;
        @AuraEnabled public Datetime decidedAt;
        @AuraEnabled public String approvalComments;
        @AuraEnabled public Boolean canSubmit;

        private ReportArtifactRow(
            Field_Trip_Run_Item__c item,
            ProcessInstance instanceValue,
            ProcessInstanceStep step,
            Boolean includeDownloadUrl,
            Boolean canSubmitForApproval
        ) {
            id = item.Id;
            runName = item.Field_Trip_Run__r?.Name;
            startDate = item.Field_Trip_Run__r?.Start_Date__c;
            endDateExclusive = item.Field_Trip_Run__r?.End_Date_Exclusive__c;
            reportGroup = item.Report_Group__c;
            objectApiName = item.Object_API_Name__c;
            fileName = item.File_Name__c;
            fileSize = item.File_Size__c;
            checksumSha256 = item.Checksum_SHA256__c;
            downloadUrl = includeDownloadUrl ? item.Download_URL__c : null;
            generatedAt = item.CreatedDate;
            approvalStatus = instanceValue == null ? 'Not Submitted' : instanceValue.Status;
            submittedBy = instanceValue?.SubmittedBy?.Name;
            submittedAt = instanceValue?.CreatedDate;
            decidedBy = instanceValue?.LastActor?.Name;
            decidedAt = instanceValue?.CompletedDate;
            approvalComments = step?.Comments;
            canSubmit = canSubmitForApproval
                && item.Status__c == 'Completed'
                && !String.isBlank(item.Download_URL__c)
                && !String.isBlank(item.Checksum_SHA256__c)
                && (instanceValue == null
                    || instanceValue.Status == 'Rejected'
                    || instanceValue.Status == 'Removed');
        }
    }
}