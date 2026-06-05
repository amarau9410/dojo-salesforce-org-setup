@RestResource(urlMapping='/careorch/shift-response')
global without sharing class CareOrchShiftResponseRest {
    @HttpGet
    global static void respond() {
        RestRequest req = RestContext.request;

        String taskIdParam = req.params.get('taskId');
        String actionParam = req.params.get('action');

        if (String.isBlank(taskIdParam) || String.isBlank(actionParam)) {
            writeHtml(400, 'Missing taskId or action parameter.');
            return;
        }

        if (!Schema.sObjectType.Task.isAccessible()) {
            writeHtml(403, 'You do not have access to Task.');
            return;
        }

        Id taskId;
        try {
            taskId = (Id) taskIdParam;
        } catch (Exception ex) {
            writeHtml(400, 'Invalid taskId parameter.');
            return;
        }

        Task taskRecord;
        try {
            taskRecord = [
                SELECT Id, OwnerId, Subject, CareOrch_Shift_Status__c
                FROM Task
                WHERE Id = :taskId
                LIMIT 1
            ];
        } catch (Exception ex) {
            writeHtml(404, 'Shift assignment not found.');
            return;
        }

        if (taskRecord.OwnerId != UserInfo.getUserId()) {
            writeHtml(403, 'This shift is not currently assigned to you.');
            return;
        }

        String normalizedAction = actionParam.trim().toLowerCase();
        if (normalizedAction == 'accept') {
            CareOrchShiftAssignmentService.notifyManagerForAcceptance(taskRecord.Id, UserInfo.getUserId());
            writeHtml(200, 'Shift accepted successfully. Your manager has been notified.');
            return;
        }

        if (normalizedAction == 'reject') {
            CareOrchShiftAssignmentService.rejectAndRouteToNextCaregiver(taskRecord.Id, UserInfo.getUserId());
            writeHtml(200, 'Shift rejected. We are contacting the next available caregiver and notifying your manager.');
            return;
        }

        writeHtml(400, 'Unsupported action. Use accept or reject.');
    }

    private static void writeHtml(Integer statusCode, String message) {
        RestResponse res = RestContext.response;
        res.statusCode = statusCode;
        res.addHeader('Content-Type', 'text/html; charset=UTF-8');
        String body =
            '<!doctype html><html><head><meta charset="utf-8" />' +
            '<title>CareOrch Shift Response</title></head><body>' +
            '<h2>CareOrch Shift Response</h2><p>' +
            escapeHtml(message) +
            '</p></body></html>';
        res.responseBody = Blob.valueOf(body);
    }

    private static String escapeHtml(String value) {
        if (value == null) {
            return '';
        }
        return value
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace('\'', '&#39;');
    }
}
