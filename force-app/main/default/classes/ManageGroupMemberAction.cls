public without sharing class ManageGroupMemberAction {
    public class Request {
        @InvocableVariable(required=true)
        public Id UserId;

        // Market code: GB, IE, ES, IT
        @InvocableVariable(required=true)
        public String MarketCode;

        // 'Add' or 'Remove'
        @InvocableVariable(required=true)
        public String Action;
    }

    public class Result {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String message;
        @InvocableVariable public Id groupId;
        @InvocableVariable public Id userId;
    }

    public class Payload {
        @InvocableVariable(required=true)
        public String value; // format examples: "<UserId>|<MarketCode>|<Action>" OR "<UserId>|<Action>|<MarketCode(s)>"
    }

    private static List<Result> doUpdateGroup(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null) return results;

        // Build map of market code -> developer name
        Map<String, String> devByCode = new Map<String, String>{
            'GB' => 'GB_Customer_Service_Agents',
            'IE' => 'IE_Customer_Service_Agents',
            'ES' => 'ES_Customer_Service_Agents',
            'IT' => 'IT_Customer_Service_Agents'
        };

        // Resolve all needed groups in one query
        Set<String> neededDev = new Set<String>();
        for (Request r : requests) {
            if (r == null) continue;
            String code = (r.MarketCode == null) ? null : r.MarketCode.trim().toUpperCase();
            if (String.isBlank(code) || !devByCode.containsKey(code)) continue;
            neededDev.add(devByCode.get(code));
        }
        Map<String, Group> groupByDev = new Map<String, Group>();
        if (!neededDev.isEmpty()) {
            for (Group g : [SELECT Id, Name, DeveloperName FROM Group WHERE Type = 'Regular' AND DeveloperName IN :neededDev]) {
                groupByDev.put(g.DeveloperName, g);
            }
        }

        List<GroupMember> toInsert = new List<GroupMember>();
        List<GroupMember> toDelete = new List<GroupMember>();

        // Prepare work by request, validating upfront
        for (Request r : requests) {
            Result res = new Result();
            res.userId = r != null ? r.UserId : null;
            try {
                if (r == null) throw new AuraHandledException('Request cannot be null');
                if (r.UserId == null) throw new AuraHandledException('UserId is required');
                String code = r.MarketCode == null ? null : r.MarketCode.trim().toUpperCase();
                if (String.isBlank(code) || !devByCode.containsKey(code)) {
                    throw new AuraHandledException('MarketCode must be one of: GB, IE, ES, IT');
                }
                String action = r.Action == null ? null : r.Action.trim();
                if (String.isBlank(action)) throw new AuraHandledException('Action is required');
                Boolean doAdd = action.equalsIgnoreCase('Add');
                Boolean doRemove = action.equalsIgnoreCase('Remove');
                if (!(doAdd || doRemove)) throw new AuraHandledException('Action must be Add or Remove');

                Group grp = groupByDev.get(devByCode.get(code));
                if (grp == null) {
                    throw new AuraHandledException('Target Public Group not found for market ' + code + ' (expected DeveloperName ' + devByCode.get(code) + ')');
                }
                res.groupId = grp.Id;

                // Check existing membership
                GroupMember existing = null;
                for (GroupMember gm : [SELECT Id, GroupId, UserOrGroupId FROM GroupMember WHERE GroupId = :grp.Id AND UserOrGroupId = :r.UserId LIMIT 1]) {
                    existing = gm; break;
                }

                if (doAdd) {
                    if (existing == null) {
                        toInsert.add(new GroupMember(GroupId = grp.Id, UserOrGroupId = r.UserId));
                        res.message = 'Planned: Add to group';
                    } else {
                        res.message = 'Already a member';
                    }
                } else if (doRemove) {
                    if (existing != null) {
                        toDelete.add(existing);
                        res.message = 'Planned: Remove from group';
                    } else {
                        res.message = 'Not a current member';
                    }
                }

                res.success = true;
            } catch (Exception ex) {
                res.success = false;
                res.message = ex.getMessage();
            }
            results.add(res);
        }

        // Execute DML in batches
        if (!toInsert.isEmpty()) {
            try { insert toInsert; }
            catch (DmlException d) {
                // propagate individual errors into results where applicable
                for (Integer i = 0; i < results.size(); i++) {
                    Result rr = results[i];
                    if (rr != null && rr.success == true && rr.message == 'Planned: Add to group') {
                        rr.success = false;
                        rr.message = 'Add failed: ' + d.getMessage();
                    }
                }
            }
        }
        if (!toDelete.isEmpty()) {
            try { delete toDelete; }
            catch (DmlException d) {
                for (Integer i = 0; i < results.size(); i++) {
                    Result rr = results[i];
                    if (rr != null && rr.success == true && rr.message == 'Planned: Remove from group') {
                        rr.success = false;
                        rr.message = 'Remove failed: ' + d.getMessage();
                    }
                }
            }
        }

        // Normalize messages
        for (Result rr : results) {
            if (rr == null) continue;
            if (rr.message == 'Planned: Add to group') rr.message = 'Added to group';
            if (rr.message == 'Planned: Remove from group') rr.message = 'Removed from group';
        }

        return results;
    }

    @InvocableMethod(label='Manage Market Group Membership (Payload)')
    public static List<Result> process(List<Payload> payloads) {
        List<Request> reqs = new List<Request>();
        if (payloads != null) {
            for (Payload pl : payloads) {
                if (pl == null || String.isBlank(pl.value)) continue;
                String p = pl.value.trim();
                List<String> parts = p.split('\\|');
                if (parts.isEmpty()) continue;
                Id userId = (Id)parts[0];
                // support both orders, and multi-markets in a comma/semicolon-separated list
                String tokenA = parts.size() > 1 ? parts[1] : null;
                String tokenB = parts.size() > 2 ? parts[2] : null;

                // Determine which token is Action vs Market codes
                // Action expected: Add/Remove (case-insensitive)
                String actionToken = null;
                String marketsToken = null;
                if (tokenA != null && (tokenA.equalsIgnoreCase('Add') || tokenA.equalsIgnoreCase('Remove'))) {
                    actionToken = tokenA;
                    marketsToken = tokenB;
                } else if (tokenB != null && (tokenB.equalsIgnoreCase('Add') || tokenB.equalsIgnoreCase('Remove'))) {
                    actionToken = tokenB;
                    marketsToken = tokenA;
                } else {
                    // fallback: assume tokenA is market code(s), tokenB is action
                    marketsToken = tokenA;
                    actionToken = tokenB;
                }

                List<String> marketCodes = new List<String>();
                if (!String.isBlank(marketsToken)) {
                    // Split by comma or semicolon
                    for (String m : marketsToken.split('[,;]')) {
                        if (!String.isBlank(m)) marketCodes.add(m.trim());
                    }
                }
                if (marketCodes.isEmpty()) marketCodes.add('');

                for (String mc : marketCodes) {
                    Request r = new Request();
                    r.UserId = userId;
                    r.MarketCode = mc;
                    r.Action = actionToken;
                    reqs.add(r);
                }
            }
        }
        return doUpdateGroup(reqs);
    }
}
