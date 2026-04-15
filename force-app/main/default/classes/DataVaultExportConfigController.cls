/**
 * @description
 * Apex controller for the DataVault Export configuration Lightning Web Component (LWC).
 *
 * What it is for:
 *  - Loads and persists the single org-level DataVault export configuration (object to export, Named Credential name, enable/disable).
 *  - Exposes getConfig (cacheable), getReadableObjectOptions, saveAndStartJob, and disableOrEnableExport to the LWC so admins can configure and trigger exports without code.
 *
 * Why it exists:
 *  - Centralizes all config access and updates through DataVault_Security_Utility (getConfigRecord, stripConfigCreatable/stripConfigUpdatable) so CRUD/FLS are enforced in one place and the UI never receives or writes data the user cannot access.
 *  - Validates object readability via DataVaultObjectAccessHelper before save so only exportable objects can be configured. Does not expose credentials or Named Credential internals—only the API name for reference.
 *
 * AppExchange considerations:
 *  - Declared with sharing; all config read/write goes through security utility and "as user" DML; no hardcoded IDs; designed for trusted UI context.
 */
public with sharing class DataVaultExportConfigController {
  /**
   * @description
   * Returns cacheable list of cloud platform options for the LWC combobox.
   * @return List of CloudPlatformOption for the combobox
   */
  @AuraEnabled(cacheable=true)
  public static List<CloudPlatformOption> getCloudPlatformOptions() {
    return DataVaultExportConfigService.getCloudPlatformOptions();
  }

  /**
   * @description
   * Returns cacheable org-level export config DTO, or null if none exists.
   * @return ConfigDTO or null
   */
  @AuraEnabled(cacheable=true)
  public static ConfigDTO getConfig() {
    return DataVaultExportConfigService.getConfig();
  }

  /**
   * @description
   * Returns list of readable SObject options (label/value) for the LWC object picklist.
   * @return List of ObjectOption (label/value pairs)
   */
  @AuraEnabled
  public static List<DataVaultObjectAccessHelper.ObjectOption> getReadableObjectOptions() {
    return DataVaultExportConfigService.getReadableObjectOptions();
  }

  /**
   * @description
   * Validates that the Named Credential is reachable; throws AuraHandledException on failure.
   * @param namedCredentialName API name of the Named Credential
   */
  @AuraEnabled
  public static void validateNamedCredentialConnection(
    String namedCredentialName
  ) {
    DataVaultExportConfigLogic.validateNamedCredentialConnection(
      namedCredentialName
    );
  }

  /**
   * @description
   * Persists the DataVault export configuration and initiates export processing. LWC entry point (Map-based). Accepts a simple Map; keys: cloudPlatform, namedCredentialName, objectApiName.
   * @param inputMap Map with keys cloudPlatform, namedCredentialName, objectApiName (all required)
   */
  @AuraEnabled
  public static void saveAndStartJobFromMap(Map<String, String> inputMap) {
    if (inputMap == null) {
      throw new AuraHandledException('Configuration input is required.');
    }

    SaveConfigInput input = new SaveConfigInput();
    input.cloudPlatform = inputMap.get('cloudPlatform');
    input.namedCredentialName = inputMap.get('namedCredentialName');
    input.objectApiName = inputMap.get('objectApiName');

    saveAndStartJob(input);
  }

  /**
   * @description
   * Persists the DataVault export configuration and initiates export processing. Internal entry point used by tests and by saveAndStartJobFromMap.
   * @param input the save input (cloudPlatform, namedCredentialName, objectApiName)
   */
  public static void saveAndStartJob(SaveConfigInput input) {
    if (input == null) {
      throw new AuraHandledException('Configuration input is required.');
    }
    try {
      DataVaultExportConfigLogic.saveAndStartJob(input);
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException('Save failed: ' + e.getMessage());
    }
  }

  /**
   * @description
   * Enables or disables the export (updates Is_Export_Enabled__c on the org-level config).
   * @param isExportEnabled true to enable, false to disable
   */
  @AuraEnabled
  public static void disableOrEnableExport(Boolean isExportEnabled) {
    DataVaultExportConfigLogic.disableOrEnableExport(isExportEnabled);
  }

  /**
   * @description
   * Input wrapper for saveAndStartJob. Reduces parameter count for PMD ExcessiveParameterList.
   */
  public class SaveConfigInput {
    @AuraEnabled
    public String cloudPlatform;
    @AuraEnabled
    public String namedCredentialName;
    @AuraEnabled
    public String objectApiName;
  }

  /**
   * @description
   * DTO for cloud platform combobox: label and value (API value).
   */
  public class CloudPlatformOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
    /**
     * @description
     * Constructs a cloud platform option.
     * @param label display label
     * @param value API value
     */
    public CloudPlatformOption(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  /**
   * @description
   * DTO for the org-level export config returned to LWC (id, name, cloud platform, credential name, object, enabled, last run stats).
   */
  public class ConfigDTO {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String cloudPlatform;
    @AuraEnabled
    public String namedCredentialName;
    @AuraEnabled
    public String objectApiName;
    @AuraEnabled
    public String objectLabel;
    @AuraEnabled
    public Boolean isExportEnabled;
    @AuraEnabled
    public Integer lastRunSuccessCount;
    @AuraEnabled
    public Integer lastRunErrorCount;
    @AuraEnabled
    public String lastRunStatus;
    @AuraEnabled
    public DateTime lastRunCompleted;

    /**
     * @description
     * Maps a custom setting record to this DTO.
     * @param c the config record
     * @return this DTO populated from c
     */
    public ConfigDTO fromRecord(DataVault_Export_Configs__c c) {
      ConfigDTO dto = new ConfigDTO();
      dto.id = c.Id;
      dto.name = c.Name;
      dto.cloudPlatform = c.Cloud_Platform__c;
      dto.namedCredentialName = c.Named_Credential_Name__c;
      dto.objectApiName = c.Object_API_Name__c;
      dto.isExportEnabled = c.Is_Export_Enabled__c;
      dto.lastRunSuccessCount = c.Last_Run_Success_Count__c != null
        ? c.Last_Run_Success_Count__c.intValue()
        : null;
      dto.lastRunErrorCount = c.Last_Run_Error_Count__c != null
        ? c.Last_Run_Error_Count__c.intValue()
        : null;
      dto.lastRunStatus = c.Last_Run_Status__c;
      dto.lastRunCompleted = c.Last_Run_Completed__c;
      return dto;
    }
  }
}
