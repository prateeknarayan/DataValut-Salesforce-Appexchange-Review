/**
 * @description
 * Test class for DataVault_Error_StackParser.
 *
 * What it is for: Verifies parse() handles valid stack traces, blank/null input, missing dot,
 * single-segment names, and parentheses so the parser never throws and populates context correctly.
 *
 * AppExchange considerations: Pure unit tests; no DML; no SeeAllData; covers all branches.
 */
@IsTest
private class DataVault_Error_StackParserTest {
  /**
   * @description
   * Verifies parse extracts className and methodName from a standard Apex stack trace.
   */
  @IsTest
  static void parseValidStackTracePopulatesContext() {
    DataVault_Error_LogContext ctx = new DataVault_Error_LogContext();
    String stackTrace = 'DataVaultExportBatch.execute: line 88, column 1\nDataVaultExportBatch.start: line 62, column 1';

    Test.startTest();
    DataVault_Error_StackParser.parse(stackTrace, ctx);
    Test.stopTest();

    System.assertEquals(
      'DataVaultExportBatch',
      ctx.apexClassName,
      'Class name should be extracted from first line'
    );
    System.assertEquals(
      'execute',
      ctx.methodName,
      'Method name should be extracted from first line'
    );
  }

  /**
   * @description
   * Verifies parse handles stack trace with parenthesized line info.
   */
  @IsTest
  static void parseWithParenthesesExtractsCorrectly() {
    DataVault_Error_LogContext ctx = new DataVault_Error_LogContext();
    String stackTrace = 'MyClass.myMethod(line 10, col 1)';

    Test.startTest();
    DataVault_Error_StackParser.parse(stackTrace, ctx);
    Test.stopTest();

    System.assertEquals(
      'MyClass',
      ctx.apexClassName,
      'Class name should be parsed before parenthesis'
    );
    System.assertEquals(
      'myMethod',
      ctx.methodName,
      'Method name should be parsed before parenthesis'
    );
  }

  /**
   * @description
   * Verifies parse is a no-op for blank stack trace.
   */
  @IsTest
  static void parseBlankStackTraceDoesNothing() {
    DataVault_Error_LogContext ctx = new DataVault_Error_LogContext();
    ctx.apexClassName = 'Original';

    Test.startTest();
    DataVault_Error_StackParser.parse('', ctx);
    DataVault_Error_StackParser.parse(null, ctx);
    Test.stopTest();

    System.assertEquals(
      'Original',
      ctx.apexClassName,
      'Context should not be modified for blank input'
    );
  }

  /**
   * @description
   * Verifies parse is a no-op when context is null.
   */
  @IsTest
  static void parseNullContextDoesNotThrow() {
    Test.startTest();
    DataVault_Error_StackParser.parse('SomeClass.someMethod', null);
    Test.stopTest();

    System.assert(true, 'parse with null context must not throw');
  }

  /**
   * @description
   * Verifies parse is a no-op when first line has no dot separator.
   */
  @IsTest
  static void parseNoDotDoesNothing() {
    DataVault_Error_LogContext ctx = new DataVault_Error_LogContext();

    Test.startTest();
    DataVault_Error_StackParser.parse('NoDotHere', ctx);
    Test.stopTest();

    System.assertEquals(
      null,
      ctx.apexClassName,
      'Context should remain null when no dot present'
    );
  }

  /**
   * @description
   * Verifies parse is a no-op when dot is at position 0 (no class name).
   */
  @IsTest
  static void parseDotAtStartDoesNothing() {
    DataVault_Error_LogContext ctx = new DataVault_Error_LogContext();

    Test.startTest();
    DataVault_Error_StackParser.parse('.methodOnly', ctx);
    Test.stopTest();

    System.assertEquals(
      null,
      ctx.apexClassName,
      'Context should remain null when dot is at start'
    );
  }
}
