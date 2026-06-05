trigger CareOrchCriticalEventTrigger on Critical_Event__c (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        CareOrchCriticalEventDispatchService.handleAfterInsert(Trigger.new);
    }
}
