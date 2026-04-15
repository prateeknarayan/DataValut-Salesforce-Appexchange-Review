/**
 * @description
 * Dedicated test class for DataVault_Error_LogContext to ensure coverage is tracked.
 *
 * AppExchange considerations: Pure unit test; no DML; no SeeAllData.
 */
@IsTest
private class DataVault_Error_LogContextTest {
  /**
   * @description
   * Verifies all public fields can be set and read back correctly.
   */
  @IsTest
  static void allFieldsCanBeSetAndRead() {
    DateTime now = System.now();
    DataVault_Error_LogContext ctx = new DataVault_Error_LogContext();
    ctx.errorType = 'General Apex Exception';
    ctx.errorMessage = 'Something went wrong';
    ctx.stackTrace = 'MyClass.myMethod: line 10';
    ctx.apexClassName = 'MyClass';
    ctx.methodName = 'myMethod';
    ctx.timestamp = now;

    System.assertEquals(
      'General Apex Exception',
      ctx.errorType,
      'errorType mismatch'
    );
    System.assertEquals(
      'Something went wrong',
      ctx.errorMessage,
      'errorMessage mismatch'
    );
    System.assertEquals(
      'MyClass.myMethod: line 10',
      ctx.stackTrace,
      'stackTrace mismatch'
    );
    System.assertEquals('MyClass', ctx.apexClassName, 'apexClassName mismatch');
    System.assertEquals('myMethod', ctx.methodName, 'methodName mismatch');
    System.assertEquals(now, ctx.timestamp, 'timestamp mismatch');
  }

  /**
   * @description
   * Verifies default state is null for all fields.
   */
  @IsTest
  static void defaultFieldsAreNull() {
    DataVault_Error_LogContext ctx = new DataVault_Error_LogContext();
    System.assertEquals(
      null,
      ctx.errorType,
      'errorType should default to null'
    );
    System.assertEquals(
      null,
      ctx.errorMessage,
      'errorMessage should default to null'
    );
    System.assertEquals(
      null,
      ctx.stackTrace,
      'stackTrace should default to null'
    );
    System.assertEquals(
      null,
      ctx.apexClassName,
      'apexClassName should default to null'
    );
    System.assertEquals(
      null,
      ctx.methodName,
      'methodName should default to null'
    );
    System.assertEquals(
      null,
      ctx.timestamp,
      'timestamp should default to null'
    );
  }
}
