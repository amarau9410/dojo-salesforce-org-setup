import { createElement } from 'lwc';
import FieldTripQuarterlyConsole from 'c/fieldTripQuarterlyConsole';
import getConsoleState from '@salesforce/apex/FieldTripRunController.getConsoleState';
import requestAnalyze from '@salesforce/apex/FieldTripRunController.requestAnalyze';

jest.mock(
    '@salesforce/apex/FieldTripRunController.getConsoleState',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/FieldTripRunController.requestAnalyze',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/FieldTripRunController.requestReports',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/FieldTripRunController.recoverRun',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/FieldTripRunController.removeRun',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const flushPromises = () => Promise.resolve();

describe('c-field-trip-quarterly-console', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows completed analysis count and the latest Analyze timestamp in UTC', async () => {
        getConsoleState.mockResolvedValue({
            targetOrg: 'Warthog',
            activeBatchJobs: 0,
            analyses: [
                { id: 'a1', lastAnalyzedAt: '2026-10-29T14:13:58.000Z' },
                { id: 'a2', lastAnalyzedAt: '2026-10-29T15:15:00.000Z' },
                { id: 'a3', lastAnalyzedAt: null }
            ],
            runs: [],
            isSandbox: true,
            canLaunchAnalyze: false,
            canGenerateReports: false,
            canManageRuns: false,
            canDownloadReports: false,
            canRecoverRuns: false
        });

        const element = createElement('c-field-trip-quarterly-console', {
            is: FieldTripQuarterlyConsole
        });
        document.body.appendChild(element);

        await flushPromises();
        await flushPromises();

        const summaryValues = [...element.shadowRoot.querySelectorAll('.status-band strong')]
            .map((value) => value.textContent);
        expect(summaryValues).toContain('2');
        expect(summaryValues).toContain('Oct 29, 2026, 3:15 PM UTC');
    });

    it('shows an explicit empty state when no analysis has completed', async () => {
        getConsoleState.mockResolvedValue({
            targetOrg: 'Warthog',
            activeBatchJobs: 0,
            analyses: [{ id: 'a1', lastAnalyzedAt: null }],
            runs: [],
            isSandbox: true,
            canLaunchAnalyze: false,
            canGenerateReports: false,
            canManageRuns: false,
            canDownloadReports: false,
            canRecoverRuns: false
        });

        const element = createElement('c-field-trip-quarterly-console', {
            is: FieldTripQuarterlyConsole
        });
        document.body.appendChild(element);

        await flushPromises();
        await flushPromises();

        const summaryValues = [...element.shadowRoot.querySelectorAll('.status-band strong')]
            .map((value) => value.textContent);
        expect(summaryValues).toContain('0');
        expect(summaryValues).toContain('No completed analyses');
    });

    it('accepts a Salesforce Analyze request at capacity and explains shutdown resilience', async () => {
        getConsoleState.mockResolvedValue({
            targetOrg: 'Warthog',
            activeBatchJobs: 3,
            analyses: [{ id: 'analysis-1', name: 'Account Analysis', objectApiName: 'Account' }],
            runs: [],
            isSandbox: true,
            canLaunchAnalyze: true,
            canGenerateReports: false,
            canManageRuns: false,
            canDownloadReports: false,
            canRecoverRuns: false
        });
        requestAnalyze.mockResolvedValue('FTR-000001');

        const element = createElement('c-field-trip-quarterly-console', {
            is: FieldTripQuarterlyConsole
        });
        document.body.appendChild(element);
        await flushPromises();
        await flushPromises();

        const analysisList = element.shadowRoot.querySelector('lightning-dual-listbox');
        expect(analysisList).not.toBeNull();
        analysisList.dispatchEvent(
            new CustomEvent('change', { detail: { value: ['analysis-1'] } })
        );
        const dateInputs = element.shadowRoot.querySelectorAll('lightning-input');
        dateInputs[0].value = '2026-06-01';
        dateInputs[0].dispatchEvent(new CustomEvent('change', { detail: { value: '2026-06-01' } }));
        dateInputs[1].value = '2026-07-01';
        dateInputs[1].dispatchEvent(new CustomEvent('change', { detail: { value: '2026-07-01' } }));
        await flushPromises();
        await flushPromises();
        [analysisList, ...dateInputs].forEach((control) => {
            jest.spyOn(control, 'reportValidity').mockReturnValue(true);
        });

        const submitButton = [...element.shadowRoot.querySelectorAll('lightning-button')].find(
            (button) => button.label === 'Launch Analyze jobs'
        );
        expect(submitButton).toBeDefined();
        expect(submitButton.disabled).toBe(false);
        submitButton.click();
        await flushPromises();
        await flushPromises();

        expect(requestAnalyze).toHaveBeenCalledWith(expect.objectContaining({
            selectedAnalysisIds: ['analysis-1']
        }));
        expect(element.shadowRoot.querySelector('[role="status"]').textContent)
            .toContain('Processing continues if you close the browser or turn off the Windows worker.');
    });
});
