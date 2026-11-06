import { createElement } from 'lwc';
import FieldUsageWorkbench from 'c/fieldUsageWorkbench';
import { refreshApex } from '@salesforce/apex';
import getFilterOptions from '@salesforce/apex/FieldUsageController.getFilterOptions';
import getUsage from '@salesforce/apex/FieldUsageController.getUsage';
import getUsageRows from '@salesforce/apex/FieldUsageController.getUsageRows';

jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/FieldUsageController.getFilterOptions', () => ({
    default: require('@salesforce/sfdx-lwc-jest').createApexTestWireAdapter(jest.fn())
}), { virtual: true });
jest.mock('@salesforce/apex/FieldUsageController.getUsage', () => ({
    default: require('@salesforce/sfdx-lwc-jest').createApexTestWireAdapter(jest.fn())
}), { virtual: true });
jest.mock('@salesforce/apex/FieldUsageController.getUsageRows', () => ({
    default: require('@salesforce/sfdx-lwc-jest').createApexTestWireAdapter(jest.fn())
}), { virtual: true });
jest.mock('@salesforce/apex/FieldTripRunController.getAllianceReportState',
    () => ({ default: jest.fn().mockResolvedValue({ approvers: [], artifacts: [] }) }),
    { virtual: true });
jest.mock('@salesforce/apex/FieldTripRunController.submitReportForApproval',
    () => ({ default: jest.fn() }), { virtual: true });

const settle = async () => {
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
};

const METRICS = {
    summary: { evidenceCount: 42482, usedCount: 20000, unusedCount: 22482, noRecordsCount: 0 },
    segments: [{ reportingGroup: 'CMSL', evidenceCount: 2409, usedCount: 1255 }]
};
const ROW = {
    id: 'usage1', reportingGroup: 'CMSL', alliance: 'CMSL', objectApiName: 'Account',
    fieldApiName: 'Name', fieldLabel: 'Account Name', usageStatus: 'Used',
    recordTypeName: 'CMSL', populationPercent: 50, recordsAnalyzed: 100,
    populatedCount: 50, lastAnalyzedAt: '2026-07-01T12:00:00.000Z'
};

function mount() {
    const element = createElement('c-field-usage-workbench', { is: FieldUsageWorkbench });
    document.body.appendChild(element);
    return element;
}

describe('c-field-usage-workbench', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('retains complete metrics when the independent detail response is truncated', async () => {
        const element = mount();
        getUsage.emit(METRICS);
        getUsageRows.emit({ rows: [ROW], isTruncated: true, rowLimit: 10000 });
        await settle();
        expect(element.shadowRoot.querySelector('.c-metrics').textContent).toContain('42482');
        expect(element.shadowRoot.querySelector('[role="status"]').textContent)
            .toContain('Metrics include all matching evidence');
        expect(element.shadowRoot.querySelector('.c-alliance-summary')).toBeNull();
        expect(element.shadowRoot.querySelector('lightning-datatable').data[0].reportingGroup)
            .toBe('CMSL');
    });

    it('renders details when rows arrive before the metrics response', async () => {
        const element = mount();
        getFilterOptions.emit({
            alliances: ['CMSL'], objectApiNames: ['Account'], canViewAllAlliances: false
        });
        await settle();
        getUsageRows.emit({ rows: [ROW], isTruncated: false, rowLimit: 10000 });
        getUsage.emit(METRICS);
        await settle();
        const table = element.shadowRoot.querySelector('lightning-datatable');
        expect(table.data).toHaveLength(1);
        expect(table.data[0].fieldLabel).toBe('Account Name');
        expect(table.columns.map((column) => column.label)).toContain('CMSL');
    });

    it('shows a detail error without discarding complete dashboard metrics', async () => {
        const element = mount();
        getUsage.emit(METRICS);
        getUsageRows.error({ message: 'Detail evidence unavailable' });
        await settle();
        expect(element.shadowRoot.querySelector('.c-metrics').textContent).toContain('42482');
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent)
            .toContain('Detail evidence unavailable');
    });

    it('shows a metrics error without presenting zero metrics as a successful response', async () => {
        const element = mount();
        getUsageRows.emit({ rows: [], isTruncated: false, rowLimit: 10000 });
        getUsage.error({ message: 'Metrics unavailable' });
        await settle();
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent)
            .toContain('Metrics unavailable');
    });

    it('handles refresh rejection and clears the loading indicator', async () => {
        const element = mount();
        getUsage.emit(METRICS);
        getUsageRows.emit({ rows: [], isTruncated: false, rowLimit: 10000 });
        await settle();
        refreshApex.mockRejectedValue({ body: { message: 'Refresh unavailable' } });
        element.shadowRoot.querySelector('lightning-button-icon').click();
        await settle();
        expect(refreshApex).toHaveBeenCalledTimes(3);
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent)
            .toContain('Refresh unavailable');
        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
    });
});
