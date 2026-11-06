import { createElement } from 'lwc';
import { createApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import DataDictionaryWorkbench from 'c/dataDictionaryWorkbench';
import getCatalog from '@salesforce/apex/DataDictionaryController.getCatalog';
import getFields from '@salesforce/apex/DataDictionaryController.getFields';
import getChangeInventory from '@salesforce/apex/DataDictionaryController.getChangeInventory';
import getDuplicateCandidates from '@salesforce/apex/DataDictionaryController.getDuplicateCandidates';

jest.mock(
    '@salesforce/apex/DataDictionaryController.getCatalog',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/DataDictionaryController.getFields',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/DataDictionaryController.getChangeInventory',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/DataDictionaryController.getDuplicateCandidates',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const getCatalogAdapter = createApexTestWireAdapter(getCatalog);

const flushPromises = () => Promise.resolve();

const CATALOG_RESPONSE = {
    summary: {
        objectCount: 1,
        approvedObjectCount: 1,
        fieldCount: 2,
        documentedFieldCount: 1,
        sensitiveFieldCount: 1,
        dependencyCount: 3,
        documentationCoverage: 50,
        lastScannedAt: '2026-08-13T10:00:00.000Z'
    },
    objects: [
        {
            id: 'a01000000000001AAA',
            label: 'Account',
            apiName: 'Account',
            category: 'Standard',
            documentationStatus: 'Approved',
            sensitivity: 'Internal',
            fieldCount: 2,
            documentedFieldCount: 1,
            sensitiveFieldCount: 1,
            dependencyCount: 3
        }
    ]
};

const FIELD_ROWS = [
    {
        id: 'a02000000000001AAA',
        label: 'Account Name',
        apiName: 'Name',
        dataType: 'string',
        documentationStatus: 'Approved',
        sensitivity: 'Internal',
        dependencyCount: 2,
        required: true,
        uniqueValue: false,
        externalId: false,
        formula: 'AnnualRevenue * 0.10',
        picklistValues: 'New\nActive',
        flsSummary: 'Sales: Read/Edit',
        dependencies: 'AccountValidationRule'
    }
];

function deferredPromise() {
    let resolve;
    let reject;
    const promise = new Promise((resolvePromise, rejectPromise) => {
        resolve = resolvePromise;
        reject = rejectPromise;
    });
    return { promise, resolve, reject };
}

function createComponent() {
    const element = createElement('c-data-dictionary-workbench', {
        is: DataDictionaryWorkbench
    });
    document.body.appendChild(element);
    return element;
}

function clickView(element, label) {
    const button = [...element.shadowRoot.querySelectorAll('lightning-button')].find(
        (candidate) => candidate.label === label
    );
    button.click();
}

describe('c-data-dictionary-workbench', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads the catalog and fields for the initial object', async () => {
        getFields.mockResolvedValue(FIELD_ROWS);
        const element = createComponent();

        getCatalogAdapter.emit(CATALOG_RESPONSE);
        await flushPromises();
        await flushPromises();

        expect(getFields).toHaveBeenCalledWith({
            dictionaryObjectId: 'a01000000000001AAA'
        });
        expect(element.shadowRoot.querySelector('.c-object-row__name').textContent).toBe(
            'Account'
        );
        expect(element.shadowRoot.querySelector('.c-object-row').getAttribute('aria-current')).toBe(
            'true'
        );
        const datatable = element.shadowRoot.querySelector('lightning-datatable');
        expect(datatable.data).toEqual(FIELD_ROWS);
        expect(element.shadowRoot.querySelector('.c-error')).toBeNull();
    });

    it('shows technical governance evidence for a selected field', async () => {
        getFields.mockResolvedValue(FIELD_ROWS);
        const element = createComponent();
        getCatalogAdapter.emit(CATALOG_RESPONSE);
        await flushPromises();
        await flushPromises();

        const datatable = element.shadowRoot.querySelector('lightning-datatable');
        datatable.dispatchEvent(new CustomEvent('rowselection', {
            detail: { selectedRows: FIELD_ROWS }
        }));
        await flushPromises();

        const technicalText = [...element.shadowRoot.querySelectorAll('.c-technical-text')]
            .map((node) => node.textContent);
        expect(technicalText).toEqual([
            'AnnualRevenue * 0.10',
            'New\nActive',
            'Sales: Read/Edit',
            'AccountValidationRule'
        ]);
    });

    it('ignores a stale field response after another object is selected', async () => {
        const firstRequest = deferredPromise();
        const secondRequest = deferredPromise();
        getFields
            .mockReturnValueOnce(firstRequest.promise)
            .mockReturnValueOnce(secondRequest.promise);
        const element = createComponent();
        getCatalogAdapter.emit({
            ...CATALOG_RESPONSE,
            objects: [
                ...CATALOG_RESPONSE.objects,
                {
                    ...CATALOG_RESPONSE.objects[0],
                    id: 'a01000000000002AAA',
                    label: 'Contact',
                    apiName: 'Contact'
                }
            ]
        });
        await flushPromises();

        const objectRows = element.shadowRoot.querySelectorAll('.c-object-row');
        objectRows[1].click();
        const contactFields = [{ ...FIELD_ROWS[0], id: 'a02000000000002AAA', label: 'Email' }];
        secondRequest.resolve(contactFields);
        await flushPromises();
        firstRequest.resolve(FIELD_ROWS);
        await flushPromises();

        expect(element.shadowRoot.querySelector('lightning-datatable').data).toEqual(contactFields);
    });

    it('loads change inventory when the change view is selected', async () => {
        getFields.mockResolvedValue(FIELD_ROWS);
        getChangeInventory.mockResolvedValue({
            summary: {
                addedCount: 1,
                changedCount: 0,
                removedCount: 0,
                reactivatedCount: 0,
                pendingReviewCount: 1,
                notificationStatus: 'Pending'
            },
            changes: [
                {
                    id: 'a03000000000001AAA',
                    metadataLabel: 'Risk Rating',
                    qualifiedApiName: 'Account.Risk_Rating__c',
                    changeType: 'Added',
                    entityType: 'Field',
                    reviewStatus: 'New'
                }
            ]
        });
        const element = createComponent();
        getCatalogAdapter.emit(CATALOG_RESPONSE);
        await flushPromises();

        clickView(element, 'Change Inventory');
        await flushPromises();

        expect(getChangeInventory).toHaveBeenCalledWith({
            searchTerm: '',
            changeType: '',
            reviewStatus: ''
        });
        const datatable = element.shadowRoot.querySelector('lightning-datatable');
        expect(datatable.data).toHaveLength(1);
        expect(datatable.data[0].qualifiedApiName).toBe('Account.Risk_Rating__c');
    });

    it('shows a sanitized message when duplicate loading fails', async () => {
        getFields.mockResolvedValue(FIELD_ROWS);
        getDuplicateCandidates.mockRejectedValue({
            body: { message: 'Duplicate inventory is unavailable.' }
        });
        const element = createComponent();
        getCatalogAdapter.emit(CATALOG_RESPONSE);
        await flushPromises();

        clickView(element, 'Potential Duplicates');
        await flushPromises();

        expect(getDuplicateCandidates).toHaveBeenCalledWith({
            searchTerm: '',
            reviewStatus: '',
            minimumConfidence: 80
        });
        expect(element.shadowRoot.querySelector('.c-error').textContent).toBe(
            'Duplicate inventory is unavailable.'
        );
    });
});
