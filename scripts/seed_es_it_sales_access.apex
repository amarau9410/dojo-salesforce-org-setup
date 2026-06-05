String stamp = Datetime.now().format('yyyyMMddHHmmss');

List<Account> accounts = new List<Account>{
    new Account(Name = 'ES Access Test Account ' + stamp, MarketId__c = 'ES', Market_Id__c = 'ES'),
    new Account(Name = 'IT Access Test Account ' + stamp, MarketId__c = 'IT', Market_Id__c = 'IT')
};

Database.SaveResult[] accountResults = Database.insert(accounts, false);
for (Integer i = 0; i < accountResults.size(); i++) {
    if (accountResults[i].isSuccess()) {
        System.debug('CREATED Account: ' + accountResults[i].getId() + ' | Name=' + accounts[i].Name);
    } else {
        for (Database.Error err : accountResults[i].getErrors()) {
            System.debug('FAILED Account: ' + accounts[i].Name + ' | ' + err.getStatusCode() + ' | ' + err.getMessage());
        }
    }
}

List<Contact> contacts = new List<Contact>();
for (Integer i = 0; i < accountResults.size(); i++) {
    if (accountResults[i].isSuccess()) {
        contacts.add(new Contact(
            LastName = (i == 0 ? 'ES' : 'IT') + ' Access Test Contact ' + stamp,
            AccountId = accountResults[i].getId()
        ));
    }
}

Database.SaveResult[] contactResults = Database.insert(contacts, false);
for (Integer i = 0; i < contactResults.size(); i++) {
    if (contactResults[i].isSuccess()) {
        System.debug('CREATED Contact: ' + contactResults[i].getId() + ' | LastName=' + contacts[i].LastName);
    } else {
        for (Database.Error err : contactResults[i].getErrors()) {
            System.debug('FAILED Contact: ' + contacts[i].LastName + ' | ' + err.getStatusCode() + ' | ' + err.getMessage());
        }
    }
}

List<Lead> leads = new List<Lead>{
    new Lead(LastName = 'ES Access Test Lead ' + stamp, Company = 'Dojo Test Co', Market_Id__c = 'ES'),
    new Lead(LastName = 'IT Access Test Lead ' + stamp, Company = 'Dojo Test Co', Market_Id__c = 'IT')
};

Database.SaveResult[] leadResults = Database.insert(leads, false);
for (Integer i = 0; i < leadResults.size(); i++) {
    if (leadResults[i].isSuccess()) {
        System.debug('CREATED Lead: ' + leadResults[i].getId() + ' | LastName=' + leads[i].LastName);
    } else {
        for (Database.Error err : leadResults[i].getErrors()) {
            System.debug('FAILED Lead: ' + leads[i].LastName + ' | ' + err.getStatusCode() + ' | ' + err.getMessage());
        }
    }
}

List<Opportunity> opportunities = new List<Opportunity>();
if (accountResults.size() > 0 && accountResults[0].isSuccess()) {
    opportunities.add(new Opportunity(
        Name = 'ES Access Test Opportunity ' + stamp,
        StageName = 'Qualification',
        CloseDate = Date.today().addDays(30),
        AccountId = accountResults[0].getId(),
        CurrencyIsoCode = 'EUR'
    ));
}
if (accountResults.size() > 1 && accountResults[1].isSuccess()) {
    opportunities.add(new Opportunity(
        Name = 'IT Access Test Opportunity ' + stamp,
        StageName = 'Qualification',
        CloseDate = Date.today().addDays(30),
        AccountId = accountResults[1].getId(),
        CurrencyIsoCode = 'EUR'
    ));
}

Database.SaveResult[] oppResults = Database.insert(opportunities, false);
for (Integer i = 0; i < oppResults.size(); i++) {
    if (oppResults[i].isSuccess()) {
        System.debug('CREATED Opportunity: ' + oppResults[i].getId() + ' | Name=' + opportunities[i].Name);
    } else {
        for (Database.Error err : oppResults[i].getErrors()) {
            System.debug('FAILED Opportunity: ' + opportunities[i].Name + ' | ' + err.getStatusCode() + ' | ' + err.getMessage());
        }
    }
}

List<ApplicationForm> applicationForms = new List<ApplicationForm>();
if (accountResults.size() > 0 && accountResults[0].isSuccess() && oppResults.size() > 0 && oppResults[0].isSuccess()) {
    applicationForms.add(new ApplicationForm(
        AccountId = accountResults[0].getId(),
        OpportunityId = oppResults[0].getId()
    ));
}
if (accountResults.size() > 1 && accountResults[1].isSuccess() && oppResults.size() > 1 && oppResults[1].isSuccess()) {
    applicationForms.add(new ApplicationForm(
        AccountId = accountResults[1].getId(),
        OpportunityId = oppResults[1].getId()
    ));
}

Database.SaveResult[] appResults = Database.insert(applicationForms, false);
for (Integer i = 0; i < appResults.size(); i++) {
    if (appResults[i].isSuccess()) {
        System.debug('CREATED ApplicationForm: ' + appResults[i].getId() + ' | AccountId=' + applicationForms[i].AccountId);
    } else {
        for (Database.Error err : appResults[i].getErrors()) {
            System.debug('FAILED ApplicationForm: AccountId=' + applicationForms[i].AccountId + ' | ' + err.getStatusCode() + ' | ' + err.getMessage());
        }
    }
}

List<SBQQ__Quote__c> quotes = new List<SBQQ__Quote__c>();
for (Integer i = 0; i < oppResults.size(); i++) {
    if (oppResults[i].isSuccess()) {
        quotes.add(new SBQQ__Quote__c(
            SBQQ__Opportunity2__c = oppResults[i].getId(),
            TerritoryAssignment__c = opportunities[i].Name.startsWith('ES') ? 'ES' : 'IT'
        ));
    }
}

Database.SaveResult[] quoteResults = Database.insert(quotes, false);
for (Integer i = 0; i < quoteResults.size(); i++) {
    if (quoteResults[i].isSuccess()) {
        System.debug('CREATED SBQQ__Quote__c: ' + quoteResults[i].getId() + ' | Territory=' + quotes[i].TerritoryAssignment__c);
    } else {
        for (Database.Error err : quoteResults[i].getErrors()) {
            System.debug('FAILED SBQQ__Quote__c: Territory=' + quotes[i].TerritoryAssignment__c + ' | ' + err.getStatusCode() + ' | ' + err.getMessage());
        }
    }
}

System.debug('DONE: seed_es_it_sales_access.apex');
