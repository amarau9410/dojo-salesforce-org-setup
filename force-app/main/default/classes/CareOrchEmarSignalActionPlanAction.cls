public without sharing class CareOrchEmarSignalActionPlanAction {
    public class Payload {
        @InvocableVariable(required=true)
        public String value;
    }

    public class Result {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String message;
        @InvocableVariable public Id observationId;
        @InvocableVariable public Id actionPlanId;
    }

    @InvocableMethod(label='Create CareOrch Medication Refused Action Plan')
    public static List<Result> process(List<Payload> payloads) {
        List<Result> results = new List<Result>();
        if (payloads == null) {
            return results;
        }

        for (Payload payload : payloads) {
            Result result = new Result();
            try {
                if (payload == null || String.isBlank(payload.value)) {
                    throw new AuraHandledException('value is required');
                }

                CareOrchEmarSignalActionPlanService.Result serviceResult =
                    CareOrchEmarSignalActionPlanService.createForObservation((Id) payload.value.trim());
                result.success = true;
                result.observationId = serviceResult.observationId;
                result.actionPlanId = serviceResult.actionPlanId;
                result.message = serviceResult.message;
            } catch (Exception ex) {
                result.success = false;
                result.message = ex.getMessage();
            }
            results.add(result);
        }

        return results;
    }
}