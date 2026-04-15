/**
 * @description
 * Test utility that centralizes test data setup for DataVault export and error-logging test classes.
 *
 * What it is for:
 *  - Creates test users with unique usernames/emails and assigns the package Permission Set so tests can run under runAs() with realistic CRUD/FLS.
 *  - Creates test DataVault_Error_Log__c records and (where used) export config and Account data so integration and batch tests have predictable data without SeeAllData.
 *
 * Why it exists:
 *  - AppExchange tests must exercise code under user context and respect CRUD/FLS; a single helper that uses USER MODE and the package Permission Set keeps all test classes consistent and avoids duplicate setup. Fail-fast when the Permission Set or required access is missing so packaging and deployment issues are caught early.
 *
 * AppExchange considerations:
 *  - No hardcoded org IDs; no SeeAllData; Permission Set must be in the package; with sharing and USER MODE used throughout.
 */
@IsTest
public with sharing class DataVaultTestSetupHelper {
  /**
   * Prefix used to generate unique test user email addresses.
   *
   * System.currentTimeMillis() is appended to guarantee uniqueness across
   * parallel test execution and repeated deployments.
   */
  private static final String USER_EMAIL_PREFIX = 'DataVault_TEST_USER';

  /**
   * @description
   * Returns the API name for DataVault_Error_Log__c as it appears in Schema (namespace-safe).
   * @return Object API name for DataVault_Error_Log__c (e.g. "DataVault_Error_Log__c" or "Namespace__DataVault_Error_Log__c")
   */
  public static String getErrorLogObjectApiName() {
    Schema.SObjectType token = DataVault_Error_Log__c.SObjectType;
    return token.getDescribe().getName();
  }

  /**
   * @description
   * Creates and inserts the specified number of DataVault_Error_Log__c records for logger/buffer tests. Tests that verify logging or buffer flush need real records without hitting external services.
   * @param count Number of log records to create
   */
  public static void createLogRecords(Integer count) {
    List<DataVault_Error_Log__c> logs = new List<DataVault_Error_Log__c>();
    for (Integer i = 0; i < count; i++) {
      logs.add(
        new DataVault_Error_Log__c(
          Error_Message__c = 'Test Error Message ' + i,
          Error_Type__c = 'General Apex Exception',
          Stack_Trace__c = 'DataVaultTestSetupHelper.createLogRecords',
          Apex_Class_Name__c = 'DataVaultTestSetupHelper',
          Method_Name__c = 'createLogRecords',
          Timestamp__c = System.now()
        )
      );
    }
    insert logs;
  }

  /**
   * @description
   * Creates and inserts a standard test User. Uses the profile from DataVaultTestUserProfileName label; falls back to current user's profile if not found. Generates unique Username and Email. Does not assign Permission Sets (handled by caller).
   * @return Inserted User record
   */
  public static User createUser() {
    Id profileId = getTestUserProfileId();
    User u = new User(
      Alias = 'tuser',
      Email = USER_EMAIL_PREFIX + System.currentTimeMillis() + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'User',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profileId,
      TimeZoneSidKey = 'America/Los_Angeles',
      UserName = 'testuser' + System.currentTimeMillis() + '@example.com'
    );
    insert as User u;
    return u;
  }

  /**
   * @description
   * Returns ProfileId for test user creation. Uses DataVaultTestUserProfileName label; falls back to current user's profile if the label profile is not found.
   * @return Profile Id for the test user
   */
  private static Id getTestUserProfileId() {
    String profileName = System.Label.DataVaultTestUserProfileName;
    if (String.isBlank(profileName)) {
      return UserInfo.getProfileId();
    }
    List<Profile> profiles = [
      SELECT Id
      FROM Profile
      WHERE Name = :profileName
      WITH USER_MODE
      LIMIT 1
    ];
    return profiles.isEmpty() ? UserInfo.getProfileId() : profiles[0].Id;
  }

  /**
   * @description
   * Assigns the DataVault Permission Set to the specified user. Fail-fast if label or Permission Set is missing so test failures indicate missing metadata.
   * @param userId Id of the User to assign the Permission Set to
   * @throws DataVault_PackageException if the Permission Set is not found
   */
  public static void assignPermissionSetIfExists(Id userId) {
    String permissionSetName = System.Label.DataVaultPermissionSetName;
    if (String.isBlank(permissionSetName)) {
      throw new DataVault_PackageException(
        'DataVaultPermissionSetName label is blank.'
      );
    }
    List<PermissionSet> psList = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :permissionSetName
      WITH USER_MODE
      LIMIT 1
    ];

    if (!psList.isEmpty()) {
      PermissionSetAssignment psa = new PermissionSetAssignment(
        AssigneeId = userId,
        PermissionSetId = psList[0].Id
      );
      insert psa;
    } else {
      throw new DataVault_PackageException(
        'Required Permission Set ' + permissionSetName + ' not found'
      );
    }
  }

  /**
   * @description
   * Convenience method that creates a test User and assigns the required DataVault Permission Set.
   * @return Id of the created User
   */
  public static Id createUserAndAssignPermissionSet() {
    User u = createUser();
    assignPermissionSetIfExists(u.Id);
    return u.Id;
  }

  /**
   * @description
   * Retrieves an existing test User created by this helper.
   * @return User record matching the test user email pattern
   * @throws DataVault_PackageException if no matching user is found
   */
  public static User getTestUser() {
    List<User> users = [
      SELECT Id
      FROM User
      WHERE Email LIKE 'DataVault_TEST_USER%'
      LIMIT 1
    ];

    if (users.isEmpty()) {
      throw new DataVault_PackageException('Test user not found');
    }
    return users[0];
  }

  /**
   * @description
   * Creates a test DataVault Export Config record (2-arg overload with default cloud platform).
   * @param objectApiName Object API name for export
   * @param namedCredentialName Named Credential API name
   * @return Created DataVault Export Config record
   */
  public static DataVault_Export_Configs__c createExportConfig(
    String objectApiName,
    String namedCredentialName
  ) {
    return createExportConfig(objectApiName, namedCredentialName, 'AWS_S3');
  }

  /**
   * @description
   * Creates a test DataVault Export Config record. Call inside System.runAs when test needs config. In test context uses system insert so tests do not depend on the test user having create on the custom setting.
   * @param objectApiName Object API name for export
   * @param namedCredentialName Named Credential API name
   * @param cloudPlatform Cloud platform API value (e.g. AWS_S3)
   * @return Created DataVault Export Config record
   */
  public static DataVault_Export_Configs__c createExportConfig(
    String objectApiName,
    String namedCredentialName,
    String cloudPlatform
  ) {
    DataVault_Export_Configs__c config = new DataVault_Export_Configs__c(
      Name = DataVaultObjectAccessHelper.CONFIG_RECORD_NAME,
      Cloud_Platform__c = String.isNotBlank(cloudPlatform)
        ? cloudPlatform
        : 'AWS_S3',
      Object_API_Name__c = objectApiName,
      Named_Credential_Name__c = namedCredentialName,
      Last_Run_Completed__c = null,
      Is_Export_Enabled__c = true
    );
    insert config;
    return config;
  }
}
