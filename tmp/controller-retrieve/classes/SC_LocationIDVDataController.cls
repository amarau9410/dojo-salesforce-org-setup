/**
 * @date 09/18/2024
 * @description Controller class for handling Location IDV Data retrieval and processing.
 */
public with sharing class SC_LocationIDVDataController {
    public static final String NA_VALUE = 'N/A';
    public static final String ERROR_OCCURRED = 'An error occurred during data retrieval. Please contact the administrator.';
    public static final String INCORRECT_ACCOUNT = 'Location or Customer IDs are missing on this account.';

    /**
     * @description Retrieves IDV data for a given account record ID.
     * @param recordId The ID of the account record.
     * @return An instance of IDVData containing the retrieved data.
     * @example
     * IDVData data = SC_LocationIDVDataController.getLocationIDVData('001XXXXXXXXXXXX');
     */
    @AuraEnabled(Cacheable=true)
    public static IDVData getLocationIDVData(String recordId) {
        IDVData idvData = new IDVData();

        try {
            List<Account> accounts = [
                    SELECT Id, ParentExternalCustomerId__c, ExternalLocationId__c, CurrencyIsoCode
                    FROM Account
                    WHERE Id = :recordId
                    AND ParentExternalCustomerId__c != NULL
                    AND ExternalLocationId__c != NULL
            ];

            if(!accounts.isEmpty()) {
                setIDVDataValues(accounts.get(0).ParentExternalCustomerId__c, accounts.get(0).ExternalLocationId__c, idvData, accounts.get(0).CurrencyIsoCode);
            } else {
                idvData.message = INCORRECT_ACCOUNT;
            }

        } catch (Exception e) {
            idvData.message = ERROR_OCCURRED;
            CORE_LogUtil.createErrorLog(e, 'SC_LocationIDVDataController');
            CORE_LogUtil.insertLogs();
        }

        return idvData;
    }

    /**
     * @description Sets the IDV data values based on the retrieved payment wrapper.
     * @param customerId The customer ID.
     * @param locationId The location ID.
     * @param idvData The IDVData instance to populate.
     * @param currencyIsoCode The currency ISO code.
     * @example
     * setIDVDataValues('cust123', 'loc456', new IDVData(), 'USD');
     */
    private static void setIDVDataValues(String customerId, String locationId, IDVData idvData, String currencyIsoCode) {
        SC_IDVDataService.PaymentWrapper paymentWrapper = SC_IDVDataService.getIDVData(customerId, locationId);

        if(paymentWrapper != null) {
            idvData.first4Digits = String.isBlank(paymentWrapper.bankAccountNumber) ? NA_VALUE : paymentWrapper.bankAccountNumber.length() < 4 ? paymentWrapper.bankAccountNumber : paymentWrapper.bankAccountNumber.substring(0, 4);

            if(paymentWrapper.transactionsLink != null) {
                idvData.transactionsLink = paymentWrapper.transactionsLink;
            }

            if(paymentWrapper.transfer != null) {
                if(paymentWrapper.transfer.get(SC_IDVUtil.AMOUNT_PARAM_NAME) != null) {
                    idvData.lastTransferAmount = currencyIsoCode + ' ' + formatAmount(paymentWrapper.transfer.get(SC_IDVUtil.AMOUNT_PARAM_NAME));
                }
            }

            if(paymentWrapper.invoice != null) {
                if(paymentWrapper.invoice.get(SC_IDVUtil.AMOUNT_PARAM_NAME) != null) {
                    idvData.lastMonthsInvoiceAmount = currencyIsoCode + ' ' + formatAmount(paymentWrapper.invoice.get(SC_IDVUtil.AMOUNT_PARAM_NAME));
                }
            }
        }
    }

    /**
     * @description Formats the amount string into a decimal format.
     * @param amountString The amount string to format.
     * @return The formatted amount as a string.
     * @example
     * String formattedAmount = formatAmount('1234.561111');
     */
    private static String formatAmount(String amountString){

        return Decimal.valueOf(amountString).format();
    }

    /**
     * @description Wrapper class for IDV data.
     */
    public class IDVData {
        @AuraEnabled
        public String first4Digits;
        @AuraEnabled
        public String transactionsLink;
        @AuraEnabled
        public String lastMonthsInvoiceAmount;
        @AuraEnabled
        public String lastTransferAmount;
        @AuraEnabled
        public String message;

        public IDVData() {
            first4Digits = NA_VALUE;
            transactionsLink = NA_VALUE;
            lastMonthsInvoiceAmount = NA_VALUE;
            lastTransferAmount = NA_VALUE;
        }
    }
}