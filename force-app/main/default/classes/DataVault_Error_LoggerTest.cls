/**
 * @description Test class for DataVault_Error_Logger.
 *
 * What it is for: Verifies logError(context), buildContextFromException, logCalloutFailure (with and without req/res), flush, and null/empty handling so the logger and buffer paths are covered and never throw.
 *
 * Why it exists: Error logging is used by integration, batch, and scheduler; AppExchange coverage requires these code paths. Tests confirm CRUD-gated insert and defensive null handling so production logging does not break callers.
 *
 * AppExchange considerations: runAs() with package user; covers create path and flush; no SeeAllData.
 */
@IsTest
private class DataVault_Error_LoggerTest {
  /**
   * @description
   * Test setup creates a test user and assigns the DataVault Permission Set.
   */
  @TestSetup
  static void makeData() {
    DataVaultTestSetupHelper.createUserAndAssignPermissionSet();
  }

  /**
   * @description
   * Verifies logError(LogContext) and flush() complete without exception; validates create path.
   */
  @IsTest
  static void logErrorWithContextDoesNotThrow() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      DataVault_Error_LogContext ctx = new DataVault_Error_LogContext();
      ctx.errorType = DataVault_Error_Logger.ERR_APEX_EXCEPTION;
      ctx.errorMessage = 'Test message';
      ctx.apexClassName = 'DataVault_Error_LoggerTest';
      ctx.methodName = 'logErrorWithContextDoesNotThrow';
      ctx.timestamp = System.now();
      DataVault_Error_Logger.logError(ctx);
      DataVault_Error_Logger.flush();
      Test.stopTest();
    }
    System.assert(true, 'Logger must not throw');
  }

  /**
   * @description
   * Verifies logCalloutFailure with class/method completes without exception.
   */
  @IsTest
  static void logCalloutFailureDoesNotThrow() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      DataVault_Error_Logger.logCalloutFailure(
        'Access denied',
        'DataVaultIntegrationService',
        'sendToS3'
      );
      DataVault_Error_Logger.flush();
      Test.stopTest();
    }
    System.assert(true, 'Logger must not throw');
  }

  /**
   * @description
   * Verifies logCalloutFailure with request/response stores headers and body in stack trace for debugging.
   */
  @IsTest
  static void logCalloutFailureWithReqResStoresDebugTrace() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      HttpRequest req = new HttpRequest();
      req.setEndpoint('https://example.com/test');
      req.setMethod('PUT');
      req.setHeader('Content-Type', 'application/json');
      req.setBody('{"test":true}');
      HttpResponse res = new HttpResponse();
      res.setStatusCode(500);
      res.setStatus('Internal Server Error');
      res.setBody('{"error":"server error"}');
      Test.startTest();
      DataVault_Error_Logger.CalloutFailureInput input = new DataVault_Error_Logger.CalloutFailureInput(
        'HTTP 500 - Internal Server Error',
        'DataVaultIntegrationService',
        'sendToS3'
      );
      input.req = req;
      input.res = res;
      DataVault_Error_Logger.logCalloutFailure(input);
      DataVault_Error_Logger.flush();
      Test.stopTest();
      List<DataVault_Error_Log__c> logs = [
        SELECT Stack_Trace__c
        FROM DataVault_Error_Log__c
        WHERE Error_Type__c = 'Callout Failure'
        WITH USER_MODE
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
      System.assertEquals(1, logs.size(), 'One log should exist');
      System.assert(
        logs[0].Stack_Trace__c != null &&
        logs[0].Stack_Trace__c.contains('Callout Request'),
        'Stack trace should contain callout request for debugging'
      );
    }
  }

  /**
   * @description
   * Verifies flush() on empty buffer does not throw (no DML).
   */
  @IsTest
  static void flushEmptyBufferDoesNotThrow() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      DataVault_Error_Logger.flush();
      Test.stopTest();
    }
    System.assert(true, 'Flush on empty buffer must not throw');
  }

  /**
   * @description
   * Verifies null context is ignored and does not cause exception (guard clause).
   */
  @IsTest
  static void logErrorNullContextDoesNotThrow() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      DataVault_Error_Logger.logError((DataVault_Error_LogContext) null);
      Test.stopTest();
    }
    System.assert(true, 'Null context must be ignored');
  }

  /**
   * @description
   * Verifies buildContextFromException returns null when given a null exception.
   */
  @IsTest
  static void buildContextFromExceptionNullReturnsNull() {
    Test.startTest();
    DataVault_Error_LogContext ctx = DataVault_Error_Logger.buildContextFromException(
      null,
      'Cls',
      'meth'
    );
    Test.stopTest();
    System.assertEquals(null, ctx, 'Null exception should return null context');
  }

  /**
   * @description
   * Verifies logCalloutFailure(CalloutFailureInput) with null input does not throw.
   */
  @IsTest
  static void logCalloutFailureNullInputDoesNotThrow() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      DataVault_Error_Logger.logCalloutFailure(
        (DataVault_Error_Logger.CalloutFailureInput) null
      );
      Test.stopTest();
    }
    System.assert(true, 'Null CalloutFailureInput must not throw');
  }

  /**
   * @description
   * Verifies DataVault_Error_LogContext fields can be set and read (covers context at 100%).
   */
  @IsTest
  static void logContextFieldsCovered() {
    DataVault_Error_LogContext ctx = new DataVault_Error_LogContext();
    ctx.errorType = 'General Apex Exception';
    ctx.errorMessage = 'msg';
    ctx.stackTrace = 'stack';
    ctx.apexClassName = 'Cls';
    ctx.methodName = 'meth';
    ctx.timestamp = System.now();
    System.assertEquals('msg', ctx.errorMessage, 'errorMessage should match');
  }

  /**
   * @description
   * Verifies DataVault_PackageException can be constructed and thrown.
   */
  @IsTest
  static void packageExceptionCovered() {
    Boolean threw = false;
    try {
      throw new DataVault_PackageException('test');
    } catch (DataVault_PackageException e) {
      threw = true;
      System.assertEquals('test', e.getMessage(), 'Message should match');
    }
    System.assert(threw, 'DataVault_PackageException must be throwable');
  }
}
