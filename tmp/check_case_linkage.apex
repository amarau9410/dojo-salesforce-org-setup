List<Case> casesToCheck = [
    SELECT Id, CaseNumber, Subject, AccountId, Account.Name, Account.ParentId, Account.Parent.Name, Legal_Entity_Account__c
    FROM Case
    WHERE Subject LIKE 'API complaint test case % - consolidated complaints'
    ORDER BY Subject
];
System.debug('CASE_COUNT=' + casesToCheck.size());
for (Case c : casesToCheck) {
    System.debug(
        'CASE=' + c.CaseNumber +
        ' ACCOUNT=' + c.Account.Name +
        ' PARENT=' + c.Account.Parent.Name +
        ' LEGAL_ENTITY_LOOKUP=' + c.Legal_Entity_Account__c
    );
}
