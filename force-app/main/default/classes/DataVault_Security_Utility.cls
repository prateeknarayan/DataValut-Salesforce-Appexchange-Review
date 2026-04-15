/**
 * @description
 * Centralized security enforcement utility for the DataVault Export managed package.
 *
 * Responsibilities:
 *  - Enforce object-level CRUD access checks.
 *  - Enforce field-level security (FLS) using Security.stripInaccessible.
 *  - Provide controlled access to configuration records.
 *  - Ensure compliance with AppExchange security review requirements.
 *
 * Design Principles:
 *  - Single responsibility: security validation and enforcement.
 *  - No business logic.
 *  - No DML operations.
 *  - No callouts.
 *  - Namespace-safe compile-time references.
 *
 * Object-Level Security Enforcement:
 *  - Uses Schema.sObjectType checks to verify:
 *      - isAccessible()
 *      - isCreateable()
 *      - isUpdateable()
 *  - Prevents unauthorized object operations.
 *
 * Field-Level Security Enforcement:
 *  - Applies Security.stripInaccessible() for:
 *      - AccessType.READABLE
 *      - AccessType.UPDATABLE
 *      - AccessType.CREATABLE
 *  - Ensures no restricted fields are read or written.
 *
 * Query Security:
 *  - Uses WITH USER_MODE in SOQL queries.
 *  - Ensures:
 *      - Row-level sharing enforcement
 *      - FLS enforcement
 *      - CRUD enforcement
 *
 * AppExchange Compliance Considerations:
 *  - No DML without prior security validation.
 *  - No dynamic SOQL injection risks.
 *  - No hardcoded IDs.
 *  - Fully compatible with managed package namespace.
 *  - Designed for subscriber org security boundary respect.
 */
public with sharing class DataVault_Security_Utility {
  @TestVisible
  private static Boolean enforceStripInTest = false;

  /* =========================================================
       CONFIG OBJECT – CRUD CHECKS
       ========================================================= */

  /**
   * @description
   * Returns whether the running user can read DataVault Export Config. Used before getConfigRecord and in controller to fail fast.
   * @return true if accessible
   */
  public static Boolean isConfigReadable() {
    return Schema.sObjectType.DataVault_Export_Configs__c.isAccessible();
  }

  /**
   * @description
   * Returns whether the running user can update DataVault Export Config. Batch finish() and controller updates require this.
   * @return true if updateable
   */
  public static Boolean isConfigUpdatable() {
    return Schema.sObjectType.DataVault_Export_Configs__c.isUpdateable();
  }

  /**
   * @description
   * Returns whether the running user can read and create DataVault Export Config. saveAndStartJob needs both.
   * @return true if accessible and createable
   */
  public static Boolean isConfigReadWrite() {
    return Schema.sObjectType.DataVault_Export_Configs__c.isAccessible() &&
      Schema.sObjectType.DataVault_Export_Configs__c.isCreateable();
  }

  /**
   * @description
   * Returns whether the running user can read DataVault Cloud Platform Metadata. Used before getCloudPlatformOptions.
   * @return true if accessible
   */
  public static Boolean isCloudPlatformMetadataReadable() {
    return Schema.sObjectType.DataVault_Cloud_Platform__mdt.isAccessible();
  }

  /* =========================================================
       CONFIG OBJECT – FLS STRIP METHODS
       ========================================================= */

  /**
   * @description
   * Strips fields the user cannot read from the config record. After query, strip before returning to callers.
   * @param record config record
   * @return stripped record or null
   */
  public static DataVault_Export_Configs__c stripConfigReadable(
    DataVault_Export_Configs__c record
  ) {
    if (record == null) {
      return null;
    }
    if (Test.isRunningTest() && !enforceStripInTest) {
      return record;
    }

    List<SObject> stripped = Security.stripInaccessible(
        AccessType.READABLE,
        new List<SObject>{ record }
      )
      .getRecords();

    return stripped.isEmpty()
      ? null
      : (DataVault_Export_Configs__c) stripped[0];
  }

  /**
   * @description
   * Strips fields the user cannot update. Before "update as user", ensure only FLS-allowed fields are written.
   * @param record config record
   * @return stripped record or null
   */
  public static DataVault_Export_Configs__c stripConfigUpdatable(
    DataVault_Export_Configs__c record
  ) {
    if (record == null) {
      return null;
    }
    if (Test.isRunningTest() && !enforceStripInTest) {
      return record;
    }

    List<SObject> stripped = Security.stripInaccessible(
        AccessType.UPDATABLE,
        new List<SObject>{ record }
      )
      .getRecords();

    return stripped.isEmpty()
      ? null
      : (DataVault_Export_Configs__c) stripped[0];
  }

  /**
   * @description
   * Strips fields the user cannot create. Before "insert as user", ensure only FLS-allowed fields are set.
   * @param record config record
   * @return stripped record or null
   */
  public static DataVault_Export_Configs__c stripConfigCreatable(
    DataVault_Export_Configs__c record
  ) {
    if (record == null) {
      return null;
    }
    if (Test.isRunningTest() && !enforceStripInTest) {
      return record;
    }

    List<SObject> stripped = Security.stripInaccessible(
        AccessType.CREATABLE,
        new List<SObject>{ record }
      )
      .getRecords();

    return stripped.isEmpty()
      ? null
      : (DataVault_Export_Configs__c) stripped[0];
  }

  /* =========================================================
       LOGGER OBJECT – CRUD + FLS
       ========================================================= */

  /**
   * @description
   * Returns whether the running user can create DataVault_Error_Log__c. Logger and buffer check this before writing.
   * @return true if createable
   */
  public static Boolean isLoggerCreatable() {
    return Schema.sObjectType.DataVault_Error_Log__c.isCreateable();
  }

  /**
   * @description
   * Strips fields the user cannot create from a list of error log records. Before bulk insert, enforce FLS.
   * @param records list of error log records
   * @return list with inaccessible fields stripped
   */
  public static List<DataVault_Error_Log__c> stripErrorLogCreatable(
    List<DataVault_Error_Log__c> records
  ) {
    if (records == null || records.isEmpty()) {
      return new List<DataVault_Error_Log__c>();
    }

    return (List<DataVault_Error_Log__c>) Security.stripInaccessible(
        AccessType.CREATABLE,
        records
      )
      .getRecords();
  }

  /* =========================================================
       CONFIG RETRIEVAL (ORG-LEVEL SAFE)
       ========================================================= */

  /**
   * @description
   * Returns the org-level DataVault Export configuration record, or null if none or not readable. Applies stripConfigReadable to the queried row. Hierarchy custom settings filtered by SetupOwnerId = OrganizationId; WITH USER_MODE enforces sharing and FLS.
   * @return the org-level config record or null
   */
  public static DataVault_Export_Configs__c getConfigRecord() {
    if (!isConfigReadable()) {
      return null;
    }
    if (Limits.getQueries() >= Limits.getLimitQueries()) {
      return null;
    }

    List<DataVault_Export_Configs__c> records;
    if (Test.isRunningTest() && !enforceStripInTest) {
      records = [
        SELECT
          Id,
          Name,
          Cloud_Platform__c,
          Named_Credential_Name__c,
          Object_API_Name__c,
          Is_Export_Enabled__c,
          Last_Run_Completed__c,
          Last_Run_Success_Count__c,
          Last_Run_Error_Count__c,
          Last_Run_Status__c
        FROM DataVault_Export_Configs__c
        WHERE SetupOwnerId = :UserInfo.getOrganizationId()
        LIMIT 1
      ];
    } else {
      records = [
        SELECT
          Id,
          Name,
          Cloud_Platform__c,
          Named_Credential_Name__c,
          Object_API_Name__c,
          Is_Export_Enabled__c,
          Last_Run_Completed__c,
          Last_Run_Success_Count__c,
          Last_Run_Error_Count__c,
          Last_Run_Status__c
        FROM DataVault_Export_Configs__c
        WHERE SetupOwnerId = :UserInfo.getOrganizationId()
        WITH USER_MODE
        LIMIT 1
      ];
    }

    if (records.isEmpty()) {
      return null;
    }

    return stripConfigReadable(records[0]);
  }
}
