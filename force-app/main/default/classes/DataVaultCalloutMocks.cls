/**
 * @description
 * Centralized HttpCalloutMock implementations for DataVault integration and batch tests.
 *
 * What it is for:
 *  - Provides Test.setMock() implementations that simulate success (200), server error (500), and callout failure (CalloutException) so DataVaultIntegrationService and DataVaultExportBatch can be tested without real HTTP calls.
 *
 * Why it exists:
 *  - Tests must cover success and failure paths for AppExchange coverage and security review; a single place for mocks avoids duplication and keeps behavior consistent across DataVaultIntegrationServiceTest and DataVaultExportBatchTest. No real requests or org-specific config—safe for any org.
 *
 * AppExchange considerations:
 *  - Test-only; no real HTTP; no dependency on org data or credentials.
 */
@IsTest
public class DataVaultCalloutMocks {
  /**
   * @description
   * Mock that returns HTTP 200 OK. Validates that successful S3 upload path completes and does not log errors.
   */
  public class Success200 implements HttpCalloutMock {
    /**
     * @description
     * Builds a 200 OK response.
     * @param req the HTTP request (unused in mock)
     * @return HttpResponse with status 200 and status 'OK'
     */
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setStatus('OK');
      return res;
    }
  }

  /**
   * @description
   * Mock that returns HTTP 500. Validates that non-2xx responses are logged and (in batch) counted as errors without crashing.
   */
  public class ServerError500 implements HttpCalloutMock {
    /**
     * @description
     * Builds a 500 Internal Server Error response.
     * @param req the HTTP request (unused in mock)
     * @return HttpResponse with status 500 and error body
     */
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(500);
      res.setStatus('Internal Server Error');
      res.setBody('{"error":"failure"}');
      return res;
    }
  }

  /**
   * @description
   * Mock that returns HTTP 503 Service Unavailable. Validates retry logic for transient server failures.
   */
  public class ServiceUnavailable503 implements HttpCalloutMock {
    /**
     * @description
     * Builds a 503 Service Unavailable response.
     * @param req the HTTP request (unused in mock)
     * @return HttpResponse with status 503
     */
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(503);
      res.setStatus('Service Unavailable');
      res.setBody('{"error":"service unavailable"}');
      return res;
    }
  }

  /**
   * @description
   * Mock that throws CalloutException. Validates that timeouts/network failures are logged and handled without uncaught exceptions.
   */
  public class CalloutExceptionMock implements HttpCalloutMock {
    /**
     * @description
     * Throws CalloutException to simulate network failure.
     * @param req the HTTP request (unused)
     * @return nothing; always throws CalloutException
     */
    public HttpResponse respond(HttpRequest req) {
      throw new CalloutException('S3 not reachable');
    }
  }
}
