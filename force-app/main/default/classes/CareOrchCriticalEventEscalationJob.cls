public with sharing class CareOrchCriticalEventEscalationJob implements Schedulable {
    private Id criticalEventId;

    public CareOrchCriticalEventEscalationJob() {
    }

    public CareOrchCriticalEventEscalationJob(Id eventId) {
        this.criticalEventId = eventId;
    }

    public void execute(SchedulableContext sc) {
        CareOrchCriticalEventDispatchService.processEscalation(criticalEventId);
    }
}
