import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getCatalog from '@salesforce/apex/DataDictionaryController.getCatalog';
import getFields from '@salesforce/apex/DataDictionaryController.getFields';
import getChangeInventory from '@salesforce/apex/DataDictionaryController.getChangeInventory';
import getDuplicateCandidates from '@salesforce/apex/DataDictionaryController.getDuplicateCandidates';

const FIELD_COLUMNS = [
    { label: 'Field', fieldName: 'label', type: 'text', initialWidth: 220 },
    { label: 'API name', fieldName: 'apiName', type: 'text', initialWidth: 240 },
    { label: 'Type', fieldName: 'dataType', type: 'text', initialWidth: 140 },
    { label: 'Status', fieldName: 'documentationStatus', type: 'text', initialWidth: 130 },
    { label: 'Sensitivity', fieldName: 'sensitivity', type: 'text', initialWidth: 120 },
    { label: 'References', fieldName: 'dependencyCount', type: 'number', initialWidth: 100 }
];

const CHANGE_COLUMNS = [
    { label: 'Detected', fieldName: 'detectedAt', type: 'date', initialWidth: 170 },
    { label: 'Change', fieldName: 'changeType', type: 'text', initialWidth: 120 },
    { label: 'Metadata', fieldName: 'metadataLabel', type: 'text', initialWidth: 200 },
    { label: 'Qualified API name', fieldName: 'qualifiedApiName', type: 'text', initialWidth: 260 },
    { label: 'Entity', fieldName: 'entityType', type: 'text', initialWidth: 100 },
    { label: 'Review', fieldName: 'reviewStatus', type: 'text', initialWidth: 140 }
];

const DUPLICATE_COLUMNS = [
    { label: 'Object', fieldName: 'objectApiName', type: 'text', initialWidth: 180 },
    { label: 'Field A', fieldName: 'fieldAApiName', type: 'text', initialWidth: 220 },
    { label: 'Field B', fieldName: 'fieldBApiName', type: 'text', initialWidth: 220 },
    { label: 'Type', fieldName: 'dataType', type: 'text', initialWidth: 120 },
    { label: 'Confidence %', fieldName: 'confidence', type: 'number', typeAttributes: { maximumFractionDigits: 2 }, initialWidth: 120 },
    { label: 'Review', fieldName: 'reviewStatus', type: 'text', initialWidth: 160 }
];

const EMPTY_SUMMARY = {
    objectCount: 0,
    approvedObjectCount: 0,
    fieldCount: 0,
    documentedFieldCount: 0,
    sensitiveFieldCount: 0,
    dependencyCount: 0,
    documentationCoverage: 0,
    lastScannedAt: null
};

const EMPTY_CHANGE_SUMMARY = {
    addedCount: 0, changedCount: 0, removedCount: 0, reactivatedCount: 0,
    pendingReviewCount: 0, latestScanStatus: '', notificationStatus: '', latestScanAt: null
};

const EMPTY_DUPLICATE_SUMMARY = {
    candidateCount: 0, newCount: 0, confirmedCount: 0, plannedCount: 0,
    averageConfidence: 0, lastEvaluatedAt: null
};

export default class DataDictionaryWorkbench extends NavigationMixin(LightningElement) {
    fieldColumns = FIELD_COLUMNS;
    changeColumns = CHANGE_COLUMNS;
    duplicateColumns = DUPLICATE_COLUMNS;
    summary = EMPTY_SUMMARY;
    changeSummary = EMPTY_CHANGE_SUMMARY;
    duplicateSummary = EMPTY_DUPLICATE_SUMMARY;
    objectRows = [];
    fieldRows = [];
    selectedObject;
    selectedField;
    searchTerm = '';
    documentationStatus = '';
    sensitivity = '';
    objectCategory = '';
    catalogError;
    fieldError;
    isCatalogLoading = true;
    isFieldLoading = false;
    wiredCatalogResult;
    activeView = 'catalog';
    changeRows = [];
    duplicateRows = [];
    selectedChange;
    selectedDuplicate;
    changeSearchTerm = '';
    changeType = '';
    changeReviewStatus = '';
    duplicateSearchTerm = '';
    duplicateReviewStatus = '';
    minimumConfidence = 80;
    governanceError;
    isGovernanceLoading = false;
    fieldRequestSequence = 0;
    governanceRequestSequence = 0;

    documentationOptions = [
        { label: 'All documentation states', value: '' },
        { label: 'Undocumented', value: 'Undocumented' },
        { label: 'Suggested', value: 'Suggested' },
        { label: 'Reviewed', value: 'Reviewed' },
        { label: 'Approved', value: 'Approved' }
    ];

    sensitivityOptions = [
        { label: 'All sensitivity levels', value: '' },
        { label: 'Unclassified', value: 'Unclassified' },
        { label: 'Public', value: 'Public' },
        { label: 'Internal', value: 'Internal' },
        { label: 'Confidential', value: 'Confidential' },
        { label: 'Restricted', value: 'Restricted' }
    ];

    categoryOptions = [
        { label: 'All object categories', value: '' },
        { label: 'Standard', value: 'Standard' },
        { label: 'Custom', value: 'Custom' },
        { label: 'Custom Metadata', value: 'Custom Metadata' },
        { label: 'Platform Event', value: 'Platform Event' },
        { label: 'Big Object', value: 'Big Object' },
        { label: 'External Object', value: 'External Object' }
    ];

    changeTypeOptions = [
        { label: 'All change types', value: '' }, { label: 'Added', value: 'Added' },
        { label: 'Changed', value: 'Changed' }, { label: 'Removed', value: 'Removed' },
        { label: 'Reactivated', value: 'Reactivated' }
    ];

    changeReviewOptions = [
        { label: 'All review states', value: '' }, { label: 'New', value: 'New' },
        { label: 'Under Review', value: 'Under Review' }, { label: 'Acknowledged', value: 'Acknowledged' },
        { label: 'Action Required', value: 'Action Required' }, { label: 'Resolved', value: 'Resolved' }
    ];

    duplicateReviewOptions = [
        { label: 'All review states', value: '' }, { label: 'New', value: 'New' },
        { label: 'Under Review', value: 'Under Review' },
        { label: 'Confirmed Duplicate', value: 'Confirmed Duplicate' },
        { label: 'Not a Duplicate', value: 'Not a Duplicate' },
        { label: 'Consolidation Planned', value: 'Consolidation Planned' },
        { label: 'Resolved', value: 'Resolved' }
    ];

    @wire(getCatalog, {
        searchTerm: '$searchTerm',
        documentationStatus: '$documentationStatus',
        sensitivity: '$sensitivity',
        objectCategory: '$objectCategory'
    })
    wiredCatalog(result) {
        this.wiredCatalogResult = result;
        this.isCatalogLoading = false;
        if (result.data) {
            this.catalogError = undefined;
            this.summary = result.data.summary || EMPTY_SUMMARY;
            this.objectRows = this.decorateObjectRows(result.data.objects || []);
            this.reconcileSelection();
        } else if (result.error) {
            this.summary = EMPTY_SUMMARY;
            this.objectRows = [];
            this.catalogError = this.reduceError(result.error);
        }
    }

    get hasObjects() {
        return this.objectRows.length > 0;
    }

    get hasFields() {
        return this.fieldRows.length > 0;
    }

    get isCatalogView() { return this.activeView === 'catalog'; }
    get isChangesView() { return this.activeView === 'changes'; }
    get isDuplicatesView() { return this.activeView === 'duplicates'; }
    get hasChanges() { return this.changeRows.length > 0; }
    get hasDuplicates() { return this.duplicateRows.length > 0; }
    get showObjectEmptyState() { return !this.isCatalogLoading && !this.hasObjects; }
    get showFieldEmptyState() { return !this.isFieldLoading && !this.hasFields; }
    get showChangeEmptyState() { return !this.isGovernanceLoading && !this.hasChanges; }
    get showDuplicateEmptyState() { return !this.isGovernanceLoading && !this.hasDuplicates; }
    get catalogButtonVariant() { return this.isCatalogView ? 'brand' : 'neutral'; }
    get changesButtonVariant() { return this.isChangesView ? 'brand' : 'neutral'; }
    get duplicatesButtonVariant() { return this.isDuplicatesView ? 'brand' : 'neutral'; }
    get hasFormula() { return Boolean(this.selectedField?.formula); }
    get hasPicklistValues() { return Boolean(this.selectedField?.picklistValues); }
    get hasFlsSummary() { return Boolean(this.selectedField?.flsSummary); }
    get hasDependencies() { return Boolean(this.selectedField?.dependencies); }
    get selectedChangeId() { return this.selectedChange ? [this.selectedChange.id] : []; }
    get selectedDuplicateId() { return this.selectedDuplicate ? [this.selectedDuplicate.id] : []; }

    get selectedFieldId() {
        return this.selectedField ? [this.selectedField.id] : [];
    }

    get objectCountLabel() {
        return `${this.objectRows.length} shown`;
    }

    get coverageValue() {
        return this.summary.documentationCoverage || 0;
    }

    handleSearch(event) {
        this.isCatalogLoading = true;
        this.searchTerm = event.target.value;
    }

    handleDocumentationFilter(event) {
        this.isCatalogLoading = true;
        this.documentationStatus = event.detail.value;
    }

    handleSensitivityFilter(event) {
        this.isCatalogLoading = true;
        this.sensitivity = event.detail.value;
    }

    handleCategoryFilter(event) {
        this.isCatalogLoading = true;
        this.objectCategory = event.detail.value;
    }

    handleObjectSelection(event) {
        const selectedId = event.currentTarget.dataset.id;
        this.selectedObject = this.objectRows.find((catalogObject) => catalogObject.id === selectedId);
        this.objectRows = this.decorateObjectRows(this.objectRows);
        this.loadFields();
    }

    handleFieldSelection(event) {
        const selectedRows = event.detail.selectedRows;
        this.selectedField = selectedRows.length ? selectedRows[0] : undefined;
    }

    async handleRefresh() {
        if (this.isCatalogView) {
            this.isCatalogLoading = true;
            await refreshApex(this.wiredCatalogResult);
            if (this.selectedObject) await this.loadFields();
        } else if (this.isChangesView) {
            await this.loadChanges();
        } else {
            await this.loadDuplicates();
        }
    }

    handleViewChange(event) {
        this.activeView = event.currentTarget.dataset.view;
        this.governanceError = undefined;
        if (this.isChangesView) this.loadChanges();
        if (this.isDuplicatesView) this.loadDuplicates();
    }

    handleChangeSearch(event) { this.changeSearchTerm = event.target.value; this.loadChanges(); }
    handleChangeType(event) { this.changeType = event.detail.value; this.loadChanges(); }
    handleChangeReview(event) { this.changeReviewStatus = event.detail.value; this.loadChanges(); }
    handleDuplicateSearch(event) { this.duplicateSearchTerm = event.target.value; this.loadDuplicates(); }
    handleDuplicateReview(event) { this.duplicateReviewStatus = event.detail.value; this.loadDuplicates(); }
    handleConfidence(event) { this.minimumConfidence = event.target.value; this.loadDuplicates(); }
    handleChangeSelection(event) { this.selectedChange = event.detail.selectedRows[0]; }
    handleDuplicateSelection(event) { this.selectedDuplicate = event.detail.selectedRows[0]; }
    handleOpenChangeRecord() { this.navigateToRecord(this.selectedChange?.id); }
    handleOpenDuplicateRecord() { this.navigateToRecord(this.selectedDuplicate?.id); }

    async loadChanges() {
        const requestSequence = ++this.governanceRequestSequence;
        this.isGovernanceLoading = true;
        this.governanceError = undefined;
        try {
            const response = await getChangeInventory({
                searchTerm: this.changeSearchTerm,
                changeType: this.changeType,
                reviewStatus: this.changeReviewStatus
            });
            if (requestSequence !== this.governanceRequestSequence || !this.isChangesView) return;
            this.changeSummary = response.summary || EMPTY_CHANGE_SUMMARY;
            this.changeRows = response.changes || [];
            this.selectedChange = undefined;
        } catch (error) {
            if (requestSequence !== this.governanceRequestSequence || !this.isChangesView) return;
            this.changeRows = [];
            this.governanceError = this.reduceError(error);
        } finally {
            if (requestSequence === this.governanceRequestSequence) {
                this.isGovernanceLoading = false;
            }
        }
    }

    async loadDuplicates() {
        const requestSequence = ++this.governanceRequestSequence;
        this.isGovernanceLoading = true;
        this.governanceError = undefined;
        try {
            const response = await getDuplicateCandidates({
                searchTerm: this.duplicateSearchTerm,
                reviewStatus: this.duplicateReviewStatus,
                minimumConfidence: this.minimumConfidence
            });
            if (requestSequence !== this.governanceRequestSequence || !this.isDuplicatesView) return;
            this.duplicateSummary = response.summary || EMPTY_DUPLICATE_SUMMARY;
            this.duplicateRows = response.candidates || [];
            this.selectedDuplicate = undefined;
        } catch (error) {
            if (requestSequence !== this.governanceRequestSequence || !this.isDuplicatesView) return;
            this.duplicateRows = [];
            this.governanceError = this.reduceError(error);
        } finally {
            if (requestSequence === this.governanceRequestSequence) {
                this.isGovernanceLoading = false;
            }
        }
    }

    handleOpenObjectRecord() {
        this.navigateToRecord(this.selectedObject?.id);
    }

    handleOpenFieldRecord() {
        this.navigateToRecord(this.selectedField?.id);
    }

    decorateObjectRows(catalogObjects) {
        const selectedId = this.selectedObject?.id;
        return catalogObjects.map((catalogObject) => ({
            ...catalogObject,
            ariaCurrent: catalogObject.id === selectedId ? 'true' : 'false',
            cssClass: catalogObject.id === selectedId
                ? 'c-object-row c-object-row_selected'
                : 'c-object-row'
        }));
    }

    reconcileSelection() {
        if (!this.objectRows.length) {
            this.selectedObject = undefined;
            this.selectedField = undefined;
            this.fieldRows = [];
            return;
        }

        const currentSelection = this.objectRows.find(
            (catalogObject) => catalogObject.id === this.selectedObject?.id
        );
        this.selectedObject = currentSelection || this.objectRows[0];
        this.objectRows = this.decorateObjectRows(this.objectRows);
        this.loadFields();
    }

    async loadFields() {
        if (!this.selectedObject) {
            this.fieldRequestSequence++;
            this.fieldRows = [];
            return;
        }

        const requestSequence = ++this.fieldRequestSequence;
        const selectedObjectId = this.selectedObject.id;
        this.isFieldLoading = true;
        this.fieldError = undefined;
        this.fieldRows = [];
        this.selectedField = undefined;
        try {
            const fieldRows = await getFields({ dictionaryObjectId: selectedObjectId });
            if (requestSequence !== this.fieldRequestSequence
                || selectedObjectId !== this.selectedObject?.id) return;
            this.fieldRows = fieldRows;
        } catch (error) {
            if (requestSequence !== this.fieldRequestSequence) return;
            this.fieldRows = [];
            this.fieldError = this.reduceError(error);
        } finally {
            if (requestSequence === this.fieldRequestSequence) {
                this.isFieldLoading = false;
            }
        }
    }

    navigateToRecord(recordId) {
        if (!recordId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                actionName: 'view'
            }
        });
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }
}