@isTest
public class FieldTripRunTestDataFactory {
    public static Field_Trip__Object_Analysis__c createAnalysis() {
        String keyPrefix = Field_Trip__Object_Analysis__c.SObjectType
            .getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix();
        return new Field_Trip__Object_Analysis__c(
            Id = (Id) (keyPrefix + '000000000001'),
            Name = 'FDMS Account Test',
            Field_Trip__Object_Name__c = 'Account',
            Field_Trip__Object_Label__c = 'Account',
            Field_Trip__Filter__c = 'RecordTypeId = \'012000000000001AAA\'',
            Field_Trip__isCustom__c = false
        );
    }

    public static User createOperator(List<String> permissionSetNames) {
        return createOperator(permissionSetNames, new Set<String>{
            'ADCB', 'AIBMS', 'Bidvest', 'CMSL', 'EMS', 'FDMS', 'UCBA', 'Unicaja', 'Vert'
        });
    }

    public static User createOperator(
        List<String> permissionSetNames,
        Set<String> reportingGroups
    ) {
        Set<String> assignedPermissionNames = new Set<String>(permissionSetNames);
        assignedPermissionNames.add('Data_Dictionary_Reader');
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniqueValue = String.valueOf(Datetime.now().getTime())
            + String.valueOf(Crypto.getRandomLong()).replace('-', '');
        User operatorUser = new User(
            Alias = 'ftoper',
            CommunityNickname = ('ft.' + uniqueValue).left(40),
            Email = 'field.trip.operator@example.com',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LastName = 'Field Trip Operator',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'Europe/London',
            Username = 'field.trip.operator.' + uniqueValue + '@example.com',
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
        Database.insert(operatorUser, AccessLevel.SYSTEM_MODE);

        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (PermissionSet permissionSetRecord : [
            SELECT Id
            FROM PermissionSet
            WHERE Name IN :assignedPermissionNames
        ]) {
            assignments.add(new PermissionSetAssignment(
                AssigneeId = operatorUser.Id,
                PermissionSetId = permissionSetRecord.Id
            ));
        }
        Database.insert(assignments, AccessLevel.SYSTEM_MODE);
        return operatorUser;
    }

    public static User createAdministratorOperator(List<String> permissionSetNames) {
        Set<String> assignedPermissionNames = new Set<String>(permissionSetNames);
        assignedPermissionNames.add('Data_Dictionary_Reader');
        Profile administratorProfile = [
            SELECT Id
            FROM Profile
            WHERE PermissionsModifyAllData = true
            LIMIT 1
        ];
        String uniqueValue = String.valueOf(Datetime.now().getTime())
            + String.valueOf(Crypto.getRandomLong()).replace('-', '');
        User administrator = new User(
            Alias = 'ftadmin',
            CommunityNickname = ('fta.' + uniqueValue).left(40),
            Email = 'field.trip.admin@example.com',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LastName = 'Field Trip Administrator',
            LocaleSidKey = 'en_US',
            ProfileId = administratorProfile.Id,
            TimeZoneSidKey = 'Europe/London',
            Username = 'field.trip.admin.' + uniqueValue + '@example.com'
        );
        Database.insert(administrator, AccessLevel.SYSTEM_MODE);

        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (PermissionSet permissionSetRecord : [
            SELECT Id
            FROM PermissionSet
            WHERE Name IN :assignedPermissionNames
        ]) {
            assignments.add(new PermissionSetAssignment(
                AssigneeId = administrator.Id,
                PermissionSetId = permissionSetRecord.Id
            ));
        }
        Database.insert(assignments, AccessLevel.SYSTEM_MODE);
        return administrator;
    }

    public static Field_Trip_Run_Item__c createCompletedWorkbook(
        Id runId,
        String reportGroup
    ) {
        Field_Trip_Run_Item__c workbook = new Field_Trip_Run_Item__c(
            Field_Trip_Run__c = runId,
            Item_Type__c = 'Workbook',
            Status__c = 'Completed',
            Report_Group__c = reportGroup,
            Object_API_Name__c = 'Account',
            File_Name__c = reportGroup + ' Account Field Usage.xlsx',
            File_Size__c = 2048,
            Checksum_SHA256__c = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
            Download_URL__c = 'https://example.com/' + reportGroup + '/field-usage.xlsx'
        );
        Database.insert(workbook, AccessLevel.SYSTEM_MODE);
        return workbook;
    }
}