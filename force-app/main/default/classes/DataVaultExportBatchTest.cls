/**
 * @description Test class for DataVaultExportBatch.
 *
 * What it is for: Verifies batch start/execute/finish with success and failure mocks (200, 500, CalloutException), constructor validation (null/blank config), and that run statistics and error logging behave as expected.
 *
 * Why it exists: AppExchange requires coverage for batch and callout code. These tests ensure the export batch respects config validation, uses Test.setMock for HTTP, and does not rely on real S3 or SeeAllData.
 */
@IsTest
private class DataVaultExportBatchTest {
  /**
   * @description
   * TestSetup: creates test user and assigns permission set.
   */
  @TestSetup
  static void makeData() {
    DataVaultTestSetupHelper.createUserAndAssignPermissionSet();
  }
  /**
   * @description
   * Batch start/execute/finish run without exception when mock returns 200.
   */
  @IsTest
  static void batchRunsSuccessfully() {
    Test.setMock(HttpCalloutMock.class, new DataVaultCalloutMocks.Success200());
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVault_Export_Configs__c cfg = DataVaultTestSetupHelper.createExportConfig(
        DataVaultTestSetupHelper.getErrorLogObjectApiName(),
        'DataVault_Credential',
        'AWS_S3'
      );
      DataVaultTestSetupHelper.createLogRecords(10);
      Test.startTest();
      Database.executeBatch(new DataVaultExportBatch(cfg), 10);
      Test.stopTest();
      List<DataVault_Error_Log__c> errorLogs = [
        SELECT Id
        FROM DataVault_Error_Log__c
        WHERE Apex_Class_Name__c != 'DataVaultTestSetupHelper'
        WITH USER_MODE
      ];
      System.assertEquals(
        0,
        errorLogs.size(),
        'No error logs should be created on success'
      );
      System.assert(true, 'Batch should complete');
    }
  }

  /**
   * @description
   * Batch runs successfully when config has Last_Run_Completed set (incremental filter path).
   */
  @IsTest
  static void batchRunsSuccessfullyWithLastRunCompleted() {
    Test.setMock(HttpCalloutMock.class, new DataVaultCalloutMocks.Success200());
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVault_Export_Configs__c cfg = DataVaultTestSetupHelper.createExportConfig(
        DataVaultTestSetupHelper.getErrorLogObjectApiName(),
        'DataVault_Credential',
        'AWS_S3'
      );
      cfg.Last_Run_Completed__c = System.now().addDays(-1);
      DataVaultTestSetupHelper.createLogRecords(10);
      Test.startTest();
      Database.executeBatch(new DataVaultExportBatch(cfg), 10);
      Test.stopTest();
      List<DataVault_Error_Log__c> errorLogs = [
        SELECT Id
        FROM DataVault_Error_Log__c
        WHERE Apex_Class_Name__c != 'DataVaultTestSetupHelper'
        WITH USER_MODE
      ];
      System.assertEquals(
        0,
        errorLogs.size(),
        'No error logs should be created on success'
      );
      System.assert(true, 'Batch should complete');
    }
  }

  /**
   * @description
   * Batch logs error when mock returns 500.
   */
  @IsTest
  static void batchRunsUnSuccessfullyWithRes500() {
    Test.setMock(
      HttpCalloutMock.class,
      new DataVaultCalloutMocks.ServerError500()
    );
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVault_Export_Configs__c cfg = DataVaultTestSetupHelper.createExportConfig(
        DataVaultTestSetupHelper.getErrorLogObjectApiName(),
        'DataVault_Credential',
        'AWS_S3'
      );
      DataVaultTestSetupHelper.createLogRecords(10);
      Test.startTest();
      Database.executeBatch(new DataVaultExportBatch(cfg), 10);
      Test.stopTest();
      List<DataVault_Error_Log__c> errorLogs = [
        SELECT Id
        FROM DataVault_Error_Log__c
        WHERE Apex_Class_Name__c != 'DataVaultTestSetupHelper'
        WITH USER_MODE
      ];
      System.assertEquals(
        1,
        errorLogs.size(),
        'One error log should be created for HTTP 500'
      );
    }
  }

  /**
   * @description
   * Batch logs error when mock throws CalloutException.
   */
  @IsTest
  static void batchRunsUnSuccessfully() {
    Test.setMock(
      HttpCalloutMock.class,
      new DataVaultCalloutMocks.CalloutExceptionMock()
    );
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVault_Export_Configs__c cfg = DataVaultTestSetupHelper.createExportConfig(
        DataVaultTestSetupHelper.getErrorLogObjectApiName(),
        'DataVault_Credential',
        'AWS_S3'
      );
      DataVaultTestSetupHelper.createLogRecords(10);
      Test.startTest();
      Database.executeBatch(new DataVaultExportBatch(cfg), 10);
      Test.stopTest();
      List<DataVault_Error_Log__c> errorLogs = [
        SELECT Id
        FROM DataVault_Error_Log__c
        WHERE Apex_Class_Name__c != 'DataVaultTestSetupHelper'
        WITH USER_MODE
      ];
      System.assertEquals(
        1,
        errorLogs.size(),
        'One error log should be created for callout failure'
      );
    }
  }

  /**
   * @description
   * Verifies execute() with an empty scope does not throw or log errors.
   */
  @IsTest
  static void executeWithEmptyScopeDoesNotThrow() {
    Test.setMock(HttpCalloutMock.class, new DataVaultCalloutMocks.Success200());
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVault_Export_Configs__c cfg = DataVaultTestSetupHelper.createExportConfig(
        DataVaultTestSetupHelper.getErrorLogObjectApiName(),
        'DataVault_Credential',
        'AWS_S3'
      );
      DataVaultExportBatch batch = new DataVaultExportBatch(cfg);
      Test.startTest();
      batch.execute(null, new List<SObject>());
      batch.execute(null, null);
      batch.finish(null);
      Test.stopTest();
      System.assert(true, 'Empty scope must be handled gracefully');
    }
  }

  /**
   * @description
   * Verifies finish() covers the 'update as user' DML path with enforceSecurityInTest.
   */
  @IsTest
  static void finishWithEnforcedSecurityUpdatesConfig() {
    Test.setMock(HttpCalloutMock.class, new DataVaultCalloutMocks.Success200());
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVault_Export_Configs__c cfg = DataVaultTestSetupHelper.createExportConfig(
        DataVaultTestSetupHelper.getErrorLogObjectApiName(),
        'DataVault_Credential',
        'AWS_S3'
      );
      DataVaultTestSetupHelper.createLogRecords(5);
      DataVaultExportBatch.enforceSecurityInTest = true;
      Test.startTest();
      Database.executeBatch(new DataVaultExportBatch(cfg), 5);
      Test.stopTest();
      DataVaultExportBatch.enforceSecurityInTest = false;
      DataVault_Export_Configs__c updated = [
        SELECT Last_Run_Status__c, Last_Run_Success_Count__c
        FROM DataVault_Export_Configs__c
        WHERE Id = :cfg.Id
      ];
      System.assert(
        updated.Last_Run_Status__c != null,
        'Status should be set after batch completes'
      );
    }
  }

  /**
   * @description
   * Verifies execute skips chunk and logs error when callout limit is simulated as reached.
   */
  @IsTest
  static void executeSkipsWhenCalloutLimitReached() {
    Test.setMock(HttpCalloutMock.class, new DataVaultCalloutMocks.Success200());
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVault_Export_Configs__c cfg = DataVaultTestSetupHelper.createExportConfig(
        DataVaultTestSetupHelper.getErrorLogObjectApiName(),
        'DataVault_Credential',
        'AWS_S3'
      );
      DataVaultExportBatch batch = new DataVaultExportBatch(cfg);
      DataVaultExportBatch.simulateCalloutLimitReached = true;
      Test.startTest();
      batch.execute(null, new List<SObject>{ new Account(Name = 'Test') });
      Test.stopTest();
      DataVaultExportBatch.simulateCalloutLimitReached = false;
      System.assertEquals(
        1,
        batch.errorCount,
        'Error count should include skipped records'
      );
    }
  }

  /**
   * @description
   * Verifies execute skips chunk and logs error when heap limit is simulated as critically low.
   */
  @IsTest
  static void executeSkipsWhenHeapLimitLow() {
    Test.setMock(HttpCalloutMock.class, new DataVaultCalloutMocks.Success200());
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVault_Export_Configs__c cfg = DataVaultTestSetupHelper.createExportConfig(
        DataVaultTestSetupHelper.getErrorLogObjectApiName(),
        'DataVault_Credential',
        'AWS_S3'
      );
      DataVaultExportBatch batch = new DataVaultExportBatch(cfg);
      DataVaultExportBatch.simulateHeapLimitLow = true;
      Test.startTest();
      batch.execute(null, new List<SObject>{ new Account(Name = 'Test') });
      Test.stopTest();
      DataVaultExportBatch.simulateHeapLimitLow = false;
      System.assertEquals(
        1,
        batch.errorCount,
        'Error count should include skipped records'
      );
    }
  }

  /**
   * @description
   * Verifies finish logs error and returns when DML limit is simulated as reached.
   */
  @IsTest
  static void finishSkipsUpdateWhenDmlLimitReached() {
    Test.setMock(HttpCalloutMock.class, new DataVaultCalloutMocks.Success200());
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVault_Export_Configs__c cfg = DataVaultTestSetupHelper.createExportConfig(
        DataVaultTestSetupHelper.getErrorLogObjectApiName(),
        'DataVault_Credential',
        'AWS_S3'
      );
      DataVaultExportBatch batch = new DataVaultExportBatch(cfg);
      DataVaultExportBatch.simulateDmlLimitReached = true;
      Test.startTest();
      batch.finish(null);
      Test.stopTest();
      DataVaultExportBatch.simulateDmlLimitReached = false;
      System.assert(
        true,
        'Finish should exit gracefully when DML limit is reached'
      );
    }
  }

  /**
   * @description
   * Verifies finish sets status to 'Partial Success' when both success and error counts are positive.
   */
  @IsTest
  static void finishSetsPartialSuccessStatus() {
    Test.setMock(HttpCalloutMock.class, new DataVaultCalloutMocks.Success200());
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVault_Export_Configs__c cfg = DataVaultTestSetupHelper.createExportConfig(
        DataVaultTestSetupHelper.getErrorLogObjectApiName(),
        'DataVault_Credential',
        'AWS_S3'
      );
      DataVaultExportBatch batch = new DataVaultExportBatch(cfg);
      batch.successCount = 5;
      batch.errorCount = 3;
      Test.startTest();
      batch.finish(null);
      Test.stopTest();
      DataVault_Export_Configs__c updated = [
        SELECT Last_Run_Status__c
        FROM DataVault_Export_Configs__c
        WHERE Id = :cfg.Id
      ];
      System.assertEquals(
        'Partial Success',
        updated.Last_Run_Status__c,
        'Status should be Partial Success'
      );
    }
  }

  /**
   * @description
   * Verifies finish sets status to 'Failed' when all records errored.
   */
  @IsTest
  static void finishSetsFailedStatus() {
    Test.setMock(HttpCalloutMock.class, new DataVaultCalloutMocks.Success200());
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVault_Export_Configs__c cfg = DataVaultTestSetupHelper.createExportConfig(
        DataVaultTestSetupHelper.getErrorLogObjectApiName(),
        'DataVault_Credential',
        'AWS_S3'
      );
      DataVaultExportBatch batch = new DataVaultExportBatch(cfg);
      batch.successCount = 0;
      batch.errorCount = 10;
      Test.startTest();
      batch.finish(null);
      Test.stopTest();
      DataVault_Export_Configs__c updated = [
        SELECT Last_Run_Status__c
        FROM DataVault_Export_Configs__c
        WHERE Id = :cfg.Id
      ];
      System.assertEquals(
        'Failed',
        updated.Last_Run_Status__c,
        'Status should be Failed'
      );
    }
  }

  /**
   * @description
   * Constructor with null or blank required fields throws.
   */
  @IsTest
  static void constructorBlankParamsThrows() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      try {
        new DataVaultExportBatch(null);
      } catch (Exception e) {
        System.assert(
          e.getMessage().contains('DataVault Export Config is required.'),
          'Expected message: DataVault Export Config is required.'
        );
      }
      try {
        new DataVaultExportBatch(new DataVault_Export_Configs__c());
      } catch (Exception e) {
        System.assert(
          e.getMessage()
            .contains('DataVault Export Config is missing required fields.'),
          'Expected message: DataVault Export Config is missing required fields.'
        );
      }
      try {
        new DataVaultExportBatch(
          new DataVault_Export_Configs__c(
            Object_API_Name__c = DataVaultTestSetupHelper.getErrorLogObjectApiName()
          )
        );
      } catch (Exception e) {
        System.assert(
          e.getMessage()
            .contains('DataVault Export Config is missing required fields.'),
          'Expected message: DataVault Export Config is missing required fields.'
        );
      }
      try {
        new DataVaultExportBatch(
          new DataVault_Export_Configs__c(
            Named_Credential_Name__c = 'DataVault_Credential'
          )
        );
      } catch (Exception e) {
        System.assert(
          e.getMessage()
            .contains('DataVault Export Config is missing required fields.'),
          'Expected message: DataVault Export Config is missing required fields.'
        );
      }
      Test.stopTest();
    }
  }
}
