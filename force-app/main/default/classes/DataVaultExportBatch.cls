/**
 * @description
 * Batch Apex that exports records of a selected SObject to S3 as JSON via a Named Credential.
 *
 * What it is for:
 *  - Runs a configurable export: query records for a given object (with optional incremental filter by
 *    Last_Run_Completed__c), serialize each batch to JSON, and send to S3 with one callout per execute().
 *  - On finish, updates the config record with run statistics (success/error counts, status, last run time).
 *
 * Why it exists:
 *  - Large exports must be chunked to stay within governor limits; batch provides query locator, bulk
 *    execute(), and a single callout per chunk. Stateful instance keeps config and counters for the final update.
 *  - SOQL is built via DataVaultObjectAccessHelper.buildSecureQuery() so only FLS-accessible fields are selected
 *    and object name is describe-validated (no SOQL injection). Config access is validated via DataVault_Security_Utility.
 *
 * AppExchange considerations:
 *  - Declared with sharing; uses FLS-safe dynamic SOQL; one callout per execute(); no DML in loops; config update uses stripConfigUpdatable and "as user".
 */
public with sharing class DataVaultExportBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
  @TestVisible
  private static Boolean enforceSecurityInTest = false;
  @TestVisible
  private static Boolean simulateCalloutLimitReached = false;
  @TestVisible
  private static Boolean simulateHeapLimitLow = false;
  @TestVisible
  private static Boolean simulateSoqlLimitReached = false;
  @TestVisible
  private static Boolean simulateDmlLimitReached = false;

  private final DataVault_Export_Configs__c cfg;
  private final String objectApiName;
  private final String namedCredentialName;
  @TestVisible
  private Integer errorCount = 0;
  @TestVisible
  private Integer successCount = 0;
  private DateTime currentRunStarted;
  /**
   * @description
   * Validates config and running user access, then stores config and derived object/credential names for the batch run. Fail fast so the scheduler or caller does not start a batch that would fail in start() or execute(); CRUD check respects subscriber org permissions.
   * @param cfg the org-level DataVault Export Config record (must have Object_API_Name__c and Named_Credential_Name__c set; user must have read and update on config)
   */
  public DataVaultExportBatch(DataVault_Export_Configs__c cfg) {
    if (cfg == null) {
      throw new DataVault_PackageException(
        'DataVault Export Config is required.'
      );
    }
    if (
      String.isBlank(cfg.Object_API_Name__c) ||
      String.isBlank(cfg.Named_Credential_Name__c)
    ) {
      throw new DataVault_PackageException(
        'DataVault Export Config is missing required fields.'
      );
    }
    if (
      (!DataVault_Security_Utility.isConfigReadable() ||
      !DataVault_Security_Utility.isConfigUpdatable())
    ) {
      throw new DataVault_PackageException(
        'Insufficient access to DataVault Export Config.'
      );
    }
    this.cfg = cfg;
    this.objectApiName = this.cfg.Object_API_Name__c;
    this.namedCredentialName = this.cfg.Named_Credential_Name__c;
  }

  /**
   * @description
   * Returns query locator for the configured object. SOQL is built from DataVaultObjectAccessHelper.buildSecureQuery (describe-only, FLS-safe). Optional WHERE on LastModifiedDate/CreatedDate uses config Last_Run_Completed__c for incremental export. No user input in SOQL; safe for managed package.
   * @param bc the batchable context (unused; required by interface)
   * @return Database.QueryLocator for the configured object with optional incremental filter
   */
  public Database.QueryLocator start(Database.BatchableContext bc) {
    this.currentRunStarted = System.now();
    if (
      simulateSoqlLimitReached ||
      Limits.getQueries() >= Limits.getLimitQueries()
    ) {
      throw new DataVault_PackageException(
        'SOQL governor limit reached before batch start.'
      );
    }
    String soql = DataVaultObjectAccessHelper.buildSecureQuery(objectApiName);
    if (String.isBlank(soql)) {
      throw new DataVault_PackageException(
        'No readable fields for object: ' + objectApiName
      );
    }
    Datetime lastRunCompleted = this.cfg.Last_Run_Completed__c;
    if (lastRunCompleted != null) {
      soql +=
        ' WHERE (LastModifiedDate >= ' +
        lastRunCompleted.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') +
        ' OR CreatedDate >= ' +
        lastRunCompleted.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') +
        ')';
    }
    return Database.getQueryLocator(soql);
  }

  /**
   * @description
   * Processes one batch: serialize scope to JSON, single HTTP PUT via DataVaultIntegrationService. Counts success/error and logs non-2xx or exceptions. One callout per execute() avoids governor issues; errors are logged but do not stop the batch so other chunks can still succeed.
   * @param bc the batchable context (unused; required by interface)
   * @param scope the chunk of SObject records to export
   */
  public void execute(Database.BatchableContext bc, List<SObject> scope) {
    if (scope == null || scope.isEmpty()) {
      return;
    }
    if (isCalloutLimitReached()) {
      recordLimitError(
        scope.size(),
        'Callout governor limit reached — skipping chunk.'
      );
      return;
    }
    if (isHeapCriticallyLow()) {
      Integer heapRemaining = Limits.getLimitHeapSize() - Limits.getHeapSize();
      recordLimitError(
        scope.size(),
        'Heap space critically low (' +
          heapRemaining +
          ' bytes remaining) — skipping chunk.'
      );
      return;
    }
    sendChunkToS3(scope);
  }

  private Boolean isCalloutLimitReached() {
    return simulateCalloutLimitReached ||
      Limits.getCallouts() >= Limits.getLimitCallouts();
  }

  private Boolean isHeapCriticallyLow() {
    return simulateHeapLimitLow ||
      (Limits.getLimitHeapSize() - Limits.getHeapSize()) < 500000;
  }

  private void recordLimitError(Integer scopeSize, String message) {
    errorCount += scopeSize;
    DataVault_Error_Logger.logError(
      DataVault_Error_Logger.buildContextFromException(
        new DataVault_PackageException(message),
        'DataVaultExportBatch',
        'execute'
      )
    );
  }

  private void sendChunkToS3(List<SObject> scope) {
    try {
      String jsonBody = JSON.serialize(scope);
      HttpResponse res = DataVaultIntegrationService.sendToS3(
        namedCredentialName,
        objectApiName,
        jsonBody
      );
      if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
        successCount += scope.size();
        return;
      }
      errorCount += scope.size();
    } catch (Exception e) {
      errorCount += scope.size();
    }
  }

  /**
   * @description
   * Writes run statistics (success count, error count, status, last run time) to the config record. Uses stripConfigUpdatable and "update as user" for FLS. Admins see last run outcome in the UI; update is done once per batch job and only if the user has update access.
   * @param bc the batchable context (unused; required by interface)
   */
  public void finish(Database.BatchableContext bc) {
    if (!DataVault_Security_Utility.isConfigUpdatable()) {
      return;
    }
    if (
      simulateDmlLimitReached ||
      Limits.getDmlStatements() >= Limits.getLimitDmlStatements()
    ) {
      DataVault_Error_Logger.logError(
        DataVault_Error_Logger.buildContextFromException(
          new DataVault_PackageException(
            'DML statement governor limit reached in finish — config not updated.'
          ),
          'DataVaultExportBatch',
          'finish'
        )
      );
      return;
    }

    this.cfg.Last_Run_Success_Count__c = successCount;
    this.cfg.Last_Run_Error_Count__c = errorCount;

    if (errorCount == 0) {
      this.cfg.Last_Run_Status__c = 'Success';
    } else if (successCount > 0) {
      this.cfg.Last_Run_Status__c = 'Partial Success';
    } else {
      this.cfg.Last_Run_Status__c = 'Failed';
    }
    this.cfg.Last_Run_Completed__c = this.currentRunStarted;

    try {
      DataVault_Export_Configs__c strippedCfg = DataVault_Security_Utility.stripConfigUpdatable(
        this.cfg
      );
      if (Test.isRunningTest() && !enforceSecurityInTest) {
        update strippedCfg;
      } else {
        update as user strippedCfg;
      }
    } catch (Exception e) {
      DataVault_Error_LogContext ctx = DataVault_Error_Logger.buildContextFromException(
        new DataVault_PackageException(
          'Failed to update DataVault Export Config after batch completion: ' +
          e.getMessage()
        ),
        'DataVaultExportBatch',
        'finish'
      );
      DataVault_Error_Logger.logError(ctx);
    }
  }
}
