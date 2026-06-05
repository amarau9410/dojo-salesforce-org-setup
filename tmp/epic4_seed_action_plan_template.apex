List<ActionPlanTemplate> existingTemplates = [
    SELECT Id
    FROM ActionPlanTemplate
    WHERE UniqueName = 'CareOrch_Medication_Refused_Template'
    LIMIT 1
];

if (existingTemplates.isEmpty()) {
    ActionPlanTemplate template = new ActionPlanTemplate(
        Name = 'CareOrch Medication Refused',
        UniqueName = 'CareOrch_Medication_Refused_Template',
        ActionPlanType = 'Industries',
        TargetEntityType = 'Account',
        Description = 'Emergency response template for medication refused signals.'
    );
    insert template;

    List<ActionPlanTemplateVersion> templateVersions = [
        SELECT Id, Name, Status, Version
        FROM ActionPlanTemplateVersion
        WHERE ActionPlanTemplateId = :template.Id
        ORDER BY CreatedDate ASC
        LIMIT 1
    ];
    if (templateVersions.isEmpty()) {
        throw new AuraHandledException('Template version was not created automatically');
    }

    ActionPlanTemplateVersion templateVersion = templateVersions[0];

    insert new List<ActionPlanTemplateItem>{
        new ActionPlanTemplateItem(
            Name = 'Emergency Vitals Check',
            ActionPlanTemplateVersionId = templateVersion.Id,
            ItemEntityType = 'Task',
            DisplayOrder = 1,
            IsRequired = true,
            IsActive = true,
            UniqueName = 'Emergency_Vitals_Check'
        ),
        new ActionPlanTemplateItem(
            Name = 'Hydration Review',
            ActionPlanTemplateVersionId = templateVersion.Id,
            ItemEntityType = 'Task',
            DisplayOrder = 2,
            IsRequired = true,
            IsActive = true,
            UniqueName = 'Hydration_Review'
        )
    };

    templateVersion.Status = 'Final';
    update templateVersion;

    System.debug('Created CareOrch Medication Refused Action Plan template stack: ' + template.Id + ', version ' + templateVersion.Id);
} else {
    System.debug('CareOrch Medication Refused Action Plan template already exists.');
}