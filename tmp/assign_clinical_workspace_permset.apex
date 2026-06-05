Id userId = UserInfo.getUserId();
PermissionSet ps = [
    SELECT Id
    FROM PermissionSet
    WHERE Name = 'CareOrch_Clinical_Workspace'
    LIMIT 1
];
Integer existing = [
    SELECT COUNT()
    FROM PermissionSetAssignment
    WHERE AssigneeId = :userId
      AND PermissionSetId = :ps.Id
];

if (existing == 0) {
    insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id);
    System.debug('Assigned CareOrch_Clinical_Workspace to current user');
} else {
    System.debug('CareOrch_Clinical_Workspace already assigned to current user');
}
