/**
 * Provides read-only catalog data for the Salesforce Data Dictionary Lightning app.
 */
public with sharing class DataDictionaryController {
    private static final Integer MAX_OBJECTS = 2000;
    private static final Integer MAX_FIELDS = 5000;
    private static final Integer MAX_CHANGES = 5000;
    private static final Integer MAX_DUPLICATES = 5000;

    /**
     * Returns catalog metrics and objects matching the supplied governance filters.
     * @param searchTerm Optional object label or API-name search text.
     * @param documentationStatus Optional exact documentation status.
     * @param sensitivity Optional exact sensitivity classification.
     * @param objectCategory Optional exact object category.
     * @return Catalog response containing global metrics and matching objects.
     */
    @AuraEnabled(cacheable=true)
    public static CatalogResponse getCatalog(
        String searchTerm,
        String documentationStatus,
        String sensitivity,
        String objectCategory
    ) {
        try {
            List<Data_Dictionary_Object__c> catalogObjects = [
                SELECT Id, Name, Qualified_API_Name__c, Label__c, Object_Category__c,
                    Metadata_Description__c, Business_Definition__c, Documentation_Status__c,
                    Sensitivity__c, Field_Count__c, Documented_Field_Count__c,
                    Sensitive_Field_Count__c, Dependency_Count__c, Last_Scanned_At__c,
                    Steward__r.Name
                FROM Data_Dictionary_Object__c
                WHERE Active__c = true
                WITH USER_MODE
                ORDER BY Label__c NULLS LAST, Qualified_API_Name__c
                LIMIT :MAX_OBJECTS
            ];

            CatalogResponse response = new CatalogResponse();
            response.summary = buildSummary(catalogObjects);
            response.objects = new List<ObjectRow>();
            for (Data_Dictionary_Object__c catalogObject : catalogObjects) {
                if (matchesFilters(
                    catalogObject,
                    searchTerm,
                    documentationStatus,
                    sensitivity,
                    objectCategory
                )) {
                    response.objects.add(new ObjectRow(catalogObject));
                }
            }
            return response;
        } catch (Exception exceptionValue) {
            throw new AuraHandledException('The data dictionary catalog could not be loaded.');
        }
    }

    /**
     * Returns active field entries for a selected dictionary object.
     * @param dictionaryObjectId Parent dictionary object record ID.
     * @return Ordered field rows, or an empty list when no object is selected.
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldRow> getFields(Id dictionaryObjectId) {
        if (dictionaryObjectId == null) {
            return new List<FieldRow>();
        }

        try {
            List<FieldRow> fieldRows = new List<FieldRow>();
            for (Data_Dictionary_Field__c catalogField : [
                SELECT Id, Name, Qualified_API_Name__c, Label__c, Data_Type__c,
                    Metadata_Description__c, Help_Text__c, Business_Definition__c,
                    Documentation_Status__c, Sensitivity__c, Compliance_Group__c,
                    Required__c, Unique__c, External_ID__c, Formula__c, Reference_To__c,
                    Picklist_Values__c, FLS_Summary__c, Dependency_Count__c, Dependencies__c,
                    Last_Scanned_At__c
                FROM Data_Dictionary_Field__c
                WHERE Dictionary_Object__c = :dictionaryObjectId AND Active__c = true
                WITH USER_MODE
                ORDER BY Label__c NULLS LAST, Qualified_API_Name__c
                LIMIT :MAX_FIELDS
            ]) {
                fieldRows.add(new FieldRow(catalogField));
            }
            return fieldRows;
        } catch (Exception exceptionValue) {
            throw new AuraHandledException('Fields for the selected object could not be loaded.');
        }
    }

    /** Returns recent metadata changes and scan-level health metrics. */
    @AuraEnabled(cacheable=true)
    public static ChangeInventoryResponse getChangeInventory(
        String searchTerm,
        String changeType,
        String reviewStatus
    ) {
        try {
            List<Data_Dictionary_Change__c> detectedChanges = [
                SELECT Id, Name, Entity_Type__c, Change_Type__c, Object_API_Name__c,
                    Qualified_API_Name__c, Metadata_Label__c, Changed_Properties__c,
                    Detected_At__c, Review_Status__c, Review_Notes__c, Retention_Until__c,
                    Dictionary_Scan__c, Dictionary_Scan__r.Name
                FROM Data_Dictionary_Change__c
                WITH USER_MODE
                ORDER BY Detected_At__c DESC, Qualified_API_Name__c
                LIMIT :MAX_CHANGES
            ];
            List<Data_Dictionary_Scan__c> latestScans = [
                SELECT Id, Name, Status__c, Started_At__c, Completed_At__c,
                    Object_Count__c, Field_Count__c, Change_Count__c,
                    Notification_Status__c, Retention_Until__c
                FROM Data_Dictionary_Scan__c
                WITH USER_MODE
                ORDER BY Started_At__c DESC
                LIMIT 1
            ];

            ChangeInventoryResponse response = new ChangeInventoryResponse();
            response.summary = new ChangeSummary();
            response.changes = new List<ChangeRow>();
            if (!latestScans.isEmpty()) {
                response.summary.applyScan(latestScans[0]);
            }
            String normalizedSearch = String.isBlank(searchTerm) ? null : searchTerm.trim().toLowerCase();
            for (Data_Dictionary_Change__c detectedChange : detectedChanges) {
                response.summary.add(detectedChange);
                if ((normalizedSearch == null
                        || containsIgnoreCase(detectedChange.Metadata_Label__c, normalizedSearch)
                        || containsIgnoreCase(detectedChange.Qualified_API_Name__c, normalizedSearch))
                    && (String.isBlank(changeType) || detectedChange.Change_Type__c == changeType)
                    && (String.isBlank(reviewStatus) || detectedChange.Review_Status__c == reviewStatus)) {
                    response.changes.add(new ChangeRow(detectedChange));
                }
            }
            return response;
        } catch (Exception exceptionValue) {
            throw new AuraHandledException('The metadata change inventory could not be loaded.');
        }
    }

    /** Returns active same-object duplicate candidates at or above the supplied confidence threshold. */
    @AuraEnabled(cacheable=true)
    public static DuplicateInventoryResponse getDuplicateCandidates(
        String searchTerm,
        String reviewStatus,
        Decimal minimumConfidence
    ) {
        try {
            List<Data_Dictionary_Duplicate__c> candidates = [
                SELECT Id, Name, Object_API_Name__c, Field_A_API_Name__c, Field_A_Label__c,
                    Field_B_API_Name__c, Field_B_Label__c, Data_Type__c, Confidence__c,
                    Evidence_Signals__c, Field_A_Dependency_Count__c,
                    Field_B_Dependency_Count__c, Review_Status__c, Review_Notes__c,
                    Detected_At__c, Last_Evaluated_At__c, Retention_Until__c
                FROM Data_Dictionary_Duplicate__c
                WHERE Active__c = true
                WITH USER_MODE
                ORDER BY Confidence__c DESC, Object_API_Name__c, Field_A_API_Name__c
                LIMIT :MAX_DUPLICATES
            ];
            DuplicateInventoryResponse response = new DuplicateInventoryResponse();
            response.summary = new DuplicateSummary();
            response.candidates = new List<DuplicateRow>();
            String normalizedSearch = String.isBlank(searchTerm) ? null : searchTerm.trim().toLowerCase();
            Decimal confidenceFloor = minimumConfidence == null ? 80 : minimumConfidence;
            for (Data_Dictionary_Duplicate__c candidate : candidates) {
                response.summary.add(candidate);
                if ((normalizedSearch == null
                        || containsIgnoreCase(candidate.Object_API_Name__c, normalizedSearch)
                        || containsIgnoreCase(candidate.Field_A_API_Name__c, normalizedSearch)
                        || containsIgnoreCase(candidate.Field_A_Label__c, normalizedSearch)
                        || containsIgnoreCase(candidate.Field_B_API_Name__c, normalizedSearch)
                        || containsIgnoreCase(candidate.Field_B_Label__c, normalizedSearch))
                    && (String.isBlank(reviewStatus) || candidate.Review_Status__c == reviewStatus)
                    && candidate.Confidence__c >= confidenceFloor) {
                    response.candidates.add(new DuplicateRow(candidate));
                }
            }
            return response;
        } catch (Exception exceptionValue) {
            throw new AuraHandledException('Potential duplicate fields could not be loaded.');
        }
    }

    private static CatalogSummary buildSummary(List<Data_Dictionary_Object__c> catalogObjects) {
        CatalogSummary summary = new CatalogSummary();
        summary.objectCount = catalogObjects.size();
        for (Data_Dictionary_Object__c catalogObject : catalogObjects) {
            summary.fieldCount += integerValue(catalogObject.Field_Count__c);
            summary.documentedFieldCount += integerValue(catalogObject.Documented_Field_Count__c);
            summary.sensitiveFieldCount += integerValue(catalogObject.Sensitive_Field_Count__c);
            summary.dependencyCount += integerValue(catalogObject.Dependency_Count__c);
            if (catalogObject.Documentation_Status__c == 'Approved') {
                summary.approvedObjectCount++;
            }
            if (summary.lastScannedAt == null || catalogObject.Last_Scanned_At__c > summary.lastScannedAt) {
                summary.lastScannedAt = catalogObject.Last_Scanned_At__c;
            }
        }
        summary.documentationCoverage = summary.fieldCount == 0
            ? 0
            : Decimal.valueOf(summary.documentedFieldCount)
                .divide(Decimal.valueOf(summary.fieldCount), 3) * 100;
        return summary;
    }

    private static Boolean matchesFilters(
        Data_Dictionary_Object__c catalogObject,
        String searchTerm,
        String documentationStatus,
        String sensitivity,
        String objectCategory
    ) {
        String normalizedSearch = String.isBlank(searchTerm) ? null : searchTerm.trim().toLowerCase();
        Boolean matchesSearch = normalizedSearch == null
            || containsIgnoreCase(catalogObject.Label__c, normalizedSearch)
            || containsIgnoreCase(catalogObject.Qualified_API_Name__c, normalizedSearch);
        return matchesSearch
            && (String.isBlank(documentationStatus)
                || catalogObject.Documentation_Status__c == documentationStatus)
            && (String.isBlank(sensitivity) || catalogObject.Sensitivity__c == sensitivity)
            && (String.isBlank(objectCategory) || catalogObject.Object_Category__c == objectCategory);
    }

    private static Boolean containsIgnoreCase(String candidate, String normalizedSearch) {
        return candidate != null && candidate.toLowerCase().contains(normalizedSearch);
    }

    private static Integer integerValue(Decimal value) {
        return value == null ? 0 : value.intValue();
    }

    /** Dashboard metrics for the active catalog. */
    public class CatalogSummary {
        @AuraEnabled public Integer objectCount = 0;
        @AuraEnabled public Integer approvedObjectCount = 0;
        @AuraEnabled public Integer fieldCount = 0;
        @AuraEnabled public Integer documentedFieldCount = 0;
        @AuraEnabled public Integer sensitiveFieldCount = 0;
        @AuraEnabled public Integer dependencyCount = 0;
        @AuraEnabled public Decimal documentationCoverage = 0;
        @AuraEnabled public Datetime lastScannedAt;
    }

    /** Catalog response returned to the Lightning app. */
    public class CatalogResponse {
        @AuraEnabled public CatalogSummary summary;
        @AuraEnabled public List<ObjectRow> objects;
    }

    public class ChangeInventoryResponse {
        @AuraEnabled public ChangeSummary summary;
        @AuraEnabled public List<ChangeRow> changes;
    }

    public class ChangeSummary {
        @AuraEnabled public Integer addedCount = 0;
        @AuraEnabled public Integer changedCount = 0;
        @AuraEnabled public Integer removedCount = 0;
        @AuraEnabled public Integer reactivatedCount = 0;
        @AuraEnabled public Integer pendingReviewCount = 0;
        @AuraEnabled public String latestScanStatus;
        @AuraEnabled public String notificationStatus;
        @AuraEnabled public Datetime latestScanAt;
        @AuraEnabled public Integer latestObjectCount = 0;
        @AuraEnabled public Integer latestFieldCount = 0;

        private void add(Data_Dictionary_Change__c source) {
            if (source.Change_Type__c == 'Added') addedCount++;
            if (source.Change_Type__c == 'Changed') changedCount++;
            if (source.Change_Type__c == 'Removed') removedCount++;
            if (source.Change_Type__c == 'Reactivated') reactivatedCount++;
            if (source.Review_Status__c == 'New' || source.Review_Status__c == 'Under Review') {
                pendingReviewCount++;
            }
        }

        private void applyScan(Data_Dictionary_Scan__c source) {
            latestScanStatus = source.Status__c;
            notificationStatus = source.Notification_Status__c;
            latestScanAt = source.Started_At__c;
            latestObjectCount = integerValue(source.Object_Count__c);
            latestFieldCount = integerValue(source.Field_Count__c);
        }
    }

    public class ChangeRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String recordNumber;
        @AuraEnabled public String entityType;
        @AuraEnabled public String changeType;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String qualifiedApiName;
        @AuraEnabled public String metadataLabel;
        @AuraEnabled public String changedProperties;
        @AuraEnabled public Datetime detectedAt;
        @AuraEnabled public String reviewStatus;
        @AuraEnabled public String reviewNotes;
        @AuraEnabled public Date retentionUntil;
        @AuraEnabled public String scanNumber;

        private ChangeRow(Data_Dictionary_Change__c source) {
            id = source.Id;
            recordNumber = source.Name;
            entityType = source.Entity_Type__c;
            changeType = source.Change_Type__c;
            objectApiName = source.Object_API_Name__c;
            qualifiedApiName = source.Qualified_API_Name__c;
            metadataLabel = source.Metadata_Label__c;
            changedProperties = source.Changed_Properties__c;
            detectedAt = source.Detected_At__c;
            reviewStatus = source.Review_Status__c;
            reviewNotes = source.Review_Notes__c;
            retentionUntil = source.Retention_Until__c;
            scanNumber = source.Dictionary_Scan__r.Name;
        }
    }

    public class DuplicateInventoryResponse {
        @AuraEnabled public DuplicateSummary summary;
        @AuraEnabled public List<DuplicateRow> candidates;
    }

    public class DuplicateSummary {
        @AuraEnabled public Integer candidateCount = 0;
        @AuraEnabled public Integer newCount = 0;
        @AuraEnabled public Integer confirmedCount = 0;
        @AuraEnabled public Integer plannedCount = 0;
        @AuraEnabled public Decimal averageConfidence = 0;
        @AuraEnabled public Datetime lastEvaluatedAt;
        private Decimal confidenceTotal = 0;

        private void add(Data_Dictionary_Duplicate__c source) {
            candidateCount++;
            confidenceTotal += source.Confidence__c == null ? 0 : source.Confidence__c;
            averageConfidence = confidenceTotal.divide(candidateCount, 2);
            if (source.Review_Status__c == 'New') newCount++;
            if (source.Review_Status__c == 'Confirmed Duplicate') confirmedCount++;
            if (source.Review_Status__c == 'Consolidation Planned') plannedCount++;
            if (lastEvaluatedAt == null || source.Last_Evaluated_At__c > lastEvaluatedAt) {
                lastEvaluatedAt = source.Last_Evaluated_At__c;
            }
        }
    }

    public class DuplicateRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String recordNumber;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fieldAApiName;
        @AuraEnabled public String fieldALabel;
        @AuraEnabled public String fieldBApiName;
        @AuraEnabled public String fieldBLabel;
        @AuraEnabled public String dataType;
        @AuraEnabled public Decimal confidence;
        @AuraEnabled public String evidenceSignals;
        @AuraEnabled public Integer fieldADependencyCount;
        @AuraEnabled public Integer fieldBDependencyCount;
        @AuraEnabled public String reviewStatus;
        @AuraEnabled public String reviewNotes;
        @AuraEnabled public Datetime detectedAt;
        @AuraEnabled public Datetime lastEvaluatedAt;
        @AuraEnabled public Date retentionUntil;

        private DuplicateRow(Data_Dictionary_Duplicate__c source) {
            id = source.Id;
            recordNumber = source.Name;
            objectApiName = source.Object_API_Name__c;
            fieldAApiName = source.Field_A_API_Name__c;
            fieldALabel = source.Field_A_Label__c;
            fieldBApiName = source.Field_B_API_Name__c;
            fieldBLabel = source.Field_B_Label__c;
            dataType = source.Data_Type__c;
            confidence = source.Confidence__c;
            evidenceSignals = source.Evidence_Signals__c;
            fieldADependencyCount = integerValue(source.Field_A_Dependency_Count__c);
            fieldBDependencyCount = integerValue(source.Field_B_Dependency_Count__c);
            reviewStatus = source.Review_Status__c;
            reviewNotes = source.Review_Notes__c;
            detectedAt = source.Detected_At__c;
            lastEvaluatedAt = source.Last_Evaluated_At__c;
            retentionUntil = source.Retention_Until__c;
        }
    }

    /** Object-level projection used by the Lightning app. */
    public class ObjectRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String recordNumber;
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String category;
        @AuraEnabled public String metadataDescription;
        @AuraEnabled public String businessDefinition;
        @AuraEnabled public String documentationStatus;
        @AuraEnabled public String sensitivity;
        @AuraEnabled public String stewardName;
        @AuraEnabled public Integer fieldCount;
        @AuraEnabled public Integer documentedFieldCount;
        @AuraEnabled public Integer sensitiveFieldCount;
        @AuraEnabled public Integer dependencyCount;
        @AuraEnabled public Datetime lastScannedAt;

        private ObjectRow(Data_Dictionary_Object__c source) {
            id = source.Id;
            recordNumber = source.Name;
            apiName = source.Qualified_API_Name__c;
            label = source.Label__c;
            category = source.Object_Category__c;
            metadataDescription = source.Metadata_Description__c;
            businessDefinition = source.Business_Definition__c;
            documentationStatus = source.Documentation_Status__c;
            sensitivity = source.Sensitivity__c;
            stewardName = source.Steward__r?.Name;
            fieldCount = integerValue(source.Field_Count__c);
            documentedFieldCount = integerValue(source.Documented_Field_Count__c);
            sensitiveFieldCount = integerValue(source.Sensitive_Field_Count__c);
            dependencyCount = integerValue(source.Dependency_Count__c);
            lastScannedAt = source.Last_Scanned_At__c;
        }
    }

    /** Field-level projection used by the Lightning app. */
    public class FieldRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String recordNumber;
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String dataType;
        @AuraEnabled public String metadataDescription;
        @AuraEnabled public String helpText;
        @AuraEnabled public String businessDefinition;
        @AuraEnabled public String documentationStatus;
        @AuraEnabled public String sensitivity;
        @AuraEnabled public String complianceGroup;
        @AuraEnabled public Boolean required;
        @AuraEnabled public Boolean uniqueValue;
        @AuraEnabled public Boolean externalId;
        @AuraEnabled public String formula;
        @AuraEnabled public String referenceTo;
        @AuraEnabled public String picklistValues;
        @AuraEnabled public String flsSummary;
        @AuraEnabled public Integer dependencyCount;
        @AuraEnabled public String dependencies;
        @AuraEnabled public Datetime lastScannedAt;

        private FieldRow(Data_Dictionary_Field__c source) {
            id = source.Id;
            recordNumber = source.Name;
            apiName = source.Qualified_API_Name__c;
            label = source.Label__c;
            dataType = source.Data_Type__c;
            metadataDescription = source.Metadata_Description__c;
            helpText = source.Help_Text__c;
            businessDefinition = source.Business_Definition__c;
            documentationStatus = source.Documentation_Status__c;
            sensitivity = source.Sensitivity__c;
            complianceGroup = source.Compliance_Group__c;
            required = source.Required__c;
            uniqueValue = source.Unique__c;
            externalId = source.External_ID__c;
            formula = source.Formula__c;
            referenceTo = source.Reference_To__c;
            picklistValues = source.Picklist_Values__c;
            flsSummary = source.FLS_Summary__c;
            dependencyCount = integerValue(source.Dependency_Count__c);
            dependencies = source.Dependencies__c;
            lastScannedAt = source.Last_Scanned_At__c;
        }
    }
}