public with sharing class CareOrchResidentClinicalLogger {
    private static final String FOOD_METRIC_TYPE = 'Food Intake (Quarter/Half/Full)';

    @AuraEnabled
    public static Id createNutritionalObservation(Id residentAccountId, String mealType, String consumptionLevel, String refusedNotes) {
        if (residentAccountId == null) {
            throw new AuraHandledException('residentAccountId is required');
        }
        if (String.isBlank(mealType)) {
            throw new AuraHandledException('mealType is required');
        }
        if (String.isBlank(consumptionLevel)) {
            throw new AuraHandledException('consumptionLevel is required');
        }

        CareObservation observation = buildNutritionalObservation(
            residentAccountId,
            mealType,
            consumptionLevel,
            refusedNotes
        );
        insert observation;
        return observation.Id;
    }

    public static CareObservation createObservation(Id residentAccountId, Decimal targetValue, String metricType, String notes) {
        if (residentAccountId == null) {
            throw new AuraHandledException('residentAccountId is required');
        }
        if (targetValue == null) {
            throw new AuraHandledException('targetValue is required');
        }
        if (String.isBlank(metricType)) {
            throw new AuraHandledException('metricType is required');
        }

        CareObservation observation = buildObservation(residentAccountId, targetValue, metricType, notes);

        SObjectAccessDecision accessDecision = Security.stripInaccessible(
            AccessType.CREATABLE,
            new List<SObject>{ observation }
        );
        List<SObject> sanitizedRecords = accessDecision.getRecords();
        if (sanitizedRecords.isEmpty()) {
            throw new AuraHandledException('CareObservation create access denied');
        }

        CareObservation sanitizedObservation = (CareObservation) sanitizedRecords[0];
        insert as user sanitizedObservation;
        return sanitizedObservation;
    }

    @TestVisible
    private static CareObservation buildNutritionalObservation(
        Id residentAccountId,
        String mealType,
        String consumptionLevel,
        String refusedNotes
    ) {
        String languageCode = UserInfo.getLanguage();
        Boolean englishAuthoredNote = isEnglishLanguage(languageCode);

        CareObservation observation = new CareObservation();
        observation.Name = 'CareOrch Nutritional Log';
        observation.ObservedSubjectId = residentAccountId;
        observation.SourceSystem = 'CareOrch';
        observation.ObservationStatus = 'Preliminary';
        observation.Metric_Type__c = FOOD_METRIC_TYPE;
        observation.Meal_Period__c = mealType;
        observation.CareOrch_Consumption_Level__c = consumptionLevel;
        observation.Food_Record__c = refusedNotes;
        observation.Care_Home_Notes__c = refusedNotes;
        observation.Daily_Intake_Date__c = Date.today();
        observation.Original_Language__c = languageCode;
        observation.Original_Observation__c = refusedNotes;
        observation.English_Translation__c = englishAuthoredNote ? refusedNotes : null;
        observation.Translation_Status__c = englishAuthoredNote ? 'Reviewed' : 'Pending';
        observation.Draft_Unverified_Translation__c = !englishAuthoredNote;

        return observation;
    }

    @TestVisible
    private static CareObservation buildObservation(Id residentAccountId, Decimal targetValue, String metricType, String notes) {
        String languageCode = UserInfo.getLanguage();
        Boolean englishAuthoredNote = isEnglishLanguage(languageCode);

        CareObservation observation = new CareObservation();
        observation.Name = 'CareOrch Resident Observation';
        observation.ObservedSubjectId = residentAccountId;
        observation.NumericValue = targetValue;
        observation.ObservedValueText = String.valueOf(targetValue.setScale(0)) + 'mL';
        observation.SourceSystem = 'CareOrch';
        observation.Metric_Type__c = metricType;
        observation.Care_Home_Notes__c = notes;
        observation.Daily_Intake_Date__c = Date.today();
        observation.Original_Language__c = languageCode;
        observation.Original_Observation__c = notes;
        observation.English_Translation__c = englishAuthoredNote ? notes : null;
        observation.Translation_Status__c = englishAuthoredNote ? 'Reviewed' : 'Pending';
        observation.Draft_Unverified_Translation__c = !englishAuthoredNote;
        return observation;
    }

    @TestVisible
    private static Boolean isEnglishLanguage(String languageCode) {
        if (String.isBlank(languageCode)) {
            return true;
        }
        return languageCode.toLowerCase().startsWith('en');
    }
}