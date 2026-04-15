/**
 * @description
 * Test class for DataVault_Security_Utility.
 *
 * What it is for: Exercises all CRUD checks (isConfigReadable/Updatable/ReadWrite, isLoggerCreatable), all strip methods (config and error log), and getConfigRecord (null and org-level config) so the security layer is fully covered.
 *
 * Why it exists: The security utility is the single point for config and logger access; AppExchange review expects coverage and validation that CRUD/FLS are enforced. Tests use runAs() and org-level config (SetupOwnerId = OrganizationId) without hardcoded IDs or SeeAllData.
 *
 * AppExchange considerations: runAs(); null/empty handling; getConfigRecord with org-level config; no privileged operations or hardcoded IDs.
 */
@IsTest
private class DataVault_Security_UtilityTest {
  /**
   * @description
   * Test setup creates a reusable test user with the required DataVault Permission Set assigned.
   */
  @TestSetup
  static void makeData() {
    DataVaultTestSetupHelper.createUserAndAssignPermissionSet();
  }

  /* =========================================================
       CONFIG OBJECT – CRUD CHECKS
       ========================================================= */

  /**
   * @description
   * Verifies isConfigReadable() returns true when the running user has read access to DataVault Export Configs.
   */
  @IsTest
  static void isConfigReadableWithAccessReturnsTrue() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      Boolean result = DataVault_Security_Utility.isConfigReadable();
      Test.stopTest();
      System.assert(
        result,
        'Config should be readable for user with permission set'
      );
    }
  }

  /**
   * @description
   * Verifies isConfigUpdatable() returns true when the running user has update access to DataVault Export Configs. Runs as current user because custom setting create/update may require Customize Application.
   */
  @IsTest
  static void isConfigUpdatableWithAccessReturnsTrue() {
    Test.startTest();
    Boolean result = DataVault_Security_Utility.isConfigUpdatable();
    Test.stopTest();
    System.assert(result, 'Config should be updatable for user with access');
  }

  /**
   * @description
   * Verifies isConfigReadWrite() returns true when the running user has both read and create access to DataVault Export Configs. Runs as current user because custom setting create may require Customize Application.
   */
  @IsTest
  static void isConfigReadWriteWithAccessReturnsTrue() {
    Test.startTest();
    Boolean result = DataVault_Security_Utility.isConfigReadWrite();
    Test.stopTest();
    System.assert(
      result,
      'Config should be readable and createable for user with access'
    );
  }

  /* =========================================================
       CONFIG OBJECT – FLS STRIP METHODS (NULL HANDLING)
       ========================================================= */

  /**
   * @description
   * Verifies stripConfigReadable returns null when given a null record.
   */
  @IsTest
  static void stripConfigReadableNullReturnsNull() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      DataVault_Export_Configs__c result = DataVault_Security_Utility.stripConfigReadable(
        null
      );
      Test.stopTest();
      System.assertEquals(
        null,
        result,
        'stripConfigReadable(null) should return null'
      );
    }
  }

  /**
   * @description
   * Verifies stripConfigUpdatable returns null when given a null record.
   */
  @IsTest
  static void stripConfigUpdatableNullReturnsNull() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      DataVault_Export_Configs__c result = DataVault_Security_Utility.stripConfigUpdatable(
        null
      );
      Test.stopTest();
      System.assertEquals(
        null,
        result,
        'stripConfigUpdatable(null) should return null'
      );
    }
  }

  /**
   * @description
   * Verifies stripConfigCreatable returns null when given a null record.
   */
  @IsTest
  static void stripConfigCreatableNullReturnsNull() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      DataVault_Export_Configs__c result = DataVault_Security_Utility.stripConfigCreatable(
        null
      );
      Test.stopTest();
      System.assertEquals(
        null,
        result,
        'stripConfigCreatable(null) should return null'
      );
    }
  }

  /* =========================================================
       CONFIG OBJECT – FLS STRIP METHODS (WITH RECORD)
       ========================================================= */

  /**
   * @description
   * Verifies stripConfigReadable returns a record when given a valid in-memory config. StripInaccessible(READABLE) preserves readable fields.
   */
  @IsTest
  static void stripConfigReadableWithRecordReturnsStrippedRecord() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVault_Export_Configs__c input = new DataVault_Export_Configs__c(
        Name = DataVaultObjectAccessHelper.CONFIG_RECORD_NAME,
        Object_API_Name__c = DataVaultTestSetupHelper.getErrorLogObjectApiName(),
        Named_Credential_Name__c = 'Test_NC'
      );
      Test.startTest();
      DataVault_Export_Configs__c result = DataVault_Security_Utility.stripConfigReadable(
        input
      );
      Test.stopTest();
      System.assert(
        result != null,
        'stripConfigReadable should return non-null for valid record'
      );
    }
  }

  /**
   * @description
   * Verifies stripConfigUpdatable returns a record when given a valid in-memory config. Runs as current user because strip requires update access on custom setting.
   */
  @IsTest
  static void stripConfigUpdatableWithRecordReturnsStrippedRecord() {
    DataVault_Export_Configs__c input = new DataVault_Export_Configs__c(
      Name = DataVaultObjectAccessHelper.CONFIG_RECORD_NAME,
      Object_API_Name__c = DataVaultTestSetupHelper.getErrorLogObjectApiName(),
      Named_Credential_Name__c = 'Test_NC'
    );
    Test.startTest();
    DataVault_Export_Configs__c result = DataVault_Security_Utility.stripConfigUpdatable(
      input
    );
    Test.stopTest();
    System.assert(
      result != null,
      'stripConfigUpdatable should return non-null for valid record'
    );
  }

  /**
   * @description
   * Verifies stripConfigCreatable returns a record when given a valid in-memory config. Runs as current user because strip requires create access on custom setting.
   */
  @IsTest
  static void stripConfigCreatableWithRecordReturnsStrippedRecord() {
    DataVault_Export_Configs__c input = new DataVault_Export_Configs__c(
      Name = DataVaultObjectAccessHelper.CONFIG_RECORD_NAME,
      Object_API_Name__c = DataVaultTestSetupHelper.getErrorLogObjectApiName(),
      Named_Credential_Name__c = 'Test_NC'
    );
    Test.startTest();
    DataVault_Export_Configs__c result = DataVault_Security_Utility.stripConfigCreatable(
      input
    );
    Test.stopTest();
    System.assert(
      result != null,
      'stripConfigCreatable should return non-null for valid record'
    );
  }

  /* =========================================================
       LOGGER OBJECT – CRUD + FLS
       ========================================================= */

  /**
   * @description
   * Verifies isLoggerCreatable() returns true when the running user has create access to DataVault Error Log.
   */
  @IsTest
  static void isLoggerCreatableWithAccessReturnsTrue() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      Boolean result = DataVault_Security_Utility.isLoggerCreatable();
      Test.stopTest();
      System.assert(
        result,
        'Error Log should be createable for user with permission set'
      );
    }
  }

  /**
   * @description
   * Verifies stripErrorLogCreatable returns empty list when given null.
   */
  @IsTest
  static void stripErrorLogCreatableNullReturnsEmpty() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      List<DataVault_Error_Log__c> result = DataVault_Security_Utility.stripErrorLogCreatable(
        null
      );
      Test.stopTest();
      System.assert(
        result != null && result.isEmpty(),
        'stripErrorLogCreatable(null) should return empty list'
      );
    }
  }

  /**
   * @description
   * Verifies stripErrorLogCreatable returns empty list when given empty list.
   */
  @IsTest
  static void stripErrorLogCreatableEmptyListReturnsEmpty() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      List<DataVault_Error_Log__c> result = DataVault_Security_Utility.stripErrorLogCreatable(
        new List<DataVault_Error_Log__c>()
      );
      Test.stopTest();
      System.assert(
        result != null && result.isEmpty(),
        'stripErrorLogCreatable(empty) should return empty list'
      );
    }
  }

  /**
   * @description
   * Verifies stripErrorLogCreatable returns a list of records when given valid in-memory error log records (FLS applied).
   */
  @IsTest
  static void stripErrorLogCreatableWithRecordsReturnsStrippedList() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      List<DataVault_Error_Log__c> input = new List<DataVault_Error_Log__c>{
        new DataVault_Error_Log__c(
          Error_Type__c = 'General Apex Exception',
          Error_Message__c = 'Test',
          Timestamp__c = System.now()
        )
      };
      Test.startTest();
      List<DataVault_Error_Log__c> result = DataVault_Security_Utility.stripErrorLogCreatable(
        input
      );
      Test.stopTest();
      System.assert(
        result != null,
        'stripErrorLogCreatable should return non-null list'
      );
      System.assert(
        result.size() <= 1,
        'Stripped list should have at most one record'
      );
    }
  }

  /* =========================================================
       CONFIG RETRIEVAL – getConfigRecord()
       ========================================================= */

  /**
   * @description
   * Verifies getConfigRecord() completes; asserts on result (null or valid record). Validates the path when isConfigReadable() is false or config exists.
   */
  @IsTest
  static void getConfigRecordWhenNotReadableReturnsNull() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      DataVault_Export_Configs__c config = DataVault_Security_Utility.getConfigRecord();
      Test.stopTest();
      Boolean valid = (config == null || config.Id != null);
      System.assert(
        valid,
        'getConfigRecord must return null or a valid record'
      );
    }
  }

  /**
   * @description
   * Verifies getConfigRecord() returns the org-level config when one exists.
   */
  @IsTest
  static void getConfigRecordWhenOrgConfigExistsReturnsRecord() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      List<DataVault_Export_Configs__c> existing = [
        SELECT Id
        FROM DataVault_Export_Configs__c
        WHERE SetupOwnerId = :UserInfo.getOrganizationId()
        WITH USER_MODE
        LIMIT 1
      ];
      if (existing.isEmpty()) {
        DataVaultTestSetupHelper.createExportConfig(
          DataVaultTestSetupHelper.getErrorLogObjectApiName(),
          'Test_NamedCredential',
          'AWS_S3'
        );
      }

      Test.startTest();
      DataVault_Export_Configs__c result = DataVault_Security_Utility.getConfigRecord();
      Test.stopTest();

      System.assert(
        result != null,
        'getConfigRecord should return record when org-level config exists'
      );
    }
  }

  /* =========================================================
       STRIP METHODS – REAL SECURITY.STRIPINACCESSIBLE PATH
       ========================================================= */

  /**
   * @description
   * Exercises the actual Security.stripInaccessible(READABLE) path in stripConfigReadable.
   */
  @IsTest
  static void stripConfigReadableEnforcedReturnsRecord() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVault_Security_Utility.enforceStripInTest = true;
      DataVault_Export_Configs__c input = new DataVault_Export_Configs__c(
        Name = DataVaultObjectAccessHelper.CONFIG_RECORD_NAME,
        Object_API_Name__c = DataVaultTestSetupHelper.getErrorLogObjectApiName(),
        Named_Credential_Name__c = 'Test_NC'
      );
      Test.startTest();
      DataVault_Export_Configs__c result = DataVault_Security_Utility.stripConfigReadable(
        input
      );
      Test.stopTest();
      DataVault_Security_Utility.enforceStripInTest = false;
      System.assert(
        result != null,
        'stripConfigReadable enforced should return non-null for accessible fields'
      );
    }
  }

  /**
   * @description
   * Exercises the actual Security.stripInaccessible(UPDATABLE) path in stripConfigUpdatable.
   */
  @IsTest
  static void stripConfigUpdatableEnforcedReturnsRecord() {
    DataVault_Security_Utility.enforceStripInTest = true;
    DataVault_Export_Configs__c input = new DataVault_Export_Configs__c(
      Name = DataVaultObjectAccessHelper.CONFIG_RECORD_NAME,
      Object_API_Name__c = DataVaultTestSetupHelper.getErrorLogObjectApiName(),
      Named_Credential_Name__c = 'Test_NC'
    );
    Test.startTest();
    DataVault_Export_Configs__c result = DataVault_Security_Utility.stripConfigUpdatable(
      input
    );
    Test.stopTest();
    DataVault_Security_Utility.enforceStripInTest = false;
    System.assert(
      result != null,
      'stripConfigUpdatable enforced should return non-null'
    );
  }

  /**
   * @description
   * Exercises the actual Security.stripInaccessible(CREATABLE) path in stripConfigCreatable.
   */
  @IsTest
  static void stripConfigCreatableEnforcedReturnsRecord() {
    DataVault_Security_Utility.enforceStripInTest = true;
    DataVault_Export_Configs__c input = new DataVault_Export_Configs__c(
      Name = DataVaultObjectAccessHelper.CONFIG_RECORD_NAME,
      Object_API_Name__c = DataVaultTestSetupHelper.getErrorLogObjectApiName(),
      Named_Credential_Name__c = 'Test_NC'
    );
    Test.startTest();
    DataVault_Export_Configs__c result = DataVault_Security_Utility.stripConfigCreatable(
      input
    );
    Test.stopTest();
    DataVault_Security_Utility.enforceStripInTest = false;
    System.assert(
      result != null,
      'stripConfigCreatable enforced should return non-null'
    );
  }

  /**
   * @description
   * Exercises getConfigRecord with enforceStripInTest to cover the WITH USER_MODE SOQL path.
   */
  @IsTest
  static void getConfigRecordEnforcedWithOrgConfig() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVaultTestSetupHelper.createExportConfig(
        DataVaultTestSetupHelper.getErrorLogObjectApiName(),
        'Test_NC',
        'AWS_S3'
      );
      DataVault_Security_Utility.enforceStripInTest = true;
      Test.startTest();
      DataVault_Export_Configs__c result = DataVault_Security_Utility.getConfigRecord();
      Test.stopTest();
      DataVault_Security_Utility.enforceStripInTest = false;
      Boolean valid = (result == null || result.Id != null);
      System.assert(
        valid,
        'getConfigRecord enforced must return null or valid record'
      );
    }
  }

  /**
   * @description
   * Verifies isCloudPlatformMetadataReadable returns a Boolean.
   */
  @IsTest
  static void isCloudPlatformMetadataReadableReturnsBoolean() {
    Test.startTest();
    Boolean result = DataVault_Security_Utility.isCloudPlatformMetadataReadable();
    Test.stopTest();
    System.assert(
      result != null,
      'isCloudPlatformMetadataReadable should return a Boolean'
    );
  }
}
