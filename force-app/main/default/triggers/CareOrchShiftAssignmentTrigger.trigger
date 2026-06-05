trigger CareOrchShiftAssignmentTrigger on Task (after insert, after update) {
    if (Trigger.isAfter) {
        CareOrchShiftAssignmentService.handleAfter(Trigger.new, Trigger.oldMap);
    }
}
