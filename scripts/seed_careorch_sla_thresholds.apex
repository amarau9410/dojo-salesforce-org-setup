Map<String, Integer> targetByCategory = new Map<String, Integer>{
    'Death' => 15,
    'DEFAULT' => 30
};

Map<String, CareOrch_SLA_Threshold__c> existingByCategory = new Map<String, CareOrch_SLA_Threshold__c>();
for (CareOrch_SLA_Threshold__c row : [
    SELECT Id, Event_Category__c, Threshold_Minutes__c, Active__c
    FROM CareOrch_SLA_Threshold__c
    WHERE Event_Category__c IN :targetByCategory.keySet()
]) {
    existingByCategory.put(row.Event_Category__c, row);
}

List<CareOrch_SLA_Threshold__c> rowsToUpsert = new List<CareOrch_SLA_Threshold__c>();
for (String category : targetByCategory.keySet()) {
    CareOrch_SLA_Threshold__c row = existingByCategory.get(category);
    if (row == null) {
        row = new CareOrch_SLA_Threshold__c(Event_Category__c = category);
    }

    row.Threshold_Minutes__c = targetByCategory.get(category);
    row.Active__c = true;
    rowsToUpsert.add(row);
}

upsert rowsToUpsert;
System.debug('Seeded CareOrch SLA thresholds: ' + rowsToUpsert.size());
