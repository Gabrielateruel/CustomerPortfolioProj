public class PortfolioAncestorsCreateHierarchyBatch implements Database.Batchable < SObject > , Database.Stateful, Database.AllowsCallouts {
    private Map <Id, UserRole>          allRoles                            = new Map <Id, UserRole> ();
    private List <CustomerPortfolio__c> custPortToCreate                    = new List <CustomerPortfolio__c> ();
    private set <string>                preventDuplicatesCustomerPortfolios = new set <string> ();
    private map <Id,set<Id>>            roleToAncestors                     = new  map <Id,set<Id>> ();
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        //get all role in the org
        allRoles         = new Map < Id, UserRole > ([SELECT Id, ParentRoleId FROM UserRole]);
        roleToAncestors  = getRoleHierarchyAncestors();
        return Database.getQueryLocator([SELECT Id, User__c, UserRole__c, User__r.UserRole.ParentRoleId, ParentContactAccountId__c, Contact__c ,CustomerPortfolioKey__c FROM CustomerPortfolio__c ]);
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
        map <CustomerPortfolio__c,set<id>> customerPortfoliosWithRolesToCreate  = new map < CustomerPortfolio__c, set < id >> ();
        set <Id> usersRolesToSearch                                             = new set < Id > ();
        
        for (CustomerPortfolio__c iCustPort: scope) {
            //booelan to find if the current role has ancestors on map to create portfolios above
            boolean hasAncestors                  = roleToAncestors.containsKey(iCustPort.User__r.UserRoleId);
            set<Id> ancestorsIdToCreatePortfolios = hasAncestors ? roleToAncestors?.get(iCustPort.User__r.UserRoleId) : new set < id > ();
            
            if (ancestorsIdToCreatePortfolios.isEmpty() == false && ancestorsIdToCreatePortfolios != null) {
                customerPortfoliosWithRolesToCreate.put(iCustPort, ancestorsIdToCreatePortfolios);
                //add roles of ancestors to query user infos later
                usersRolesToSearch.addAll(ancestorsIdToCreatePortfolios);
            }
        }
        
        if(customerPortfoliosWithRolesToCreate.isEmpty() == false) {
            //Creates a map with roles as keys to retrieve the corresponding list of users.
            Map<Id,List<User>> userRoleToUsersMap = getUsersFromRoles(usersRolesToSearch);
            setPortofoliosToCreate(scope, customerPortfoliosWithRolesToCreate,userRoleToUsersMap);
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
    public void setPortofoliosToCreate(List<CustomerPortfolio__c> scope,  map <CustomerPortfolio__c,set<id>> customerPortfoliosWithRolesToCreate,Map<Id,List<User>> userRoleToUsersMap) {
        for (CustomerPortfolio__c iCust: scope) preventDuplicatesCustomerPortfolios.add(iCust.CustomerPortfolioKey__c);
        for (CustomerPortfolio__c iCustPort: customerPortfoliosWithRolesToCreate.keySet()) {
            Set < Id > rolesIdToCreate = customerPortfoliosWithRolesToCreate.get(iCustPort);
            for (Id roleId: rolesIdToCreate) {
                if (userRoleToUsersMap.containsKey(roleId)) {
                    for (User matchingUser: userRoleToUsersMap.get(roleId)) {
                        if (preventDuplicatesCustomerPortfolios.contains(string.valueOf(matchingUser.Id) + string.valueOf(iCustPort.Contact__c)) == false) {
                            addCustPortRecordToCreate(iCustPort, matchingUser.Id);
                        }
                    }
                }
            }
        }
    }
    
    
    public void addCustPortRecordToCreate(CustomerPortfolio__c custPortRecordToCopy, Id matchingUserId){
        CustomerPortfolio__c newCustPortfolio = new CustomerPortfolio__c(
            User__c    = matchingUserId,
            Contact__c = custPortRecordToCopy.Contact__c,
            Source__c  = 'Internal',
            CustomerPortfolioKey__c = string.valueOf(matchingUserId) + string.valueOf(custPortRecordToCopy.Contact__c)
        );
        preventDuplicatesCustomerPortfolios.add(string.valueOf(matchingUserId) + string.valueOf(custPortRecordToCopy.Contact__c));
        custPortToCreate.add(newCustPortfolio);
    }
    
    public void finish(Database.BatchableContext bc) {
        if(custPortToCreate.isEmpty()==false) Database.insert(custPortToCreate, false);
        Database.executeBatch(new PortfolioAncestorsDeletHierarchyBatch(), 200);
    }
}