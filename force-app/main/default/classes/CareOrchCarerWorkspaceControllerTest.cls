@IsTest
private inherited sharing class CareOrchCarerWorkspaceControllerTest {
    @TestSetup
    static void setupData() {
        Account contextAccount = new Account(Name = 'CareOrch Workspace Context');
        insert contextAccount;

        insert new List<Task>{
            new Task(
                OwnerId = UserInfo.getUserId(),
                Subject = 'Morning meds round',
                Status = 'Not Started',
                Priority = 'High',
                ActivityDate = Date.today(),
                WhatId = contextAccount.Id
            ),
            new Task(
                OwnerId = UserInfo.getUserId(),
                Subject = 'Closed task should be hidden',
                Status = 'Completed',
                Priority = 'Normal',
                ActivityDate = Date.today().addDays(-1),
                WhatId = contextAccount.Id
            )
        };
    }

    @IsTest
    static void getOpenTasksForCurrentCarer_returnsOnlyOpenTasks() {
        Test.startTest();
        List<CareOrchCarerWorkspaceController.WorkspaceTask> tasks =
            CareOrchCarerWorkspaceController.getOpenTasksForCurrentCarer();
        Test.stopTest();

        System.assertEquals(1, tasks.size());
        System.assertEquals('Morning meds round', tasks[0].subject);
        System.assertEquals('High', tasks[0].priority);
    }

    @IsTest
    static void completeTask_marksTaskCompleted() {
        Task openTask = [
            SELECT Id, Status
            FROM Task
            WHERE Subject = 'Morning meds round'
            WITH USER_MODE
            LIMIT 1
        ];

        Test.startTest();
        CareOrchCarerWorkspaceController.completeTask(openTask.Id);
        Test.stopTest();

        Task updatedTask = [
            SELECT Id, Status
            FROM Task
            WHERE Id = :openTask.Id
            WITH USER_MODE
            LIMIT 1
        ];
        System.assertEquals('Completed', updatedTask.Status);
    }
}