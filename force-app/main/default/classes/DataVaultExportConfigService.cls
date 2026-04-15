/**
 * @description
 * Service for read-only DataVault Export configuration data passed from Apex to LWC.
 * Contains getCloudPlatformOptions, getConfig, and getReadableObjectOptions.
 *
 * Why it exists: Provides data to LWC; write operations (saveAndStartJob, validateNamedCredentialConnection,
 * disableOrEnableExport) remain in the controller.
 */
public with sharing class DataVaultExportConfigService {
  /**
   * @description
   * Returns cloud platform options from active custom metadata.
   * @return list of label/value options
   */
  public static List<DataVaultExportConfigController.CloudPlatformOption> getCloudPlatformOptions() {
    checkCloudPlatformReadable();
    return buildCloudPlatformOptions();
  }

  /**
   * @description
   * Returns org-level export config as DTO, or null if none.
   * @return ConfigDTO or null
   */
  public static DataVaultExportConfigController.ConfigDTO getConfig() {
    checkConfigReadable();
    DataVault_Export_Configs__c config = DataVault_Security_Utility.getConfigRecord();
    if (config == null || config.Id == null) {
      return null;
    }
    DataVaultExportConfigController.ConfigDTO dto = new DataVaultExportConfigController.ConfigDTO()
      .fromRecord(config);
    if (String.isNotBlank(dto.objectApiName)) {
      Schema.DescribeSObjectResult describeResult = DataVaultObjectAccessHelper.getDescribeSObjectResult(
        dto.objectApiName
      );
      dto.objectLabel = describeResult != null
        ? describeResult.getLabel()
        : dto.objectApiName;
    }
    return dto;
  }

  /**
   * @description
   * Returns readable SObject options for the object picklist.
   * @return list of ObjectOption
   */
  public static List<DataVaultObjectAccessHelper.ObjectOption> getReadableObjectOptions() {
    checkConfigReadable();
    return DataVaultObjectAccessHelper.getReadableObjectOptions();
  }

  /**
   * @description
   * Builds cloud platform options from custom metadata.
   * @return list of CloudPlatformOption
   */
  private static List<DataVaultExportConfigController.CloudPlatformOption> buildCloudPlatformOptions() {
    List<DataVaultExportConfigController.CloudPlatformOption> options = new List<DataVaultExportConfigController.CloudPlatformOption>();
    for (DataVault_Cloud_Platform__mdt mdt : [
      SELECT Label, Api_Value__c
      FROM DataVault_Cloud_Platform__mdt
      WHERE Is_Active__c = TRUE
      WITH USER_MODE
      ORDER BY Display_Order__c ASC NULLS LAST, Label ASC
    ]) {
      options.add(
        new DataVaultExportConfigController.CloudPlatformOption(
          mdt.Label,
          mdt.Api_Value__c
        )
      );
    }
    return options;
  }

  private static void checkCloudPlatformReadable() {
    if (!DataVault_Security_Utility.isCloudPlatformMetadataReadable()) {
      throw new AuraHandledException(
        'You do not have read access to DataVault Cloud Platform Metadata.'
      );
    }
  }

  private static void checkConfigReadable() {
    if (!DataVault_Security_Utility.isConfigReadable()) {
      throw new AuraHandledException(
        'You do not have read access to DataVault Export Config.'
      );
    }
  }
}
