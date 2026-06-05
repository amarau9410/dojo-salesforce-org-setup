import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getSnapshot from '@salesforce/apex/CareOrchManagerCockpitController.getSnapshot';
import getCriticalSlaBreachRows from '@salesforce/apex/CareOrchManagerCockpitController.getCriticalSlaBreachRows';
import getAtRiskShiftRows from '@salesforce/apex/CareOrchManagerCockpitController.getAtRiskShiftRows';
import getPendingTranslationRows from '@salesforce/apex/CareOrchManagerCockpitController.getPendingTranslationRows';
import getOpenRiskAgingRows from '@salesforce/apex/CareOrchManagerCockpitController.getOpenRiskAgingRows';
import getAssignableCaregivers from '@salesforce/apex/CareOrchManagerCockpitController.getAssignableCaregivers';
import reassignShift from '@salesforce/apex/CareOrchManagerCockpitController.reassignShift';
import saveRows from '@salesforce/apex/CareOrchManagerCockpitController.saveRows';
import logPhoneOverride from '@salesforce/apex/CareOrchManagerCockpitController.logPhoneOverride';

const REFRESH_MS = 30000;

const CRITICAL_COLUMNS = [
    {
        type: 'button',
        fixedWidth: 80,
        typeAttributes: {
            label: 'Open',
            name: 'open',
            variant: 'base'
        }
    },
    { label: 'Event', fieldName: 'Name', type: 'text' },
    { label: 'Resident', fieldName: 'ResidentName', type: 'text' },
    { label: 'Category', fieldName: 'Event_Category__c', type: 'text' },
    { label: 'Status', fieldName: 'Status__c', type: 'text', editable: true },
    { label: 'SLA (min)', fieldName: 'SlaMinutes', type: 'number' },
    { label: 'Overdue (min)', fieldName: 'MinutesOverdue', type: 'number' },
    {
        type: 'button',
        fixedWidth: 150,
        typeAttributes: {
            label: 'Log Phone Override',
            name: 'log_override',
            variant: 'neutral'
        }
    }
];

const SHIFT_COLUMNS = [
    {
        type: 'button',
        fixedWidth: 80,
        typeAttributes: {
            label: 'Open',
            name: 'open',
            variant: 'base'
        }
    },
    { label: 'Shift', fieldName: 'Subject', type: 'text' },
    { label: 'Patient', fieldName: 'PatientName', type: 'text' },
    { label: 'Status', fieldName: 'CareOrch_Shift_Status__c', type: 'text' },
    { label: 'Likely To Fail', fieldName: 'Likely_To_Fail__c', type: 'boolean' },
    { label: 'At Risk', fieldName: 'CareOrch_At_Risk__c', type: 'boolean', editable: true },
    { label: 'Risk Reason', fieldName: 'CareOrch_At_Risk_Reason__c', type: 'text', editable: true },
    { label: 'Contacted', fieldName: 'CareOrch_Contacted_Count__c', type: 'number' },
    { label: 'Rejected', fieldName: 'CareOrch_Rejected_Count__c', type: 'number' },
    {
        type: 'button',
        fixedWidth: 95,
        typeAttributes: {
            label: 'Reassign',
            name: 'reassign',
            variant: 'neutral'
        }
    }
];

const TRANSLATION_COLUMNS = [
    {
        type: 'button',
        fixedWidth: 80,
        typeAttributes: {
            label: 'Open',
            name: 'open',
            variant: 'base'
        }
    },
    { label: 'Observation', fieldName: 'Name', type: 'text' },
    { label: 'Original Text', fieldName: 'Original_Observation__c', type: 'text' },
    { label: 'Machine Translation', fieldName: 'Auto_Translated_Notes__c', type: 'text', editable: true },
    { label: 'Status', fieldName: 'Translation_Status__c', type: 'text', editable: true },
    {
        label: 'Updated',
        fieldName: 'LastModifiedDate',
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }
    }
];

const AGING_COLUMNS = [
    {
        type: 'button',
        fixedWidth: 80,
        typeAttributes: {
            label: 'Open',
            name: 'open',
            variant: 'base'
        }
    },
    { label: 'Event', fieldName: 'Name', type: 'text' },
    { label: 'Status', fieldName: 'Status__c', type: 'text', editable: true },
    { label: 'Resident', fieldName: 'ResidentName', type: 'text' },
    { label: 'Overdue (min)', fieldName: 'MinutesOverdue', type: 'number' },
    {
        type: 'button',
        fixedWidth: 150,
        typeAttributes: {
            label: 'Log Phone Override',
            name: 'log_override',
            variant: 'neutral'
        }
    }
];

export default class CareOrchManagerCockpit extends NavigationMixin(LightningElement) {
    snapshot;
    trendRows = [];
    casePriorityRows = [];
    rows = [];
    draftValues = [];
    panelKey = 'critical';
    panelTitle = 'Critical SLA Breaches';
    panelColumns = CRITICAL_COLUMNS;
    agingDayFilter;
    agingSegmentFilter;

    showReassignModal = false;
    selectedTaskId;
    caregiverOptions = [];
    selectedCaregiverId;
    managerReassignNote = '';
    reassignInFlight = false;

    wiredSnapshotResult;
    refreshHandle;

    @wire(getSnapshot)
    wiredSnapshot(result) {
        this.wiredSnapshotResult = result;
        if (result.data) {
            this.snapshot = result.data;
            this.trendRows = (result.data.trend || []).map((row) => ({
                ...row,
                openWidth: this.normalizeWidth(row.averageOpenAgeHours),
                resolutionWidth: this.normalizeWidth(row.averageResolutionHours)
            }));

            const sourceRows = result.data.casePriority || [];
            const maxCount = sourceRows.reduce((maxValue, row) => {
                const count = Number(row.count || 0);
                return Math.max(maxValue, count);
            }, 0);
            this.casePriorityRows = sourceRows.map((row) => ({
                ...row,
                widthStyle: this.normalizeCasePriorityWidth(row.count, maxCount),
                barClass: this.getPriorityBarClass(row.priority)
            }));
        }
    }

    connectedCallback() {
        this.loadPanelRows(this.panelKey);
        this.refreshHandle = window.setInterval(() => {
            this.refreshAll();
        }, REFRESH_MS);
    }

    disconnectedCallback() {
        if (this.refreshHandle) {
            window.clearInterval(this.refreshHandle);
        }
    }

    get criticalCount() {
        return this.snapshot?.criticalSlaBreaches || 0;
    }

    get atRiskShiftCount() {
        return this.snapshot?.atRiskShifts || 0;
    }

    get translationCount() {
        return this.snapshot?.pendingTranslationReviews || 0;
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get hasCasePriorityRows() {
        return this.casePriorityRows.length > 0;
    }

    get deathSlaMinutes() {
        return this.snapshot?.deathSlaMinutes || 15;
    }

    get defaultSlaMinutes() {
        return this.snapshot?.defaultSlaMinutes || 30;
    }

    get panelDescription() {
        if (this.panelKey === 'critical') {
            return 'Active incidents where SLA timer elapsed with no acknowledgment.';
        }
        if (this.panelKey === 'shifts') {
            return 'Open shifts flagged as likely to fail based on rejection and routing pattern.';
        }
        if (this.panelKey === 'translations') {
            return 'Machine-translated observations awaiting human validation.';
        }
        return 'Aging trend and active incident list for intervention speed tracking.';
    }

    get hasAgingFilter() {
        return this.panelKey === 'aging' && !!this.agingDayFilter && !!this.agingSegmentFilter;
    }

    get agingFilterLabel() {
        if (!this.hasAgingFilter) {
            return '';
        }
        const segmentLabel = this.agingSegmentFilter === 'resolved' ? 'Resolved' : 'Open';
        return `${segmentLabel} incidents for ${this.agingDayFilter}`;
    }

    get hasCaregiverOptions() {
        return this.caregiverOptions.length > 0;
    }

    get disableReassignConfirm() {
        return this.reassignInFlight || !this.selectedTaskId || !this.selectedCaregiverId;
    }

    async handleRefresh() {
        await this.refreshAll();
    }

    async refreshAll() {
        if (this.wiredSnapshotResult) {
            await refreshApex(this.wiredSnapshotResult);
        }
        await this.loadPanelRows(this.panelKey);
    }

    async handleWidgetClick(event) {
        const selected = event.currentTarget.dataset.panel;
        if (!selected) {
            return;
        }

        if (selected !== 'aging') {
            this.agingDayFilter = null;
            this.agingSegmentFilter = null;
        }

        this.panelKey = selected;
        this.draftValues = [];

        if (selected === 'critical') {
            this.panelTitle = 'Critical SLA Breaches';
            this.panelColumns = CRITICAL_COLUMNS;
        } else if (selected === 'shifts') {
            this.panelTitle = 'At-Risk Shifts';
            this.panelColumns = SHIFT_COLUMNS;
        } else if (selected === 'translations') {
            this.panelTitle = 'Pending Translation Reviews';
            this.panelColumns = TRANSLATION_COLUMNS;
        } else {
            this.panelTitle = 'Open Risk Aging';
            this.panelColumns = AGING_COLUMNS;
        }

        await this.loadPanelRows(selected);
    }

    async loadPanelRows(panel) {
        try {
            if (panel === 'critical') {
                const records = await getCriticalSlaBreachRows({ limitSize: 100 });
                this.rows = (records || []).map((row) => {
                    const createdAt = row.CreatedDate ? new Date(row.CreatedDate).getTime() : Date.now();
                    const ageMinutes = (Date.now() - createdAt) / 60000;
                    const slaMinutes = this.getSlaMinutes(row.Event_Category__c);
                    return {
                        ...row,
                        ResidentName: row.Client_Account__r ? row.Client_Account__r.Name : '',
                        AssignedToName: row.Assigned_To__r ? row.Assigned_To__r.Name : '',
                        SlaMinutes: slaMinutes,
                        MinutesOverdue: Math.max(0, Number((ageMinutes - slaMinutes).toFixed(2)))
                    };
                });
                return;
            }
            if (panel === 'shifts') {
                const records = await getAtRiskShiftRows({ limitSize: 100 });
                this.rows = (records || []).map((row) => ({
                    ...row,
                    OwnerName: row.Owner ? row.Owner.Name : '',
                    PatientName: row.What ? row.What.Name : ''
                }));
                return;
            }
            if (panel === 'translations') {
                this.rows = await getPendingTranslationRows({ limitSize: 100 });
                return;
            }
            const records = await getOpenRiskAgingRows({
                limitSize: 100,
                dayKey: this.agingDayFilter,
                segment: this.agingSegmentFilter
            });
            this.rows = (records || []).map((row) => {
                const createdAt = row.CreatedDate ? new Date(row.CreatedDate).getTime() : Date.now();
                const ageMinutes = (Date.now() - createdAt) / 60000;
                const slaMinutes = this.getSlaMinutes(row.Event_Category__c);
                return {
                    ...row,
                    ResidentName: row.Client_Account__r ? row.Client_Account__r.Name : '',
                    MinutesOverdue: Math.max(0, Number((ageMinutes - slaMinutes).toFixed(2)))
                };
            });
        } catch (error) {
            this.rows = [];
            this.notifyError('Unable to load cockpit panel', error);
        }
    }

    getSlaMinutes(eventCategory) {
        return eventCategory === 'Death' ? this.deathSlaMinutes : this.defaultSlaMinutes;
    }

    handleCellChange(event) {
        this.draftValues = event.detail.draftValues;
    }

    async handleSave(event) {
        const drafts = event.detail.draftValues || [];
        if (!drafts.length) {
            return;
        }

        try {
            await saveRows({
                panelKey: this.panelKey,
                draftValuesJson: JSON.stringify(drafts)
            });
            this.draftValues = [];
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Saved',
                    message: 'Record updates applied.',
                    variant: 'success'
                })
            );
            await this.refreshAll();
        } catch (error) {
            this.notifyError('Unable to save row changes', error);
        }
    }

    async handleRowAction(event) {
        const actionName = event.detail.action?.name;
        const row = event.detail.row;
        if (!row || !actionName) {
            return;
        }

        if (actionName === 'open') {
            this.navigateToView(row.Id);
            return;
        }

        if (actionName === 'reassign') {
            await this.openReassignModal(row.Id);
            return;
        }

        if (actionName === 'log_override') {
            try {
                await logPhoneOverride({ criticalEventId: row.Id });
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Phone Override Logged',
                        message: 'Manual communication override was recorded.',
                        variant: 'success'
                    })
                );
                await this.refreshAll();
            } catch (error) {
                this.notifyError('Unable to log phone override', error);
            }
        }
    }

    async handleTrendSegmentClick(event) {
        const day = event.currentTarget.dataset.day;
        const segment = event.currentTarget.dataset.segment;
        if (!day || !segment) {
            return;
        }

        this.panelKey = 'aging';
        this.panelTitle = 'Open Risk Aging';
        this.panelColumns = AGING_COLUMNS;
        this.agingDayFilter = day;
        this.agingSegmentFilter = segment;
        this.draftValues = [];
        await this.loadPanelRows('aging');
    }

    async handleClearAgingFilter() {
        this.agingDayFilter = null;
        this.agingSegmentFilter = null;
        await this.loadPanelRows('aging');
    }

    async openReassignModal(taskId) {
        this.selectedTaskId = taskId;
        this.selectedCaregiverId = null;
        this.managerReassignNote = '';
        this.reassignInFlight = false;
        this.showReassignModal = true;

        try {
            const options = await getAssignableCaregivers({ taskId });
            this.caregiverOptions = (options || []).map((row) => ({
                label: `${row.name} (${row.email})`,
                value: row.userId
            }));
        } catch (error) {
            this.caregiverOptions = [];
            this.notifyError('Unable to load caregivers', error);
        }
    }

    handleCloseReassignModal() {
        this.showReassignModal = false;
        this.selectedTaskId = null;
        this.selectedCaregiverId = null;
        this.managerReassignNote = '';
        this.caregiverOptions = [];
        this.reassignInFlight = false;
    }

    handleCaregiverChange(event) {
        this.selectedCaregiverId = event.detail.value;
    }

    handleManagerNoteChange(event) {
        this.managerReassignNote = event.detail.value;
    }

    async handleConfirmReassign() {
        if (this.disableReassignConfirm) {
            return;
        }

        this.reassignInFlight = true;
        try {
            await reassignShift({
                taskId: this.selectedTaskId,
                caregiverId: this.selectedCaregiverId,
                managerNote: this.managerReassignNote
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Shift Reassigned',
                    message: 'Manual reassignment applied in-line.',
                    variant: 'success'
                })
            );
            this.handleCloseReassignModal();
            await this.refreshAll();
        } catch (error) {
            this.notifyError('Unable to reassign shift', error);
            this.reassignInFlight = false;
        }
    }

    navigateToView(recordId) {
        const objectApiName = this.panelKey === 'translations'
            ? 'CareObservation'
            : this.panelKey === 'shifts'
                ? 'Task'
                : 'Critical_Event__c';

        this[NavigationMixin.Navigate](
            {
                type: 'standard__recordPage',
                attributes: {
                    recordId,
                    objectApiName,
                    actionName: 'view'
                }
            }
        );
    }

    navigateToEdit(recordId, objectApiName) {
        this[NavigationMixin.Navigate](
            {
                type: 'standard__recordPage',
                attributes: {
                    recordId,
                    objectApiName,
                    actionName: 'edit'
                }
            }
        );
    }

    normalizeWidth(value) {
        const scaled = Number(value || 0) * 3;
        return `${Math.max(6, Math.min(100, scaled))}%`;
    }

    normalizeCasePriorityWidth(value, maxCount) {
        const current = Number(value || 0);
        if (!maxCount || maxCount <= 0) {
            return 'width: 0%;';
        }
        const scaled = (current / maxCount) * 100;
        const width = Math.max(0, Math.min(100, Number(scaled.toFixed(2))));
        return `width: ${width}%;`;
    }

    getPriorityBarClass(priority) {
        if (priority === 'Critical') {
            return 'priority-bar priority-critical';
        }
        if (priority === 'High') {
            return 'priority-bar priority-high';
        }
        if (priority === 'Medium') {
            return 'priority-bar priority-medium';
        }
        if (priority === 'Low') {
            return 'priority-bar priority-low';
        }
        return 'priority-bar priority-unspecified';
    }

    notifyError(title, error) {
        const message = error?.body?.message || error?.message || 'Unknown error';
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant: 'error'
            })
        );
    }
}
