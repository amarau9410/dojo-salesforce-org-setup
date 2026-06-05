List<Account> updates = new List<Account>{
    new Account(Id='001S900001JnoeeIAB', ExternalCustomerId__c='197836976248146'),
    new Account(Id='001S900001Jo85bIAB', ExternalLocationId__c='111936622491984'),
    new Account(Id='001S900001JoPb6IAF', ExternalLocationId__c='114121022789124'),
    new Account(Id='001S900001JoPb7IAF', ExternalLocationId__c='791228222374621'),
    new Account(Id='001S900001JoPbAIAV', ExternalLocationId__c='462032142081052'),
    new Account(Id='001S900001JoPb8IAF', ExternalLocationId__c='709311332063515'),
    new Account(Id='001S900001JoPb9IAF', ExternalLocationId__c='293398324420722')
};
update updates;
System.debug('Updated Green Dragon parent and child external IDs: ' + updates.size());
