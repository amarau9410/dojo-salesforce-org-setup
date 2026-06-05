List<Account> updates = new List<Account>{
    new Account(Id='001S900001Jo85bIAB', ParentId='001S900001Kj7EKIAZ', ExternalLocationId__c='111936622491984'),
    new Account(Id='001S900001JoPb6IAF', ParentId='001S900001Kj7EKIAZ', ExternalLocationId__c='114121022789124'),
    new Account(Id='001S900001JoPb7IAF', ParentId='001S900001Kj7EKIAZ', ExternalLocationId__c='791228222374621'),
    new Account(Id='001S900001JoPbAIAV', ParentId='001S900001Kj7EKIAZ', ExternalLocationId__c='462032142081052'),
    new Account(Id='001S900001JoPb8IAF', ParentId='001S900001Kj7EKIAZ', ExternalLocationId__c='709311332063515'),
    new Account(Id='001S900001JoPb9IAF', ParentId='001S900001Kj7EKIAZ', ExternalLocationId__c='293398324420722')
};
update updates;
System.debug('Updated Green Dragon locations: ' + updates.size());
