public with sharing class CareOrchAssignGuardrailSvc {
    private static final Integer MAX_LOW_NEEDS = 5;
    private static final Integer MAX_HIGH_NEEDS = 2;

    private class ResidentRisk {
        Boolean isHigh = false;
        Boolean isAggressive = false;
    }

    private class ShiftStats {
        Integer total = 0;
        Integer high = 0;
        Integer aggressive = 0;

        void add(ResidentRisk risk) {
            total++;
            if (risk != null && risk.isHigh) {
                high++;
            }
            if (risk != null && risk.isAggressive) {
                aggressive++;
            }
        }

        void subtract(ResidentRisk risk) {
            total = Math.max(0, total - 1);
            if (risk != null && risk.isHigh) {
                high = Math.max(0, high - 1);
            }
            if (risk != null && risk.isAggressive) {
                aggressive = Math.max(0, aggressive - 1);
            }
        }

        Integer lowCount() {
            Integer low = total - high;
            return low < 0 ? 0 : low;
        }
    }

    public static void enforceBeforeSave(List<CareOrch_Resident_Assignment__c> newRows, Map<Id, CareOrch_Resident_Assignment__c> oldMap) {
        if (newRows == null || newRows.isEmpty()) {
            return;
        }

        Set<Id> shiftIds = new Set<Id>();
        Set<Id> residentIds = new Set<Id>();

        for (CareOrch_Resident_Assignment__c row : newRows) {
            if (row.Shift_Task__c != null) {
                shiftIds.add(row.Shift_Task__c);
            }
            if (row.Resident_Account__c != null) {
                residentIds.add(row.Resident_Account__c);
            }
            CareOrch_Resident_Assignment__c oldRow = oldMap == null ? null : oldMap.get(row.Id);
            if (oldRow != null) {
                if (oldRow.Shift_Task__c != null) {
                    shiftIds.add(oldRow.Shift_Task__c);
                }
                if (oldRow.Resident_Account__c != null) {
                    residentIds.add(oldRow.Resident_Account__c);
                }
            }
        }

        if (shiftIds.isEmpty()) {
            return;
        }

        Map<Id, ShiftStats> statsByShift = getCurrentStatsByShift(shiftIds);
        Map<Id, ResidentRisk> riskByResident = getRiskByResident(residentIds);
        Map<Id, Shift_Lifecycle__c> shiftsById = new Map<Id, Shift_Lifecycle__c>([
            SELECT Id, CareOrch_Second_Caregiver_Coverage__c
            FROM Shift_Lifecycle__c
            WHERE Id IN :shiftIds
        ]);

        for (CareOrch_Resident_Assignment__c row : newRows) {
            CareOrch_Resident_Assignment__c oldRow = oldMap == null ? null : oldMap.get(row.Id);

            if (oldRow != null && oldRow.CareOrch_Assignment_Active__c && oldRow.Shift_Task__c != null) {
                ShiftStats oldShiftStats = getOrCreateStats(statsByShift, oldRow.Shift_Task__c);
                oldShiftStats.subtract(riskByResident.get(oldRow.Resident_Account__c));
            }

            if (row.CareOrch_Assignment_Active__c && row.Shift_Task__c != null) {
                ShiftStats newShiftStats = getOrCreateStats(statsByShift, row.Shift_Task__c);
                newShiftStats.add(riskByResident.get(row.Resident_Account__c));

                Shift_Lifecycle__c parentShift = shiftsById.get(row.Shift_Task__c);
                Boolean hasSecondCoverage = parentShift != null && parentShift.CareOrch_Second_Caregiver_Coverage__c;

                if (newShiftStats.aggressive > 0 && !hasSecondCoverage) {
                    row.addError('Lone-worker safeguard: second caregiver coverage is required for hyper-aggressive resident assignments.');
                    continue;
                }

                if (newShiftStats.high > MAX_HIGH_NEEDS) {
                    row.addError('Capacity safeguard exceeded: maximum 2 high-needs residents per shift context.');
                    continue;
                }

                if (newShiftStats.lowCount() > MAX_LOW_NEEDS) {
                    row.addError('Capacity safeguard exceeded: maximum 5 low-needs residents per shift context.');
                }
            }
        }
    }

    public static void refreshShiftRollups(List<CareOrch_Resident_Assignment__c> newRows, Map<Id, CareOrch_Resident_Assignment__c> oldMap) {
        Set<Id> shiftIds = collectImpactedShiftIds(newRows, oldMap);
        if (shiftIds.isEmpty()) {
            return;
        }

        Map<Id, ShiftStats> statsByShift = getCurrentStatsByShift(shiftIds);

        List<Shift_Lifecycle__c> shiftsToUpdate = new List<Shift_Lifecycle__c>();
        for (Shift_Lifecycle__c shiftRow : [
            SELECT Id, CareOrch_Second_Caregiver_Coverage__c
            FROM Shift_Lifecycle__c
            WHERE Id IN :shiftIds
        ]) {
            ShiftStats stats = statsByShift.get(shiftRow.Id);
            if (stats == null) {
                stats = new ShiftStats();
            }

            Shift_Lifecycle__c updateRow = new Shift_Lifecycle__c(Id = shiftRow.Id);
            updateRow.CareOrch_Assignment_Count__c = stats.total;
            updateRow.CareOrch_High_Needs_Count__c = stats.high;
            updateRow.CareOrch_Capacity_Risk_Warning__c = buildWarning(stats, shiftRow.CareOrch_Second_Caregiver_Coverage__c);
            shiftsToUpdate.add(updateRow);
        }

        if (!shiftsToUpdate.isEmpty()) {
            update shiftsToUpdate;
        }
    }

    private static String buildWarning(ShiftStats stats, Boolean hasSecondCoverage) {
        if (stats == null) {
            return null;
        }

        if (stats.aggressive > 0 && !hasSecondCoverage) {
            return 'Lone-worker safeguard warning: second caregiver coverage required for hyper-aggressive resident assignment.';
        }

        if (stats.high > MAX_HIGH_NEEDS) {
            return 'Capacity warning: high-needs resident count exceeds threshold (max 2).';
        }

        if (stats.lowCount() > MAX_LOW_NEEDS) {
            return 'Capacity warning: low-needs resident count exceeds threshold (max 5).';
        }

        return null;
    }

    private static Set<Id> collectImpactedShiftIds(List<CareOrch_Resident_Assignment__c> newRows, Map<Id, CareOrch_Resident_Assignment__c> oldMap) {
        Set<Id> shiftIds = new Set<Id>();

        if (newRows != null) {
            for (CareOrch_Resident_Assignment__c row : newRows) {
                if (row.Shift_Task__c != null) {
                    shiftIds.add(row.Shift_Task__c);
                }
                CareOrch_Resident_Assignment__c oldRow = oldMap == null ? null : oldMap.get(row.Id);
                if (oldRow != null && oldRow.Shift_Task__c != null) {
                    shiftIds.add(oldRow.Shift_Task__c);
                }
            }
        }

        if (oldMap != null && !oldMap.isEmpty() && (newRows == null || newRows.isEmpty())) {
            for (CareOrch_Resident_Assignment__c oldRow : oldMap.values()) {
                if (oldRow.Shift_Task__c != null) {
                    shiftIds.add(oldRow.Shift_Task__c);
                }
            }
        }

        return shiftIds;
    }

    private static Map<Id, ShiftStats> getCurrentStatsByShift(Set<Id> shiftIds) {
        Map<Id, ShiftStats> statsByShift = new Map<Id, ShiftStats>();

        if (shiftIds == null || shiftIds.isEmpty()) {
            return statsByShift;
        }

        List<CareOrch_Resident_Assignment__c> assignments = [
            SELECT Id, Shift_Task__c, Resident_Account__c,
                   Resident_Account__r.CareOrch_Mobility_Assistance_Required__c,
                   Resident_Account__r.CareOrch_Hyper_Aggressive_Behavior__c
            FROM CareOrch_Resident_Assignment__c
            WHERE Shift_Task__c IN :shiftIds
              AND CareOrch_Assignment_Active__c = true
        ];

        for (CareOrch_Resident_Assignment__c row : assignments) {
            ShiftStats stats = getOrCreateStats(statsByShift, row.Shift_Task__c);
            ResidentRisk risk = new ResidentRisk();
            if (row.Resident_Account__r != null) {
                risk.isAggressive = row.Resident_Account__r.CareOrch_Hyper_Aggressive_Behavior__c;
                risk.isHigh = row.Resident_Account__r.CareOrch_Mobility_Assistance_Required__c || risk.isAggressive;
            }
            stats.add(risk);
        }

        return statsByShift;
    }

    private static Map<Id, ResidentRisk> getRiskByResident(Set<Id> residentIds) {
        Map<Id, ResidentRisk> riskByResident = new Map<Id, ResidentRisk>();

        if (residentIds == null || residentIds.isEmpty()) {
            return riskByResident;
        }

        for (Account resident : [
            SELECT Id, CareOrch_Mobility_Assistance_Required__c, CareOrch_Hyper_Aggressive_Behavior__c
            FROM Account
            WHERE Id IN :residentIds
        ]) {
            ResidentRisk risk = new ResidentRisk();
            risk.isAggressive = resident.CareOrch_Hyper_Aggressive_Behavior__c;
            risk.isHigh = resident.CareOrch_Mobility_Assistance_Required__c || risk.isAggressive;
            riskByResident.put(resident.Id, risk);
        }

        return riskByResident;
    }

    private static ShiftStats getOrCreateStats(Map<Id, ShiftStats> statsByShift, Id shiftId) {
        ShiftStats stats = statsByShift.get(shiftId);
        if (stats == null) {
            stats = new ShiftStats();
            statsByShift.put(shiftId, stats);
        }
        return stats;
    }
}
