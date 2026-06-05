@IsTest
private class CareOrchLeadAssignmentServiceTest {
    private static Lead buildCareEnquiryLead(Id careEnquiryRtId) {
        return new Lead(
            LastName = 'UAT Lead',
            Company = 'CareOrch Test Company',
            RecordTypeId = careEnquiryRtId,
            CareOrch_Enquiry_Source__c = 'Hospital',
            CareOrch_Funding_Type__c = 'Private',
            CareOrch_Requested_Care_Type__c = 'Residential',
            CareOrch_Target_Admission_Date__c = Date.today().addDays(10),
            CareOrch_Medical_Conditions__c = 'Diabetes',
            CareOrch_Care_Needs__c = 'Mobility support',
            CareOrch_Dietary_Needs__c = 'Low sugar',
            CareOrch_Contact_Information__c = 'Next of kin on file',
            CareOrch_Check_In_Date__c = Date.today().addDays(14),
            CareOrch_Tour_Feedback_Satisfactory__c = true
        );
    }

    @IsTest
    static void careEnquiryLeadIsAssignedToAdmissionsQueue() {
        Id careEnquiryRtId = CareOrchLeadAssignmentService.getCareEnquiryRecordTypeId();
        System.assertNotEquals(null, careEnquiryRtId, 'Care_Enquiry record type must exist for this test.');

        Id queueId = CareOrchLeadAssignmentService.getAdmissionsQueueId();
        System.assertNotEquals(null, queueId, 'CareOrch_Admissions queue must exist for this test.');

        Lead testLead = new Lead(
            LastName = 'UAT Lead',
            Company = 'CareOrch Test Company',
            RecordTypeId = careEnquiryRtId,
            CareOrch_Funding_Type__c = 'Private',
            CareOrch_Requested_Care_Type__c = 'Residential',
            CareOrch_Target_Admission_Date__c = Date.today().addDays(5)
        );

        insert testLead;

        Lead inserted = [SELECT Id, OwnerId FROM Lead WHERE Id = :testLead.Id LIMIT 1];
        System.assertEquals(queueId, inserted.OwnerId, 'Care enquiry leads should route to admissions queue.');
    }

    @IsTest
    static void conversionBlockedWithoutActivatedContract() {
        Id careEnquiryRtId = CareOrchLeadAssignmentService.getCareEnquiryRecordTypeId();
        System.assertNotEquals(null, careEnquiryRtId, 'Care_Enquiry record type must exist for this test.');

        Lead testLead = buildCareEnquiryLead(careEnquiryRtId);
        insert testLead;

        Lead oldRow = [
            SELECT Id, RecordTypeId, IsConverted, CareOrch_Check_In_Date__c
            FROM Lead
            WHERE Id = :testLead.Id
            LIMIT 1
        ];

        Lead convertingRow = new Lead(
            Id = oldRow.Id,
            RecordTypeId = oldRow.RecordTypeId,
            IsConverted = true,
            CareOrch_Check_In_Date__c = oldRow.CareOrch_Check_In_Date__c
        );

        Test.startTest();
        CareOrchLeadAssignmentService.enforceConversionReadiness(
            new List<Lead>{ convertingRow },
            new Map<Id, Lead>{ oldRow.Id => oldRow }
        );
        Test.stopTest();

        System.assertEquals(1, convertingRow.getErrors().size(), 'Conversion should fail when no activated contract is associated.');
        System.assert(convertingRow.getErrors()[0].getMessage().contains('Activated Contract'));
    }

    @IsTest
    static void conversionSucceedsWhenContractActivated() {
        Id careEnquiryRtId = CareOrchLeadAssignmentService.getCareEnquiryRecordTypeId();
        System.assertNotEquals(null, careEnquiryRtId, 'Care_Enquiry record type must exist for this test.');

        Account residentAccount = new Account(Name = 'Resident Contract Account');
        insert residentAccount;

        Contract residentContract = new Contract(
            AccountId = residentAccount.Id,
            StartDate = Date.today(),
            Status = 'Draft',
            ContractTerm = 12
        );
        insert residentContract;

        residentContract.Status = 'Activated';
        update residentContract;

        Lead testLead = buildCareEnquiryLead(careEnquiryRtId);
        insert testLead;

        Lead oldRow = [
            SELECT Id, RecordTypeId, IsConverted, CareOrch_Check_In_Date__c, CareOrch_Dietary_Needs__c
            FROM Lead
            WHERE Id = :testLead.Id
            LIMIT 1
        ];

        Lead convertingRow = (Lead) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'Id' => oldRow.Id,
                    'RecordTypeId' => oldRow.RecordTypeId,
                    'IsConverted' => true,
                    'ConvertedAccountId' => residentAccount.Id,
                    'CareOrch_Check_In_Date__c' => oldRow.CareOrch_Check_In_Date__c,
                    'CareOrch_Dietary_Needs__c' => oldRow.CareOrch_Dietary_Needs__c
                }
            ),
            Lead.class
        );

        Test.startTest();
        CareOrchLeadAssignmentService.enforceConversionReadiness(
            new List<Lead>{ convertingRow },
            new Map<Id, Lead>{ oldRow.Id => oldRow }
        );
        CareOrchLeadAssignmentService.syncDietaryNeedsToConvertedAccount(
            new List<Lead>{ convertingRow },
            new Map<Id, Lead>{ oldRow.Id => oldRow }
        );
        Test.stopTest();

        System.assertEquals(0, convertingRow.getErrors().size(), 'Conversion readiness should pass when activated contract and check-in date are present.');

        Account refreshedAccount = [
            SELECT Id, CareOrch_Dietary_Needs__c
            FROM Account
            WHERE Id = :residentAccount.Id
            LIMIT 1
        ];
        System.assertEquals('Low sugar', refreshedAccount.CareOrch_Dietary_Needs__c, 'Converted account should inherit dietary notes from lead.');
    }
}
