Id rtId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('Care_Enquiry').getRecordTypeId();
Group q = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'CareOrch_Admissions' LIMIT 1];
Lead l = new Lead(LastName='Routing Verification 3', Company='CareOrch Verify Co', RecordTypeId=rtId, CareOrch_Funding_Type__c='Private', CareOrch_Requested_Care_Type__c='Residential', CareOrch_Target_Admission_Date__c=Date.today().addDays(7));
insert l;
Lead inserted = [SELECT Id, OwnerId FROM Lead WHERE Id = :l.Id LIMIT 1];
System.debug('CAREORCH_VERIFY Lead=' + inserted.Id + ' Owner=' + inserted.OwnerId + ' Queue=' + q.Id);
