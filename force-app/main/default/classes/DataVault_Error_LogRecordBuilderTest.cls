/**
 * @description
 * Test class for DataVault_Error_LogRecordBuilder.
 *
 * What it is for: Verifies build() with null context, valid context, and truncate() edge cases
 * so the record builder is fully exercised.
 *
 * AppExchange considerations: No DML; pure unit tests; no SeeAllData.
 */
@IsTest
private class DataVault_Error_LogRecordBuilderTest {
  /**
   * @description
   * Verifies build(null) returns null.
   */
  @IsTest
  static void buildNullReturnsNull() {
    Test.startTest();
    DataVault_Error_Log__c result = DataVault_Error_LogRecordBuilder.build(
      null
    );
    Test.stopTest();
    System.assertEquals(null, result, 'build(null) should return null');
  }

  /**
   * @description
   * Verifies build with a fully populated context returns a valid record.
   */
  @IsTest
  static void buildWithContextReturnsRecord() {
    DataVault_Error_LogContext ctx = new DataVault_Error_LogContext();
    ctx.errorType = 'General Apex Exception';
    ctx.errorMessage = 'Test error';
    ctx.stackTrace = 'TestClass.testMethod line 42';
    ctx.apexClassName = 'TestClass';
    ctx.methodName = 'testMethod';
    ctx.timestamp = System.now();

    Test.startTest();
    DataVault_Error_Log__c result = DataVault_Error_LogRecordBuilder.build(ctx);
    Test.stopTest();

    System.assert(result != null, 'build should return non-null');
    System.assertEquals(
      'General Apex Exception',
      result.Error_Type__c,
      'Error type should match'
    );
    System.assertEquals(
      'Test error',
      result.Error_Message__c,
      'Error message should match'
    );
    System.assertEquals(
      'TestClass',
      result.Apex_Class_Name__c,
      'Class name should match'
    );
    System.assertEquals(
      'testMethod',
      result.Method_Name__c,
      'Method name should match'
    );
  }

  /**
   * @description
   * Verifies build sets default error type when context errorType is blank.
   */
  @IsTest
  static void buildBlankErrorTypeUsesDefault() {
    DataVault_Error_LogContext ctx = new DataVault_Error_LogContext();
    ctx.errorMessage = 'Test error';

    Test.startTest();
    DataVault_Error_Log__c result = DataVault_Error_LogRecordBuilder.build(ctx);
    Test.stopTest();

    System.assertEquals(
      DataVault_Error_Logger.ERR_APEX_EXCEPTION,
      result.Error_Type__c,
      'Blank errorType should default to General Apex Exception'
    );
  }

  /**
   * @description
   * Verifies build sets timestamp to now when context timestamp is null.
   */
  @IsTest
  static void buildNullTimestampUsesNow() {
    DataVault_Error_LogContext ctx = new DataVault_Error_LogContext();
    ctx.errorMessage = 'Test';
    ctx.timestamp = null;

    Test.startTest();
    DataVault_Error_Log__c result = DataVault_Error_LogRecordBuilder.build(ctx);
    Test.stopTest();

    System.assert(
      result.Timestamp__c != null,
      'Timestamp should default to now'
    );
  }

  /**
   * @description
   * Verifies truncate returns null for blank input.
   */
  @IsTest
  static void truncateBlankReturnsNull() {
    Test.startTest();
    String result = DataVault_Error_LogRecordBuilder.truncate('', 100);
    String resultNull = DataVault_Error_LogRecordBuilder.truncate(null, 100);
    Test.stopTest();
    System.assertEquals(null, result, 'Blank string should return null');
    System.assertEquals(null, resultNull, 'Null string should return null');
  }

  /**
   * @description
   * Verifies truncate returns the full string when within limit.
   */
  @IsTest
  static void truncateWithinLimitReturnsFullString() {
    Test.startTest();
    String result = DataVault_Error_LogRecordBuilder.truncate('short', 100);
    Test.stopTest();
    System.assertEquals(
      'short',
      result,
      'Short string should be returned as-is'
    );
  }

  /**
   * @description
   * Verifies truncate truncates when string exceeds limit.
   */
  @IsTest
  static void truncateOverLimitTruncates() {
    Test.startTest();
    String result = DataVault_Error_LogRecordBuilder.truncate('abcdefghij', 5);
    Test.stopTest();
    System.assertEquals(
      'abcde',
      result,
      'String should be truncated to maxLen'
    );
  }
}
