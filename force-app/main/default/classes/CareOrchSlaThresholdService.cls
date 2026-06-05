public without sharing class CareOrchSlaThresholdService {
    private static final Integer DEATH_FALLBACK_MINUTES = 15;
    private static final Integer DEFAULT_FALLBACK_MINUTES = 30;

    private static Map<String, Integer> thresholdByCategory;

    public static Integer getThresholdMinutes(String eventCategory) {
        Map<String, Integer> thresholds = getThresholds();
        String normalizedCategory = normalizeCategory(eventCategory);

        if (thresholds.containsKey(normalizedCategory)) {
            return thresholds.get(normalizedCategory);
        }
        if (thresholds.containsKey('DEFAULT')) {
            return thresholds.get('DEFAULT');
        }
        return normalizedCategory == 'DEATH' ? DEATH_FALLBACK_MINUTES : DEFAULT_FALLBACK_MINUTES;
    }

    public static Map<String, Integer> getThresholds() {
        if (thresholdByCategory != null) {
            return new Map<String, Integer>(thresholdByCategory);
        }

        Map<String, Integer> loaded = new Map<String, Integer>();
        for (CareOrch_SLA_Threshold__c thresholdRecord : [
            SELECT Event_Category__c, Threshold_Minutes__c, Active__c
            FROM CareOrch_SLA_Threshold__c
            WHERE Active__c = true
        ]) {
            String categoryKey = normalizeCategory(thresholdRecord.Event_Category__c);
            if (String.isBlank(categoryKey) || thresholdRecord.Threshold_Minutes__c == null) {
                continue;
            }
            loaded.put(categoryKey, Integer.valueOf(thresholdRecord.Threshold_Minutes__c));
        }

        thresholdByCategory = loaded;
        return new Map<String, Integer>(thresholdByCategory);
    }

    @TestVisible
    static void resetCache() {
        thresholdByCategory = null;
    }

    private static String normalizeCategory(String category) {
        String normalized = String.isBlank(category) ? 'DEFAULT' : category.trim().toUpperCase();
        return normalized == 'OTHER' ? 'DEFAULT' : normalized;
    }
}
