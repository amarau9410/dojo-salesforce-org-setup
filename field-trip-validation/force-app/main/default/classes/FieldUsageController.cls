/**
 * Provides read-only Field Trip population evidence for the Field Usage workbench.
 */
public with sharing class FieldUsageController {
    private static final Integer MAX_USAGE_ROWS = 10000;
    private static final Integer USAGE_QUERY_LIMIT = MAX_USAGE_ROWS + 1;

    /**
     * Returns the active reporting segments and objects available to the current user.
     * @return Filter options derived from synchronized Field Trip evidence.
     */
    @AuraEnabled(cacheable=true)
    public static FilterOptions getFilterOptions() {
        try {
            FilterOptions options = new FilterOptions();
            options.alliances = new List<String>();
            options.objectApiNames = new List<String>();
            options.canViewAllAlliances = canCurrentUserModifyAllData();
            Set<String> authorizedReportingGroups = getAuthorizedReportingGroups();

            options.alliances = FieldUsageDataAccess.getReportingGroups(
                authorizedReportingGroups
            );
            options.objectApiNames = FieldUsageDataAccess.getObjectApiNames(
                authorizedReportingGroups
            );
            return options;
        } catch (Exception exceptionValue) {
            throw new AuraHandledException('Field usage filters could not be loaded.');
        }
    }

    /**
    * Returns Field Trip evidence for an optional reporting segment and field filters.
    * @param alliance Optional reporting group; blank includes only authorized groups.
     * @param objectApiName Optional object API name.
     * @param usageStatus Optional exact usage classification.
     * @param searchTerm Optional field label or API-name search text.
     * @return Usage rows and metrics for the matching evidence.
     */
    @AuraEnabled(cacheable=true)
    public static UsageResponse getUsage(
        String alliance,
        String objectApiName,
        String usageStatus,
        String searchTerm
    ) {
        UsageResponse response = new UsageResponse();
        response.summary = new UsageSummary();
        response.rows = new List<UsageRow>();
        response.segments = new List<SegmentSummary>();
        response.rowLimit = MAX_USAGE_ROWS;
        Set<String> authorizedReportingGroups = getAuthorizedReportingGroups();
        if (String.isBlank(alliance)
            && authorizedReportingGroups != null
            && authorizedReportingGroups.isEmpty()) {
            return response;
        }
        if (!String.isBlank(alliance)
            && authorizedReportingGroups != null
            && !authorizedReportingGroups.contains(alliance)) {
            throw new AuraHandledException('You are not authorized to view this reporting segment.');
        }

        try {
            for (AggregateResult result : FieldUsageDataAccess.getUsageSummary(
                authorizedReportingGroups,
                alliance,
                objectApiName,
                usageStatus,
                searchTerm
            )) {
                response.summary.addAggregate(result);
            }
            Map<String, SegmentSummary> segmentByName = new Map<String, SegmentSummary>();
            for (AggregateResult result : FieldUsageDataAccess.getUsageByReportingGroup(
                authorizedReportingGroups,
                alliance,
                objectApiName,
                usageStatus,
                searchTerm
            )) {
                String reportingGroup = (String) result.get('reportingGroup');
                if (!segmentByName.containsKey(reportingGroup)) {
                    segmentByName.put(reportingGroup, new SegmentSummary(reportingGroup));
                }
                segmentByName.get(reportingGroup).addAggregate(result);
            }
            for (AggregateResult result : FieldUsageDataAccess.getPreviousUsageByReportingGroup(
                authorizedReportingGroups,
                alliance,
                objectApiName,
                usageStatus,
                searchTerm
            )) {
                String reportingGroup = (String) result.get('reportingGroup');
                if (segmentByName.containsKey(reportingGroup)) {
                    segmentByName.get(reportingGroup).addPreviousAggregate(result);
                }
            }
            for (AggregateResult result : FieldUsageDataAccess.getAnalysisSamplesByReportingGroup(
                authorizedReportingGroups,
                alliance,
                objectApiName,
                usageStatus,
                searchTerm
            )) {
                String reportingGroup = (String) result.get('reportingGroup');
                if (segmentByName.containsKey(reportingGroup)) {
                    segmentByName.get(reportingGroup).addAnalysisSample(result);
                }
            }
            for (SegmentSummary segment : segmentByName.values()) {
                segment.finalizeAverages();
            }
            response.segments.addAll(segmentByName.values());
            List<Data_Dictionary_Field_Usage__c> evidenceRows =
                FieldUsageDataAccess.getUsageEvidence(
                    authorizedReportingGroups,
                    alliance,
                    objectApiName,
                    usageStatus,
                    searchTerm,
                    USAGE_QUERY_LIMIT
                );
            response.isTruncated = evidenceRows.size() > MAX_USAGE_ROWS;
            Integer returnedRows = Math.min(evidenceRows.size(), MAX_USAGE_ROWS);
            for (Integer indexValue = 0; indexValue < returnedRows; indexValue++) {
                response.rows.add(new UsageRow(evidenceRows[indexValue]));
            }
            return response;
        } catch (Exception exceptionValue) {
            throw new AuraHandledException('Field usage evidence could not be loaded.');
        }
    }

    /**
     * Returns null for a system administrator, otherwise the user's alliance entitlements.
     * @return Authorized reporting groups, or null when all groups are authorized.
     */
    public static Set<String> getAuthorizedReportingGroups() {
        if (canCurrentUserModifyAllData()) {
            return null;
        }

        User currentUser = [
            SELECT Visible_Alliance_ADCB__c, Visible_Alliance_AIBMS__c,
                Visible_Alliance_CMSL__c, Visible_Alliance_EMS__c,
                Visible_Alliance_FDMS__c, Visible_Alliance_FDMSSA__c,
                Visible_Alliance_UCBA__c, Visible_Alliance_Unicaja__c,
                Visible_Alliance_VERT__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];

        Set<String> reportingGroups = new Set<String>();
        addReportingGroup(reportingGroups, 'ADCB', currentUser.Visible_Alliance_ADCB__c);
        addReportingGroup(reportingGroups, 'AIBMS', currentUser.Visible_Alliance_AIBMS__c);
        addReportingGroup(reportingGroups, 'CMSL', currentUser.Visible_Alliance_CMSL__c);
        addReportingGroup(reportingGroups, 'EMS', currentUser.Visible_Alliance_EMS__c);
        addReportingGroup(reportingGroups, 'FDMS', currentUser.Visible_Alliance_FDMS__c);
        addReportingGroup(reportingGroups, 'Bidvest', currentUser.Visible_Alliance_FDMSSA__c);
        addReportingGroup(reportingGroups, 'UCBA', currentUser.Visible_Alliance_UCBA__c);
        addReportingGroup(reportingGroups, 'Unicaja', currentUser.Visible_Alliance_Unicaja__c);
        addReportingGroup(reportingGroups, 'Vert', currentUser.Visible_Alliance_VERT__c);
        return reportingGroups;
    }

    /**
     * Indicates whether the current user's profile grants Modify All Data.
     * @return True only for an administrator-level user.
     */
    public static Boolean isCurrentUserAdministrator() {
        return canCurrentUserModifyAllData();
    }

    private static Boolean canCurrentUserModifyAllData() {
        if (!Schema.sObjectType.Profile.isAccessible()
            || !Schema.sObjectType.Profile.fields.PermissionsModifyAllData.isAccessible()) {
            return false;
        }
        Profile currentProfile = [
            SELECT PermissionsModifyAllData
            FROM Profile
            WHERE Id = :UserInfo.getProfileId()
            WITH USER_MODE
        ];
        return currentProfile.PermissionsModifyAllData;
    }

    private static void addReportingGroup(
        Set<String> reportingGroups,
        String reportingGroup,
        Boolean isVisible
    ) {
        if (isVisible) {
            reportingGroups.add(reportingGroup);
        }
    }

    private static Integer integerValue(Decimal value) {
        return value == null ? 0 : value.intValue();
    }

    /** Available values for workbench filters. */
    public class FilterOptions {
        @AuraEnabled public List<String> alliances;
        @AuraEnabled public List<String> objectApiNames;
        @AuraEnabled public Boolean canViewAllAlliances;
    }

    /** Field-usage response returned to the Lightning app. */
    public class UsageResponse {
        @AuraEnabled public UsageSummary summary;
        @AuraEnabled public List<UsageRow> rows;
        @AuraEnabled public List<SegmentSummary> segments;
        @AuraEnabled public Boolean isTruncated = false;
        @AuraEnabled public Integer rowLimit;
    }

    /** Metrics for one authorized reporting segment. */
    public class SegmentSummary {
        @AuraEnabled public String reportingGroup;
        @AuraEnabled public Integer evidenceCount = 0;
        @AuraEnabled public Integer usedCount = 0;
        @AuraEnabled public Integer unusedCount = 0;
        @AuraEnabled public Integer noRecordsCount = 0;
        @AuraEnabled public Decimal averagePopulationPercent;
        @AuraEnabled public Integer recordsAnalyzed = 0;
        @AuraEnabled public Datetime latestAnalyzedAt;
        @AuraEnabled public Integer previousUsedCount = 0;
        @AuraEnabled public Integer previousUnusedCount = 0;
        @AuraEnabled public Integer previousNoRecordsCount = 0;
        @AuraEnabled public Decimal previousAveragePopulationPercent;
        @AuraEnabled public Integer previousRecordsAnalyzed = 0;
        @AuraEnabled public Datetime previousAnalyzedAt;
        private Decimal populationTotal = 0;
        private Integer previousEvidenceCount = 0;
        private Decimal previousPopulationTotal = 0;

        private SegmentSummary(String reportingGroup) {
            this.reportingGroup = reportingGroup;
        }

        private void addAggregate(AggregateResult result) {
            String usageStatus = (String) result.get('usageStatus');
            Integer statusCount = ((Decimal) result.get('evidenceCount')).intValue();
            evidenceCount += statusCount;
            populationTotal += (Decimal) result.get('populationTotal') ?? 0;
            if (usageStatus == 'Used') {
                usedCount += statusCount;
            } else if (usageStatus == 'Unused') {
                unusedCount += statusCount;
            } else if (usageStatus == 'No Records') {
                noRecordsCount += statusCount;
            }
            Datetime statusLatest = (Datetime) result.get('latestAnalyzedAt');
            if (statusLatest != null
                && (latestAnalyzedAt == null || statusLatest > latestAnalyzedAt)) {
                latestAnalyzedAt = statusLatest;
            }
        }

        private void addPreviousAggregate(AggregateResult result) {
            String usageStatus = (String) result.get('usageStatus');
            Integer statusCount = ((Decimal) result.get('evidenceCount')).intValue();
            previousEvidenceCount += statusCount;
            previousPopulationTotal += (Decimal) result.get('populationTotal') ?? 0;
            if (usageStatus == 'Used') {
                previousUsedCount += statusCount;
            } else if (usageStatus == 'Unused') {
                previousUnusedCount += statusCount;
            } else if (usageStatus == 'No Records') {
                previousNoRecordsCount += statusCount;
            }
            Datetime statusLatest = (Datetime) result.get('latestAnalyzedAt');
            if (statusLatest != null
                && (previousAnalyzedAt == null || statusLatest > previousAnalyzedAt)) {
                previousAnalyzedAt = statusLatest;
            }
        }

        private void addAnalysisSample(AggregateResult result) {
            recordsAnalyzed += integerValue((Decimal) result.get('recordsAnalyzed'));
            previousRecordsAnalyzed += integerValue(
                (Decimal) result.get('previousRecordsAnalyzed')
            );
        }

        private void finalizeAverages() {
            averagePopulationPercent = evidenceCount == 0
                ? null
                : populationTotal / evidenceCount;
            previousAveragePopulationPercent = previousEvidenceCount == 0
                ? null
                : previousPopulationTotal / previousEvidenceCount;
        }
    }

    /** Metrics for the currently filtered evidence. */
    public class UsageSummary {
        @AuraEnabled public Integer evidenceCount = 0;
        @AuraEnabled public Integer usedCount = 0;
        @AuraEnabled public Integer unusedCount = 0;
        @AuraEnabled public Integer noRecordsCount = 0;
        @AuraEnabled public Datetime latestAnalyzedAt;

        private void addAggregate(AggregateResult result) {
            String usageStatus = (String) result.get('usageStatus');
            Integer statusCount = ((Decimal) result.get('evidenceCount')).intValue();
            evidenceCount += statusCount;
            if (usageStatus == 'Used') {
                usedCount += statusCount;
            } else if (usageStatus == 'Unused') {
                unusedCount += statusCount;
            } else if (usageStatus == 'No Records') {
                noRecordsCount += statusCount;
            }
            Datetime statusLatest = (Datetime) result.get('latestAnalyzedAt');
            if (statusLatest != null
                && (latestAnalyzedAt == null || statusLatest > latestAnalyzedAt)) {
                latestAnalyzedAt = statusLatest;
            }
        }
    }

    /** Field-level population, dependency, and access projection. */
    public class UsageRow {
        @AuraEnabled public Id id;
        @AuraEnabled public Id dictionaryFieldId;
        @AuraEnabled public String fieldLabel;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String usageStatus;
        @AuraEnabled public String catalogMatchStatus;
        @AuraEnabled public Decimal populationPercent;
        @AuraEnabled public Integer recordsAnalyzed;
        @AuraEnabled public Integer populatedCount;
        @AuraEnabled public Integer dependencyCount;
        @AuraEnabled public String dependencies;
        @AuraEnabled public String flsSummary;
        @AuraEnabled public String analysisName;
        @AuraEnabled public String alliance;
        @AuraEnabled public String reportingGroup;
        @AuraEnabled public String recordTypeId;
        @AuraEnabled public String recordTypeName;
        @AuraEnabled public String sourceOrgId;
        @AuraEnabled public String sourceAnalysisId;
        @AuraEnabled public Datetime lastAnalyzedAt;
        @AuraEnabled public Datetime lastSyncedAt;

        private UsageRow(Data_Dictionary_Field_Usage__c source) {
            id = source.Id;
            dictionaryFieldId = source.Dictionary_Field__c;
            fieldLabel = source.Field_Label__c;
            objectApiName = source.Object_API_Name__c;
            fieldApiName = source.Field_API_Name__c;
            usageStatus = source.Usage_Status__c;
            populationPercent = source.Population_Percent__c ?? 0;
            recordsAnalyzed = integerValue(source.Records_Analyzed__c);
            populatedCount = integerValue(source.Populated_Count__c);
            dependencyCount = integerValue(source.Dictionary_Field__r?.Dependency_Count__c);
            dependencies = source.Dictionary_Field__r?.Dependencies__c;
            flsSummary = source.Dictionary_Field__r?.FLS_Summary__c;
            catalogMatchStatus = source.Catalog_Match_Status__c;
            analysisName = source.Analysis_Name__c;
            alliance = source.Alliance__c;
            reportingGroup = source.Reporting_Group__c;
            recordTypeId = source.Record_Type_Id__c;
            recordTypeName = source.Record_Type_Name__c;
            sourceOrgId = source.Source_Org_Id__c;
            sourceAnalysisId = source.Source_Analysis_Id__c;
            lastAnalyzedAt = source.Last_Analyzed_At__c;
            lastSyncedAt = source.Last_Synced_At__c;
        }
    }
}