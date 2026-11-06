/**
 * Schedules durable Salesforce-hosted Analyze monitoring and prevents overlapping passes.
 */
public with sharing class FieldTripAnalyzeScheduler implements Schedulable {
    private static final String SCHEDULER_NAME = 'Field Trip Analyze Orchestrator';
    private static final String SCHEDULER_CRON = '0 0 * * * ?';
    private static final String REQUIRED_PERMISSION = 'Launch_Field_Trip_Analyze';

    /**
     * Queues one orchestration pass when no previous pass is waiting or running.
     * @param context Scheduled execution context.
     */
    public void execute(SchedulableContext context) {
        startProcessingIfIdle();
    }

    /**
     * Starts the queue when no orchestration pass is already active.
     */
    public static void startProcessingIfIdle() {
        requirePermission();
        if (!FieldTripAnalyzeRepository.hasActiveQueueable()) {
            System.enqueueJob(new FieldTripAnalyzeOrchestrator());
        }
    }

    /**
     * Ensures the recurring monitor exists without creating duplicate schedules.
     * @return Existing or newly scheduled CronTrigger ID.
     */
    public static String scheduleMonitor() {
        requirePermission();
        List<CronTrigger> existingJobs = FieldTripAnalyzeRepository.findActiveSchedules();
        if (!existingJobs.isEmpty()) {
            return String.valueOf(existingJobs[0].Id);
        }
        return String.valueOf((Id) System.schedule(
            SCHEDULER_NAME,
            SCHEDULER_CRON,
            new FieldTripAnalyzeScheduler()
        ));
    }

    private static void requirePermission() {
        if (!FeatureManagement.checkPermission(REQUIRED_PERMISSION)) {
            throw new SchedulerException(
                'The scheduled Analyze monitor requires the Field Trip Analyze Operator permission.'
            );
        }
    }

    private class SchedulerException extends Exception {}
}
