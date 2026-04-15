/**
 * @description
 * Utility class that centralizes object- and field-level access checks using Salesforce describe metadata.
 *
 * What it is for:
 *  - Determines which SObjects the running user can read and builds FLS-safe dynamic SOQL (SELECT
 *    only accessible fields, FROM validated object name) for batch, integration, and UI.
 *  - Exposes a list of readable objects as label/value options for picklists and validates object
 *    access before export or query operations.
 *
 * Why it exists:
 *  - Apex runs in system context by default; this helper ensures all export and UI flows respect
 *    CRUD and FLS so subscriber org security is not bypassed. Describe-driven queries avoid SOQL
 *    injection because field and object names come from Schema metadata, not user input concatenation.
 *  - Single place for access logic so batch, controller, and scheduler stay consistent and
 *    AppExchange review can verify security in one utility.
 *
 * AppExchange considerations:
 *  - Declared with sharing to respect subscriber org sharing rules.
 *  - No direct SOQL built from user input; object name is validated via getGlobalDescribe() and
 *    field list from describe only. Safe for managed packages and namespace.
 */
public with sharing class DataVaultObjectAccessHelper {
  /**
   * Name of the default configuration record used by export configuration controllers and batch processes.
   * Why: Constant enables deterministic lookup of configuration in Custom Settings without hardcoded IDs.
   */
  public static final String CONFIG_RECORD_NAME = 'Default';

  private static Map<String, Schema.SObjectType> cachedGlobalDescribe;
  private static Map<String, Schema.DescribeSObjectResult> describeCache = new Map<String, Schema.DescribeSObjectResult>();

  private static Map<String, Schema.SObjectType> getCachedGlobalDescribe() {
    if (cachedGlobalDescribe == null) {
      cachedGlobalDescribe = Schema.getGlobalDescribe();
    }
    return cachedGlobalDescribe;
  }

  /**
   * @description
   * Returns a list of selectable SObjects the running user can read and query. UI must only offer objects the user can legally export; describe ensures the list respects FLS/CRUD.
   * @return List of ObjectOption DTOs representing readable SObjects
   */
  public static List<ObjectOption> getReadableObjectOptions() {
    List<ObjectOption> options = new List<ObjectOption>();
    Map<String, Schema.SObjectType> globalDescribe = getCachedGlobalDescribe();
    List<String> apiNames = new List<String>();
    Map<String, String> labelByApiName = new Map<String, String>();

    for (String apiName : globalDescribe.keySet()) {
      Schema.DescribeSObjectResult dr = globalDescribe.get(apiName)
        .getDescribe();

      if (dr.isAccessible() && dr.isQueryable()) {
        apiNames.add(apiName);
        labelByApiName.put(apiName, dr.getLabel());
      }
    }

    apiNames.sort();

    for (String apiName : apiNames) {
      options.add(new ObjectOption(labelByApiName.get(apiName), apiName));
    }
    return options;
  }

  /**
   * @description
   * Lightweight DTO for LWC/Aura combobox: label (user-facing) and value (API name). Keeps UI and Apex contract simple.
   */
  public class ObjectOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;

    /**
     * @description
     * Constructs an object option with label and value.
     * @param label display label
     * @param value API name
     */
    public ObjectOption(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  /**
   * @description
   * Determines whether the running user has read and query access to the specified SObject. This check should be performed before building dynamic SOQL, starting batch jobs, or executing exports.
   * @param objectApiName API name of the SObject
   * @return true if the object is readable and queryable; false otherwise
   */
  public static Boolean isObjectReadable(String objectApiName) {
    if (String.isBlank(objectApiName)) {
      return false;
    }
    Schema.DescribeSObjectResult dr = getDescribeSObjectResult(objectApiName);

    return dr != null && dr.isAccessible() && dr.isQueryable();
  }

  /**
   * @description
   * Safely returns the DescribeSObjectResult for the given API name. Never throws; returns null if blank, invalid, or not in org. Callers can validate object existence and accessibility without try/catch.
   * @param objectApiName API name of the SObject
   * @return DescribeSObjectResult or null if not found
   */
  public static Schema.DescribeSObjectResult getDescribeSObjectResult(
    String objectApiName
  ) {
    if (String.isBlank(objectApiName)) {
      return null;
    }
    String key = objectApiName.toLowerCase();
    if (describeCache.containsKey(key)) {
      return describeCache.get(key);
    }
    try {
      Schema.SObjectType ot = getCachedGlobalDescribe().get(objectApiName);

      Schema.DescribeSObjectResult dr = ot == null ? null : ot.getDescribe();
      describeCache.put(key, dr);
      return dr;
    } catch (Exception e) {
      describeCache.put(key, null);
      return null;
    }
  }

  /**
   * @description
   * Strips inaccessible fields from a list of SObjects using Security.stripInaccessible. Centralizes FLS enforcement for any access type.
   * @param accessType AccessType enum value (READABLE, CREATABLE, UPDATABLE)
   * @param records List of SObjects to strip inaccessible fields from
   * @return List of SObjects with inaccessible fields stripped
   */
  public static List<SObject> stripInaccessibleFields(
    AccessType accessType,
    List<SObject> records
  ) {
    return Security.stripInaccessible(accessType, records).getRecords();
  }

  /**
   * @description
   * Returns field API names the running user has read (FLS) access to for the given SObject. Used to build SELECT clauses. SOQL built from this list only includes accessible fields.
   * @param objectApiName API name of the SObject
   * @return List of accessible field API names
   */
  public static List<String> getReadableFieldApiNames(String objectApiName) {
    Schema.DescribeSObjectResult dr = getDescribeSObjectResult(objectApiName);

    if (dr == null || !dr.isAccessible() || !dr.isQueryable()) {
      return new List<String>();
    }

    List<String> fields = new List<String>();
    for (Schema.SObjectField f : dr.fields.getMap().values()) {
      if (f.getDescribe().isAccessible()) {
        fields.add(f.getDescribe().getName());
      }
    }
    return fields;
  }

  /**
   * @description
   * Builds an FLS-safe SOQL query: SELECT accessible fields FROM ObjectApiName. Returns null if no readable fields. Field list and object name come only from describe metadata (no SOQL injection).
   * @param objectApiName API name of the SObject
   * @return SOQL query string or null if no readable fields exist
   */
  public static String buildSecureQuery(String objectApiName) {
    List<String> fields = getReadableFieldApiNames(objectApiName);
    if (fields.isEmpty()) {
      return null;
    }
    return 'SELECT ' + String.join(fields, ',') + ' FROM ' + objectApiName;
  }
}
