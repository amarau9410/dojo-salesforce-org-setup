import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getMyShiftTasks from '@salesforce/apex/CareOrchShiftInboxController.getMyShiftTasks';
import { refreshApex } from '@salesforce/apex';

const COLUMNS = [
    {
        type: 'button',
        typeAttributes: {
            label: 'Open',
            name: 'open',
            variant: 'base'
        }
    },
    {
        label: 'Shift',
        fieldName: 'subject',
        type: 'text'
    },
    {
        label: 'Patient',
        fieldName: 'patientName',
        type: 'text'
    },
    {
        label: 'Status',
        fieldName: 'status',
        type: 'text'
    },
    {
        label: 'Start',
        fieldName: 'shiftStart',
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }
    },
    {
        label: 'End',
        fieldName: 'shiftEnd',
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }
    },
    {
        label: 'Contacted',
        fieldName: 'contactedCount',
        type: 'number'
    },
    {
        label: 'Rejected',
        fieldName: 'rejectedCount',
        type: 'number'
    },
    {
        label: 'At Risk',
        fieldName: 'atRisk',
        type: 'boolean'
    },
    {
        label: 'Risk Reason',
        fieldName: 'atRiskReason',
        type: 'text'
    },
    {
        label: 'First Response (min)',
        fieldName: 'timeToFirstResponseMinutes',
        type: 'number',
        typeAttributes: {
            minimumFractionDigits: 0,
            maximumFractionDigits: 2
        }
    },
    {
        label: 'Time to Fill (min)',
        fieldName: 'timeToFillMinutes',
        type: 'number',
        typeAttributes: {
            minimumFractionDigits: 0,
            maximumFractionDigits: 2
        }
    }
];

export default class CareOrchShiftInbox extends NavigationMixin(LightningElement) {
    columns = COLUMNS;
    rows = [];
    wiredResult;

    @wire(getMyShiftTasks)
    wiredTasks(result) {
        this.wiredResult = result;
        if (result.data) {
            this.rows = result.data.map((row) => ({
                ...row,
                patientName: row.patientName || 'Not specified',
                status: row.status || 'Pending',
                atRiskReason: row.atRiskReason || ''
            }));
        } else {
            this.rows = [];
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    async handleRefresh() {
        await refreshApex(this.wiredResult);
    }

    handleRowAction(event) {
        const row = event.detail.row;
        if (!row?.taskId) {
            return;
        }

        this[NavigationMixin.Navigate](
            {
                type: 'standard__recordPage',
                attributes: {
                    recordId: row.taskId,
                    objectApiName: 'Task',
                    actionName: 'view'
                }
            }
        );
    }
}
