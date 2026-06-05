import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getUpcomingShiftAgenda from '@salesforce/apex/CareOrchMyCalendarController.getUpcomingShiftAgenda';
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
        label: 'Start',
        fieldName: 'startDateTime',
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
        fieldName: 'endDateTime',
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
    }
];

export default class CareOrchMyCalendar extends NavigationMixin(LightningElement) {
    columns = COLUMNS;
    rows = [];
    wiredResult;

    @wire(getUpcomingShiftAgenda)
    wiredAgenda(result) {
        this.wiredResult = result;
        if (result.data) {
            this.rows = result.data.map((item) => ({
                ...item,
                patientName: item.patientName || 'Not specified'
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
