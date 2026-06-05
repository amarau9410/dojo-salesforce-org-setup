Account parent = new Account(
    Name='Green Dragon Pub Group LTD',
    RecordTypeId='012Q5000001u7eAIAQ',
    ExternalCustomerId__c='197836976248146'
);
insert parent;
System.debug(parent.Id);
