/**
 * @description
 * Builds DataVault_Error_Log__c records from DataVault_Error_LogContext with safe string truncation.
 *
 * What it is for:
 *  - Converts a context object (error type, message, stack, class, method, timestamp) into a
 *    single DataVault_Error_Log__c record ready for insert, with all text fields bounded to schema limits.
 *
 * Why it exists:
 *  - Centralizes truncation and field mapping so the logger and buffer do not duplicate logic or
 *    risk DML failures from oversized text. Long stack traces and messages are capped to avoid
 *    governor or field length issues in subscriber orgs.
 *
 * AppExchange considerations:
 *  - Declared with sharing; no DML or callouts; only builds an sObject from trusted context data.
 *  - Truncation limits align with typical long text field sizes and reduce risk of storage or logging abuse.
 */
public with sharing class DataVault_Error_LogRecordBuilder {
  private static final Integer MAX_MESSAGE_LENGTH = 32768;
  private static final Integer MAX_STACK_LENGTH = 32768;
  private static final Integer MAX_NAME_LENGTH = 255;

  /**
   * @description
   * Builds one DataVault_Error_Log__c from context; truncates all text to schema/limit sizes.
   * @param ctx the error log context (nullable)
   * @return DataVault_Error_Log__c record or null if ctx is null
   */
  public static DataVault_Error_Log__c build(DataVault_Error_LogContext ctx) {
    if (ctx == null) {
      return null;
    }
    DataVault_Error_Log__c log = new DataVault_Error_Log__c();
    log.Error_Type__c = String.isNotBlank(ctx.errorType)
      ? ctx.errorType
      : DataVault_Error_Logger.ERR_APEX_EXCEPTION;
    log.Error_Message__c = truncate(ctx.errorMessage, MAX_MESSAGE_LENGTH);
    log.Stack_Trace__c = truncate(ctx.stackTrace, MAX_STACK_LENGTH);
    log.Apex_Class_Name__c = truncate(ctx.apexClassName, MAX_NAME_LENGTH);
    log.Method_Name__c = truncate(ctx.methodName, MAX_NAME_LENGTH);
    log.Timestamp__c = ctx.timestamp != null ? ctx.timestamp : System.now();
    return log;
  }

  /**
   * @description
   * Truncates string to maxLen; returns null for blank. Used for all text fields so error messages and stack traces never exceed field limits.
   * @param s the string to truncate
   * @param maxLen maximum length
   * @return truncated string or null if blank
   */
  public static String truncate(String s, Integer maxLen) {
    if (String.isBlank(s)) {
      return null;
    }
    return s.length() <= maxLen ? s : s.substring(0, maxLen);
  }
}
