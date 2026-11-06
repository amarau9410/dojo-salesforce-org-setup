import { createElement } from 'lwc';
import FieldTripQuarterlyConsole from 'c/fieldTripQuarterlyConsole';
import getConsoleState from '@salesforce/apex/FieldTripRunController.getConsoleState';
import requestAnalyze from '@salesforce/apex/FieldTripRunController.requestAnalyze';
import requestReports from '@salesforce/apex/FieldTripRunController.requestReports';

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
        jest.useRealTimers();
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

    it.each(['Analyze', 'Generate Reports'])(
        'requires an explicit Production confirmation for %s',
        async (operation) => {
            getConsoleState.mockResolvedValue({
                targetOrg: 'Prod',
                isSandbox: false,
                canLaunchAnalyze: true,
                canGenerateReports: true,
                analyses: [{ id: 'analysis-1', name: 'CMSL', objectApiName: 'Contact' }],
                runs: []
            });
            requestAnalyze.mockResolvedValue('analyze-run');
            requestReports.mockResolvedValue('report-run');
            const element = createElement('c-field-trip-quarterly-console', {
                is: FieldTripQuarterlyConsole
            });
            document.body.appendChild(element);
            await flushPromises();
            await flushPromises();

            element.shadowRoot.querySelector('lightning-radio-group').dispatchEvent(
                new CustomEvent('change', { detail: { value: operation } })
            );
            await flushPromises();
            await flushPromises();
            element.shadowRoot.querySelector('lightning-dual-listbox').dispatchEvent(
                new CustomEvent('change', {
                    detail: { value: operation === 'Analyze' ? ['analysis-1'] : ['CMSL'] }
                })
            );
            await flushPromises();
            await flushPromises();

            const inputs = [...element.shadowRoot.querySelectorAll('lightning-input')];
            const confirmation = inputs.find((input) => input.type === 'checkbox');
            expect(confirmation.label).toBe('I confirm this operation will run against Production');
            const submit = [...element.shadowRoot.querySelectorAll('lightning-button')]
                .find((button) => button.label === (
                    operation === 'Analyze' ? 'Launch Analyze jobs' : 'Generate reports'
                ));
            expect(submit.disabled).toBe(true);
            expect(requestAnalyze).not.toHaveBeenCalled();
            expect(requestReports).not.toHaveBeenCalled();

            confirmation.checked = true;
            confirmation.dispatchEvent(new CustomEvent('change'));
            await flushPromises();
            await flushPromises();
            expect(submit.disabled).toBe(false);
            confirmation.checked = false;
            confirmation.dispatchEvent(new CustomEvent('change'));
            await flushPromises();
            await flushPromises();
            expect(submit.disabled).toBe(true);
            confirmation.checked = true;
            confirmation.dispatchEvent(new CustomEvent('change'));
            await flushPromises();
            await flushPromises();
            [...inputs, element.shadowRoot.querySelector('lightning-dual-listbox')]
                .forEach((control) => {
                    jest.spyOn(control, 'reportValidity').mockReturnValue(true);
                });
            submit.click();
            await flushPromises();
            await flushPromises();
            const request = operation === 'Analyze' ? requestAnalyze : requestReports;
            expect(request).toHaveBeenCalledWith(expect.objectContaining({
                confirmedProduction: true
            }));
        }
    );

    it('polls a persisted Processing run to completion and stops polling', async () => {
        jest.useFakeTimers();
        const state = {
            targetOrg: 'Admin',
            isSandbox: true,
            analyses: [],
            runs: [{
                id: 'run-1',
                name: 'FTR-pilot',
                operation: 'Analyze',
                status: 'Processing',
                items: []
            }]
        };
        getConsoleState.mockResolvedValueOnce(state).mockResolvedValue({
            ...state,
            runs: [{ ...state.runs[0], status: 'Completed' }]
        });
        const element = createElement('c-field-trip-quarterly-console', {
            is: FieldTripQuarterlyConsole
        });
        document.body.appendChild(element);
        await flushPromises();
        await flushPromises();
        expect(element.shadowRoot.querySelector('.run-summary').textContent)
            .toContain('Processing');
        expect(element.shadowRoot.querySelector('.production-confirmation')).toBeNull();
        jest.advanceTimersByTime(15000);
        await flushPromises();
        await flushPromises();
        expect(element.shadowRoot.querySelector('.run-summary').textContent)
            .toContain('Completed');
        expect(getConsoleState).toHaveBeenCalledTimes(2);
        jest.advanceTimersByTime(30000);
        expect(getConsoleState).toHaveBeenCalledTimes(2);
    });
});
