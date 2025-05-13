public class PortfolioAncestorsDeletHierarchyBatch implements Database.Batchable < SObject > , Database.Stateful, Database.AllowsCallouts {
    private set<Id> parentRolesId            = new set<Id>();
    private set<Id> lowerRolesInHierarchy    = new set<Id>(); 
    private Map<Id, Set<Id>> roleToAncestors = new Map<Id, Set<Id>>();
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        //Build all role necessary roles hierarchy 
        List<UserRole> roleList = [SELECT Id, ParentRoleId FROM UserRole];
        parentRolesId           = getParentRoles(roleList);
        lowerRolesInHierarchy   = getLowerHierarchies(roleList,parentRolesId);
        roleToAncestors = getAncestorHierarchy(roleList);
        //Retrieves all Contacts to Compare with existing Portfolios
        return Database.getQueryLocator([SELECT Id FROM Contact]);
    }
    
    public void execute(Database.BatchableContext bc, List <Contact> scope) {
        //gets a set all Contacts to retrieve with existing Portfolios
        if(scope.isEmpty()==false){
            set<Id> customersId = setCustomerIds(scope);
            List < CustomerPortfolio__c > allPortfolios = [SELECT Id, User__c, Contact__c, Source__c, CustomerPortfolio__c.User__r.UserRoleId,User__r.UserRole.ParentRoleId FROM CustomerPortfolio__c WHERE Contact__c IN: customersId];
            //Call method to delete portfolios in upper Hierarchy
            if(!allPortfolios.isEmpty()) getPortfoliosToDeleteInUpperHierarchy(allPortfolios,customersId);
        }
    }
    //Creates a set all Contacts to Compare with existing Portfolios
    public set<Id> setCustomerIds(List<Contact> scope){
        set<Id> customersId = new set<Id>();
        for(Contact iCon : scope) customersId.add(iCon.Id);
        return customersId;
    }
    //Creates a set with all parent roles from org
    public set<Id> getParentRoles(List<UserRole> roleList){
        Set<Id> allLowerRoleIds = new Set <Id> ();
        for (UserRole role: roleList) {
            if (role.ParentRoleId != null) {
                parentRolesId.add(role.ParentRoleId);
            }
        }
        return parentRolesId;
    }
    // get all roles that in the bottom of the hierarchy
    public set<Id> getLowerHierarchies(List<UserRole> allRoleList, set<id> allParentRolesId){
        Set<Id> allLowerRoleIds = new Set <Id> ();
        for (UserRole role: allRoleList) allLowerRoleIds.add(role.Id);
        allLowerRoleIds.removeAll(allParentRolesId);
        return allLowerRoleIds;
    }
    // get all portoflios with upper roles 
    public void getPortfoliosToDeleteInUpperHierarchy(List<CustomerPortfolio__c> allPortfolios, set<Id> customersId ){
        map<Id,set<Id>> existingConsWithRoles = new  map<Id,set<Id>>();
        map<Id,set<Id>> contactsToLowerRolesToNotDelete = new map<Id,set<Id>> ();
        
        for(CustomerPortfolio__c  iCustPort : allPortfolios){
            if(lowerRolesInHierarchy.contains(iCustPort.User__r.UserRoleId)){
                //Removes contacts that exist in the database for lower hierarchies (the lower hierarchy determines who will have access above).
                customersId.remove(iCustPort.Contact__c);
                //Creates a map with the lower roles that has contact in Portfolios
                if(!contactsToLowerRolesToNotDelete.containsKey(iCustPort.User__r.UserRoleId)) contactsToLowerRolesToNotDelete.put(iCustPort.User__r.UserRoleId,new set<Id>{});
                contactsToLowerRolesToNotDelete.get(iCustPort.User__r.UserRoleId).add(iCustPort.Contact__c);
            }
        }
        
        map<Id,set<Id>> parentRolesWithContactsToDelete = new map<Id,set<Id>> ();
        //Creates a map with upper hierarchy from lower roles with the respective contacts that exisits on database, that will help to know which role above should be deleted to each contact.
        for(Id roleId : contactsToLowerRolesToNotDelete.keySet()){
            for(Id parentRole : roleToAncestors.get(roleId)){
                if(!parentRolesWithContactsToDelete.containsKey(parentRole)) parentRolesWithContactsToDelete.put(parentRole,new set<Id>());
                parentRolesWithContactsToDelete.get(parentRole).addAll(contactsToLowerRolesToNotDelete.get(roleId));
            }
        }
        //Now compares what exists in the database with the upper hierarchy to determine what should be deleted.
        list<CustomerPortfolio__c> cpToDelete = new list<CustomerPortfolio__c>();
        for(CustomerPortfolio__c  iCustPort : allPortfolios){
            if(parentRolesId.contains(iCustPort.User__r.UserRoleId) && customersId.contains(iCustPort.Contact__c) && iCustPort.Source__c == 'Internal' ){
                if(parentRolesWithContactsToDelete.get(iCustPort.User__r.UserRoleId).contains(iCustPort.Contact__c)==false){
                    cpToDelete.add(iCustPort);
                }
            }
        }      //Calls delete method.
        if(cpToDelete.isEmpty()==false) finalDeletePortfolios(cpToDelete);
    }
    
    //Creates the map to get ancestors roles 
    public Map<Id, Set<Id>> getAncestorHierarchy(list<UserRole> allRoleList) {
        Map<Id, Set<Id>> roleToAncestors = new Map<Id, Set<Id>>();
        Map<Id, Id> roleParentMap = new Map<Id, Id>();
        for (UserRole role : allRoleList) roleParentMap.put(role.Id, role.ParentRoleId);
        for (Id roleId : roleParentMap.keySet()) {
            Set<Id> ancestors = new Set<Id>();
            Id currentParentId = roleParentMap?.get(roleId);
            while (currentParentId != null) {
                ancestors.add(currentParentId);
                currentParentId = roleParentMap?.get(currentParentId);
            }
            roleToAncestors.put(roleId, ancestors);
        }
        return roleToAncestors;
    }
    
    public void finalDeletePortfolios(list<CustomerPortfolio__c> cpToDelete){
        Database.DeleteResult[] deletedPortfoliosResults = Database.delete(cpToDelete, false);
        for (Integer i = 0; i < deletedPortfoliosResults.size(); i++) {
            if (!deletedPortfoliosResults[i].isSuccess()) {
                System.debug('Failed Portfolios Deletion: ' + deletedPortfoliosResults[i].getErrors()[0].getMessage());
                System.debug('Send Email To Tech Lead with Failed');
            }
        }
    } 
    
    public void finish(Database.BatchableContext bc) {
        Database.executeBatch(new PortfolioAccessShareBatch(), 200);
    }
    
    
}
