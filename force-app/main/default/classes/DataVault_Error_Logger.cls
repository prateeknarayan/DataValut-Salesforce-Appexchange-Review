/**
 * @description
 * Thin orchestration layer for DataVault and integration error logging to DataVault_Error_Log__c.
 *
 * What it is for:
 *  - Single entry point for logging callout failures and general Apex exceptions. Builds log
 *    records from context, applies FLS/CRUD via the buffer, and triggers flush when needed.
 *
 * Why it exists:
 *  - Callers (integration service, batch, scheduler) need a simple, fire-and-forget way to log
 *    errors without knowing about record building, truncation, or buffer thresholds. The logger
 *    delegates to DataVault_Error_LogRecordBuilder (build) and DataVault_Error_LogBuffer (buffer + flush),
 *    so security and governor limits are enforced in one place.
 *  - Designed to never throw so that logging failures do not interrupt the main execution path.
 *
 * AppExchange considerations:
 *  - Declared with sharing; CRUD for DataVault_Error_Log__c is checked via DataVault_Security_Utility before writing.
 *  - No sensitive data in log content; messages and stack traces are truncated and stored for diagnostics only.
 */
public with sharing class DataVault_Error_Logger {
  /** Error type picklist values for DataVault_Error_Log__c. */
  public static final String ERR_CALLOUT_FAILURE = 'Callout Failure';
  public static final String ERR_APEX_EXCEPTION = 'General Apex Exception';

  private static final Integer MAX_MESSAGE_LENGTH = 32768;
  private static final Integer MAX_STACK_LENGTH = 32768;
  private static final Integer MAX_CALLOUT_DEBUG_LENGTH = 16384;

  /**
   * @description Logs an error from context. CRUD check; build record; add to buffer; maybe flush. Never throws.
   * @param context The error log context with error type, message, stack trace, class/method, timestamp
   */
  public static void logError(DataVault_Error_LogContext context) {
    if (context == null || !isCreateable()) {
      return;
    }

    DataVault_Error_Log__c log = DataVault_Error_LogRecordBuilder.build(
      context
    );
    if (log != null) {
      DataVault_Error_LogBuffer.add(log);
      DataVault_Error_LogBuffer.maybeFlush();
    }
  }

  /**
   * @description
   * Builds LogContext from an Exception for use with logError(LogContext). Callers MUST pass apexClassName and methodName so every log has explicit class/method for traceability.
   * @param e The exception to convert
   * @param apexClassName The Apex class where the error occurred (required)
   * @param methodName The method where the error occurred (required)
   * @return DataVault_Error_LogContext Populated context, or null if e is null
   */
  public static DataVault_Error_LogContext buildContextFromException(
    Exception e,
    String apexClassName,
    String methodName
  ) {
    if (e == null) {
      return null;
    }
    DataVault_Error_LogContext ctx = new DataVault_Error_LogContext();
    ctx.errorType = ERR_APEX_EXCEPTION;
    ctx.errorMessage = DataVault_Error_LogRecordBuilder.truncate(
      e.getMessage(),
      MAX_MESSAGE_LENGTH
    );
    ctx.stackTrace = DataVault_Error_LogRecordBuilder.truncate(
      e.getStackTraceString(),
      MAX_STACK_LENGTH
    );
    ctx.timestamp = System.now();
    ctx.apexClassName = DataVault_Error_LogRecordBuilder.truncate(
      apexClassName,
      255
    );
    ctx.methodName = DataVault_Error_LogRecordBuilder.truncate(methodName, 255);
    return ctx;
  }

  /**
   * @description
   * Input for logging a callout failure with optional request/response. Use when logging HTTP or callout errors with optional request/response for debugging.
   */
  public class CalloutFailureInput {
    /** Error message (e.g. HTTP status or CalloutException message). */
    public String message;
    /** Apex class where the failure occurred. */
    public String apexClassName;
    /** Method where the failure occurred. */
    public String methodName;
    /** Optional HttpRequest; when set, headers and body are added to stack trace. */
    public HttpRequest req;
    /** Optional HttpResponse; when set, status and body are added to stack trace. */
    public HttpResponse res;

    /**
     * @description
     * Constructs input for logCalloutFailure. Set req and res after construction when request/response are available.
     * @param message error message
     * @param apexClassName class name
     * @param methodName method name
     */
    public CalloutFailureInput(
      String message,
      String apexClassName,
      String methodName
    ) {
      this.message = message;
      this.apexClassName = apexClassName;
      this.methodName = methodName;
    }
  }

  /**
   * @description
   * Logs a callout failure with class/method. Use when request/response are not available.
   * @param message The error message (e.g. CalloutException message)
   * @param apexClassName The Apex class where the failure occurred
   * @param methodName The method where the failure occurred
   */
  public static void logCalloutFailure(
    String message,
    String apexClassName,
    String methodName
  ) {
    logCalloutFailure(
      new CalloutFailureInput(message, apexClassName, methodName)
    );
  }

  /**
   * @description
   * Logs a callout failure from input (message, class, method, optional request/response). Request/response are added to stack trace when provided.
   * @param input callout failure details
   */
  public static void logCalloutFailure(CalloutFailureInput input) {
    if (input == null) {
      return;
    }
    DataVault_Error_LogContext ctx = new DataVault_Error_LogContext();
    ctx.errorType = ERR_CALLOUT_FAILURE;
    ctx.errorMessage = DataVault_Error_LogRecordBuilder.truncate(
      input.message,
      MAX_MESSAGE_LENGTH
    );
    ctx.timestamp = System.now();
    ctx.apexClassName = DataVault_Error_LogRecordBuilder.truncate(
      input.apexClassName,
      255
    );
    ctx.methodName = DataVault_Error_LogRecordBuilder.truncate(
      input.methodName,
      255
    );
    ctx.stackTrace = buildCalloutDebugTrace(input.req, input.res);
    logError(ctx);
  }

  /**
   * @description
   * Builds a debug trace string from callout request/response for Stack_Trace__c. Includes headers and body (truncated) for debugging.
   * @param req optional HttpRequest (headers/body added to trace)
   * @param res optional HttpResponse (status/body added to trace)
   * @return concatenated trace string or null if both null
   */
  private static String buildCalloutDebugTrace(
    HttpRequest req,
    HttpResponse res
  ) {
    List<String> parts = new List<String>();
    if (req != null) {
      parts.add('--- Callout Request ---');
      String contentType = req.getHeader('Content-Type');
      if (String.isNotBlank(contentType)) {
        parts.add('Content-Type: ' + contentType);
      }
      String body = req.getBody();
      if (String.isNotBlank(body)) {
        String truncated = DataVault_Error_LogRecordBuilder.truncate(
          body,
          MAX_CALLOUT_DEBUG_LENGTH
        );
        parts.add('Body (truncated): ' + truncated);
      }
    }
    if (res != null) {
      parts.add('--- Callout Response ---');
      parts.add('Status: ' + res.getStatusCode() + ' ' + res.getStatus());
      String body = res.getBody();
      if (String.isNotBlank(body)) {
        String truncated = DataVault_Error_LogRecordBuilder.truncate(
          body,
          MAX_CALLOUT_DEBUG_LENGTH
        );
        parts.add('Body (truncated): ' + truncated);
      }
    }
    if (parts.isEmpty()) {
      return null;
    }
    return DataVault_Error_LogRecordBuilder.truncate(
      String.join(parts, '\n'),
      MAX_STACK_LENGTH
    );
  }

  /**
   * @description
   * Persists all buffered log records in one DML. Call after critical error paths so logs are not lost in async contexts. Buffer may hold records that have not yet met the flush threshold; flush() guarantees they are written.
   */
  public static void flush() {
    DataVault_Error_LogBuffer.flush();
  }

  /**
   * @description
   * Checks if the current user has create access to DataVault_Error_Log__c via DataVault_Security_Utility. Avoids writing when the user lacks FLS/CRUD.
   * @return true if the user can create DataVault_Error_Log__c
   */
  private static Boolean isCreateable() {
    return DataVault_Security_Utility.isLoggerCreatable();
  }
}
