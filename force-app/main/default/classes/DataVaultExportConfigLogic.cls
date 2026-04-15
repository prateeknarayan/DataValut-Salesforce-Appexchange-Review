/**
 * @description
 * Internal logic helper for DataVaultExportConfigController write operations.
 * Not exposed to LWC directly; all entry points remain on the controller.
 */
public with sharing class DataVaultExportConfigLogic {
  private static final String CONFIG_RECORD_NAME = DataVaultObjectAccessHelper.CONFIG_RECORD_NAME;

  /**
   * @description
   * Validates Named Credential via callout; throws AuraHandledException if unreachable or invalid.
   * @param namedCredentialName API name of the Named Credential
   */
  public static void validateNamedCredentialConnection(
    String namedCredentialName
  ) {
    checkConfigReadable();
    if (String.isBlank(namedCredentialName)) {
      throw new AuraHandledException('Named Credential Name is required.');
    }
    try {
      DataVaultIntegrationService.validateNamedCredentialConnection(
        namedCredentialName
      );
    } catch (Exception e) {
      throw new AuraHandledException(
        'Named Credential connection could not be verified. Please ensure the Named Credential exists in Setup and is configured correctly. Error: ' +
        e.getMessage()
      );
    }
  }

  /**
   * @description
   * Persists config (create or update) and schedules export job.
   * @param input cloudPlatform, namedCredentialName, objectApiName
   */
  public static void saveAndStartJob(
    DataVaultExportConfigController.SaveConfigInput input
  ) {
    String platform = DataVaultExportConfigValidator.validateSaveInputs(input);
    checkConfigCreateUpdate();

    DataVault_Export_Configs__c config = DataVault_Security_Utility.getConfigRecord();
    if (config != null && config.Id != null) {
      updateConfig(config, input, platform);
    } else {
      createNewConfig(platform, input);
    }
  }

  /**
   * @description
   * Sets Is_Export_Enabled__c on the org-level config.
   * @param isExportEnabled true to enable, false to disable
   */
  public static void disableOrEnableExport(Boolean isExportEnabled) {
    checkConfigCreateUpdate();
    DataVault_Export_Configs__c existing = DataVault_Security_Utility.getConfigRecord();
    if (existing == null || existing.Id == null) {
      throw new AuraHandledException('DataVault Export Config not found.');
    }
    existing.Is_Export_Enabled__c = isExportEnabled;
    existing = DataVault_Security_Utility.stripConfigUpdatable(existing);
    requireDmlCapacity();
    update as user existing;
  }

  /**
   * @description
   * Creates a new org-level config record and starts the export job.
   * @param platform cloud platform API value
   * @param input save input with credential and object
   */
  private static void createNewConfig(
    String platform,
    DataVaultExportConfigController.SaveConfigInput input
  ) {
    DataVault_Export_Configs__c config = new DataVault_Export_Configs__c();
    config.Name = CONFIG_RECORD_NAME;
    config.Cloud_Platform__c = platform;
    config.Named_Credential_Name__c = input.namedCredentialName;
    config.Object_API_Name__c = input.objectApiName;
    config.Last_Run_Completed__c = null;
    config.Last_Run_Success_Count__c = null;
    config.Last_Run_Error_Count__c = null;
    config.Last_Run_Status__c = null;
    config.Is_Export_Enabled__c = true;
    config = DataVault_Security_Utility.stripConfigCreatable(config);
    if (config == null) {
      throw new AuraHandledException(
        'You do not have permission to create the required configuration fields.'
      );
    }
    requireDmlCapacity();
    insert as user config;
    scheduleExportJob();
  }

  private static void scheduleExportJob() {
    if (Test.isRunningTest()) {
      new DataVaultExportScheduler().execute(null);
    } else {
      System.schedule(
        'DataVault Daily Export',
        '0 59 23 * * ?',
        new DataVaultExportScheduler()
      );
    }
  }

  private static void updateConfig(
    DataVault_Export_Configs__c existingRec,
    DataVaultExportConfigController.SaveConfigInput input,
    String platform
  ) {
    Boolean isRecordChanged = false;
    isRecordChanged =
      applyFieldIfChanged(
        existingRec,
        DataVault_Export_Configs__c.Object_API_Name__c,
        input.objectApiName
      ) || isRecordChanged;
    isRecordChanged =
      applyFieldIfChanged(
        existingRec,
        DataVault_Export_Configs__c.Named_Credential_Name__c,
        input.namedCredentialName
      ) || isRecordChanged;
    isRecordChanged =
      applyFieldIfChanged(
        existingRec,
        DataVault_Export_Configs__c.Cloud_Platform__c,
        platform
      ) || isRecordChanged;
    if (!isRecordChanged) {
      return;
    }
    existingRec = DataVault_Security_Utility.stripConfigUpdatable(existingRec);
    if (existingRec == null) {
      throw new AuraHandledException(
        'You do not have permission to update the configuration.'
      );
    }
    requireDmlCapacity();
    update as user existingRec;
  }

  private static Boolean applyFieldIfChanged(
    DataVault_Export_Configs__c rec,
    Schema.SObjectField field,
    String newVal
  ) {
    String currentVal = (String) rec.get(field);
    if (String.isNotBlank(newVal) && newVal != currentVal) {
      rec.put(field, newVal);
      return true;
    }
    return false;
  }

  private static void checkConfigReadable() {
    if (!DataVault_Security_Utility.isConfigReadable()) {
      throw new AuraHandledException(
        'You do not have read access to DataVault Export Config.'
      );
    }
  }

  private static void checkConfigCreateUpdate() {
    if (!hasConfigCreateUpdateAccess()) {
      throw new AuraHandledException(
        'You do not have create/update access to DataVault Export Config.'
      );
    }
  }

  private static Boolean hasConfigCreateUpdateAccess() {
    return DataVault_Security_Utility.isConfigReadWrite() &&
      DataVault_Security_Utility.isConfigUpdatable();
  }

  private static void requireDmlCapacity() {
    if (Limits.getDmlStatements() >= Limits.getLimitDmlStatements()) {
      throw new AuraHandledException(
        'Governor limit reached: no DML statements remaining.'
      );
    }
    if (Limits.getDmlRows() >= Limits.getLimitDmlRows()) {
      throw new AuraHandledException(
        'Governor limit reached: no DML rows remaining.'
      );
    }
  }
}
