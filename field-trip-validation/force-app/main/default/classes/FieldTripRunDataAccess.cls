/**
 * Retrieves governed run and artifact projections after the calling controller authorizes access.
 * The class is not exposed to Lightning and requires the Data Governance workbench permission.
 */
public without sharing class FieldTripRunDataAccess {
    private static final String ACCESS_PERMISSION = 'Access_Data_Governance_Workbenches';

    public static List<Field_Trip_Run__c> getRecentRuns(Integer rowLimit) {
        requireWorkbenchAccess();
        return Database.queryWithBinds(
            'SELECT Id, Name, Operation__c, Status__c, Start_Date__c, '
                + 'End_Date_Exclusive__c, Target_Org__c, Report_Groups__c, Requested_By__c, '
                + 'Requested_By__r.Name, CreatedDate, Started_At__c, Completed_At__c, '
                + 'Output_Folder_URL__c, Failure_Summary__c FROM Field_Trip_Run__c '
                + 'ORDER BY CreatedDate DESC LIMIT :rowLimit',
            new Map<String, Object>{ 'rowLimit' => rowLimit },
            AccessLevel.SYSTEM_MODE
        );
    }

    public static List<Field_Trip_Run_Item__c> getRunItems(Set<Id> runIds) {
        requireWorkbenchAccess();
        if (runIds.isEmpty()) {
            return new List<Field_Trip_Run_Item__c>();
        }
        return Database.queryWithBinds(
            'SELECT Id, Field_Trip_Run__c, Item_Type__c, Status__c, Object_API_Name__c, '
                + 'Report_Group__c, Apex_Job_Id__c, File_Name__c, File_Size__c, '
                + 'Checksum_SHA256__c, Download_URL__c, Error_Count__c, Failure_Summary__c '
                + 'FROM Field_Trip_Run_Item__c WHERE Field_Trip_Run__c IN :runIds '
                + 'ORDER BY CreatedDate',
            new Map<String, Object>{ 'runIds' => runIds },
            AccessLevel.SYSTEM_MODE
        );
    }

    public static Field_Trip_Run_Item__c getRunItem(Id reportItemId) {
        requireWorkbenchAccess();
        List<Field_Trip_Run_Item__c> items = Database.queryWithBinds(
            'SELECT Id, Item_Type__c, Status__c, Report_Group__c, Download_URL__c, '
                + 'Checksum_SHA256__c FROM Field_Trip_Run_Item__c '
                + 'WHERE Id = :reportItemId LIMIT 1',
            new Map<String, Object>{ 'reportItemId' => reportItemId },
            AccessLevel.SYSTEM_MODE
        );
        return items.isEmpty() ? null : items[0];
    }

    public static void openApprovalSubmissionGate(Id reportItemId) {
        requireWorkbenchAccess();
        Database.update(new Field_Trip_Run_Item__c(
            Id = reportItemId,
            Approval_Submission_Gate__c = true
        ), AccessLevel.SYSTEM_MODE);
    }

    public static Approval.ProcessResult submitForApproval(
        Approval.ProcessSubmitRequest request
    ) {
        requireWorkbenchAccess();
        return Approval.process(request);
    }

    public static Boolean hasPendingApproval(Id reportItemId) {
        requireWorkbenchAccess();
        List<SObject> pendingProcesses = Database.queryWithBinds(
            'SELECT Id FROM ProcessInstance '
                + 'WHERE TargetObjectId = :reportItemId AND Status = \'Pending\' LIMIT 1',
            new Map<String, Object>{ 'reportItemId' => reportItemId },
            AccessLevel.SYSTEM_MODE
        );
        return !pendingProcesses.isEmpty();
    }

    public static List<Field_Trip_Run_Item__c> getWorkbookItems(
        String alliance,
        Integer rowLimit
    ) {
        requireWorkbenchAccess();
        return Database.queryWithBinds(
            'SELECT Id, Name, Field_Trip_Run__c, Field_Trip_Run__r.Name, '
                + 'Field_Trip_Run__r.Start_Date__c, Field_Trip_Run__r.End_Date_Exclusive__c, '
                + 'Item_Type__c, Status__c, Report_Group__c, Object_API_Name__c, '
                + 'File_Name__c, File_Size__c, Checksum_SHA256__c, Download_URL__c, '
                + 'CreatedDate FROM Field_Trip_Run_Item__c '
                + 'WHERE Report_Group__c = :alliance AND Item_Type__c = \'Workbook\' '
                + 'ORDER BY CreatedDate DESC LIMIT :rowLimit',
            new Map<String, Object>{ 'alliance' => alliance, 'rowLimit' => rowLimit },
            AccessLevel.SYSTEM_MODE
        );
    }

    public static List<ProcessInstance> getProcessInstances(Set<Id> itemIds) {
        requireWorkbenchAccess();
        if (itemIds.isEmpty()) {
            return new List<ProcessInstance>();
        }
        return Database.queryWithBinds(
            'SELECT Id, TargetObjectId, Status, SubmittedBy.Name, CreatedDate, '
                + 'CompletedDate, LastActor.Name FROM ProcessInstance '
                + 'WHERE TargetObjectId IN :itemIds ORDER BY CreatedDate DESC',
            new Map<String, Object>{ 'itemIds' => itemIds },
            AccessLevel.SYSTEM_MODE
        );
    }

    public static List<ProcessInstanceStep> getProcessSteps(Set<Id> processIds) {
        requireWorkbenchAccess();
        if (processIds.isEmpty()) {
            return new List<ProcessInstanceStep>();
        }
        return Database.queryWithBinds(
            'SELECT Id, ProcessInstanceId, StepStatus, Actor.Name, Comments, CreatedDate '
                + 'FROM ProcessInstanceStep WHERE ProcessInstanceId IN :processIds '
                + 'ORDER BY CreatedDate DESC',
            new Map<String, Object>{ 'processIds' => processIds },
            AccessLevel.SYSTEM_MODE
        );
    }

    private static void requireWorkbenchAccess() {
        if (!FeatureManagement.checkPermission(ACCESS_PERMISSION)) {
            throw new SecurityException('Data Governance workbench access is required.');
        }
    }
}