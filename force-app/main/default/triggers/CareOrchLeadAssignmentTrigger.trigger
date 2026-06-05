trigger CareOrchLeadAssignmentTrigger on Lead (before insert, before update, after update) {
    if (Trigger.isBefore) {
        CareOrchLeadAssignmentService.routeCareEnquiries(Trigger.new);
        if (Trigger.isUpdate) {
            CareOrchLeadAssignmentService.enforceConversionReadiness(Trigger.new, Trigger.oldMap);
        }
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        CareOrchLeadAssignmentService.syncDietaryNeedsToConvertedAccount(Trigger.new, Trigger.oldMap);
    }
}
