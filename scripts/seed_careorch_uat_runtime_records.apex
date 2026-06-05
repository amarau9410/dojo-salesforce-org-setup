Integer recordCount = 5;
String stamp = Datetime.now().formatGMT('yyyyMMddHHmmss');
Id currentUserId = UserInfo.getUserId();

System.debug('CAREORCH_UAT_SEED_START ' + stamp);

RecordType operationalAlertRt = [
    SELECT Id
    FROM RecordType
    WHERE SobjectType = 'Case' AND DeveloperName = 'Operational_Alert'
    LIMIT 1
];

List<Account> residents = new List<Account>();
for (Integer i = 1; i <= recordCount; i++) {
    residents.add(new Account(
        Name = 'UAT Resident ' + stamp + ' ' + i,
        CareOrch_Preferred_Notification_Method__c = 'Voice'
    ));
}
insert residents;

List<Contact> contacts = new List<Contact>();
Map<Id, Contact> primaryContactByAccount = new Map<Id, Contact>();
for (Integer i = 0; i < residents.size(); i++) {
    Contact c = new Contact(
        LastName = 'Primary Contact ' + (i + 1),
        AccountId = residents[i].Id,
        Relationship_Type__c = 'Primary Contact',
        Emergency_Opt_In__c = true,
        Email = 'uat.primary.' + stamp + '.' + (i + 1) + '@example.com'
    );
    contacts.add(c);
}
insert contacts;
for (Contact c : contacts) {
    primaryContactByAccount.put(c.AccountId, c);
}

List<Task> shifts = new List<Task>();
for (Integer i = 0; i < residents.size(); i++) {
    Boolean atRisk = Math.mod(i, 2) == 0;
    shifts.add(new Task(
        OwnerId = currentUserId,
        Subject = 'UAT Shift ' + stamp + ' ' + (i + 1),
        Status = 'Not Started',
        Priority = 'Normal',
        ActivityDate = Date.today(),
        WhatId = residents[i].Id,
        CareOrch_Shift_Start__c = System.now().addMinutes(-45 + i),
        CareOrch_Shift_End__c = System.now().addMinutes(90 + i),
        CareOrch_Shift_Status__c = atRisk ? 'Pending' : 'Accepted',
        CareOrch_Contacted_Count__c = atRisk ? 2 : 1,
        CareOrch_Rejected_Count__c = atRisk ? 1 : 0,
        CareOrch_At_Risk__c = atRisk,
        CareOrch_At_Risk_Reason__c = atRisk ? 'High rejection streak' : null
    ));
}
insert shifts;

List<Shift_Lifecycle__c> shiftLifecycles = new List<Shift_Lifecycle__c>();
for (Integer i = 0; i < recordCount; i++) {
    shiftLifecycles.add(new Shift_Lifecycle__c(
        Assigned_To__c = currentUserId,
        Status__c = (Math.mod(i, 3) == 0) ? 'Escalated' : 'Assigned',
        Contact_Attempt_Count__c = Math.mod(i, 3) + 1,
        Rejection_Count__c = Math.mod(i, 2),
        Time_to_First_Response_Minutes__c = 5 + i,
        Time_to_Fill_Minutes__c = 10 + i
    ));
}
insert shiftLifecycles;

List<String> taxonomies = new List<String>{ 'Fall', 'Medication Error', 'Serious Injury' };
List<String> eventCategories = new List<String>{ 'Other', 'Serious Health Concern', 'Death' };

List<Critical_Event__c> criticalEvents = new List<Critical_Event__c>();
for (Integer i = 0; i < residents.size(); i++) {
    criticalEvents.add(new Critical_Event__c(
        Client_Account__c = residents[i].Id,
        Event_Category__c = eventCategories[Math.mod(i, eventCategories.size())],
        Status__c = 'Open',
        Assigned_To__c = currentUserId,
        Critical_Event_Taxonomy__c = taxonomies[Math.mod(i, taxonomies.size())],
        Observation_Type__c = 'Behavioral',
        Behavioral_Notes__c = 'UAT critical event seed ' + stamp + ' #' + (i + 1),
        Active_Shift_Task_Id__c = shifts[i].Id
    ));
}
insert criticalEvents;

List<Communication_Log__c> manualLogs = new List<Communication_Log__c>();
for (Integer i = 0; i < criticalEvents.size(); i++) {
    Id accountId = criticalEvents[i].Client_Account__c;
    Contact linkedContact = primaryContactByAccount.get(accountId);
    manualLogs.add(new Communication_Log__c(
        Critical_Event__c = criticalEvents[i].Id,
        Contact__c = linkedContact != null ? linkedContact.Id : null,
        Assigned_To__c = currentUserId,
        Channel__c = 'Voice',
        Status__c = 'Sent',
        Acknowledged__c = false,
        Dispatched_Timestamp__c = System.now().addMinutes(-10)
    ));
}
insert manualLogs;

Integer observationCount = 0;

List<Case> operationalAlerts = new List<Case>();
List<String> severities = new List<String>{ 'Critical', 'High', 'Medium', 'Low' };
for (Integer i = 0; i < residents.size(); i++) {
    operationalAlerts.add(new Case(
        RecordTypeId = operationalAlertRt.Id,
        AccountId = residents[i].Id,
        Subject = 'UAT Operational Alert ' + stamp + ' ' + (i + 1),
        Origin = 'Phone',
        Status = 'New',
        Priority = 'High',
        Description = 'UAT seeded operational alert from critical event ' + criticalEvents[i].Id,
        CareOrch_Alert_Source__c = 'Critical Event',
        CareOrch_Severity__c = severities[Math.mod(i, severities.size())],
        CareOrch_Critical_Event__c = criticalEvents[i].Id
    ));
}
insert operationalAlerts;

Integer commCount = [SELECT COUNT() FROM Communication_Log__c WHERE Critical_Event__c IN :criticalEvents];

System.debug('CAREORCH_UAT_SEED_SUMMARY stamp=' + stamp +
    ' accounts=' + residents.size() +
    ' contacts=' + contacts.size() +
    ' tasks=' + shifts.size() +
    ' shiftLifecycle=' + shiftLifecycles.size() +
    ' criticalEvents=' + criticalEvents.size() +
    ' communicationLogs=' + commCount +
    ' observations=' + observationCount +
    ' cases=' + operationalAlerts.size());
