/**
 * @description
 * Validates save input for DataVault Export Config (cloud platform, credential, object). Used by DataVaultExportConfigLogic to keep validation logic and cyclomatic complexity in one place.
 */
public with sharing class DataVaultExportConfigValidator {
  /**
   * @description
   * Validates input and cloud platform; returns trimmed platform. Throws AuraHandledException on any validation failure.
   * @param input save input
   * @return trimmed cloud platform API value
   */
  public static String validateSaveInputs(
    DataVaultExportConfigController.SaveConfigInput input
  ) {
    requireNonBlankCloudPlatform(input);
    String platform = input.cloudPlatform.trim();
    requireCredentialAndObject(input);
    requireValidCloudPlatform(platform);
    requireObjectReadable(input.objectApiName);
    return platform;
  }

  private static void requireNonBlankCloudPlatform(
    DataVaultExportConfigController.SaveConfigInput input
  ) {
    if (String.isBlank(input.cloudPlatform)) {
      throw new AuraHandledException('Cloud Platform is required.');
    }
  }

  private static void requireCredentialAndObject(
    DataVaultExportConfigController.SaveConfigInput input
  ) {
    if (
      String.isBlank(input.namedCredentialName) ||
      String.isBlank(input.objectApiName)
    ) {
      throw new AuraHandledException(
        'Named Credential Name and Object API Name are required.'
      );
    }
  }

  private static void requireValidCloudPlatform(String platform) {
    if (!isValidCloudPlatform(platform)) {
      throw new AuraHandledException(
        'Invalid or inactive Cloud Platform: ' + platform
      );
    }
  }

  private static void requireObjectReadable(String objectApiName) {
    if (!DataVaultObjectAccessHelper.isObjectReadable(objectApiName)) {
      throw new AuraHandledException(
        'You do not have read access to object: ' + objectApiName
      );
    }
  }

  private static Boolean isValidCloudPlatform(String apiValue) {
    if (!DataVault_Security_Utility.isCloudPlatformMetadataReadable()) {
      throw new AuraHandledException(
        'You do not have read access to DataVault Cloud Platform Metadata.'
      );
    }
    List<DataVault_Cloud_Platform__mdt> matches = [
      SELECT Id
      FROM DataVault_Cloud_Platform__mdt
      WHERE Api_Value__c = :apiValue AND Is_Active__c = TRUE
      WITH USER_MODE
      LIMIT 1
    ];
    return !matches.isEmpty();
  }
}
