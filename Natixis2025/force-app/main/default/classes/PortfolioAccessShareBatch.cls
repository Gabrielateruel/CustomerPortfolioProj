public class PortfolioAccessShareBatch implements  Database.Batchable <SObject> , Database.Stateful, Database.AllowsCallouts {
    private list<AccountShare> newAccountShares    = new List<AccountShare>();
    private list<ContactShare> newContactShares    = new List<ContactShare>();
    private list<AccountShare> deleteAccountShares = new List<AccountShare>();
    private list<ContactShare> deleteContactShares = new List<ContactShare>();
    
    public Database.QueryLocator start(Database.BatchableContext bc){
        // Retrieves all created and deleted records to manage AccessSharing
        return Database.getQueryLocator([SELECT Id,	User__c,UserRole__c,User__r.UserRole.ParentRoleId,ParentContactAccountId__c , Contact__c,IsDeleted FROM CustomerPortfolio__c ALL ROWS ]);
    }
    
    public void execute(Database.BatchableContext bc, List<CustomerPortfolio__c> scope){
        // Executes deletion and creation of AccessSharing
        if(scope.isEmpty()==false)  deleteAccesses(scope);
        if(scope.isEmpty()==false)  executeAccessShareCreation(scope);
    }
    
    // Retrieves all users with Accounts and Contacts from deleted Portfolios to remove AccessSharing
    public void deleteAccesses(List<CustomerPortfolio__c> scope){
        map<Id,set<Id>> userWithAccountsAndContactsToDelete = new map<Id,set<Id>>();
        // If the record is deleted, add the user’s current Contacts and Accounts to the map for access removal
        for (CustomerPortfolio__c iCustomerPortf : scope) {
            if(iCustomerPortf.isDeleted == true){
                if(!userWithAccountsAndContactsToDelete.containsKey(iCustomerPortf.User__c)) userWithAccountsAndContactsToDelete.put(iCustomerPortf.User__c, new set<Id>{} );
                userWithAccountsAndContactsToDelete.get(iCustomerPortf.User__c).add(iCustomerPortf.Contact__c);
                userWithAccountsAndContactsToDelete.get(iCustomerPortf.User__c).add(iCustomerPortf.ParentContactAccountId__c);
            }
        }
        // If there are users with Accounts and/or Contacts to remove access, call methods to search for AccessSharing records to delete
        if(userWithAccountsAndContactsToDelete.isEmpty() == false){
            getAccAccessToDelete( userWithAccountsAndContactsToDelete);
            getContactAccessToDelete( userWithAccountsAndContactsToDelete);
        }
        
        
    }
    //Searches AccountShares to delete matching user and Customers to delete
    public void getAccAccessToDelete(map<Id,set<Id>> userWithAccountsAndContactsToDelete){
        Set<Id> accountsToRemove = new Set<Id>();
        for(set<Id> accIdsSet : userWithAccountsAndContactsToDelete.values()) accountsToRemove.addAll(accIdsSet);
        for(AccountShare iAccShare : [SELECT Id, AccountId,UserOrGroupId FROM AccountShare WHERE UserOrGroupId IN :userWithAccountsAndContactsToDelete.keySet() AND AccountId IN :accountsToRemove AND RowCause = 'Manual' AND Id NOT IN: deleteAccountShares ]){
            if(userWithAccountsAndContactsToDelete.containsKey(iAccShare.UserOrGroupId)){
                if(userWithAccountsAndContactsToDelete.get(iAccShare.UserOrGroupId).contains(iAccShare.AccountId)) deleteAccountShares.add(iAccShare);
            }
            
        }
    }
    // Searches for ContactShare records to delete that match users and Customers
    public void getContactAccessToDelete(map<Id,set<Id>> userWithAccountsAndContactsToDelete){
        Set<Id> contactsToRemove = new Set<Id>();
        for(set<Id> accIdsSet : userWithAccountsAndContactsToDelete.values()) contactsToRemove.addAll(accIdsSet);
        for(ContactShare iConShare : [SELECT Id, ContactId, UserOrGroupId FROM ContactShare WHERE UserOrGroupId IN :userWithAccountsAndContactsToDelete.keySet() AND ContactId IN :contactsToRemove AND RowCause = 'Manual' AND Id NOT IN: deleteContactShares ]){
            if(userWithAccountsAndContactsToDelete.containsKey(iConShare.UserOrGroupId)){
                if(userWithAccountsAndContactsToDelete.get(iConShare.UserOrGroupId).contains(iConShare.ContactId)) deleteContactShares.add(iConShare);
            }
        }
    }
    // Handles AccessShare creation logic by retrieving users with Accounts and Contacts that require access sharing
    public void executeAccessShareCreation(list<CustomerPortfolio__c> triggerNew ) {
        map<Id,set<Id>>    getCustomerByUserKey                    = returnUsersWithCustomersInPortfolios(triggerNew);
        set<Id>            customersIds                            = returnSetOfCustomers(getCustomerByUserKey);
        map<Id,set<Id>>    getExistingAccSharingByUser             = getExistingAccountsSharingByUserAndCustomers(customersIds, getCustomerByUserKey.keySet());
        map<Id,set<Id>>    getExistingexistingContactSharingByUser = getExistingContactsSharingByUserAndCustomers(customersIds, getCustomerByUserKey.keySet());
        list<AccountShare> accShareToCreate                        = getAccountsSharingToCreate(triggerNew, getExistingAccSharingByUser);
        list<ContactShare> contactShareToCreate                    = getContactsSharingToCreate(triggerNew, getExistingAccSharingByUser);
        if(accShareToCreate.isEmpty() == false) newAccountShares.addAll(accShareToCreate);
        if(contactShareToCreate.isEmpty() == false) newContactShares.addAll(contactShareToCreate);
    }
    // Creates a map where users are keys and associated Accounts and Contacts are stored in sets for access sharing
    public map<Id,set<Id>> returnUsersWithCustomersInPortfolios(list<CustomerPortfolio__c> triggerNew){
        map<Id,set<Id>> getCustomerByUser = new  map<Id,set<Id>>();
        for(CustomerPortfolio__c iCustPort : triggerNew){
            if(iCustPort.isDeleted == false){
                if(!getCustomerByUser.containsKey(iCustPort.User__c)) getCustomerByUser.put(iCustPort.User__c,new set<Id>());
                getCustomerByUser.get(iCustPort.User__c).add(iCustPort.Contact__c);
                getCustomerByUser.get(iCustPort.User__c).add(iCustPort.ParentContactAccountId__c);
            }
        }
        return getCustomerByUser;
    }
    // Retrieves user IDs from the map to query AccessSharing in the database
    public set<Id> returnSetOfCustomers( map<Id,set<Id>> getCustomerByUser){
        set<Id> customersIds = new set<Id> ();
        for(set<Id> iCustomersIds : getCustomerByUser.values()) customersIds.addAll(iCustomersIds);
        return customersIds;
    }
    // Retrieves existing AccountShare records to prevent duplicate access sharing Exception 
    public map<Id,set<Id>> getExistingAccountsSharingByUserAndCustomers(set<Id> targetAccountIds, set<id> userTargetIds){
        map<Id,set<Id>> usersWithAccess = new map<Id,set<Id>>();
        for(AccountShare iAccShare : [SELECT UserOrGroupId,AccountId FROM AccountShare WHERE AccountId IN :targetAccountIds AND UserOrGroupId IN: userTargetIds]){
            if(!usersWithAccess.containsKey(iAccShare.UserOrGroupId)) usersWithAccess.put(iAccShare.UserOrGroupId, new set<Id>{});
            usersWithAccess.get(iAccShare.UserOrGroupId).add(iAccShare.AccountId);
        }
        return usersWithAccess;
    }
    // Retrieves existing ContactShare records to prevent duplicate access sharing Exception 
    public map<Id,set<Id>> getExistingContactsSharingByUserAndCustomers(set<Id> targetContactIds, set<id> userTargetIds){
        map<Id,set<Id>> usersWithAccess = new map<Id,set<Id>>();
        for(ContactShare iConShare : [SELECT UserOrGroupId,ContactId FROM ContactShare WHERE ContactId IN :targetContactIds AND UserOrGroupId IN: userTargetIds]){
            if(! usersWithAccess.containsKey(iConShare.UserOrGroupId))  usersWithAccess.put(iConShare.UserOrGroupId, new set<Id>{});
            usersWithAccess.get(iConShare.UserOrGroupId).add(iConShare.ContactId);
        }
        return usersWithAccess;
    }
    // Compares new portfolios against existing access shares to determine which AccountShares need to be created
    public list<AccountShare> getAccountsSharingToCreate (list<CustomerPortfolio__c> triggerNew, map<Id,set<Id>> getExistingAccSharingByUser){
        list<AccountShare> accShareToCreate = new list<AccountShare>();
        for(CustomerPortfolio__c iCustPort : triggerNew){
            if(iCustPort.isDeleted == false){
                if(getExistingAccSharingByUser.containsKey(iCustPort.User__c)){
                    if(!getExistingAccSharingByUser.get(iCustPort.User__c).contains(iCustPort.ParentContactAccountId__c))accShareToCreate.add(setAccShareRecord(iCustPort.User__c, iCustPort.ParentContactAccountId__c));
                } else accShareToCreate.add(setAccShareRecord(iCustPort.User__c, iCustPort.ParentContactAccountId__c));
            }
        }
        return accShareToCreate;
    }
    // Compares new portfolios against existing access shares to determine which ´ContactShares need to be created
    public list<ContactShare> getContactsSharingToCreate (list<CustomerPortfolio__c> triggerNew, map<Id,set<Id>> getExistingContactSharingByUser){
        list<ContactShare> contactShareToCreate = new list<ContactShare>();
        for(CustomerPortfolio__c iCustPort : triggerNew){
            if(iCustPort.isDeleted == false){
                if(getExistingContactSharingByUser.containsKey(iCustPort.User__c)){
                    if(!getExistingContactSharingByUser.get(iCustPort.User__c).contains(iCustPort.Contact__c))contactShareToCreate.add(setContactShareRecord(iCustPort.User__c,iCustPort.Contact__c));
                } else contactShareToCreate.add(setContactShareRecord(iCustPort.User__c,iCustPort.Contact__c ));
            }
        }
        return contactShareToCreate;
    }
    
    //Construct AccountShare Object **Attention OpportunityAccessLevel is needed to dont get Exceptions**
    public AccountShare setAccShareRecord(Id userId, Id accId){
        AccountShare newAccShare   = new AccountShare(
            AccountAccessLevel     = 'Read',
            AccountId              = accId,
            OpportunityAccessLevel = 'Read', 
            UserOrGroupId          = userId
        );
        return newAccShare;
        
    }
    //Construct ContactShare Object 
    public ContactShare setContactShareRecord(Id userId, Id conId){
        ContactShare newConShare = new ContactShare(
            ContactAccessLevel   = 'Read',
            ContactId            = conId,
            UserOrGroupId        = userId
        );
        return newConShare;
    }
    
    // Insert and delete all records and and handle Exceptions
    public void finish(Database.BatchableContext bc){
        if (!deleteAccountShares.isEmpty()) {
            Database.DeleteResult[] deleteAccountResults = Database.delete(deleteAccountShares, false);
            for (Integer i = 0; i < deleteAccountResults.size(); i++) {
                if (!deleteAccountResults[i].isSuccess()) {
                    System.debug('Failed Account Share Deletion: ' + deleteAccountResults[i].getErrors()[0].getMessage());
                    System.debug('Send Email To Tech Lead with Failed');
                }
            }
        }
        
        if (!deleteContactShares.isEmpty()) {
            Database.DeleteResult[] deleteContactResults = Database.delete(deleteContactShares, false);
            for (Integer i = 0; i < deleteContactResults.size(); i++) {
                if (!deleteContactResults[i].isSuccess()) {
                    System.debug('Failed Contact Share Deletion: ' + deleteContactResults[i].getErrors()[0].getMessage());
                    System.debug('Send Email To Tech Lead with Failed');
                }
            }
        }
        
        if (!newAccountShares.isEmpty()) {
            Database.SaveResult[] insertAccountResults = Database.insert(newAccountShares, false);
            for (Integer i = 0; i < insertAccountResults.size(); i++) {
                if (!insertAccountResults[i].isSuccess()) {
                    System.debug('Failed Account Share Insertion: ' + insertAccountResults[i].getErrors()[0].getMessage());
                    System.debug('Send Email To Tech Lead with Failed');
                }
            }
        }
        
        if (!newContactShares.isEmpty()) {
            Database.SaveResult[] insertContactResults = Database.insert(newContactShares, false);
            for (Integer i = 0; i < insertContactResults.size(); i++) {
                if (!insertContactResults[i].isSuccess()) {
                    System.debug('Failed Contact Share Insertion: ' + insertContactResults[i].getErrors()[0].getMessage());
                    System.debug('Send Email To Tech Lead with Failed');
                }
            }
        }
        
        
    }
    
}
