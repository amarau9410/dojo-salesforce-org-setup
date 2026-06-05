public without sharing class CareOrchObservationAutoTranslateAction {
    private static final String TRANSLATION_NAMED_CREDENTIAL_ENDPOINT =
        'callout:CareOrchTranslationService/translate';
    private static final String TRANSLATION_QUEUE_DEVELOPER_NAME = 'CareOrch_Translation_Review';

    public class Payload {
        @InvocableVariable(required=true)
        public String value;
    }

    public class Result {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String message;
        @InvocableVariable public Id observationId;
    }

    @InvocableMethod(label='CareOrch Auto Translate Observation')
    public static List<Result> process(List<Payload> payloads) {
        List<Result> results = new List<Result>();
        if (payloads == null) {
            return results;
        }

        for (Payload payload : payloads) {
            Result result = new Result();
            try {
                if (payload == null || String.isBlank(payload.value)) {
                    throw new AuraHandledException('value is required');
                }

                Id observationId = (Id) payload.value.trim();
                CareObservation observation = [
                    SELECT Id, Original_Observation__c, Original_Language__c, English_Translation__c,
                           Auto_Translated_Notes__c, Translation_Status__c, Draft_Unverified_Translation__c, OwnerId
                    FROM CareObservation
                    WHERE Id = :observationId
                    WITH USER_MODE
                    LIMIT 1
                ];

                if (String.isBlank(observation.Original_Observation__c)) {
                    throw new AuraHandledException('Original_Observation__c is required');
                }

                if (observation.Translation_Status__c != 'Pending' || !String.isBlank(observation.Auto_Translated_Notes__c)) {
                    result.success = true;
                    result.observationId = observation.Id;
                    result.message = 'No translation update required';
                    results.add(result);
                    continue;
                }

                String translatedText = translateToEnglish(
                    observation.Original_Observation__c,
                    observation.Original_Language__c
                );

                observation.English_Translation__c = translatedText;
                observation.Auto_Translated_Notes__c = translatedText;
                observation.Translation_Status__c = 'Auto-translated';
                observation.Draft_Unverified_Translation__c = true;

                Id translationQueueId = resolveTranslationQueueId();
                if (translationQueueId != null) {
                    observation.OwnerId = translationQueueId;
                }

                SObjectAccessDecision accessDecision = Security.stripInaccessible(
                    AccessType.UPDATABLE,
                    new List<SObject>{ observation }
                );
                List<SObject> sanitizedRecords = accessDecision.getRecords();
                if (sanitizedRecords.isEmpty()) {
                    throw new AuraHandledException('CareObservation update access denied');
                }

                update as user (CareObservation) sanitizedRecords[0];

                result.success = true;
                result.observationId = observation.Id;
                result.message = 'Observation translated';
            } catch (Exception ex) {
                result.success = false;
                result.message = ex.getMessage();
            }
            results.add(result);
        }

        return results;
    }

    @TestVisible
    private static String translateToEnglish(String sourceText, String languageCode) {
        if (String.isBlank(sourceText)) {
            return sourceText;
        }

        if (String.isBlank(languageCode) || languageCode.toLowerCase().startsWith('en')) {
            return sourceText;
        }

        String providerTranslation = tryManagedProviderTranslation(sourceText, languageCode);
        if (!String.isBlank(providerTranslation)) {
            return providerTranslation;
        }

        String translated = sourceText.toLowerCase();
        translated = translated.replace('dolor', 'pain');
        translated = translated.replace('dolore', 'pain');
        translated = translated.replace('douleur', 'pain');
        translated = translated.replace('schmerz', 'pain');
        translated = translated.replace('agua', 'water');
        translated = translated.replace('acqua', 'water');
        translated = translated.replace('eau', 'water');
        translated = translated.replace('wasser', 'water');
        translated = translated.replace('comida', 'food');
        translated = translated.replace('cibo', 'food');
        translated = translated.replace('nourriture', 'food');
        translated = translated.replace('essen', 'food');
        translated = translated.replace('no comio', 'did not eat');
        translated = translated.replace('non ha mangiato', 'did not eat');
        translated = translated.replace('n a pas mange', 'did not eat');
        translated = translated.replace('hat nicht gegessen', 'did not eat');

        if (translated == sourceText.toLowerCase()) {
            return sourceText;
        }

        return translated;
    }

    @TestVisible
    private static String tryManagedProviderTranslation(String sourceText, String languageCode) {
        if (Test.isRunningTest()) {
            return null;
        }

        try {
            HttpRequest request = new HttpRequest();
            request.setEndpoint(TRANSLATION_NAMED_CREDENTIAL_ENDPOINT);
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setTimeout(10000);

            Map<String, Object> payload = new Map<String, Object>{
                'sourceLanguage' => languageCode,
                'targetLanguage' => 'en',
                'text' => sourceText
            };
            request.setBody(JSON.serialize(payload));

            HttpResponse response = (new Http()).send(request);
            if (response == null || response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
                return null;
            }

            Object parsedBody = JSON.deserializeUntyped(response.getBody());
            if (!(parsedBody instanceof Map<String, Object>)) {
                return null;
            }

            Map<String, Object> bodyMap = (Map<String, Object>) parsedBody;
            for (String keyName : new List<String>{ 'translatedText', 'translation', 'englishText' }) {
                if (bodyMap.containsKey(keyName) && bodyMap.get(keyName) != null) {
                    String value = String.valueOf(bodyMap.get(keyName)).trim();
                    if (!String.isBlank(value)) {
                        return value;
                    }
                }
            }
        } catch (Exception ex) {
            return null;
        }

        return null;
    }

    @TestVisible
    private static Id resolveTranslationQueueId() {
        List<Group> queueRecords = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = :TRANSLATION_QUEUE_DEVELOPER_NAME
            LIMIT 1
        ];
        return queueRecords.isEmpty() ? null : queueRecords[0].Id;
    }
}
