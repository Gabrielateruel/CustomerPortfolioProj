public class CustomerPortofolioWrapper {
    public Id roleId;
    public Id contactId;
    public boolean isFavorite;
    
    public CustomerPortofolioWrapper( Id roleId, Id contactId, boolean isFavorite) {
    this.roleId               =  roleId;
    this.contactId            = contactId;
    this.isFavorite           = isFavorite;

    }
}