/**
 * @description
 * Data holder (context object) for error log entries used by the DataVault error logging framework.
 *
 * What it is for:
 *  - Carries error metadata (type, message, stack trace, class/method, timestamp) from the
 *    point of failure to the logger, which then builds and persists DataVault_Error_Log__c records.
 *
 * Why it exists:
 *  - Decouples error capture from record construction and persistence, so the logger and
 *    buffer can apply truncation, CRUD checks, and FLS without duplicating logic at every call site.
 *  - Ensures a single, consistent shape for all error log data before it is written to the custom object.
 *
 * AppExchange considerations:
 *  - Declared with sharing to respect subscriber org security context.
 *  - Contains only non-sensitive operational data (class name, method name, error type/message,
 *    timestamp, stack trace). No PII, credentials, or secrets—safe for persistence in subscriber orgs.
 *  - Fields map 1:1 to DataVault_Error_Log__c; used only for internal package error diagnostics.
 */
public with sharing class DataVault_Error_LogContext {
  /** Error Type picklist value: Callout Failure or General Apex Exception. */
  public String errorType;
  /** Short error message; truncated by logger before persist. */
  public String errorMessage;
  /** Apex stack trace string; truncated by logger. */
  public String stackTrace;
  /** Class where error occurred; from stack or caller. */
  public String apexClassName;
  /** Method where error occurred; from stack or caller. */
  public String methodName;
  /** When the error occurred (set by logger if null). */
  public DateTime timestamp;
}
