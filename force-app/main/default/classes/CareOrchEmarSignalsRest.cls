@RestResource(urlMapping='/CareOrch/v1/eMARSignals/*')
global with sharing class CareOrchEmarSignalsRest {
    private static final Set<String> ALLOWED_PAYLOAD_KEYS = new Set<String>{
        'residentExternalId',
        'signalType',
        'timestamp',
        'notes'
    };

    global class EmarSignalRequest {
        public String residentExternalId;
        public String signalType;
        public Datetime timestamp;
        public String notes;
    }

    global class EmarSignalResponse {
        public Id residentId;
        public Id observationId;
        public Id actionPlanId;
        public String status;
    }

    @HttpPost
    global static EmarSignalResponse ingestSignal() {
        RestRequest requestContext = RestContext.request;
        if (requestContext == null || requestContext.requestBody == null) {
            raiseRestError('Request body is required', 400);
        }

        EmarSignalRequest payload = parsePayload(requestContext.requestBody.toString());

        validatePayload(payload);

        Account resident = resolveResident(payload.residentExternalId);
        CareObservation observation = buildObservation(resident.Id, payload);

        SObjectAccessDecision observationDecision = Security.stripInaccessible(
            AccessType.CREATABLE,
            new List<SObject>{ observation }
        );
        List<SObject> sanitizedObservations = observationDecision.getRecords();
        if (sanitizedObservations.isEmpty()) {
            raiseRestError('Observation create access denied', 403);
        }

        observation = (CareObservation) sanitizedObservations[0];
        insert as user observation;

        EmarSignalResponse responseBody = new EmarSignalResponse();
        responseBody.residentId = resident.Id;
        responseBody.observationId = observation.Id;
        responseBody.status = 'Accepted';

        if (payload.signalType == 'Medication Refused') {
            responseBody.actionPlanId = resolveLatestActionPlanId(resident.Id);
        }

        RestContext.response.statusCode = 201;
        return responseBody;
    }

    private static EmarSignalRequest parsePayload(String requestBody) {
        Object parsedBody;
        try {
            parsedBody = JSON.deserializeUntyped(requestBody);
        } catch (JSONException ex) {
            raiseRestError('Invalid JSON payload', 400);
            return null;
        }

        if (!(parsedBody instanceof Map<String, Object>)) {
            raiseRestError('Payload must be a JSON object', 400);
        }

        Map<String, Object> payloadMap = (Map<String, Object>) parsedBody;
        for (String key : payloadMap.keySet()) {
            if (!ALLOWED_PAYLOAD_KEYS.contains(key)) {
                raiseRestError('Unexpected payload parameter: ' + key, 400);
            }
        }

        try {
            return (EmarSignalRequest) JSON.deserialize(requestBody, EmarSignalRequest.class);
        } catch (JSONException ex) {
            raiseRestError('Invalid JSON payload', 400);
            return null;
        }
    }

    private static void validatePayload(EmarSignalRequest payload) {
        if (payload == null) {
            raiseRestError('Payload is required', 400);
        }
        if (String.isBlank(payload.residentExternalId)) {
            raiseRestError('residentExternalId is required', 400);
        }
        if (String.isBlank(payload.signalType)) {
            raiseRestError('signalType is required', 400);
        }
        if (payload.notes != null && payload.notes.length() > 32768) {
            raiseRestError('notes exceeds maximum length', 400);
        }
    }

    private static Account resolveResident(String residentExternalId) {
        try {
            List<Contact> matchingContacts = [
                SELECT Id
                FROM Contact
                WHERE Resident_External_Id__c = :residentExternalId
                WITH USER_MODE
                LIMIT 1
            ];
            if (!matchingContacts.isEmpty()) {
                List<Account> residents = [
                    SELECT Id, Name, PersonContactId
                    FROM Account
                    WHERE IsPersonAccount = true
                    AND PersonContactId = :matchingContacts[0].Id
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!residents.isEmpty()) {
                    return residents[0];
                }
            }
        } catch (QueryException ex) {
            // Fallback resident matching below handles this safely.
        }

        List<Account> residentByName = [
            SELECT Id, Name, PersonContactId
            FROM Account
            WHERE IsPersonAccount = true
            AND Name = :residentExternalId
            WITH USER_MODE
            LIMIT 1
        ];
        if (residentByName.isEmpty()) {
            raiseRestError('Resident not found', 404);
        }
        return residentByName[0];
    }

    private static CareObservation buildObservation(Id residentId, EmarSignalRequest payload) {
        CareObservation observation = new CareObservation();
        observation.Signal_Value__c = payload.signalType;
        observation.Care_Home_Notes__c = payload.notes;
        observation.Name = 'CareOrch ' + payload.signalType;
        observation.ObservationStatus = 'final';
        observation.ObservedSubjectId = residentId;
        observation.ObservedValueText = payload.signalType;
        observation.SourceSystem = 'CareOrch';
        return observation;
    }

    private static Id resolveLatestActionPlanId(Id residentId) {
        List<ActionPlan> actionPlans = [
            SELECT Id
            FROM ActionPlan
            WHERE TargetId = :residentId
            AND Name LIKE 'High Priority - CareOrch Medication Refused%'
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return actionPlans.isEmpty() ? null : actionPlans[0].Id;
    }

    private static void raiseRestError(String message, Integer statusCode) {
        RestContext.response.statusCode = statusCode;
        throw new CareOrchRestException(message);
    }

    global class CareOrchRestException extends Exception {
    }
}