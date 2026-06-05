import { LightningElement, api, track, wire } from 'lwc';
import { getFieldValue, getRecord } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import NAME_FIELD from '@salesforce/schema/User.Name';
import AGGRESSIVE_FIELD from '@salesforce/schema/Account.CareOrch_Hyper_Aggressive_Behavior__c';
import MOBILITY_FIELD from '@salesforce/schema/Account.CareOrch_Mobility_Assistance_Required__c';
import getOpenTasksForCurrentCarer from '@salesforce/apex/CareOrchCarerWorkspaceController.getOpenTasksForCurrentCarer';
import completeTask from '@salesforce/apex/CareOrchCarerWorkspaceController.completeTask';
import createNutritionalObservation from '@salesforce/apex/CareOrchResidentClinicalLogger.createNutritionalObservation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const OFFLINE_SYNC_KEY = 'careOrch.pendingTaskCompletions';
const MEAL_OPTIONS = [
    { label: 'Breakfast', value: 'Breakfast' },
    { label: 'Lunch', value: 'Lunch' },
    { label: 'Dinner', value: 'Dinner' },
    { label: 'Snack', value: 'Snack' },
    { label: 'Other', value: 'Other' }
];

const CONSUMPTION_OPTIONS = [
    { label: 'All', value: 'All' },
    { label: 'Most', value: 'Most' },
    { label: 'Half', value: 'Half' },
    { label: 'Little', value: 'Little' },
    { label: 'None', value: 'None' }
];

export default class CareOrchCarerWorkspace extends LightningElement {
    @api recordId;
    userId = USER_ID;
    @track tasks = [];
    @track isNutritionModalOpen = false;
    @track isNutritionSaving = false;
    @track nutritionResidentId = '';
    @track nutritionMealPeriod = 'Other';
    @track nutritionConsumptionLevel = 'Half';
    @track nutritionNotes = '';
    wiredTasksResult;
    pendingSyncTaskIds = new Set();
    performanceStartMs;
    firstPaintLogged = false;
    firstPaintMs;

    connectedCallback() {
        this.performanceStartMs = performance.now();
        this.restorePendingSyncTaskIds();
        window.addEventListener('online', this.handleOnline);
        this.nutritionResidentId = this.recordId || '';
    }

    disconnectedCallback() {
        window.removeEventListener('online', this.handleOnline);
    }

    renderedCallback() {
        if (this.firstPaintLogged) {
            return;
        }

        this.firstPaintLogged = true;
        requestAnimationFrame(() => {
            this.firstPaintMs = Number((performance.now() - this.performanceStartMs).toFixed(2));
            // Prints a mobile layout paint metric for emulation diagnostics.
            // eslint-disable-next-line no-console
            console.info(`[CareOrch] Mobile layout paint: ${this.firstPaintMs}ms`);
        });
    }

    handleOnline = async () => {
        await this.flushPendingCompletions();
    };

    @wire(getRecord, { recordId: '$userId', fields: [NAME_FIELD] }) userRecord;
    @wire(getRecord, { recordId: '$recordId', fields: [AGGRESSIVE_FIELD, MOBILITY_FIELD] }) residentRecord;

    @wire(getOpenTasksForCurrentCarer)
    wiredTasks(result) {
        this.wiredTasksResult = result;
        if (result.data) {
            this.tasks = result.data.map((task) => this.mapTask(task, this.pendingSyncTaskIds.has(task.taskId)));
            if (navigator.onLine) {
                this.flushPendingCompletions();
            }
        } else if (result.error) {
            this.tasks = [];
            this.showToast('Task load failed', 'Unable to load assigned tasks.', 'error');
        }
    }

    get userDisplayName() {
        return getFieldValue(this.userRecord.data, NAME_FIELD) || 'Carer';
    }

    get paintMetricLabel() {
        if (typeof this.firstPaintMs !== 'number') {
            return 'Measuring mobile paint...';
        }
        return `Layout paint ${this.firstPaintMs}ms`;
    }

    get showEmptyState() {
        return this.tasks.length === 0;
    }

    get taskCards() {
        return this.tasks;
    }

    get mealOptions() {
        return MEAL_OPTIONS;
    }

    get consumptionOptions() {
        return CONSUMPTION_OPTIONS;
    }

    get nutritionResidentHelper() {
        return this.recordId ? 'Resident context captured from the current record.' : 'Paste the resident Account Id when working from the app or home page.';
    }

    get nutritionSubmitDisabled() {
        return this.isNutritionSaving || !this.nutritionResidentId || !this.nutritionMealPeriod || !this.nutritionConsumptionLevel;
    }

    get showResidentAlertBanner() {
        return Boolean(this.recordId) && (this.residentHasAggressiveRisk || this.residentHasMobilityRisk);
    }

    get residentHasAggressiveRisk() {
        return Boolean(getFieldValue(this.residentRecord?.data, AGGRESSIVE_FIELD));
    }

    get residentHasMobilityRisk() {
        return Boolean(getFieldValue(this.residentRecord?.data, MOBILITY_FIELD));
    }

    mapTask(task, forcePending = false) {
        const isPending = forcePending || Boolean(task.isCompleting || task.isQueuedForSync);
        const statusLabel = isPending
            ? navigator.onLine
                ? 'Task Completed (syncing...)'
                : 'Task Completed (queued offline)'
            : task.status;

        return {
            ...task,
            whatName: task.whatName || 'Resident task',
            dueLabel: task.activityDate || 'when ready',
            statusLabel,
            actionLabel: isPending ? 'Completed' : 'Complete Task',
            isActionDisabled: isPending,
            cardClass: isPending ? 'task-card task-card_completed' : 'task-card',
            syncHint: isPending
                ? navigator.onLine
                    ? 'Saving to server...'
                    : 'Saved locally. Sync resumes when online.'
                : null
        };
    }

    handleOpenNutritionLogger() {
        this.isNutritionModalOpen = true;
    }

    handleNutritionResidentChange(event) {
        this.nutritionResidentId = event.detail.value;
    }

    handleNutritionMealChange(event) {
        this.nutritionMealPeriod = event.detail.value;
    }

    handleNutritionConsumptionChange(event) {
        this.nutritionConsumptionLevel = event.detail.value;
    }

    handleNutritionNotesChange(event) {
        this.nutritionNotes = event.detail.value;
    }

    closeNutritionModal() {
        this.isNutritionModalOpen = false;
        this.nutritionResidentId = this.recordId || '';
        this.nutritionMealPeriod = 'Other';
        this.nutritionConsumptionLevel = 'Half';
        this.nutritionNotes = '';
    }

    async handleSubmitNutrition() {
        if (this.nutritionSubmitDisabled) {
            return;
        }

        this.isNutritionSaving = true;
        try {
            await createNutritionalObservation({
                residentAccountId: this.nutritionResidentId.trim(),
                mealType: this.nutritionMealPeriod,
                consumptionLevel: this.nutritionConsumptionLevel,
                refusedNotes: this.nutritionNotes.trim()
            });

            this.showToast('Nutritional log saved', 'The entry is now locked for audit consistency.', 'success');
            this.closeNutritionModal();
        } catch (error) {
            this.showToast('Nutritional log failed', this.normalizeError(error), 'error');
        } finally {
            this.isNutritionSaving = false;
        }
    }

    async handleCompleteTask(event) {
        const taskId = event.currentTarget.dataset.taskId;
        if (!taskId) {
            return;
        }

        const priorTasks = [...this.tasks];
        this.pendingSyncTaskIds.add(taskId);
        this.persistPendingSyncTaskIds();
        this.tasks = this.tasks.map((task) =>
            task.taskId === taskId ? this.mapTask({ ...task, isCompleting: true }, true) : task
        );
        this.showToast('Task Completed', 'Saved instantly and syncing in background.', 'success');

        await this.syncCompletedTask(taskId, priorTasks);
    }

    async syncCompletedTask(taskId, priorTasks) {
        try {
            await completeTask({ taskId });
            this.pendingSyncTaskIds.delete(taskId);
            this.persistPendingSyncTaskIds();
            this.tasks = this.tasks.filter((task) => task.taskId !== taskId);
            await refreshApex(this.wiredTasksResult);
        } catch (error) {
            if (this.isOfflineSyncError(error)) {
                this.tasks = this.tasks.map((task) =>
                    task.taskId === taskId ? this.mapTask({ ...task, isQueuedForSync: true }, true) : task
                );
                this.showToast('Offline Queue', 'Task completion queued for sync when connectivity returns.', 'info');
                return;
            }

            this.pendingSyncTaskIds.delete(taskId);
            this.persistPendingSyncTaskIds();
            this.tasks = priorTasks;
            this.showToast('Task completion failed', this.normalizeError(error), 'error');
        }
    }

    async flushPendingCompletions() {
        if (this.pendingSyncTaskIds.size === 0 || !navigator.onLine) {
            return;
        }

        const pendingTaskIds = [...this.pendingSyncTaskIds];
        for (const taskId of pendingTaskIds) {
            const snapshot = [...this.tasks];
            await this.syncCompletedTask(taskId, snapshot);
        }
    }

    restorePendingSyncTaskIds() {
        try {
            const stored = window.localStorage.getItem(OFFLINE_SYNC_KEY);
            if (!stored) {
                return;
            }

            const parsed = JSON.parse(stored);
            if (Array.isArray(parsed)) {
                this.pendingSyncTaskIds = new Set(parsed);
            }
        } catch (error) {
            this.pendingSyncTaskIds = new Set();
        }
    }

    persistPendingSyncTaskIds() {
        window.localStorage.setItem(OFFLINE_SYNC_KEY, JSON.stringify([...this.pendingSyncTaskIds]));
    }

    isOfflineSyncError(error) {
        const message = this.normalizeError(error).toLowerCase();
        return !navigator.onLine || message.includes('network') || message.includes('offline') || message.includes('failed to fetch');
    }

    normalizeError(error) {
        return error?.body?.message || 'An unexpected error occurred.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}