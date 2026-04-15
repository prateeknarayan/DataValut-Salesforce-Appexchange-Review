/**
 * @description
 * Buffered logging utility for DataVault_Error_Log__c that batches records and inserts in a single DML operation.
 *
 * What it is for:
 *  - Accumulates log records in memory and flushes them in bulk (single insert) when a size
 *    threshold or DML row limit is approached, so the package does not exceed governor limits
 *    or perform DML inside loops.
 *
 * Why it exists:
 *  - Multiple errors in one transaction (e.g. batch chunks) would otherwise require one insert
 *    per log; a buffer reduces DML statements and rows and keeps behavior predictable under load.
 *  - CRUD is checked and Security.stripInaccessible(CREATABLE) is applied before insert so
 *    only fields the user can create are written—required for AppExchange FLS enforcement.
 *  - Catches DmlException on insert so that logging failures do not cause recursive errors or
 *    interrupt the main flow.
 *
 * AppExchange considerations:
 *  - No DML inside loops; single bulk insert per flush.
 *  - Object-level CRUD and field-level security enforced via DataVault_Security_Utility and stripInaccessible.
 *  - Declared with sharing to respect subscriber org security.
 */
public with sharing class DataVault_Error_LogBuffer {
  private static final Integer FLUSH_SIZE_THRESHOLD = 100;
  private static List<DataVault_Error_Log__c> buffer = new List<DataVault_Error_Log__c>();
  /**
   * Stores the last DmlException from a failed flush so (1) the catch block is non-empty
   * for PMD compliance, (2) no System.debug is used (AppExchange security review), and
   * (3) tests can inspect the failure via @TestVisible without exposing it to callers.
   * Logging must never interrupt the main execution flow, so the exception is absorbed here.
   */
  @TestVisible
  private static DmlException lastFlushException;

  /**
   * @description
   * Adds a log entry to the in-memory buffer. May trigger flush if threshold or governor limit is near. Ensures logs are persisted in batches.
   * @param log the error log record to buffer (ignored if null)
   */
  public static void add(DataVault_Error_Log__c log) {
    if (log == null) {
      return;
    }
    buffer.add(log);
    maybeFlush();
  }

  /**
   * @description
   * Flushes all buffered records in a single DML operation. No-op if buffer is empty or user lacks create access. Single insert respects governor limits and FLS.
   */
  public static void flush() {
    if (buffer.isEmpty()) {
      return;
    }

    if (!DataVault_Security_Utility.isLoggerCreatable()) {
      buffer.clear();
      return;
    }

    if (!canSafelyFlush()) {
      buffer.clear();
      return;
    }

    List<DataVault_Error_Log__c> toInsert = new List<DataVault_Error_Log__c>(
      buffer
    );

    buffer.clear();

    List<DataVault_Error_Log__c> safe = DataVault_Security_Utility.stripErrorLogCreatable(
      toInsert
    );

    if (safe.isEmpty()) {
      return;
    }
    try {
      insert as user safe;
    } catch (DmlException e) {
      lastFlushException = e;
    }
  }

  /**
   * @description
   * Flushes buffer when size threshold or DML row limit is near. Called after each add() so batches are written in time.
   */
  public static void maybeFlush() {
    if (shouldFlush()) {
      flush();
    }
  }

  /**
   * @description
   * Determines whether buffer should be flushed based on buffer size threshold, proximity to DML row governor limit, and DML statement governor limit.
   * @return true if buffer should be flushed
   */
  private static Boolean shouldFlush() {
    Integer limitRows = Limits.getLimitDmlRows();
    Integer usedRows = Limits.getDmlRows();

    Boolean nearRowLimit = usedRows + buffer.size() >= limitRows - 1;

    Boolean nearStatementLimit =
      Limits.getDmlStatements() >= Limits.getLimitDmlStatements() - 1;

    Boolean sizeThresholdReached = buffer.size() >= FLUSH_SIZE_THRESHOLD;

    return nearRowLimit || nearStatementLimit || sizeThresholdReached;
  }

  /**
   * @description
   * Checks whether it is safe to perform a DML insert within the current transaction. Returns false if DML statements or DML rows are at or above governor limits.
   * @return true if at least one DML statement and one DML row remain
   */
  public static Boolean canSafelyFlush() {
    return Limits.getDmlStatements() < Limits.getLimitDmlStatements() &&
      Limits.getDmlRows() + buffer.size() <= Limits.getLimitDmlRows();
  }
}
