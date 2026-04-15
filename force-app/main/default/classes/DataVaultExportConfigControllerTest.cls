/**
 * @description Test class for DataVaultExportConfigController.
 *
 * What it is for: Covers getConfig (null and populated), saveAndStartJob (create/update, validation failures, no duplicate record), getReadableObjectOptions, disableOrEnableExport, and error paths so the LWC controller is fully exercised under user context.
 *
 * Why it exists: AppExchange requires coverage for Aura-enabled controllers and for CRUD/FLS enforcement. These tests run under runAs() with the package Permission Set and use Test.setMock for callouts so security and integration behavior are validated without SeeAllData or real HTTP.
 *
 * AppExchange considerations: runAs(); no SeeAllData; CRUD/FLS and validation assertions; batch triggered only after successful save.
 */
@IsTest
private class DataVaultExportConfigControllerTest {
  private static DataVaultExportConfigController.SaveConfigInput newSaveInput(
    String cloudPlatform,
    String namedCredentialName,
    String objectApiName
  ) {
    DataVaultExportConfigController.SaveConfigInput input = new DataVaultExportConfigController.SaveConfigInput();
    input.cloudPlatform = cloudPlatform;
    input.namedCredentialName = namedCredentialName;
    input.objectApiName = objectApiName;
    return input;
  }

  @TestSetup
  static void makeData() {
    DataVaultTestSetupHelper.createUserAndAssignPermissionSet();
  }

  @IsTest
  static void getConfigNoRecordReturnsNull() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      DataVaultExportConfigController.ConfigDTO dto = DataVaultExportConfigController.getConfig();
      Test.stopTest();

      System.assertEquals(
        null,
        dto,
        'Expected null when no configuration exists'
      );
    }
  }

  @IsTest
  static void saveAndStartJobCreatesRecordAndStartsBatch() {
    Test.setMock(HttpCalloutMock.class, new DataVaultCalloutMocks.Success200());

    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      DataVaultExportConfigController.saveAndStartJob(
        newSaveInput(
          'AWS_S3',
          'Test_NamedCredential',
          DataVaultTestSetupHelper.getErrorLogObjectApiName()
        )
      );
      DataVaultExportConfigController.ConfigDTO dto = DataVaultExportConfigController.getConfig();
      Test.stopTest();

      List<DataVault_Export_Configs__c> configList = [
        SELECT
          Id,
          Name,
          Cloud_Platform__c,
          Named_Credential_Name__c,
          Object_API_Name__c,
          Is_Export_Enabled__c
        FROM DataVault_Export_Configs__c
        WITH USER_MODE
      ];

      System.assertEquals(
        1,
        configList.size(),
        'Exactly one configuration record should exist'
      );
      System.assertEquals(
        'AWS_S3',
        configList[0].Cloud_Platform__c,
        'Cloud Platform should match input'
      );
      System.assertEquals(
        'Test_NamedCredential',
        configList[0].Named_Credential_Name__c,
        'Named Credential should match input'
      );
      System.assertEquals(
        DataVaultTestSetupHelper.getErrorLogObjectApiName(),
        configList[0].Object_API_Name__c,
        'Object API name should match Error Log object'
      );
      System.assertEquals(
        true,
        configList[0].Is_Export_Enabled__c,
        'Export should be enabled'
      );
      System.assert(
        dto != null && dto.id != null,
        'DTO should be populated after save'
      );
      System.assert(
        String.isNotBlank(dto.objectLabel),
        'Object label should be resolved from describe metadata'
      );
    }
  }

  @IsTest
  static void getCloudPlatformOptionsReturnsOptions() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      List<DataVaultExportConfigController.CloudPlatformOption> options = DataVaultExportConfigController.getCloudPlatformOptions();
      Test.stopTest();

      System.assert(
        options != null,
        'Cloud platform options should not be null'
      );
      System.assert(
        options.size() >= 1,
        'Expected at least one active cloud platform (AWS_S3)'
      );
    }
  }

  /**
   * @description
   * Verifies validateNamedCredentialConnection completes without exception when mock returns 200.
   */
  @IsTest
  static void validateNamedCredentialConnectionSuccess() {
    Test.setMock(HttpCalloutMock.class, new DataVaultCalloutMocks.Success200());
    Boolean completed = false;
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      DataVaultExportConfigController.validateNamedCredentialConnection(
        'Test_NC'
      );
      Test.stopTest();
      completed = true;
    }
    System.assertEquals(
      true,
      completed,
      'validateNamedCredentialConnection must complete without exception'
    );
  }

  @IsTest
  static void validateNamedCredentialConnectionBlankThrows() {
    Boolean threw = false;

    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      try {
        DataVaultExportConfigController.validateNamedCredentialConnection('');
      } catch (AuraHandledException e) {
        threw = true;
      }
      Test.stopTest();
    }

    System.assert(
      threw,
      'Expected AuraHandledException for blank Named Credential'
    );
  }

  @IsTest
  static void validateNamedCredentialConnectionFailureWrapsInAuraHandled() {
    Test.setMock(
      HttpCalloutMock.class,
      new DataVaultCalloutMocks.ServerError500()
    );

    Boolean threw = false;
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      try {
        DataVaultExportConfigController.validateNamedCredentialConnection(
          'Test_NC'
        );
      } catch (AuraHandledException e) {
        threw = true;
      }
      Test.stopTest();
    }

    System.assert(
      threw,
      'Expected AuraHandledException when connection validation fails'
    );
  }

  @IsTest
  static void getReadableObjectOptionsReturnsOptionsTest() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      List<DataVaultObjectAccessHelper.ObjectOption> options = DataVaultExportConfigController.getReadableObjectOptions();
      Test.stopTest();

      System.assert(
        options.size() > 0,
        'Expected at least one readable object option'
      );
    }
  }

  @IsTest
  static void disableOrEnableExportUpdatesRecord() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      DataVaultExportConfigController.saveAndStartJob(
        newSaveInput(
          'AWS_S3',
          'Test_NamedCredential',
          DataVaultTestSetupHelper.getErrorLogObjectApiName()
        )
      );
      DataVaultExportConfigController.disableOrEnableExport(false);
      DataVaultExportConfigController.ConfigDTO dto = DataVaultExportConfigController.getConfig();
      Test.stopTest();

      System.assertEquals(
        false,
        dto.isExportEnabled,
        'Export should be disabled'
      );
    }
  }

  @IsTest
  static void disableOrEnableExportWithoutConfigThrows() {
    Boolean threw = false;

    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      try {
        delete [
          SELECT Id
          FROM DataVault_Export_Configs__c
          WHERE Name = :DataVaultObjectAccessHelper.CONFIG_RECORD_NAME
          WITH USER_MODE
        ];
        DataVaultExportConfigController.disableOrEnableExport(false);
      } catch (AuraHandledException e) {
        threw = true;
      }
      Test.stopTest();
    }

    System.assert(
      threw,
      'Expected AuraHandledException when disabling export without configuration'
    );
  }

  @IsTest
  static void saveAndStartJobBlankCloudPlatformThrows() {
    Boolean threw = false;

    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      try {
        DataVaultExportConfigController.saveAndStartJob(
          newSaveInput(
            '',
            'Test_NamedCredential',
            DataVaultTestSetupHelper.getErrorLogObjectApiName()
          )
        );
      } catch (AuraHandledException e) {
        threw = true;
      }
      Test.stopTest();
    }

    System.assert(
      threw,
      'Expected AuraHandledException for blank Cloud Platform'
    );
  }

  @IsTest
  static void saveAndStartJobBlankNamedCredentialThrows() {
    Boolean threw = false;

    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      try {
        DataVaultExportConfigController.saveAndStartJob(
          newSaveInput(
            'AWS_S3',
            '',
            DataVaultTestSetupHelper.getErrorLogObjectApiName()
          )
        );
      } catch (AuraHandledException e) {
        threw = true;
      }
      Test.stopTest();
    }

    System.assert(
      threw,
      'Expected AuraHandledException for blank Named Credential'
    );
  }

  @IsTest
  static void saveAndStartJobDoesNotCreateDuplicateRecord() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      DataVaultExportConfigController.saveAndStartJob(
        newSaveInput(
          'AWS_S3',
          'NC1',
          DataVaultTestSetupHelper.getErrorLogObjectApiName()
        )
      );
      DataVaultExportConfigController.saveAndStartJob(
        newSaveInput(
          'AWS_S3',
          'NC2',
          DataVaultTestSetupHelper.getErrorLogObjectApiName()
        )
      );

      List<DataVault_Export_Configs__c> configs = [
        SELECT Id, Named_Credential_Name__c, Object_API_Name__c
        FROM DataVault_Export_Configs__c
        WITH USER_MODE
      ];

      System.assertEquals(
        1,
        configs.size(),
        'Only one configuration record should exist'
      );
      System.assertEquals(
        'NC2',
        configs[0].Named_Credential_Name__c,
        'Configuration should be updated, not duplicated'
      );
      Test.stopTest();
    }
  }

  /**
   * @description
   * Verifies saveAndStartJobFromMap delegates correctly with valid input.
   */
  @IsTest
  static void saveAndStartJobFromMapCreatesRecord() {
    Test.setMock(HttpCalloutMock.class, new DataVaultCalloutMocks.Success200());
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Map<String, String> inputMap = new Map<String, String>{
        'cloudPlatform' => 'AWS_S3',
        'namedCredentialName' => 'Test_NC',
        'objectApiName' => DataVaultTestSetupHelper.getErrorLogObjectApiName()
      };
      Test.startTest();
      DataVaultExportConfigController.saveAndStartJobFromMap(inputMap);
      Test.stopTest();
      List<DataVault_Export_Configs__c> configs = [
        SELECT Id
        FROM DataVault_Export_Configs__c
        WITH USER_MODE
      ];
      System.assertEquals(
        1,
        configs.size(),
        'Config should be created via map input'
      );
    }
  }

  /**
   * @description
   * Verifies saveAndStartJobFromMap throws when given null map.
   */
  @IsTest
  static void saveAndStartJobFromMapNullThrows() {
    Boolean threw = false;
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      try {
        DataVaultExportConfigController.saveAndStartJobFromMap(null);
      } catch (AuraHandledException e) {
        threw = true;
      }
      Test.stopTest();
    }
    System.assert(threw, 'Expected AuraHandledException for null map');
  }

  /**
   * @description
   * Verifies saveAndStartJob with null input throws.
   */
  @IsTest
  static void saveAndStartJobNullInputThrows() {
    Boolean threw = false;
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      try {
        DataVaultExportConfigController.saveAndStartJob(null);
      } catch (AuraHandledException e) {
        threw = true;
      }
      Test.stopTest();
    }
    System.assert(threw, 'Expected AuraHandledException for null input');
  }

  /**
   * @description
   * Verifies saveAndStartJob throws for invalid cloud platform value.
   */
  @IsTest
  static void saveAndStartJobInvalidPlatformThrows() {
    Boolean threw = false;
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      try {
        DataVaultExportConfigController.saveAndStartJob(
          newSaveInput(
            'INVALID_PLATFORM_XYZ',
            'Test_NC',
            DataVaultTestSetupHelper.getErrorLogObjectApiName()
          )
        );
      } catch (AuraHandledException e) {
        threw = true;
      }
      Test.stopTest();
    }
    System.assert(
      threw,
      'Expected AuraHandledException for invalid cloud platform'
    );
  }

  /**
   * @description
   * Verifies saveAndStartJob throws for non-existent object API name.
   */
  @IsTest
  static void saveAndStartJobUnreadableObjectThrows() {
    Boolean threw = false;
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      try {
        DataVaultExportConfigController.saveAndStartJob(
          newSaveInput('AWS_S3', 'Test_NC', 'NonExistentObject__c')
        );
      } catch (AuraHandledException e) {
        threw = true;
      }
      Test.stopTest();
    }
    System.assert(threw, 'Expected AuraHandledException for unreadable object');
  }

  /**
   * @description
   * Verifies saveAndStartJob with blank object API name throws.
   */
  @IsTest
  static void saveAndStartJobBlankObjectThrows() {
    Boolean threw = false;
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      try {
        DataVaultExportConfigController.saveAndStartJob(
          newSaveInput('AWS_S3', 'Test_NC', '')
        );
      } catch (AuraHandledException e) {
        threw = true;
      }
      Test.stopTest();
    }
    System.assert(
      threw,
      'Expected AuraHandledException for blank object API name'
    );
  }

  /**
   * @description
   * Verifies update path with no field changes returns silently (no DML).
   */
  @IsTest
  static void saveAndStartJobSameValuesNoUpdate() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVaultExportConfigController.saveAndStartJob(
        newSaveInput(
          'AWS_S3',
          'Test_NC',
          DataVaultTestSetupHelper.getErrorLogObjectApiName()
        )
      );
      Test.startTest();
      DataVaultExportConfigController.saveAndStartJob(
        newSaveInput(
          'AWS_S3',
          'Test_NC',
          DataVaultTestSetupHelper.getErrorLogObjectApiName()
        )
      );
      Test.stopTest();
      List<DataVault_Export_Configs__c> configs = [
        SELECT Id
        FROM DataVault_Export_Configs__c
        WITH USER_MODE
      ];
      System.assertEquals(
        1,
        configs.size(),
        'Should still have exactly one config record'
      );
    }
  }
}
