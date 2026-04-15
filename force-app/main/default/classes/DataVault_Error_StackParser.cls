/**
 * @description
 * Parses Apex stack trace strings to extract the first class and method name for error logging.
 *
 * What it is for:
 *  - Populates apexClassName and methodName on DataVault_Error_LogContext from the first line of
 *    an Apex stack trace (e.g. "ClassName.methodName(line:column)").
 *
 * Why it exists:
 *  - Error logs are more actionable when they include where the error occurred; stack traces
 *    are long and not always storable in full. Extracting the first frame gives a consistent,
 *    compact identifier without storing full stack text in every scenario.
 *  - Keeps parsing logic in one place so all callers (e.g. buildContextFromException) get the same behavior.
 *
 * AppExchange considerations:
 *  - Declared with sharing; no DML, no callouts, no user input beyond stack trace string.
 *  - Does not process or store PII; stack content is operational only and truncated by the logger.
 */
public with sharing class DataVault_Error_StackParser {
  /**
   * @description
   * Sets apexClassName and methodName on context from first line of stackTrace. Expects format like "ClassName.methodName(line)". No-op if stackTrace blank or unparseable.
   * @param stackTrace the stack trace string
   * @param ctx the context to populate (must not be null for updates)
   */
  public static void parse(String stackTrace, DataVault_Error_LogContext ctx) {
    if (String.isBlank(stackTrace) || ctx == null) {
      return;
    }
    String firstLine = firstLineOf(stackTrace);
    if (String.isBlank(firstLine) || !firstLine.contains('.')) {
      return;
    }
    String classAndMethod = substringBeforeLineInfo(firstLine);
    Integer lastDot = classAndMethod.lastIndexOf('.');
    if (lastDot <= 0) {
      return;
    }
    ctx.apexClassName = classAndMethod.substring(0, lastDot).trim();
    ctx.methodName = classAndMethod.substring(lastDot + 1).trim();
  }

  private static String firstLineOf(String stackTrace) {
    List<String> lines = stackTrace.split('\n');
    return lines.isEmpty() ? '' : lines.get(0);
  }

  private static String substringBeforeLineInfo(String line) {
    Integer paren = line.indexOf('(');
    if (paren > 0) {
      return line.substring(0, paren);
    }
    Integer colon = line.indexOf(':');
    if (colon > 0) {
      return line.substring(0, colon);
    }
    return line;
  }
}
