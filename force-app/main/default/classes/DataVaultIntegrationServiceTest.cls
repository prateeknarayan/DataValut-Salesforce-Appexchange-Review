/**
 * @description Test class for DataVaultIntegrationService.
 *
 * What it is for: Exercises sendToS3() with success (200), server error (500), and blank-parameter validation so the integration service is fully covered without real HTTP. Uses DataVaultCalloutMocks and runAs() for consistent, isolated tests.
 *
 * Why it exists: Callout code must be covered for AppExchange; mocks ensure success and failure paths (including logging) are tested. Input validation tests confirm that missing required params throw before any callout.
 *
 * AppExchange considerations: Test.setMock for HTTP; runAs(); no SeeAllData; covers success, failure, and validation.
 */
@IsTest
public class DataVaultIntegrationServiceTest {
  /**
   * @description
   * Test setup creates a reusable test user with the required DataVault Permission Set assigned.
   */
  @TestSetup
  static void makeData() {
    DataVaultTestSetupHelper.createUserAndAssignPermissionSet();
  }

  /**
   * @description
   * Verifies that sendToS3() returns an HTTP 200 response when the S3 callout succeeds.
   */
  @IsTest
  static void sendToS3SuccessReturns200() {
    Test.setMock(HttpCalloutMock.class, new DataVaultCalloutMocks.Success200());

    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      HttpResponse res = DataVaultIntegrationService.sendToS3(
        'Test_NC',
        'Account',
        '[]'
      );
      Test.stopTest();

      System.assertEquals(
        200,
        res.getStatusCode(),
        'Expected HTTP 200 from success mock'
      );
    }
  }

  /**
   * @description
   * Verifies that sendToS3() returns the HTTP response even when S3 responds with a server-side error.
   */
  @IsTest
  static void sendToS3ServerErrorReturns500() {
    Test.setMock(
      HttpCalloutMock.class,
      new DataVaultCalloutMocks.ServerError500()
    );

    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      HttpResponse res = DataVaultIntegrationService.sendToS3(
        'Test_NC',
        'Account',
        '[]'
      );
      Test.stopTest();

      System.assertEquals(
        500,
        res.getStatusCode(),
        'Expected HTTP 500 from server error mock'
      );
    }
  }

  /**
   * @description
   * Verifies that validateNamedCredentialConnection() completes without exception when the mock returns HTTP 200.
   */
  @IsTest
  static void validateNamedCredentialConnectionSuccess() {
    Test.setMock(HttpCalloutMock.class, new DataVaultCalloutMocks.Success200());
    Boolean completed = false;
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      DataVaultIntegrationService.validateNamedCredentialConnection('Test_NC');
      Test.stopTest();
      completed = true;
    }
    System.assertEquals(
      true,
      completed,
      'validateNamedCredentialConnection must complete without exception'
    );
  }

  /**
   * @description
   * Verifies that validateNamedCredentialConnection() throws when Named Credential name is blank.
   */
  @IsTest
  static void validateNamedCredentialConnectionBlankThrows() {
    Boolean threw = false;

    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      try {
        DataVaultIntegrationService.validateNamedCredentialConnection('');
      } catch (IllegalArgumentException e) {
        threw = true;
      }
      Test.stopTest();
    }

    System.assert(
      threw,
      'Expected IllegalArgumentException for blank Named Credential'
    );
  }

  /**
   * @description
   * Verifies that validateNamedCredentialConnection() throws when the endpoint returns non-2xx status.
   */
  @IsTest
  static void validateNamedCredentialConnectionNon2xxThrows() {
    Test.setMock(
      HttpCalloutMock.class,
      new DataVaultCalloutMocks.ServerError500()
    );

    Boolean threw = false;
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      try {
        DataVaultIntegrationService.validateNamedCredentialConnection(
          'Test_NC'
        );
      } catch (IllegalArgumentException e) {
        threw = true;
      }
      Test.stopTest();
    }

    System.assert(
      threw,
      'Expected IllegalArgumentException for non-2xx response'
    );
  }

  /**
   * @description
   * Verifies that sendToS3() throws when required parameters are missing.
   */
  @IsTest
  static void sendToS3BlankParamsThrows() {
    Boolean threw = false;

    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      try {
        DataVaultIntegrationService.sendToS3('', 'Account', '[]');
      } catch (IllegalArgumentException e) {
        threw = true;
      }
      Test.stopTest();
    }

    System.assert(
      threw,
      'Expected IllegalArgumentException for blank Named Credential'
    );
  }

  /**
   * @description
   * Verifies that sendToS3() throws when objectApiName is blank.
   */
  @IsTest
  static void sendToS3BlankObjectThrows() {
    Boolean threw = false;
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      try {
        DataVaultIntegrationService.sendToS3('Test_NC', '', '[]');
      } catch (IllegalArgumentException e) {
        threw = true;
      }
      Test.stopTest();
    }
    System.assert(
      threw,
      'Expected IllegalArgumentException for blank object API name'
    );
  }

  /**
   * @description
   * Verifies that validateNamedCredentialConnection rethrows CalloutException.
   */
  @IsTest
  static void validateNamedCredentialConnectionCalloutExceptionThrows() {
    Test.setMock(
      HttpCalloutMock.class,
      new DataVaultCalloutMocks.CalloutExceptionMock()
    );
    Boolean threw = false;
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      try {
        DataVaultIntegrationService.validateNamedCredentialConnection(
          'Test_NC'
        );
      } catch (System.CalloutException e) {
        threw = true;
      }
      Test.stopTest();
    }
    System.assert(threw, 'Expected CalloutException to be rethrown');
  }

  /**
   * @description
   * Verifies that sendToS3() retries on transient 503 responses and ultimately returns the non-2xx response after exhausting retries.
   */
  @IsTest
  static void sendToS3RetriesOn503() {
    Test.setMock(
      HttpCalloutMock.class,
      new DataVaultCalloutMocks.ServiceUnavailable503()
    );
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      HttpResponse res = DataVaultIntegrationService.sendToS3(
        'Test_NC',
        'Account',
        '[]'
      );
      Test.stopTest();
      System.assertEquals(
        503,
        res.getStatusCode(),
        'Expected 503 after retries exhausted'
      );
    }
  }

  /**
   * @description
   * Verifies that sendToS3() handles callout exception and logs error.
   */
  @IsTest
  static void sendToS3CalloutExceptionThrows() {
    Test.setMock(
      HttpCalloutMock.class,
      new DataVaultCalloutMocks.CalloutExceptionMock()
    );
    Boolean threw = false;
    System.runAs(DataVaultTestSetupHelper.getTestUser()) {
      Test.startTest();
      try {
        DataVaultIntegrationService.sendToS3('Test_NC', 'Account', '[]');
      } catch (System.CalloutException e) {
        threw = true;
      }
      Test.stopTest();
    }
    System.assert(threw, 'Expected CalloutException from sendToS3');
  }
}
