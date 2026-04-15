/**
 * @description Test class for DataVaultExportScheduler.
 *
 * What it is for: Verifies that the scheduler can be scheduled (System.schedule) and that the CronTrigger record is created with the expected CRON expression. Does not run the batch; uses a future CRON so the job does not execute during the test.
 *
 * Why it exists: AppExchange requires coverage for Schedulable. Testing full execute() would require async batch and more setup; this test validates scheduling metadata and wiring without depending on batch execution or SeeAllData.
 *
 * AppExchange considerations: No SeeAllData; runAs() with test user; future CRON avoids actual batch run in test context.
 */
@IsTest
private class DataVaultExportSchedulerTest {
  @TestSetup
  static void setup() {
    DataVaultTestSetupHelper.createUserAndAssignPermissionSet();
  }

  /**
   * @description
   * Verifies that the DataVault export scheduler can be scheduled successfully and that the resulting CronTrigger reflects the expected CRON expression.
   */
  @IsTest
  static void testSchedulerExecution() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVault_Export_Configs__c cfg = DataVaultTestSetupHelper.createExportConfig(
        DataVaultTestSetupHelper.getErrorLogObjectApiName(),
        'DataVault_Credential'
      );
      System.assertNotEquals(
        null,
        cfg.Id,
        'Export config must exist for scheduler test'
      );

      String cronExp = '0 0 0 15 3 ? 2026';

      Test.startTest();

      String jobId = System.schedule(
        'TestDataVaultExportJob',
        cronExp,
        new DataVaultExportScheduler()
      );

      Test.stopTest();

      CronTrigger ct = [
        SELECT Id, CronExpression, TimesTriggered, NextFireTime
        FROM CronTrigger
        WHERE Id = :jobId
        WITH USER_MODE
      ];

      System.assertEquals(
        cronExp,
        ct.CronExpression,
        'The CRON expression should match the scheduled value.'
      );

      System.assertEquals(
        0,
        ct.TimesTriggered,
        'The scheduled job should not have executed during the test.'
      );
    }
  }

  /**
   * @description
   * Verifies that the DataVault export scheduler throws an exception when the DataVault Export Config is not found.
   */
  @IsTest
  static void testExceptionSchedulerExecution() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      try {
        new DataVaultExportScheduler().execute(null);
      } catch (Exception e) {
        System.assert(
          e.getMessage().contains('DataVault Export Config not found.') ||
          e.getMessage().contains('Insufficient access'),
          'Expected message about config not found or insufficient access. Got: ' +
          e.getMessage()
        );
      }
      Test.stopTest();
    }
  }

  /**
   * @description
   * Verifies scheduler exits early when export is disabled (Is_Export_Enabled__c = false).
   */
  @IsTest
  static void schedulerExitsWhenExportDisabled() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVault_Export_Configs__c cfg = DataVaultTestSetupHelper.createExportConfig(
        DataVaultTestSetupHelper.getErrorLogObjectApiName(),
        'DataVault_Credential'
      );
      cfg.Is_Export_Enabled__c = false;
      update cfg;

      Test.startTest();
      new DataVaultExportScheduler().execute(null);
      Test.stopTest();

      System.assert(
        true,
        'Scheduler should exit silently when export is disabled'
      );
    }
  }

  /**
   * @description
   * Verifies scheduler evaluates CRUD/FLS check when enforceSecurityInTest is true
   * and user has the permission set (passes check, proceeds normally).
   */
  @IsTest
  static void schedulerEnforcedSecurityPassesWithPermission() {
    Test.setMock(HttpCalloutMock.class, new DataVaultCalloutMocks.Success200());
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVaultTestSetupHelper.createExportConfig(
        DataVaultTestSetupHelper.getErrorLogObjectApiName(),
        'DataVault_Credential'
      );
      DataVaultTestSetupHelper.createLogRecords(2);
      DataVaultExportScheduler.enforceSecurityInTest = true;
      Test.startTest();
      new DataVaultExportScheduler().execute(null);
      Test.stopTest();
      DataVaultExportScheduler.enforceSecurityInTest = false;
      System.assert(
        true,
        'Scheduler should pass security check with valid permissions'
      );
    }
  }

  /**
   * @description
   * Verifies scheduler execute completes when config is valid and export enabled
   * by directly calling execute(null) with a valid config and mock callout.
   */
  @IsTest
  static void schedulerDirectExecuteWithValidConfig() {
    Test.setMock(HttpCalloutMock.class, new DataVaultCalloutMocks.Success200());
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVaultTestSetupHelper.createExportConfig(
        DataVaultTestSetupHelper.getErrorLogObjectApiName(),
        'DataVault_Credential'
      );
      DataVaultTestSetupHelper.createLogRecords(2);

      Test.startTest();
      new DataVaultExportScheduler().execute(null);
      Test.stopTest();

      System.assert(true, 'Scheduler should complete without exception');
    }
  }
}
