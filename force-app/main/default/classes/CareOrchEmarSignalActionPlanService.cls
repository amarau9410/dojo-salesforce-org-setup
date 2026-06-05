public without sharing class CareOrchEmarSignalActionPlanService {
    public static final String MEDICATION_REFUSED = 'Medication Refused';
    public static final String TEMPLATE_UNIQUE_NAME = 'CareOrch_Medication_Refused_Template';

    public class Result {
        public Id observationId;
        public Id actionPlanId;
        public List<Id> taskIds = new List<Id>();
        public String message;
    }

    public static Result createForObservation(Id observationId) {
        if (observationId == null) {
            throw new AuraHandledException('observationId is required');
        }

        List<CareObservation> observations = [
            SELECT Id, Signal_Value__c, ObservedSubjectId, Care_Home_Notes__c, Name
            FROM CareObservation
            WHERE Id = :observationId
            WITH USER_MODE
            LIMIT 1
        ];
        if (observations.isEmpty()) {
            throw new AuraHandledException('CareObservation not found');
        }

        CareObservation observation = observations[0];
        Result result = new Result();
        result.observationId = observation.Id;

        if (observation.Signal_Value__c != MEDICATION_REFUSED) {
            result.message = 'No action plan required';
            return result;
        }

        List<Account> residents = [
            SELECT Id, Name, OwnerId
            FROM Account
            WHERE Id = :observation.ObservedSubjectId
            WITH USER_MODE
            LIMIT 1
        ];
        if (residents.isEmpty()) {
            throw new AuraHandledException('Resident not found for observation');
        }
        Account resident = residents[0];

        List<ActionPlanTemplate> templates = [
            SELECT Id, Name, UniqueName, ActionPlanType, TargetEntityType
            FROM ActionPlanTemplate
            WHERE UniqueName = :TEMPLATE_UNIQUE_NAME
            WITH USER_MODE
            LIMIT 1
        ];
        if (templates.isEmpty()) {
            throw new AuraHandledException('Action plan template not found: ' + TEMPLATE_UNIQUE_NAME);
        }
        ActionPlanTemplate template = templates[0];

        List<ActionPlanTemplateVersion> versions = [
            SELECT Id, Name, Version, Status
            FROM ActionPlanTemplateVersion
            WHERE ActionPlanTemplateId = :template.Id
            AND Status = 'Final'
            WITH USER_MODE
            ORDER BY Version DESC
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            throw new AuraHandledException('Active template version not found for ' + TEMPLATE_UNIQUE_NAME);
        }
        ActionPlanTemplateVersion templateVersion = versions[0];

        List<ActionPlanTemplateItem> templateItems = [
            SELECT Id, Name, DisplayOrder, ItemEntityType, IsRequired
            FROM ActionPlanTemplateItem
            WHERE ActionPlanTemplateVersionId = :templateVersion.Id
            AND IsActive = true
            WITH USER_MODE
            ORDER BY DisplayOrder ASC, CreatedDate ASC
        ];
        if (templateItems.isEmpty()) {
            throw new AuraHandledException('Action plan template has no active items');
        }

        ActionPlan actionPlan = new ActionPlan();
        actionPlan.Name = 'High Priority - CareOrch Medication Refused - ' + resident.Name;
        actionPlan.TargetId = resident.Id;
        actionPlan.OwnerId = resident.OwnerId;
        actionPlan.ActionPlanTemplateVersionId = templateVersion.Id;
        actionPlan.ActionPlanType = String.isBlank(template.ActionPlanType) ? 'Industries' : template.ActionPlanType;
        actionPlan.ActionPlanState = 'Not Started';
        actionPlan.StatusCode = 'NotStarted';
        actionPlan.RecordCreationType = 'Autocreated';

        insert as user actionPlan;

        List<Task> generatedTasks = new List<Task>();
        for (ActionPlanTemplateItem templateItem : templateItems) {
            generatedTasks.add(new Task(
                OwnerId = resident.OwnerId,
                WhatId = resident.Id,
                Subject = templateItem.Name,
                Status = 'Not Started',
                Priority = 'High',
                ActivityDate = Date.today(),
                Description = observation.Care_Home_Notes__c
            ));
        }
        insert as user generatedTasks;

        List<ActionPlanItem> generatedItems = new List<ActionPlanItem>();
        for (Integer index = 0; index < templateItems.size(); index++) {
            ActionPlanTemplateItem templateItem = templateItems[index];
            Task generatedTask = generatedTasks[index];
            generatedItems.add(new ActionPlanItem(
                Name = templateItem.Name,
                ActionPlanId = actionPlan.Id,
                ItemId = generatedTask.Id,
                ItemState = 'Pending',
                ActionPlanTemplateItemId = templateItem.Id,
                IsRequired = true,
                DisplayOrder = templateItem.DisplayOrder
            ));
            result.taskIds.add(generatedTask.Id);
        }
        insert as user generatedItems;

        result.actionPlanId = actionPlan.Id;
        result.message = 'Action plan created';
        return result;
    }
}