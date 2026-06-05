import { LightningElement, track } from 'lwc';
import getIncidentContext from '@salesforce/apex/CareOrchCriticalIncidentController.getIncidentContext';
import createIncident from '@salesforce/apex/CareOrchCriticalIncidentController.createIncident';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const TAXONOMY_OPTIONS = [
    { label: 'Fall', value: 'Fall' },
    { label: 'Medication Error', value: 'Medication Error' },
    { label: 'Serious Injury', value: 'Serious Injury' },
    { label: 'Elopement / Missing Resident', value: 'Elopement / Missing Resident' },
    { label: 'Resident-to-Resident Altercation', value: 'Resident-to-Resident Altercation' },
    { label: 'Choking Incident', value: 'Choking Incident' },
    { label: 'Unresponsive / Loss of Consciousness', value: 'Unresponsive / Loss of Consciousness' },
    { label: 'Sudden Clinical Deterioration', value: 'Sudden Clinical Deterioration' },
    { label: 'Skin Integrity Failure (Severe Pressure Ulcer)', value: 'Skin Integrity Failure (Severe Pressure Ulcer)' },
    { label: 'Unexplained Injury', value: 'Unexplained Injury' }
];

export default class CareOrchIncidentLogger extends LightningElement {
    @track isModalOpen = false;
    @track isBusy = false;
    @track contextMessage = '';
    @track contextError = '';

    selectedTaxonomy;
    context;
    latitude;
    longitude;

    get taxonomyOptions() {
        return TAXONOMY_OPTIONS;
    }

    get isStepOne() {
        return this.isModalOpen && !this.selectedTaxonomy;
    }

    get isStepTwo() {
        return this.isModalOpen && this.selectedTaxonomy;
    }

    get submitDisabled() {
        return this.isBusy || !this.selectedTaxonomy;
    }

    async handleLaunchLogger() {
        this.isModalOpen = true;
        this.isBusy = true;
        this.selectedTaxonomy = null;
        this.contextError = '';
        this.contextMessage = 'Capturing active shift and location...';

        await Promise.all([this.captureGeolocation(), this.loadIncidentContext()]);
        this.isBusy = false;

        if (this.context?.shiftTaskId) {
            this.contextMessage = `Shift: ${this.context.shiftSummary}`;
        } else {
            this.contextError = 'No active shift context found. Start your shift before logging a critical incident.';
            this.contextMessage = '';
        }
    }

    handleTaxonomyChange(event) {
        this.selectedTaxonomy = event.detail.value;
    }

    async handleSubmitIncident() {
        if (this.submitDisabled) {
            return;
        }

        this.isBusy = true;
        try {
            const result = await createIncident({
                taxonomy: this.selectedTaxonomy,
                latitude: this.latitude,
                longitude: this.longitude
            });

            this.showToast('Incident Logged', result.message, 'success');
            this.closeModal();
        } catch (error) {
            this.showToast('Incident logging failed', this.normalizeError(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    closeModal() {
        this.isModalOpen = false;
        this.selectedTaxonomy = null;
        this.context = null;
        this.contextMessage = '';
        this.contextError = '';
        this.latitude = null;
        this.longitude = null;
    }

    async loadIncidentContext() {
        try {
            this.context = await getIncidentContext();
        } catch (error) {
            this.contextError = this.normalizeError(error);
        }
    }

    captureGeolocation() {
        return new Promise((resolve) => {
            if (!navigator.geolocation) {
                resolve();
                return;
            }

            navigator.geolocation.getCurrentPosition(
                (position) => {
                    this.latitude = Number(position.coords.latitude.toFixed(6));
                    this.longitude = Number(position.coords.longitude.toFixed(6));
                    resolve();
                },
                () => {
                    resolve();
                },
                {
                    enableHighAccuracy: true,
                    maximumAge: 30000,
                    timeout: 4000
                }
            );
        });
    }

    normalizeError(error) {
        return error?.body?.message || 'Unexpected error while logging incident.';
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
