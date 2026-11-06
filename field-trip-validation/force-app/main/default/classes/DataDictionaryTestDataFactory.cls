@isTest
public class DataDictionaryTestDataFactory {
    public static User createDictionaryReader() {
        return createDictionaryReader('ddread', new Set<String>(), false);
    }

    public static User createDictionaryReader(
        String aliasValue,
        Set<String> reportingGroups,
        Boolean assignStewardPermission
    ) {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniqueValue = String.valueOf(Datetime.now().getTime());
        User dictionaryReader = new User(
            Alias = aliasValue,
            CommunityNickname = aliasValue + '.' + uniqueValue,
            Email = 'dictionary.reader@example.com',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LastName = 'Dictionary Reader',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'Europe/London',
            Username = aliasValue + '.' + uniqueValue + '@example.com',
            Visible_Alliance_ADCB__c = reportingGroups.contains('ADCB'),
            Visible_Alliance_AIBMS__c = reportingGroups.contains('AIBMS'),
            Visible_Alliance_CMSL__c = reportingGroups.contains('CMSL'),
            Visible_Alliance_EMS__c = reportingGroups.contains('EMS'),
            Visible_Alliance_FDMS__c = reportingGroups.contains('FDMS'),
            Visible_Alliance_FDMSSA__c = reportingGroups.contains('Bidvest'),
            Visible_Alliance_UCBA__c = reportingGroups.contains('UCBA'),
            Visible_Alliance_Unicaja__c = reportingGroups.contains('Unicaja'),
            Visible_Alliance_VERT__c = reportingGroups.contains('Vert')
        );
        Database.insert(dictionaryReader, AccessLevel.SYSTEM_MODE);

        Set<String> permissionNames = new Set<String>{ 'Data_Dictionary_Reader' };
        if (assignStewardPermission) {
            permissionNames.add('Field_Usage_All_Alliances');
        }
        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (PermissionSet permissionValue : [
            SELECT Id FROM PermissionSet WHERE Name IN :permissionNames
        ]) {
            assignments.add(new PermissionSetAssignment(
                AssigneeId = dictionaryReader.Id,
                PermissionSetId = permissionValue.Id
            ));
        }
        Database.insert(assignments, AccessLevel.SYSTEM_MODE);
        return dictionaryReader;
    }

    public static User createSystemAdministrator(String aliasValue) {
        Profile administratorProfile = [
            SELECT Id FROM Profile WHERE PermissionsModifyAllData = true LIMIT 1
        ];
        String uniqueValue = String.valueOf(Datetime.now().getTime());
        User administrator = new User(
            Alias = aliasValue,
            CommunityNickname = aliasValue + '.' + uniqueValue,
            Email = 'field.usage.admin@example.com',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LastName = 'Field Usage Administrator',
            LocaleSidKey = 'en_US',
            ProfileId = administratorProfile.Id,
            TimeZoneSidKey = 'Europe/London',
            Username = aliasValue + '.' + uniqueValue + '@example.com'
        );
        Database.insert(administrator, AccessLevel.SYSTEM_MODE);
        PermissionSet readerPermission = [
            SELECT Id FROM PermissionSet WHERE Name = 'Data_Dictionary_Reader' LIMIT 1
        ];
        Database.insert(new PermissionSetAssignment(
            AssigneeId = administrator.Id,
            PermissionSetId = readerPermission.Id
        ), AccessLevel.SYSTEM_MODE);
        return administrator;
    }

    public static Data_Dictionary_Object__c createCatalogObject(String apiName, Boolean insertRecord) {
        Data_Dictionary_Object__c catalogObject = new Data_Dictionary_Object__c(
            Catalog_Key__c = '00DTEST-' + apiName,
            Qualified_API_Name__c = apiName,
            Label__c = apiName.replace('__c', '').replace('_', ' '),
            Object_Category__c = apiName.endsWith('__c') ? 'Custom' : 'Standard',
            Documentation_Status__c = 'Approved',
            Sensitivity__c = 'Internal',
            Field_Count__c = 251,
            Documented_Field_Count__c = 200,
            Sensitive_Field_Count__c = 5,
            Dependency_Count__c = 12,
            Last_Scanned_At__c = Datetime.newInstance(2026, 8, 6, 12, 0, 0),
            Active__c = true
        );
        if (insertRecord) {
            Database.insert(catalogObject, AccessLevel.SYSTEM_MODE);
        }
        return catalogObject;
    }

    public static List<Data_Dictionary_Field__c> createCatalogFields(
        Id dictionaryObjectId,
        Integer recordCount,
        Boolean insertRecords
    ) {
        List<Data_Dictionary_Field__c> catalogFields = new List<Data_Dictionary_Field__c>();
        for (Integer indexValue = 0; indexValue < recordCount; indexValue++) {
            catalogFields.add(new Data_Dictionary_Field__c(
                Dictionary_Object__c = dictionaryObjectId,
                Catalog_Key__c = '00DTEST-Account-Field_' + indexValue + '__c',
                Qualified_API_Name__c = 'Field_' + indexValue + '__c',
                Label__c = 'Field ' + indexValue,
                Data_Type__c = 'string',
                Documentation_Status__c = indexValue == 0 ? 'Approved' : 'Undocumented',
                Sensitivity__c = indexValue == 0 ? 'Restricted' : 'Internal',
                Required__c = indexValue == 0,
                Dependency_Count__c = indexValue,
                Active__c = true
            ));
        }
        if (insertRecords) {
            Database.insert(catalogFields, AccessLevel.SYSTEM_MODE);
        }
        return catalogFields;
    }

    public static List<Data_Dictionary_Field_Usage__c> createFieldUsage(
        List<Data_Dictionary_Field__c> catalogFields,
        Boolean insertRecords
    ) {
        List<Data_Dictionary_Field_Usage__c> usageRows = new List<Data_Dictionary_Field_Usage__c>{
            buildUsage(catalogFields[0].Id, catalogFields[0].Qualified_API_Name__c, 'CMSL', 250, 125, 50, 'Used'),
            buildUsage(catalogFields[1].Id, catalogFields[1].Qualified_API_Name__c, 'CMSL', 250, 0, 0, 'Unused'),
            buildUsage(catalogFields[2].Id, catalogFields[2].Qualified_API_Name__c, 'FDMS', 0, 0, 0, 'No Records')
        };
        if (insertRecords) {
            Database.insert(usageRows, AccessLevel.SYSTEM_MODE);
        }
        return usageRows;
    }

    private static Data_Dictionary_Field_Usage__c buildUsage(
        Id dictionaryFieldId,
        String fieldApiName,
        String alliance,
        Integer recordsAnalyzed,
        Integer populatedCount,
        Decimal populationPercent,
        String usageStatus
    ) {
        Data_Dictionary_Field_Usage__c usageRow = new Data_Dictionary_Field_Usage__c(
            Dictionary_Field__c = dictionaryFieldId,
            Catalog_Key__c = '00DTEST-' + alliance + '-' + fieldApiName,
            Source_Org_Id__c = '00D000000000001AAA',
            Source_Analysis_Id__c = alliance == 'CMSL' ? 'a00000000000001AAA' : 'a00000000000002AAA',
            Analysis_Name__c = alliance + ' Account Analysis',
            Alliance__c = alliance,
            Reporting_Group__c = alliance,
            Object_API_Name__c = 'Account',
            Field_API_Name__c = fieldApiName,
            Field_Label__c = fieldApiName.replace('__c', '').replace('_', ' '),
            Catalog_Match_Status__c = 'Matched',
            Record_Type_Name__c = alliance,
            Records_Analyzed__c = recordsAnalyzed,
            Populated_Count__c = populatedCount,
            Population_Percent__c = populationPercent,
            Usage_Status__c = usageStatus,
            Last_Analyzed_At__c = Datetime.newInstance(2026, 8, 1, 12, 0, 0),
            Last_Synced_At__c = Datetime.newInstance(2026, 8, 2, 12, 0, 0),
            Active__c = true
        );
        if (usageStatus != 'No Records') {
            usageRow.Previous_Records_Analyzed__c = 200;
            usageRow.Previous_Populated_Count__c = usageStatus == 'Used' ? 0 : 50;
            usageRow.Previous_Population_Percent__c = usageStatus == 'Used' ? 0 : 25;
            usageRow.Previous_Usage_Status__c = usageStatus == 'Used' ? 'Unused' : 'Used';
            usageRow.Previous_Analyzed_At__c = Datetime.newInstance(2026, 7, 1, 12, 0, 0);
        }
        return usageRow;
    }
}