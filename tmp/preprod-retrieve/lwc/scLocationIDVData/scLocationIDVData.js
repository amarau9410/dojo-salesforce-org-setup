/**
 * @description LWC component for fetching and displaying Location IDV Data.
 */
import { LightningElement, api } from 'lwc';
import getLocationIDVData from '@salesforce/apex/SC_LocationIDVDataController.getLocationIDVData';

export default class scLocationIdvData extends LightningElement {
    @api recordId;

    accountData = {
        first4Digits: '',
        transactionsLink: '',
        lastMonthsInvoiceAmount: '',
        lastTransferAmount: '',
        message: ''
    };

    isLoading = true;

    /**
     * @description Lifecycle hook that is invoked when the component is inserted into the DOM.
     */
    connectedCallback() {
        this.fetchExternalData();
    }

    /**
     * @description Fetches external data using the Apex method getLocationIDVData.
     */
    fetchExternalData() {
        getLocationIDVData({ recordId: this.recordId })
            .then(data => {
                this.accountData = {
                    first4Digits: data.first4Digits,
                    transactionsLink: data.transactionsLink,
                    lastMonthsInvoiceAmount: data.lastMonthsInvoiceAmount,
                    lastTransferAmount: data.lastTransferAmount,
                    message: data.message
                };
                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error fetching account data:', error);
                this.isLoading = false;
            });
    }
}