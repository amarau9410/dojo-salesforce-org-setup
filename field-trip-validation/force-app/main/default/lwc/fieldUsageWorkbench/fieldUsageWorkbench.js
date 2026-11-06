import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getFilterOptions from '@salesforce/apex/FieldUsageController.getFilterOptions';
import getUsage from '@salesforce/apex/FieldUsageController.getUsage';
import getAllianceReportState from '@salesforce/apex/FieldTripRunController.getAllianceReportState';
import submitReportForApproval from '@salesforce/apex/FieldTripRunController.submitReportForApproval';

const NON_STANDARD_OBJECT_SUFFIXES = ['__c', '__mdt', '__x', '__b'];

const WORKBOOK_BASE_COLUMNS = [
    { label: 'Object', fieldName: 'objectApiName', type: 'text', initialWidth: 150 },
    { label: 'Field API name', fieldName: 'fieldApiName', type: 'text', initialWidth: 230 },
    { label: 'Field label', fieldName: 'fieldLabel', type: 'text', initialWidth: 210 }
];

const WORKBOOK_TOTAL_COLUMNS = [
    { label: 'Total population', fieldName: 'totalPopulationLabel', type: 'text', initialWidth: 135 },
    { label: 'Field usage', fieldName: 'usageStatus', type: 'text', initialWidth: 125 },
    { label: 'Populated records', fieldName: 'populatedCount', type: 'number', initialWidth: 145 },
    { label: 'Records analyzed', fieldName: 'recordsAnalyzed', type: 'number', initialWidth: 140 }
];

const SEGMENT_COLUMNS = [
    { label: 'Reporting segment', fieldName: 'reportingGroup', type: 'text', initialWidth: 190 },
    { label: 'Current used', fieldName: 'usedCount', type: 'number', initialWidth: 120 },
    { label: 'Previous used', fieldName: 'previousUsedLabel', type: 'text', initialWidth: 125 },
    { label: 'Current unused', fieldName: 'unusedCount', type: 'number', initialWidth: 130 },
    { label: 'Previous unused', fieldName: 'previousUnusedLabel', type: 'text', initialWidth: 135 },
    { label: 'Current population', fieldName: 'averagePopulationLabel', type: 'text', initialWidth: 155 },
    { label: 'Previous population', fieldName: 'previousAveragePopulationLabel', type: 'text', initialWidth: 165 },
    { label: 'Current records', fieldName: 'recordsAnalyzed', type: 'number', initialWidth: 135 },
    { label: 'Previous records', fieldName: 'previousRecordsLabel', type: 'text', initialWidth: 140 },
    { label: 'Current analysis', fieldName: 'latestAnalyzedAt', type: 'date', initialWidth: 180,
        typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' } },
    { label: 'Previous analysis', fieldName: 'previousAnalyzedAtLabel', type: 'text', initialWidth: 180 },
    { type: 'button', initialWidth: 125, typeAttributes: {
        label: 'View fields', name: 'view', iconName: 'utility:table', variant: 'base'
    } }
];

const EMPTY_SUMMARY = {
    evidenceCount: 0,
    usedCount: 0,
    unusedCount: 0,
    noRecordsCount: 0,
    latestAnalyzedAt: null
};

export default class FieldUsageWorkbench extends NavigationMixin(LightningElement) {
    usageColumns = SEGMENT_COLUMNS;
    summary = EMPTY_SUMMARY;
    usageRows = [];
    segmentRows = [];
    displayRows = [];
    allianceSummaryRows = [];
    alliance = '';
    objectApiName = '';
    usageStatus = '';
    searchTerm = '';
    canViewAllAlliances = false;
    allianceOptions = [{ label: 'My reporting segments', value: '' }];
    objectOptions = [{ label: 'All objects', value: '' }];
    selectedRow;
    filterError;
    usageError;
    usageWarning;
    isLoading = true;
    wiredOptionsResult;
    wiredUsageResult;
    reportState = {
        approvers: [],
        artifacts: [],
        canDownloadReports: false,
        canSubmitForApproval: false
    };
    reportError;
    isReportLoading = false;
    isApprovalDialogOpen = false;
    selectedArtifact;
    selectedApproverId = '';
    approvalComments = '';

    statusOptions = [
        { label: 'All usage states', value: '' },
        { label: 'Used', value: 'Used' },
        { label: 'Unused', value: 'Unused' },
        { label: 'No Records', value: 'No Records' }
    ];

    @wire(getFilterOptions)
    wiredOptions(result) {
        this.wiredOptionsResult = result;
        if (result.data) {
            this.filterError = undefined;
            this.canViewAllAlliances = Boolean(result.data.canViewAllAlliances);
            this.allianceOptions = [
                { label: this.allSegmentsLabel, value: '' },
                ...(result.data.alliances || []).map((value) => ({ label: value, value }))
            ];
            this.objectOptions = [
                { label: 'All objects', value: '' },
                ...(result.data.objectApiNames || []).map((value) => ({ label: value, value }))
            ];
            if (!this.canViewAllAlliances
                && !this.alliance
                && result.data.alliances?.length === 1) {
                this.alliance = result.data.alliances[0];
                this.loadReportState();
            }
        } else if (result.error) {
            this.isLoading = false;
            this.filterError = this.reduceError(result.error);
        }
    }

    @wire(getUsage, {
        alliance: '$alliance',
        objectApiName: '$objectApiName',
        usageStatus: '$usageStatus',
        searchTerm: '$searchTerm'
    })
    wiredUsage(result) {
        this.wiredUsageResult = result;
        this.isLoading = false;
        if (result.data) {
            this.usageError = undefined;
            this.usageWarning = result.data.isTruncated
                ? `More than ${result.data.rowLimit} rows match. Narrow the object, status, or search filters to review the complete result.`
                : undefined;
            this.summary = result.data.summary || EMPTY_SUMMARY;
            this.usageRows = result.data.rows || [];
            this.segmentRows = result.data.segments || [];
            this.allianceSummaryRows = this.buildAllianceSummaryRows();
            this.buildDataset();
            this.reconcileSelection();
        } else if (result.error) {
            this.summary = EMPTY_SUMMARY;
            this.usageRows = [];
            this.segmentRows = [];
            this.displayRows = [];
            this.selectedRow = undefined;
            this.usageWarning = undefined;
            this.allianceSummaryRows = [];
            this.usageError = this.reduceError(result.error);
        }
    }

    get hasRows() {
        return this.displayRows.length > 0;
    }

    get selectedRowId() {
        return this.selectedRow ? [this.selectedRow.datasetId] : [];
    }

    get isSegmentSelected() {
        return Boolean(this.alliance);
    }

    get dashboardScope() {
        const segment = this.alliance || this.allSegmentsLabel;
        const objectName = this.objectApiName || 'All objects';
        const status = this.usageStatus || 'All usage states';
        return `${segment} | ${objectName} | ${status}`;
    }

    get allSegmentsLabel() {
        return this.canViewAllAlliances
            ? 'All reporting segments'
            : 'My reporting segments';
    }

    get datasetHeading() {
        return this.isSegmentSelected
            ? `${this.alliance} field usage workbook`
            : 'Reporting segment overview';
    }

    get showAllianceSummary() {
        return !this.isSegmentSelected && this.allianceSummaryRows.length > 0;
    }

        buildAllianceSummaryRows() {
            const fieldAlliances = new Map();
            this.usageRows.forEach((row) => {
                if (!row || row.usageStatus !== 'Used' || !this.isStandardObject(row.objectApiName)) {
                    return;
                }
                const fieldKey = `${row.objectApiName}.${row.fieldApiName}`;
                if (!fieldAlliances.has(fieldKey)) {
                    fieldAlliances.set(fieldKey, new Set());
                }
                fieldAlliances.get(fieldKey).add(row.alliance || row.reportingGroup || 'Unknown');
            });

            const rowsByAlliancePeriod = new Map();
            this.usageRows.forEach((row) => {
                if (!row || row.usageStatus !== 'Used' || !this.isStandardObject(row.objectApiName)) {
                    return;
                }
                const fieldKey = `${row.objectApiName}.${row.fieldApiName}`;
                const alliances = fieldAlliances.get(fieldKey);
                if (!alliances || alliances.size !== 1) {
                    return;
                }

                const alliance = [...alliances][0];
                const periodLabel = this.formatQuarterLabel(row.lastAnalyzedAt);
                const rowKey = `${alliance}::${periodLabel}`;
                if (!rowsByAlliancePeriod.has(rowKey)) {
                    rowsByAlliancePeriod.set(rowKey, {
                        key: rowKey,
                        alliance,
                        periodLabel,
                        fields: new Set()
                    });
                }
                rowsByAlliancePeriod.get(rowKey).fields.add(fieldKey);
            });

            return [...rowsByAlliancePeriod.values()]
                .map((row) => ({
                    key: row.key,
                    alliance: row.alliance,
                    periodLabel: row.periodLabel,
                    fields: [...row.fields].sort((left, right) => left.localeCompare(right)),
                    fieldsLabel: [...row.fields].sort((left, right) => left.localeCompare(right)).join(', '),
                    fieldCountLabel: this.formatFieldCount(row.fields.size)
                }))
                .sort((left, right) => {
                    const allianceCompare = left.alliance.localeCompare(right.alliance);
                    if (allianceCompare !== 0) {
                        return allianceCompare;
                    }
                    return this.quarterSortValue(left.periodLabel) - this.quarterSortValue(right.periodLabel);
                });
        }

        isStandardObject(objectApiName) {
            if (!objectApiName) {
                return false;
            }
            return !NON_STANDARD_OBJECT_SUFFIXES.some((suffix) => objectApiName.endsWith(suffix));
        }

        formatQuarterLabel(value) {
            if (!value) {
                return 'Unknown period';
            }
            const dateValue = new Date(value);
            if (Number.isNaN(dateValue.getTime())) {
                return 'Unknown period';
            }
            const quarter = Math.floor(dateValue.getUTCMonth() / 3) + 1;
            return `${this.ordinalQuarter(quarter)} Quarter`;
        }

        formatFieldCount(count) {
            return count === 1 ? '1 field' : `${count} fields`;
        }

        ordinalQuarter(quarter) {
            if (quarter === 1) {
                return '1st';
            }
            if (quarter === 2) {
                return '2nd';
            }
            if (quarter === 3) {
                return '3rd';
            }
            return '4th';
        }

        quarterSortValue(periodLabel) {
            const match = periodLabel?.match(/^(\d)(?:st|nd|rd|th) Quarter$/);
            return match ? Number(match[1]) : 99;
        }

    get datasetDescription() {
        return this.isSegmentSelected
            ? 'Population by field and record type. Each cell states whether the field is used.'
            : 'Current and previous values include only your assigned reporting segments. Select View fields to inspect one segment.';
    }

    get evidenceLabel() {
        return `${this.summary.evidenceCount} matching`;
    }

    get usedFilterLabel() {
        return `Used (${this.summary.usedCount})`;
    }

    get unusedFilterLabel() {
        return `Unused (${this.summary.unusedCount})`;
    }

    get noRecordsFilterLabel() {
        return `No records (${this.summary.noRecordsCount})`;
    }

    get allStatusVariant() {
        return this.usageStatus ? 'neutral' : 'brand';
    }

    get usedStatusVariant() {
        return this.usageStatus === 'Used' ? 'brand' : 'neutral';
    }

    get unusedStatusVariant() {
        return this.usageStatus === 'Unused' ? 'brand' : 'neutral';
    }

    get noRecordsStatusVariant() {
        return this.usageStatus === 'No Records' ? 'brand' : 'neutral';
    }

    get reportArtifacts() {
        return (this.reportState.artifacts || []).map((artifact) => ({
            ...artifact,
            isDownloadDisabled: !(this.reportState.canDownloadReports && artifact.downloadUrl),
            isSubmitDisabled: !(artifact.canSubmit
                && this.reportState.canSubmitForApproval
                && this.approverOptions.length),
            approvalClass: `c-approval-status c-approval-status_${(artifact.approvalStatus || '')
                .toLowerCase().replaceAll(' ', '-')}`,
            windowLabel: `${artifact.startDate} to ${artifact.endDateExclusive} (exclusive)`,
            sizeLabel: this.formatFileSize(artifact.fileSize)
        }));
    }

    get approverOptions() {
        return (this.reportState.approvers || []).map((approver) => ({
            label: approver.label,
            value: approver.id
        }));
    }

    get hasReportArtifacts() {
        return this.reportArtifacts.length > 0;
    }

    get approvalDialogTitle() {
        return this.selectedArtifact
            ? `Submit ${this.selectedArtifact.fileName} for approval`
            : 'Submit report for approval';
    }

    get isApprovalSubmitDisabled() {
        return !this.selectedArtifact || !this.selectedApproverId || this.isReportLoading;
    }

    handleAllianceChange(event) {
        this.startLoading();
        this.alliance = event.detail.value;
        this.loadReportState();
    }

    handleObjectChange(event) {
        this.startLoading();
        this.objectApiName = event.detail.value;
    }

    handleStatusChange(event) {
        this.startLoading();
        this.usageStatus = event.detail.value;
    }

    handleStatusQuickFilter(event) {
        this.startLoading();
        this.usageStatus = event.currentTarget.dataset.status || '';
    }

    handleSearch(event) {
        this.startLoading();
        this.searchTerm = event.target.value;
    }

    handleRowSelection(event) {
        const datasetRow = event.detail.selectedRows[0];
        this.selectedRow = this.usageRows.find((row) => row.id === datasetRow?.sourceId);
        if (this.selectedRow) {
            this.selectedRow = { ...this.selectedRow, datasetId: datasetRow.datasetId };
        }
    }

    handleSegmentAction(event) {
        if (event.detail.action.name !== 'view') {
            return;
        }
        this.startLoading();
        this.alliance = event.detail.row.reportingGroup;
        this.loadReportState();
    }

    async handleRefresh() {
        this.startLoading();
        await Promise.all([
            refreshApex(this.wiredOptionsResult),
            refreshApex(this.wiredUsageResult),
            this.loadReportState()
        ]);
    }

    async loadReportState() {
        if (!this.alliance) {
            this.reportState = { approvers: [], artifacts: [] };
            return;
        }
        this.isReportLoading = true;
        this.reportError = undefined;
        try {
            this.reportState = await getAllianceReportState({ alliance: this.alliance });
        } catch (error) {
            this.reportState = { approvers: [], artifacts: [] };
            this.reportError = this.reduceError(error);
        } finally {
            this.isReportLoading = false;
        }
    }

    handleDownloadReport(event) {
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
            this.reportError = 'The report link is invalid. Refresh the workbench or contact an administrator.';
        }
    }

    handleOpenApprovalDialog(event) {
        this.selectedArtifact = this.reportArtifacts.find(
            (artifact) => artifact.id === event.currentTarget.dataset.id
        );
        this.selectedApproverId = '';
        this.approvalComments = '';
        this.isApprovalDialogOpen = Boolean(this.selectedArtifact);
    }

    handleCloseApprovalDialog() {
        this.isApprovalDialogOpen = false;
        this.selectedArtifact = undefined;
        this.selectedApproverId = '';
        this.approvalComments = '';
    }

    handleApproverChange(event) {
        this.selectedApproverId = event.detail.value;
    }

    handleApprovalCommentsChange(event) {
        this.approvalComments = event.target.value;
    }

    async handleSubmitForApproval() {
        if (this.isApprovalSubmitDisabled) {
            return;
        }
        this.isReportLoading = true;
        this.reportError = undefined;
        try {
            await submitReportForApproval({
                reportItemId: this.selectedArtifact.id,
                approverId: this.selectedApproverId,
                comments: this.approvalComments
            });
            this.handleCloseApprovalDialog();
            await this.loadReportState();
        } catch (error) {
            this.reportError = this.reduceError(error);
            this.isReportLoading = false;
        }
    }

    handleOpenFieldRecord() {
        if (!this.selectedRow?.dictionaryFieldId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.selectedRow.dictionaryFieldId,
                actionName: 'view'
            }
        });
    }

    startLoading() {
        this.isLoading = true;
        this.selectedRow = undefined;
    }

    buildDataset() {
        if (!this.isSegmentSelected) {
            this.usageColumns = SEGMENT_COLUMNS;
            this.displayRows = this.buildSegmentRows();
            return;
        }

        const recordTypes = [...new Set(this.usageRows.map((row) => row.recordTypeName || 'All records'))]
            .sort((left, right) => left.localeCompare(right));
        this.usageColumns = [
            ...WORKBOOK_BASE_COLUMNS,
            ...recordTypes.map((recordTypeName, index) => ({
                label: recordTypeName,
                fieldName: `recordType${index}`,
                type: 'text',
                initialWidth: 165
            })),
            ...WORKBOOK_TOTAL_COLUMNS
        ];

        const recordTypeIndex = new Map(recordTypes.map((name, index) => [name, index]));
        const fieldsByKey = new Map();
        this.usageRows.forEach((row) => {
            const fieldKey = `${row.objectApiName}.${row.fieldApiName}`;
            let field = fieldsByKey.get(fieldKey);
            if (!field) {
                field = {
                    datasetId: fieldKey,
                    sourceId: row.id,
                    objectApiName: row.objectApiName,
                    fieldApiName: row.fieldApiName,
                    fieldLabel: row.fieldLabel,
                    populatedCount: 0,
                    recordsAnalyzed: 0,
                    totalPopulation: 0,
                    statuses: []
                };
                fieldsByKey.set(fieldKey, field);
            }
            const recordTypeName = row.recordTypeName || 'All records';
            field[`recordType${recordTypeIndex.get(recordTypeName)}`] = this.formatUsageCell(row);
            field.populatedCount += Number(row.populatedCount || 0);
            field.recordsAnalyzed += Number(row.recordsAnalyzed || 0);
            field.totalPopulation += Number(row.populationPercent || 0);
            field.statuses.push(row.usageStatus);
            if (row.usageStatus === 'Used') {
                field.sourceId = row.id;
            }
        });

        this.displayRows = [...fieldsByKey.values()].map((field) => ({
            ...field,
            totalPopulationLabel: `${field.totalPopulation.toFixed(1)}%`,
            usageStatus: this.rollupUsageStatus(field.statuses)
        })).sort((left, right) => left.fieldLabel.localeCompare(right.fieldLabel));
    }

    buildSegmentRows() {
        return this.segmentRows.map((segment) => ({
            ...segment,
            datasetId: segment.reportingGroup,
            averagePopulationLabel: this.formatPercentage(segment.averagePopulationPercent),
            previousUsedLabel: segment.previousAnalyzedAt
                ? String(segment.previousUsedCount)
                : 'Not available',
            previousUnusedLabel: segment.previousAnalyzedAt
                ? String(segment.previousUnusedCount)
                : 'Not available',
            previousAveragePopulationLabel: this.formatPercentage(
                segment.previousAveragePopulationPercent
            ),
            previousRecordsLabel: segment.previousAnalyzedAt
                ? String(segment.previousRecordsAnalyzed)
                : 'Not available',
            previousAnalyzedAtLabel: this.formatDate(segment.previousAnalyzedAt)
        }))
            .sort((left, right) => left.reportingGroup.localeCompare(right.reportingGroup));
    }

    formatUsageCell(row) {
        if (row.usageStatus === 'No Records') {
            return 'No records';
        }
        return `${Number(row.populationPercent || 0).toFixed(1)}% | ${row.usageStatus}`;
    }

    formatPercentage(value) {
        return value === null || value === undefined
            ? 'Not available'
            : `${Number(value).toFixed(1)}%`;
    }

    formatDate(value) {
        return value
            ? new Intl.DateTimeFormat('en-GB', {
                day: '2-digit',
                month: 'short',
                year: 'numeric'
            }).format(new Date(value))
            : 'Not available';
    }

    rollupUsageStatus(statuses) {
        if (statuses.includes('Used')) {
            return 'Used';
        }
        if (statuses.includes('Unused')) {
            return 'Unused';
        }
        return 'No Records';
    }

    reconcileSelection() {
        if (!this.isSegmentSelected || !this.displayRows.length) {
            this.selectedRow = undefined;
            return;
        }
        const selectedDataset = this.displayRows.find(
            (row) => row.datasetId === this.selectedRow?.datasetId
        ) || this.displayRows[0];
        const sourceRow = this.usageRows.find((row) => row.id === selectedDataset.sourceId);
        this.selectedRow = sourceRow
            ? { ...sourceRow, datasetId: selectedDataset.datasetId }
            : undefined;
    }

    formatFileSize(bytes) {
        if (!bytes) {
            return 'Size unavailable';
        }
        const megabytes = Number(bytes) / (1024 * 1024);
        return megabytes >= 1
            ? `${megabytes.toFixed(1)} MB`
            : `${Math.ceil(Number(bytes) / 1024)} KB`;
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }
}