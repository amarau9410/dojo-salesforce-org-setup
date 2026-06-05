import { LightningElement, api } from 'lwc';

export default class CareOrchResidentAlertBanner extends LightningElement {
    @api aggressiveFlag = false;
    @api mobilityFlag = false;

    get bannerMessage() {
        if (this.aggressiveFlag) {
            return 'Resident has a hyper-aggressive behaviour flag. Use two-carer procedures and de-escalation protocol before task execution.';
        }

        if (this.mobilityFlag) {
            return 'Resident requires mobility assistance. Confirm hoist/walker support and perform transfer checks before care actions.';
        }

        return '';
    }
}
