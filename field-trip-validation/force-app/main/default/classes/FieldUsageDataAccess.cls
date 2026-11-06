/**
 * Retrieves Field Usage projections after the calling controller authorizes the alliance.
 * Direct record sharing remains private so list views, reports, and APIs cannot bypass that check.
 */
public without sharing class FieldUsageDataAccess {
    private static final String ACCESS_PERMISSION = 'Access_Data_Governance_Workbenches';

    public static List<String> getReportingGroups(Set<String> authorizedGroups) {
        requireWorkbenchAccess();
        List<String> groups = new List<String>();
        if (authorizedGroups == null) {
            for (AggregateResult result : (List<AggregateResult>) Database.query(
                'SELECT Reporting_Group__c reportingGroup, COUNT(Id) evidenceCount '
                    + 'FROM Data_Dictionary_Field_Usage__c WHERE Active__c = true '
                    + 'GROUP BY Reporting_Group__c ORDER BY Reporting_Group__c',
                AccessLevel.SYSTEM_MODE
            )) {
                groups.add((String) result.get('reportingGroup'));
            }
        } else if (!authorizedGroups.isEmpty()) {
            for (AggregateResult result : (List<AggregateResult>) Database.queryWithBinds(
                'SELECT Reporting_Group__c reportingGroup, COUNT(Id) evidenceCount '
                    + 'FROM Data_Dictionary_Field_Usage__c '
                    + 'WHERE Active__c = true AND Reporting_Group__c IN :authorizedGroups '
                    + 'GROUP BY Reporting_Group__c ORDER BY Reporting_Group__c',
                new Map<String, Object>{ 'authorizedGroups' => authorizedGroups },
                AccessLevel.SYSTEM_MODE
            )) {
                groups.add((String) result.get('reportingGroup'));
            }
        }
        return groups;
    }

    public static List<String> getObjectApiNames(Set<String> authorizedGroups) {
        requireWorkbenchAccess();
        List<String> objectApiNames = new List<String>();
        if (authorizedGroups == null) {
            for (AggregateResult result : (List<AggregateResult>) Database.query(
                'SELECT Object_API_Name__c objectApiName, COUNT(Id) evidenceCount '
                    + 'FROM Data_Dictionary_Field_Usage__c WHERE Active__c = true '
                    + 'GROUP BY Object_API_Name__c ORDER BY Object_API_Name__c',
                AccessLevel.SYSTEM_MODE
            )) {
                objectApiNames.add((String) result.get('objectApiName'));
            }
        } else if (!authorizedGroups.isEmpty()) {
            for (AggregateResult result : (List<AggregateResult>) Database.queryWithBinds(
                'SELECT Object_API_Name__c objectApiName, COUNT(Id) evidenceCount '
                    + 'FROM Data_Dictionary_Field_Usage__c '
                    + 'WHERE Active__c = true AND Reporting_Group__c IN :authorizedGroups '
                    + 'GROUP BY Object_API_Name__c ORDER BY Object_API_Name__c',
                new Map<String, Object>{ 'authorizedGroups' => authorizedGroups },
                AccessLevel.SYSTEM_MODE
            )) {
                objectApiNames.add((String) result.get('objectApiName'));
            }
        }
        return objectApiNames;
    }

    public static List<Data_Dictionary_Field_Usage__c> getUsageEvidence(
        Set<String> authorizedGroups,
        String alliance,
        String objectApiName,
        String usageStatus,
        String searchTerm,
        Integer rowLimit
    ) {
        requireWorkbenchAccess();
        QueryScope queryScope = buildUsageScope(
            authorizedGroups,
            alliance,
            objectApiName,
            usageStatus,
            searchTerm
        );
        queryScope.binds.put('rowLimit', rowLimit);

        return Database.queryWithBinds(
            'SELECT Id, Dictionary_Field__c, Dictionary_Field__r.Label__c, Field_Label__c, '
                + 'Dictionary_Field__r.Qualified_API_Name__c, '
                + 'Dictionary_Field__r.Dependency_Count__c, Dictionary_Field__r.Dependencies__c, '
                + 'Dictionary_Field__r.FLS_Summary__c, Source_Org_Id__c, '
                + 'Source_Analysis_Id__c, Analysis_Name__c, Alliance__c, Reporting_Group__c, '
                + 'Object_API_Name__c, Field_API_Name__c, Record_Type_Id__c, '
                + 'Record_Type_Name__c, Records_Analyzed__c, Populated_Count__c, '
                + 'Population_Percent__c, Usage_Status__c, Catalog_Match_Status__c, '
                + 'Last_Analyzed_At__c, Last_Synced_At__c '
                + 'FROM Data_Dictionary_Field_Usage__c WHERE '
                + String.join(queryScope.predicates, ' AND ')
                + ' ORDER BY Reporting_Group__c, Object_API_Name__c, '
                + 'Dictionary_Field__r.Label__c NULLS LAST, '
                + 'Field_API_Name__c LIMIT :rowLimit',
            queryScope.binds,
            AccessLevel.SYSTEM_MODE
        );
    }

    public static List<AggregateResult> getUsageByReportingGroup(
        Set<String> authorizedGroups,
        String alliance,
        String objectApiName,
        String usageStatus,
        String searchTerm
    ) {
        requireWorkbenchAccess();
        QueryScope queryScope = buildUsageScope(
            authorizedGroups,
            alliance,
            objectApiName,
            usageStatus,
            searchTerm
        );
        return Database.queryWithBinds(
            'SELECT Reporting_Group__c reportingGroup, Usage_Status__c usageStatus, '
                + 'Previous_Usage_Status__c previousUsageStatus, '
                + 'Source_Analysis_Id__c analysisId, '
                + 'DAY_ONLY(Previous_Analyzed_At__c) previousDay, '
                + 'COUNT(Id) evidenceCount, SUM(Population_Percent__c) populationTotal, '
                + 'MAX(Last_Analyzed_At__c) latestAnalyzedAt, '
                + 'SUM(Previous_Population_Percent__c) previousPopulationTotal, '
                + 'MAX(Previous_Analyzed_At__c) previousAnalyzedAt, '
                + 'MAX(Records_Analyzed__c) recordsAnalyzed, '
                + 'MAX(Previous_Records_Analyzed__c) previousRecordsAnalyzed '
                + 'FROM Data_Dictionary_Field_Usage__c WHERE '
                + String.join(queryScope.predicates, ' AND ')
                + ' GROUP BY Reporting_Group__c, Usage_Status__c, '
                + 'Previous_Usage_Status__c, Source_Analysis_Id__c, '
                + 'DAY_ONLY(Previous_Analyzed_At__c) '
                + 'ORDER BY Reporting_Group__c',
            queryScope.binds,
            AccessLevel.SYSTEM_MODE
        );
    }

    private static QueryScope buildUsageScope(
        Set<String> authorizedGroups,
        String alliance,
        String objectApiName,
        String usageStatus,
        String searchTerm
    ) {
        QueryScope queryScope = new QueryScope();
        queryScope.predicates.add('Active__c = true');
        if (!String.isBlank(alliance)) {
            queryScope.predicates.add('Reporting_Group__c = :alliance');
            queryScope.binds.put('alliance', alliance);
        } else if (authorizedGroups != null) {
            queryScope.predicates.add('Reporting_Group__c IN :authorizedGroups');
            queryScope.binds.put('authorizedGroups', authorizedGroups);
        }
        if (!String.isBlank(objectApiName)) {
            queryScope.predicates.add('Object_API_Name__c = :objectApiName');
            queryScope.binds.put('objectApiName', objectApiName);
        }
        if (!String.isBlank(usageStatus)) {
            queryScope.predicates.add('Usage_Status__c = :usageStatus');
            queryScope.binds.put('usageStatus', usageStatus);
        }
        if (!String.isBlank(searchTerm)) {
            queryScope.predicates.add(
                '(Field_Label__c LIKE :searchPattern OR Field_API_Name__c LIKE :searchPattern)'
            );
            queryScope.binds.put('searchPattern', '%' + searchTerm.trim() + '%');
        }
        return queryScope;
    }

    private class QueryScope {
        private List<String> predicates = new List<String>();
        private Map<String, Object> binds = new Map<String, Object>();
    }

    private static void requireWorkbenchAccess() {
        if (!FeatureManagement.checkPermission(ACCESS_PERMISSION)) {
            throw new SecurityException('Data Governance workbench access is required.');
        }
    }
}