Task t = [
    SELECT Id, OwnerId, Subject, CareOrch_Shift_Status__c
    FROM Task
    WHERE Subject LIKE 'UAT Shift 20260601%'
    ORDER BY CreatedDate DESC
    LIMIT 1
];
Id targetCaregiverId = [
    SELECT AssigneeId
    FROM PermissionSetAssignment
    WHERE PermissionSet.Name = 'CareOrch_Floor_Carer'
      AND AssigneeId != :t.OwnerId
    LIMIT 1
].AssigneeId;

System.debug('Before owner=' + t.OwnerId + ' status=' + t.CareOrch_Shift_Status__c + ' task=' + t.Id);
CareOrchManagerCockpitController.reassignShift(t.Id, targetCaregiverId, 'UAT verify reassign');
Task updatedTask = [
    SELECT Id, OwnerId, CareOrch_Shift_Status__c, CareOrch_Handover_Comment__c
    FROM Task
    WHERE Id = :t.Id
    LIMIT 1
];
System.debug('After owner=' + updatedTask.OwnerId + ' status=' + updatedTask.CareOrch_Shift_Status__c + ' task=' + updatedTask.Id);
System.debug('Comment=' + updatedTask.CareOrch_Handover_Comment__c);
