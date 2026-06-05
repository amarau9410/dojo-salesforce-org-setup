public with sharing class CareOrchCarerWorkspaceController {
    public class WorkspaceTask {
        @AuraEnabled public Id taskId;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public Date activityDate;
        @AuraEnabled public Id whatId;
        @AuraEnabled public String whatName;
    }

    @AuraEnabled(cacheable=true)
    public static List<WorkspaceTask> getOpenTasksForCurrentCarer() {
        List<WorkspaceTask> workspaceTasks = new List<WorkspaceTask>();
        for (Task taskRecord : [
            SELECT Id, Subject, Status, Priority, ActivityDate, WhatId, What.Name
            FROM Task
            WHERE OwnerId = :UserInfo.getUserId()
            AND IsClosed = false
            WITH USER_MODE
            ORDER BY Priority DESC, ActivityDate ASC NULLS LAST, LastModifiedDate DESC
            LIMIT 25
        ]) {
            WorkspaceTask workspaceTask = new WorkspaceTask();
            workspaceTask.taskId = taskRecord.Id;
            workspaceTask.subject = taskRecord.Subject;
            workspaceTask.status = taskRecord.Status;
            workspaceTask.priority = taskRecord.Priority;
            workspaceTask.activityDate = taskRecord.ActivityDate;
            workspaceTask.whatId = taskRecord.WhatId;
            workspaceTask.whatName = taskRecord.What != null ? taskRecord.What.Name : null;
            workspaceTasks.add(workspaceTask);
        }
        return workspaceTasks;
    }

    @AuraEnabled
    public static void completeTask(Id taskId) {
        if (taskId == null) {
            throw new AuraHandledException('taskId is required');
        }

        List<Task> taskRecords = [
            SELECT Id, Status, IsClosed
            FROM Task
            WHERE Id = :taskId
            WITH USER_MODE
            LIMIT 1
        ];
        if (taskRecords.isEmpty()) {
            throw new AuraHandledException('Task not found');
        }

        Task taskRecord = taskRecords[0];
        if (taskRecord.IsClosed) {
            return;
        }

        taskRecord.Status = 'Completed';

        SObjectAccessDecision accessDecision = Security.stripInaccessible(
            AccessType.UPDATABLE,
            new List<SObject>{ taskRecord }
        );
        List<SObject> sanitizedRecords = accessDecision.getRecords();
        if (sanitizedRecords.isEmpty()) {
            throw new AuraHandledException('Task update access denied');
        }

        update as user (Task) sanitizedRecords[0];
    }
}