import { LightningElement } from 'lwc';
import getConsoleState from '@salesforce/apex/FieldTripRunController.getConsoleState';
import requestAnalyze from '@salesforce/apex/FieldTripRunController.requestAnalyze';
import requestReports from '@salesforce/apex/FieldTripRunController.requestReports';
import recoverRun from '@salesforce/apex/FieldTripRunController.recoverRun';
import removeRun from '@salesforce/apex/FieldTripRunController.removeRun';

const REPORT_GROUPS = ['ADCB', 'AIBMS', 'Bidvest', 'CMSL', 'EMS', 'FDMS', 'UCBA', 'Unicaja', 'Vert'];
const ACTIVE_STATUSES = new Set(['Requested', 'Processing']);
const REFRESH_INTERVAL_MS = 15000;

export default class FieldTripQuarterlyConsole extends LightningElement {
    state = {
        targetOrg: '',
        activeBatchJobs: 0,
        analyses: [],
        runs: [],
        isSandbox: true,
        canLaunchAnalyze: false,
        canGenerateReports: false,
        canDownloadReports: false,
        canManageRuns: false,
        canRecoverRuns: false
    };
    operation = 'Analyze';
    startDate = '';
    endDateExclusive = '';
    selectedAnalysisIds = [];
    selectedReportGroups = ['FDMS'];
    confirmedProduction = false;
    isLoading = false;
    isSubmitting = false;
    errorMessage;
    successMessage;
    refreshTimer;
    isRecoveryDialogOpen = false;
    selectedRecoveryRun;
    recoveryReason = '';

    operationOptions = [
        { label: 'Analyze', value: 'Analyze' },
        { label: 'Generate reports', value: 'Generate Reports' }
    ];

    connectedCallback() {
        this.setDefaultWindow();
        this.loadState();
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    get isAnalyzeOperation() {
        return this.operation === 'Analyze';
    }

    get analysisOptions() {
        return (this.state.analyses || []).map((analysis) => ({
            label: `${analysis.objectApiName} | ${analysis.name}`,
            value: analysis.id,
            description: analysis.filter || 'No filter'
        }));
    }

    get reportGroupOptions() {
        return REPORT_GROUPS.map((value) => ({ label: value, value }));
    }

    get runs() {
        return (this.state.runs || []).map((run) => ({
            ...run,
            iconName: run.operation === 'Analyze' ? 'standard:metrics' : 'standard:document',
            statusClass: this.statusClass(run.status),
            windowLabel: `${run.startDate} to ${run.endDateExclusive} (exclusive)`,
            hasItems: Boolean(run.items?.length),
            canOpenFolder: Boolean(this.state.canDownloadReports && run.outputFolderUrl),
            canRecover: Boolean(this.state.canRecoverRuns && run.status === 'Processing'),
            canDeleteRun: Boolean(this.state.canManageRuns && run.canDelete),
            items: (run.items || []).map((item) => ({
                ...item,
                iconName: item.itemType === 'Analyze Job' ? 'utility:settings' : 'doctype:excel',
                statusClass: this.statusClass(item.status),
                displayName: item.fileName || `${item.objectApiName || 'Field Trip'} Analyze`,
                detailLabel: this.itemDetail(item),
                canDownload: Boolean(this.state.canDownloadReports && item.downloadUrl),
                downloadLabel: `Download ${item.fileName || 'report'}`
            }))
        }));
    }

    get hasRuns() {
        return this.runs.length > 0;
    }

    get runCount() {
        return this.state.runs?.length || 0;
    }

    get analysisCount() {
        return this.state.analyses?.length || 0;
    }

    get analyzedAnalysisCount() {
        return (this.state.analyses || []).filter((analysis) => {
            return analysis.lastAnalyzedAt && !Number.isNaN(Date.parse(analysis.lastAnalyzedAt));
        }).length;
    }

    get latestAnalyzeLabel() {
        const latestTimestamp = (this.state.analyses || []).reduce((latest, analysis) => {
            const timestamp = Date.parse(analysis.lastAnalyzedAt);
            return Number.isNaN(timestamp) ? latest : Math.max(latest, timestamp);
        }, 0);

        if (!latestTimestamp) {
            return 'No completed analyses';
        }

        const formattedTimestamp = new Intl.DateTimeFormat('en-US', {
            dateStyle: 'medium',
            timeStyle: 'short',
            timeZone: 'UTC'
        }).format(new Date(latestTimestamp));
        return `${formattedTimestamp} UTC`;
    }

    get environmentLabel() {
        if (!this.state.targetOrg) {
            return 'Loading';
        }
        return this.state.isSandbox ? 'Sandbox' : 'Production';
    }

    get environmentClass() {
        return this.state.isSandbox ? 'environment environment_sandbox' : 'environment environment_production';
    }

    get requiresProductionConfirmation() {
        return this.state.targetOrg && !this.state.isSandbox;
    }

    get recoveryDialogTitle() {
        return this.selectedRecoveryRun
            ? `Recover ${this.selectedRecoveryRun.name}`
            : 'Recover Field Trip run';
    }

    get isRecoverySubmitDisabled() {
        return this.isSubmitting || this.recoveryReason.trim().length < 20;
    }

    get submitLabel() {
        return this.isAnalyzeOperation ? 'Launch Analyze jobs' : 'Generate reports';
    }

    get submitIcon() {
        return this.isAnalyzeOperation ? 'utility:play' : 'utility:table';
    }

    get isSubmitDisabled() {
        const lacksPermission = this.isAnalyzeOperation
            ? !this.state.canLaunchAnalyze
            : !this.state.canGenerateReports;
        const lacksSelection = this.isAnalyzeOperation
            ? !this.selectedAnalysisIds.length
            : !this.selectedReportGroups.length;
        return this.isLoading || this.isSubmitting || lacksPermission || lacksSelection
            || !this.startDate || !this.endDateExclusive
            || (this.requiresProductionConfirmation && !this.confirmedProduction);
    }

    async loadState() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            this.state = await getConsoleState();
            this.configurePolling();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
            this.stopPolling();
        } finally {
            this.isLoading = false;
        }
    }

    async handleRefresh() {
        await this.loadState();
    }

    handleOperationChange(event) {
        this.operation = event.detail.value;
        this.successMessage = undefined;
        this.errorMessage = undefined;
    }

    handleStartDateChange(event) {
        this.startDate = event.target.value;
    }

    handleEndDateChange(event) {
        this.endDateExclusive = event.target.value;
    }

    handleAnalysisSelection(event) {
        this.selectedAnalysisIds = event.detail.value;
    }

    handleReportGroupSelection(event) {
        this.selectedReportGroups = event.detail.value;
    }

    handleProductionConfirmation(event) {
        this.confirmedProduction = event.target.checked;
    }

    async handleSubmit() {
        if (!this.reportValidity()) {
            return;
        }
        this.isSubmitting = true;
        this.errorMessage = undefined;
        this.successMessage = undefined;
        try {
            const parameters = {
                startDate: this.startDate,
                endDateExclusive: this.endDateExclusive,
                confirmedProduction: this.confirmedProduction
            };
            const runId = this.isAnalyzeOperation
                ? await requestAnalyze({ ...parameters, selectedAnalysisIds: this.selectedAnalysisIds })
                : await requestReports({ ...parameters, selectedReportGroups: this.selectedReportGroups });
            this.successMessage = this.isAnalyzeOperation
                ? `Analyze request ${runId} was accepted by Salesforce. Processing continues if you close the browser or turn off the Windows worker.`
                : `Report request ${runId} is queued for the Windows report worker.`;
            await this.loadState();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSubmitting = false;
        }
    }

    handleDownload(event) {
        const url = event.currentTarget.dataset.url;
        if (!url) {
            return;
        }
        try {
            const downloadUrl = new URL(url);
            if (downloadUrl.protocol !== 'https:') {
                throw new Error('Unsupported download protocol.');
            }
            window.open(downloadUrl.href, '_blank', 'noopener');
        } catch {
            this.errorMessage = 'The report link is invalid. Refresh the console or contact an administrator.';
        }
    }

    handleOpenRecoveryDialog(event) {
        this.selectedRecoveryRun = this.runs.find(
            (run) => run.id === event.currentTarget.dataset.id
        );
        this.recoveryReason = '';
        this.isRecoveryDialogOpen = Boolean(this.selectedRecoveryRun);
    }

    handleCloseRecoveryDialog() {
        this.isRecoveryDialogOpen = false;
        this.selectedRecoveryRun = undefined;
        this.recoveryReason = '';
    }

    handleRecoveryReasonChange(event) {
        this.recoveryReason = event.target.value;
    }

    async handleRecoverRun() {
        if (this.isRecoverySubmitDisabled || !this.selectedRecoveryRun) {
            return;
        }
        this.isSubmitting = true;
        this.errorMessage = undefined;
        try {
            await recoverRun({
                runId: this.selectedRecoveryRun.id,
                reason: this.recoveryReason
            });
            this.successMessage = `${this.selectedRecoveryRun.name} was marked Failed and released for a replacement request.`;
            this.handleCloseRecoveryDialog();
            await this.loadState();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSubmitting = false;
        }
    }

    async handleRemoveRun(event) {
        const selectedRun = this.runs.find((run) => run.id === event.currentTarget.dataset.id);
        if (!selectedRun || !window.confirm(`Remove ${selectedRun.name} from run history?`)) {
            return;
        }
        this.isSubmitting = true;
        this.errorMessage = undefined;
        this.successMessage = undefined;
        try {
            await removeRun({ runId: selectedRun.id });
            this.successMessage = `${selectedRun.name} was removed from run history.`;
            await this.loadState();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSubmitting = false;
        }
    }

    reportValidity() {
        return [...this.template.querySelectorAll('lightning-input, lightning-dual-listbox')]
            .reduce((isValid, control) => control.reportValidity() && isValid, true);
    }

    configurePolling() {
        const hasActiveRuns = (this.state.runs || []).some((run) => ACTIVE_STATUSES.has(run.status));
        if (hasActiveRuns && !this.refreshTimer) {
            this.refreshTimer = window.setInterval(() => this.loadState(), REFRESH_INTERVAL_MS);
        } else if (!hasActiveRuns) {
            this.stopPolling();
        }
    }

    stopPolling() {
        if (this.refreshTimer) {
            window.clearInterval(this.refreshTimer);
            this.refreshTimer = undefined;
        }
    }

    setDefaultWindow() {
        const now = new Date();
        const quarterStartMonth = Math.floor(now.getMonth() / 3) * 3;
        const start = new Date(Date.UTC(now.getFullYear(), quarterStartMonth, 1));
        const end = new Date(Date.UTC(now.getFullYear(), quarterStartMonth + 3, 1));
        this.startDate = start.toISOString().slice(0, 10);
        this.endDateExclusive = end.toISOString().slice(0, 10);
    }

    statusClass(status) {
        const normalized = (status || '').toLowerCase().replaceAll(' ', '-');
        return `status status_${normalized}`;
    }

    itemDetail(item) {
        if (item.itemType === 'Analyze Job') {
            return item.apexJobId ? `Apex job ${item.apexJobId}` : 'Awaiting worker submission';
        }
        if (item.reportGroup && item.objectApiName) {
            return `${item.reportGroup} | ${item.objectApiName}`;
        }
        return item.itemType;
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'The Field Trip operation could not be completed.';
    }
}