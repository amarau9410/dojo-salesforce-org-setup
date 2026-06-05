List<CareObservation> candidates = [
    SELECT Id, Original_Observation__c, Original_Language__c, English_Translation__c, Translation_Status__c
    FROM CareObservation
    WHERE Translation_Status__c = 'Pending Translation'
    AND Original_Observation__c != null
    AND English_Translation__c = null
    LIMIT 1
];

if (candidates.isEmpty()) {
    System.debug('No pending translation candidate found. Create/update one CareObservation with Translation_Status__c = Pending Translation and rerun.');
} else {
    CareObservation target = candidates[0];

    CareOrchObservationAutoTranslateAction.Payload payload =
        new CareOrchObservationAutoTranslateAction.Payload();
    payload.value = String.valueOf(target.Id);

    List<CareOrchObservationAutoTranslateAction.Result> results =
        CareOrchObservationAutoTranslateAction.process(
            new List<CareOrchObservationAutoTranslateAction.Payload>{ payload }
        );

    System.debug('Auto-translate action results: ' + JSON.serializePretty(results));

    CareObservation refreshed = [
        SELECT Id, Original_Observation__c, Original_Language__c, English_Translation__c, Translation_Status__c
        FROM CareObservation
        WHERE Id = :target.Id
        LIMIT 1
    ];

    System.debug('Post-translate record: ' + JSON.serializePretty(refreshed));
}
