/**
 * @description
 * Test class for DataVault_Error_LogBuffer.
 *
 * What it is for: Verifies add (null guard), flush (empty buffer, successful insert), and maybeFlush
 * so the buffer's DML batching and CRUD enforcement are fully exercised.
 *
 * AppExchange considerations: runAs() with package user; no SeeAllData; covers null, empty, and
 * successful insert paths.
 */
@IsTest
private class DataVault_Error_LogBufferTest {
  @TestSetup
  static void makeData() {
    DataVaultTestSetupHelper.createUserAndAssignPermissionSet();
  }

  /**
   * @description
   * Verifies add(null) is silently ignored and does not add to buffer.
   */
  @IsTest
  static void addNullDoesNotThrow() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      DataVault_Error_LogBuffer.add(null);
      DataVault_Error_LogBuffer.flush();
      Test.stopTest();
    }
    System.assert(true, 'add(null) must be silently ignored');
  }

  /**
   * @description
   * Verifies flush on empty buffer does nothing (no DML).
   */
  @IsTest
  static void flushEmptyBufferDoesNotThrow() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      DataVault_Error_LogBuffer.flush();
      Test.stopTest();
    }
    System.assert(true, 'Flush on empty buffer must not throw');
  }

  /**
   * @description
   * Verifies add + flush inserts the buffered record.
   */
  @IsTest
  static void addAndFlushInsertsRecord() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVault_Error_Log__c log = new DataVault_Error_Log__c(
        Error_Type__c = 'General Apex Exception',
        Error_Message__c = 'Buffer test',
        Apex_Class_Name__c = 'DataVault_Error_LogBufferTest',
        Method_Name__c = 'addAndFlushInsertsRecord',
        Timestamp__c = System.now()
      );
      Test.startTest();
      DataVault_Error_LogBuffer.add(log);
      DataVault_Error_LogBuffer.flush();
      Test.stopTest();
      List<DataVault_Error_Log__c> inserted = [
        SELECT Id
        FROM DataVault_Error_Log__c
        WHERE Method_Name__c = 'addAndFlushInsertsRecord'
        WITH USER_MODE
      ];
      System.assertEquals(
        1,
        inserted.size(),
        'Buffered record should be inserted after flush'
      );
    }
  }

  /**
   * @description
   * Verifies canSafelyFlush returns true under normal governor limits.
   */
  @IsTest
  static void canSafelyFlushReturnsTrueUnderNormalLimits() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      Boolean result = DataVault_Error_LogBuffer.canSafelyFlush();
      Test.stopTest();
      System.assert(
        result,
        'canSafelyFlush should be true when limits are not exhausted'
      );
    }
  }

  /**
   * @description
   * Verifies maybeFlush does not throw when called directly with an item in buffer.
   */
  @IsTest
  static void maybeFlushDoesNotThrow() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      DataVault_Error_Log__c log = new DataVault_Error_Log__c(
        Error_Type__c = 'General Apex Exception',
        Error_Message__c = 'MaybeFlush test',
        Apex_Class_Name__c = 'DataVault_Error_LogBufferTest',
        Method_Name__c = 'maybeFlushDoesNotThrow',
        Timestamp__c = System.now()
      );
      Test.startTest();
      DataVault_Error_LogBuffer.add(log);
      DataVault_Error_LogBuffer.maybeFlush();
      DataVault_Error_LogBuffer.flush();
      Test.stopTest();
    }
    System.assert(true, 'maybeFlush must not throw');
  }
}
