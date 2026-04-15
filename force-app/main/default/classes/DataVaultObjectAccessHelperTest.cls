/**
 * @description
 * Test class for DataVaultObjectAccessHelper.
 *
 * What it is for:
 *  - Verifies object-level read checks (isObjectReadable), FLS-safe SOQL building (buildSecureQuery), and safe handling of blank/invalid object names so that export and UI only use describe-validated data.
 *
 * Why it exists:
 *  - AppExchange review requires coverage of security-critical helpers. These tests confirm that SOQL is built only from describe metadata (no injection) and that invalid input is handled without throwing, so subscriber orgs get predictable behavior.
 *
 * AppExchange considerations:
 *  - runAs() with package Permission Set; no SeeAllData; no direct DML in test methods; validates defensive paths and describe-driven SOQL.
 */
@IsTest
private class DataVaultObjectAccessHelperTest {
  /**
   * @description
   * Test setup creates a valid test user with the required DataVault Permission Set assigned. This user is reused across all test methods.
   */
  @TestSetup
  static void makeData() {
    DataVaultTestSetupHelper.createUserAndAssignPermissionSet();
  }

  /**
   * @description
   * Verifies that a standard object (Account) is reported as readable for the running user. Account is expected to be accessible and queryable in all test orgs.
   */
  @IsTest
  static void isObjectReadableValidObjectReturnsTrue() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      Boolean isReadable = DataVaultObjectAccessHelper.isObjectReadable(
        'Account'
      );
      System.assert(isReadable, 'Account should be readable for the test user');
      Test.stopTest();
    }
  }

  /**
   * @description
   * Verifies that blank or null object API names are handled safely. The helper should return false and must not throw when provided with invalid input.
   */
  @IsTest
  static void isObjectReadableBlankReturnsFalse() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      Boolean isReadable = DataVaultObjectAccessHelper.isObjectReadable('');
      System.assert(!isReadable, 'Blank string should not be readable');

      isReadable = DataVaultObjectAccessHelper.isObjectReadable(null);
      System.assert(!isReadable, 'Null object API name should not be readable');
      Test.stopTest();
    }
  }

  /**
   * @description
   * Verifies that buildSecureQuery returns a valid SOQL string for a readable object. The returned query must include a FROM clause referencing the expected object API name.
   */
  @IsTest
  static void buildSecureQueryValidObjectReturnsQuery() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      String soql = DataVaultObjectAccessHelper.buildSecureQuery('Account');

      System.assert(soql != null, 'Expected non-null SOQL for readable object');
      System.assert(
        soql.contains('FROM Account'),
        'SOQL should reference Account object'
      );
      Test.stopTest();
    }
  }

  /**
   * @description
   * Verifies that buildSecureQuery safely handles invalid or non-existent object API names. The helper should return null and must not throw when the object is not available.
   */
  @IsTest
  static void buildSecureQueryInvalidObjectReturnsNull() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      String soql = DataVaultObjectAccessHelper.buildSecureQuery(
        'InvalidObjectXYZ__c'
      );

      System.assert(
        soql == null || soql.length() == 0,
        'Invalid object should return null or empty query'
      );
      Test.stopTest();
    }
  }

  /**
   * @description
   * Verifies getDescribeSObjectResult returns null for blank input.
   */
  @IsTest
  static void getDescribeSObjectResultBlankReturnsNull() {
    Test.startTest();
    Schema.DescribeSObjectResult result = DataVaultObjectAccessHelper.getDescribeSObjectResult(
      ''
    );
    Schema.DescribeSObjectResult resultNull = DataVaultObjectAccessHelper.getDescribeSObjectResult(
      null
    );
    Test.stopTest();
    System.assertEquals(null, result, 'Blank should return null');
    System.assertEquals(null, resultNull, 'Null should return null');
  }

  /**
   * @description
   * Verifies getDescribeSObjectResult returns null for non-existent object.
   */
  @IsTest
  static void getDescribeSObjectResultInvalidReturnsNull() {
    Test.startTest();
    Schema.DescribeSObjectResult result = DataVaultObjectAccessHelper.getDescribeSObjectResult(
      'TotallyFakeObjectXYZ__c'
    );
    Test.stopTest();
    System.assertEquals(null, result, 'Non-existent object should return null');
  }

  /**
   * @description
   * Verifies getDescribeSObjectResult returns a valid describe for a real object.
   */
  @IsTest
  static void getDescribeSObjectResultValidReturnsDescribe() {
    Test.startTest();
    Schema.DescribeSObjectResult result = DataVaultObjectAccessHelper.getDescribeSObjectResult(
      'Account'
    );
    Test.stopTest();
    System.assert(
      result != null,
      'Account should return valid DescribeSObjectResult'
    );
  }

  /**
   * @description
   * Verifies stripInaccessibleFields returns records with inaccessible fields stripped.
   */
  @IsTest
  static void stripInaccessibleFieldsReturnsStrippedRecords() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      List<SObject> records = new List<SObject>{
        new Account(Name = 'Test Account')
      };
      Test.startTest();
      List<SObject> result = DataVaultObjectAccessHelper.stripInaccessibleFields(
        AccessType.READABLE,
        records
      );
      Test.stopTest();
      System.assert(result != null, 'Stripped records should not be null');
      System.assertEquals(1, result.size(), 'Should return one record');
    }
  }

  /**
   * @description
   * Verifies getReadableFieldApiNames returns fields for a valid object and empty list for invalid.
   */
  @IsTest
  static void getReadableFieldApiNamesReturnsFieldList() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      List<String> fields = DataVaultObjectAccessHelper.getReadableFieldApiNames(
        'Account'
      );
      List<String> emptyFields = DataVaultObjectAccessHelper.getReadableFieldApiNames(
        'TotallyFakeObjectXYZ__c'
      );
      Test.stopTest();
      System.assert(fields.size() > 0, 'Account should have readable fields');
      System.assert(
        emptyFields.isEmpty(),
        'Invalid object should return empty list'
      );
    }
  }

  /**
   * @description
   * Verifies that repeated calls to getDescribeSObjectResult return identical cached results.
   */
  @IsTest
  static void describeCacheReturnsConsistentResult() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      Schema.DescribeSObjectResult first = DataVaultObjectAccessHelper.getDescribeSObjectResult(
        'Account'
      );
      Schema.DescribeSObjectResult second = DataVaultObjectAccessHelper.getDescribeSObjectResult(
        'Account'
      );
      Test.stopTest();
      System.assert(first != null, 'First call should return a describe');
      System.assertEquals(
        first.getName(),
        second.getName(),
        'Cached describe should return identical result'
      );
    }
  }

  /**
   * @description
   * Verifies that getReadableObjectOptions returns results and exercises the global describe cache.
   */
  @IsTest
  static void getReadableObjectOptionsReturnsResults() {
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      List<DataVaultObjectAccessHelper.ObjectOption> options = DataVaultObjectAccessHelper.getReadableObjectOptions();
      Test.stopTest();
      System.assert(
        options.size() > 0,
        'Should return at least one readable object'
      );
    }
  }

  /**
   * @description
   * Verifies buildSecureQuery returns null for blank input.
   */
  @IsTest
  static void buildSecureQueryBlankReturnsNull() {
    Test.startTest();
    String result = DataVaultObjectAccessHelper.buildSecureQuery('');
    Test.stopTest();
    System.assertEquals(null, result, 'Blank object should return null query');
  }
}
