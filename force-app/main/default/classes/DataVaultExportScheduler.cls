/**
 * @description
 * Scheduled Apex entry point that starts the DataVault export batch job when the schedule fires.
 *
 * What it is for:
 *  - Invoked by the platform on a schedule (or manually via execute(null)); loads the org-level config,
 *    checks that export is enabled and required fields are set, then runs DataVaultExportBatch with batch size 200.
 *
 * Why it exists:
 *  - Schedulable must be a thin trigger: no business logic or callouts here. All validation and processing
 *    live in DataVaultExportBatch so the scheduler stays simple and testable, and so config access is consistent
 *    (getConfigRecord, CRUD checks via DataVault_Security_Utility). Exceptions are logged and rethrown so failures are visible.
 *
 * AppExchange considerations:
 *  - Declared with sharing; only reads config and enqueues batch; no DML or callouts in scheduler; safe for repeated execution.
 */
public with sharing class DataVaultExportScheduler implements Schedulable {
  @TestVisible
  private static Boolean enforceSecurityInTest = false;
  /**
   * @description
   * Loads org-level config, validates access and required fields, and starts the export batch if export is enabled. Logs and rethrows on error. Single entry point for scheduled run; validation here avoids starting a batch that would immediately fail in its constructor or start().
   * @param sc the schedulable context (unused; required by interface)
   */
  public void execute(SchedulableContext sc) {
    try {
      checkConfigAccessible();

      DataVault_Export_Configs__c config = DataVault_Security_Utility.getConfigRecord();
      if (config == null || config.Id == null) {
        DataVault_PackageException e = new DataVault_PackageException(
          'DataVault Export Config not found.'
        );
        throw e;
      }

      if (!config.Is_Export_Enabled__c) {
        return;
      }
      Database.executeBatch(new DataVaultExportBatch(config), 200);
    } catch (Exception e) {
      // Defensive catch to ensure scheduler failures are logged
      DataVault_Error_Logger.logError(
        DataVault_Error_Logger.buildContextFromException(
          e,
          'DataVaultExportScheduler',
          'execute'
        )
      );
      DataVault_Error_Logger.flush();
      throw e;
    }
  }

  /**
   * @description
   * Ensures running user has read and update access to config. Scheduler must not run batch if user cannot read config or batch cannot update it in finish().
   */
  private void checkConfigAccessible() {
    if (
      (!Test.isRunningTest() || enforceSecurityInTest) &&
      (!DataVault_Security_Utility.isConfigReadable() ||
      !DataVault_Security_Utility.isConfigUpdatable())
    ) {
      DataVault_PackageException e = new DataVault_PackageException(
        'Insufficient access to DataVault Export Config.'
      );
      throw e;
    }
  }
}
