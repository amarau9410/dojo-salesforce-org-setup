@isTest
private class FieldTripAnalyzeSchedulerTest {
    @isTest
    static void shouldReuseExistingSchedule_WhenMonitorIsScheduledTwice() {
        User operatorUser = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Analyze_Operator' }
        );
        System.runAs(operatorUser) {
            Test.startTest();
            String firstScheduleId = FieldTripAnalyzeScheduler.scheduleMonitor();
            String secondScheduleId = FieldTripAnalyzeScheduler.scheduleMonitor();
            Test.stopTest();

            Assert.areEqual(firstScheduleId, secondScheduleId,
                'Repeated setup should not create a duplicate recurring schedule');
            Assert.areEqual(1, [
                SELECT COUNT()
                FROM CronTrigger
                WHERE CronJobDetail.Name = 'Field Trip Analyze Orchestrator'
            ], 'Only one monitor schedule should exist');
        }
    }

    @isTest
    static void shouldEnqueueOnePass_WhenScheduledExecutionRuns() {
        User operatorUser = FieldTripRunTestDataFactory.createAdministratorOperator(
            new List<String>{ 'Field_Trip_Analyze_Operator' }
        );
        System.runAs(operatorUser) {
            Test.startTest();
            new FieldTripAnalyzeScheduler().execute((SchedulableContext) null);
            Test.stopTest();

            Assert.areEqual(1, [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE ApexClass.Name = 'FieldTripAnalyzeOrchestrator'
                    AND JobType = 'Queueable'
            ], 'A scheduled tick should enqueue one orchestration pass');
        }
    }

    @isTest
    static void shouldRejectScheduleSetup_WhenUserLacksAnalyzePermission() {
        User userWithoutAnalyzePermission = FieldTripRunTestDataFactory.createOperator(
            new List<String>()
        );
        System.runAs(userWithoutAnalyzePermission) {
            Boolean permissionErrorThrown = false;
            try {
                FieldTripAnalyzeScheduler.scheduleMonitor();
            } catch (Exception exceptionValue) {
                permissionErrorThrown = exceptionValue.getMessage().contains(
                    'requires the Field Trip Analyze Operator permission'
                );
            }
            Assert.isTrue(permissionErrorThrown,
                'Only a Field Trip Analyze Operator should install the recurring schedule');
        }
    }
}
