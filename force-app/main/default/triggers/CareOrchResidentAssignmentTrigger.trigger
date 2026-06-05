trigger CareOrchResidentAssignmentTrigger on CareOrch_Resident_Assignment__c (before insert, before update, after insert, after update, after delete, after undelete) {
    if (Trigger.isBefore) {
        CareOrchAssignGuardrailSvc.enforceBeforeSave(Trigger.new, Trigger.oldMap);
    }

    if (Trigger.isAfter) {
        if (Trigger.isDelete) {
            CareOrchAssignGuardrailSvc.refreshShiftRollups(null, Trigger.oldMap);
        } else {
            CareOrchAssignGuardrailSvc.refreshShiftRollups(Trigger.new, Trigger.oldMap);
        }
    }
}
