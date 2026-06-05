List<Account> updates = new List<Account>{
    new Account(Id='001S900001JoPb6IAF', TradingStreet__c='Harbour Lane', TradingHouseNameNumber__c='18', TradingCity__c='Bristol', TradingState__c='Somerset', TradingPostalCode__c='BS1 4DJ', TradingCountryCode__c='GB', TradingLocality__c='Clifton'),
    new Account(Id='001S900001JoPb7IAF', TradingStreet__c='Kingfisher Road', TradingHouseNameNumber__c='42', TradingCity__c='Bath', TradingState__c='Somerset', TradingPostalCode__c='BA1 2LT', TradingCountryCode__c='GB', TradingLocality__c='Lansdown'),
    new Account(Id='001S900001JoPb8IAF', TradingStreet__c='Market Street', TradingHouseNameNumber__c='7', TradingCity__c='Exeter', TradingState__c='Devon', TradingPostalCode__c='EX4 3PQ', TradingCountryCode__c='GB', TradingLocality__c='St David''s'),
    new Account(Id='001S900001JoPb9IAF', TradingStreet__c='Whistle Yard', TradingHouseNameNumber__c='11', TradingCity__c='Cheltenham', TradingState__c='Gloucestershire', TradingPostalCode__c='GL50 1QA', TradingCountryCode__c='GB', TradingLocality__c='Montpellier'),
    new Account(Id='001S900001JoPbAIAV', TradingStreet__c='Station Approach', TradingHouseNameNumber__c='25', TradingCity__c='Cardiff', TradingState__c='South Glamorgan', TradingPostalCode__c='CF10 2GD', TradingCountryCode__c='GB', TradingLocality__c='Butetown'),
    new Account(Id='001S900001Jo85bIAB', TradingStreet__c='Malt House Row', TradingHouseNameNumber__c='3', TradingCity__c='Worcester', TradingState__c='Worcestershire', TradingPostalCode__c='WR1 2EY', TradingCountryCode__c='GB', TradingLocality__c='City Centre')
};
update updates;
System.debug('Updated pretend trading addresses for Green Dragon locations: ' + updates.size());
