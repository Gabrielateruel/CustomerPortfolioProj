public without sharing class PortfolioAncestorsCreateHierarchyBatch implements  Database.Batchable <SObject> , Database.Stateful, Database.AllowsCallouts {
    private Map <Id, UserRole>          allRoles                            = new Map <Id, UserRole> ();
    private map <Id,set<Id>>            roleToAncestors                     = new  map <Id,set<Id>> ();
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        //get all role in the org
        allRoles         = new Map < Id, UserRole > ([SELECT Id, ParentRoleId FROM UserRole]);
        roleToAncestors  = getRoleHierarchyAncestors();
        DateTime fourHoursAgo = System.now().addHours(-4);
        return Database.getQueryLocator([SELECT Id, User__c, UserRole__c, User__r.UserRole.ParentRoleId, ParentContactAccountId__c, Contact__c ,CustomerPortfolioKey__c,Favorite__c FROM CustomerPortfolio__c WHERE Source__c =: 'External'/* AND (CreatedDate >=: fourHoursAgo OR LastModifiedDate >=: fourHoursAgo)*/ ]);
    }
    
    //Creates a map with all roles with respective ancestors 
    public map <Id,set <Id>> getRoleHierarchyAncestors() {
        map <Id, set <Id>> roleToAncestorsHelper = new map <Id,set<Id>> ();
        for (Id roleId: allRoles.keySet()) {
            Set < Id > ancestors = new Set < Id > ();
            Id currentParentId = allRoles.get(roleId).ParentRoleId;
            while (currentParentId != null) {
                ancestors.add(currentParentId);
                currentParentId = allRoles.get(currentParentId)?.ParentRoleId;
            }
            roleToAncestorsHelper.put(roleId, ancestors);
        }
        return roleToAncestorsHelper;
    }
    
    public void execute(Database.BatchableContext bc, List < CustomerPortfolio__c > scope) {
        checkIfPortfolioshasAncestors(scope);
    }
    
    //Execute the logic to create Portfolios to ancestors 
    public void checkIfPortfolioshasAncestors(list<CustomerPortfolio__c> scope){
        set <Id> usersRolesToSearch                                             = new set < Id > ();
        list<CustomerPortofolioWrapper> custPortfoliosToCreate                  = new list<CustomerPortofolioWrapper>();
        
        for (CustomerPortfolio__c iCustPort: scope) {
            //booelan to find if the current role has ancestors on map to create portfolios above
            boolean hasAncestors                  = roleToAncestors.containsKey(iCustPort.User__r.UserRoleId);
            set<Id> ancestorsIdToCreatePortfolios = hasAncestors ? roleToAncestors?.get(iCustPort.User__r.UserRoleId) : new set < id > ();
            
            if (ancestorsIdToCreatePortfolios.isEmpty() == false && ancestorsIdToCreatePortfolios != null) {
                for(Id roleId : ancestorsIdToCreatePortfolios){
                    CustomerPortofolioWrapper newPortfolio = new CustomerPortofolioWrapper(
                        roleId,
                        iCustPort.Contact__c,
                        iCustPort.Favorite__c
                    );
                    custPortfoliosToCreate.add(newPortfolio);
                }
                //add roles of ancestors to query user infos later
                usersRolesToSearch.addAll(ancestorsIdToCreatePortfolios);
                usersRolesToSearch.add(iCustPort.User__r.UserRoleId);
            }
        }
        if(custPortfoliosToCreate.isEmpty() == false) {
            //Creates a map with roles as keys to retrieve the corresponding list of users.
            Map<Id,List<User>> userRoleToUsersMap = getUsersFromRoles(usersRolesToSearch);
            setPortofoliosToCreate(custPortfoliosToCreate ,userRoleToUsersMap);
        }
    }
    
    //create map with roles to get users on it
    public Map <Id,List<User>> getUsersFromRoles(set<Id> usersRolesToSearch) {
        
        Map <Id,List <User>> userRoleToUsersMap = new Map < Id, List < User >> ();
        for (User iUser: [SELECT Id, UserRoleId FROM User WHERE UserRoleId IN: usersRolesToSearch]) {
            if (!userRoleToUsersMap.containsKey(iUser.UserRoleId)) userRoleToUsersMap.put(iUser.UserRoleId, new List < User > ());
            
            userRoleToUsersMap.get(iUser.UserRoleId).add(iUser);
        }
        return userRoleToUsersMap;
    }
    
    //execute logic to create portfolios
    public void setPortofoliosToCreate(list <CustomerPortofolioWrapper> listWrapper,Map<Id,List<User>> userRoleToUsersMap) {
        list<CustomerPortfolio__c> custPortToCreate       = new list<CustomerPortfolio__c>();
        system.debug('listWrapper '+ listWrapper);
        for(CustomerPortofolioWrapper iCutPortToCopy : listWrapper){
            if(userRoleToUsersMap.containsKey(iCutPortToCopy.roleId)){
                for(User iUser : userRoleToUsersMap.get(iCutPortToCopy.roleId)){
                    custPortToCreate.add(setCustomerPortfolioRecord(iUser.Id, iCutPortToCopy.contactId));
                }
            }
        }
        if(custPortToCreate.isEmpty()==false) insertPortfolio(custPortToCreate);
    }
    
    public CustomerPortfolio__c setCustomerPortfolioRecord( Id userId, Id contactId){
        CustomerPortfolio__c newCustPortfolio = new CustomerPortfolio__c(
            User__c    = userId,
            Contact__c = contactId,           
            Source__c  = 'Internal',
            CustomerPortfolioKey__c =  string.valueOf(userId) + string.valueOf(contactId)
        );
        return newCustPortfolio;
    }
    
    public void insertPortfolio(list<CustomerPortfolio__c> custPortToCreate ){
        
        Database.SaveResult[] insertPortfoliosResult = Database.insert(custPortToCreate, false);
        for (Integer i = 0; i < insertPortfoliosResult.size(); i++) {
            if (!insertPortfoliosResult[i].isSuccess()) {
                System.debug('Failed Contact Share Insertion: ' + insertPortfoliosResult[i].getErrors()[0].getMessage());
                System.debug('Send Email To Tech Lead with Failed and Save on Log Object');
            }
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        Database.executeBatch(new CustomerPortfolioSecondaryBatch(), 200);
    }
}
