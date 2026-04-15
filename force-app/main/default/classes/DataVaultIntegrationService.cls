/**
 * @description
 * Service-layer utility that sends serialized JSON payloads to S3 via a Salesforce Named Credential.
 *
 * What it is for:
 *  - Single method sendToS3(namedCredentialName, objectApiName, jsonBody): builds the S3 path, sets up the HTTP PUT request using the Named Credential, and sends the body. Returns HttpResponse; logs non-2xx and exceptions then rethrows so callers can handle.
 *
 * Why it exists:
 *  - All callout logic and error logging live in one place so batch and future callers do not duplicate endpoint construction or logging. No credentials or endpoints are stored in Apex—only the Named Credential API name is passed; the platform resolves URL and auth. This satisfies AppExchange requirements for no secrets in code and for consistent, secure outbound calls.
 *
 * AppExchange considerations:
 *  - Declared with sharing; no hardcoded URLs, credentials, or headers; callout errors are logged via DataVault_Error_Logger and flushed for async contexts; intended for use from classes that declare Database.AllowsCallouts.
 */
public with sharing class DataVaultIntegrationService {
  /** HTTP method used for S3 uploads. */
  private static final String HTTP_METHOD_PUT = 'PUT';

  /** Content-Type header value for JSON payloads. */
  private static final String CONTENT_TYPE_JSON = 'application/json';

  private static final Integer MAX_RETRIES = 2;
  private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{
    429,
    502,
    503,
    504
  };

  /**
   * @description
   * Validates that the Named Credential connection is set up and reachable. Performs a lightweight HEAD request. Must be called before saveAndStartJob because DML cannot follow a callout in the same transaction.
   * @param namedCredentialName API name of the Named Credential (base URL and auth configured in Setup)
   * @throws CalloutException if the Named Credential does not exist or connection fails
   * @throws IllegalArgumentException if the response status is not 2xx (user must resolve before saving)
   */
  public static void validateNamedCredentialConnection(
    String namedCredentialName
  ) {
    if (String.isBlank(namedCredentialName)) {
      throw new IllegalArgumentException('Named Credential Name is required.');
    }
    HttpRequest req = buildHeadRequest('callout:' + namedCredentialName + '/');
    try {
      HttpResponse res = new Http().send(req);
      require2xxStatus(res);
    } catch (Exception e) {
      rethrowConnectionException(e);
    }
  }

  private static HttpRequest buildHeadRequest(String endpoint) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(endpoint);
    req.setMethod('HEAD');
    req.setTimeout(10000);
    return req;
  }

  private static void require2xxStatus(HttpResponse res) {
    Integer statusCode = res.getStatusCode();
    if (statusCode >= 200 && statusCode < 300) {
      return;
    }
    String statusMsg = String.isNotBlank(res.getStatus())
      ? res.getStatus()
      : 'Unknown';
    throw new IllegalArgumentException(
      'HTTP ' +
        statusCode +
        ' - ' +
        statusMsg +
        '. Please resolve the connection error before saving.'
    );
  }

  private static void rethrowConnectionException(Exception e) {
    if (e instanceof IllegalArgumentException) {
      throw (IllegalArgumentException) e;
    }
    if (e instanceof System.CalloutException) {
      throw (System.CalloutException) e;
    }
    throw new System.CalloutException(
      'Named Credential connection failed: ' + e.getMessage() + '.',
      e
    );
  }

  /**
   * @description
   * Uploads a JSON payload to S3 at /{ObjectApiName}/{timestamp}.json using the given Named Credential. Logs non-2xx and exceptions, then rethrows. Caller gets the response for flow control; errors are persisted to DataVault_Error_Log__c.
   * @param namedCredentialName API name of the Named Credential (base URL and auth configured in Setup)
   * @param objectApiName API name of the SObject being exported (used in path only)
   * @param jsonBody Serialized JSON payload
   * @return HttpResponse from the S3 endpoint
   */
  public static HttpResponse sendToS3(
    String namedCredentialName,
    String objectApiName,
    String jsonBody
  ) {
    validateSendToS3Params(namedCredentialName, objectApiName);
    String path =
      '/' +
      objectApiName +
      '/' +
      String.valueOf(System.currentTimeMillis()) +
      '.json';
    HttpRequest req = buildPutRequest(
      'callout:' + namedCredentialName + path,
      jsonBody
    );
    return executeSendToS3(req);
  }

  private static void validateSendToS3Params(
    String namedCredentialName,
    String objectApiName
  ) {
    if (String.isBlank(namedCredentialName) || String.isBlank(objectApiName)) {
      throw new IllegalArgumentException(
        'Named Credential Name and Object API Name are required.'
      );
    }
  }

  private static HttpRequest buildPutRequest(String endpoint, String jsonBody) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(endpoint);
    req.setMethod(HTTP_METHOD_PUT);
    req.setHeader('Content-Type', CONTENT_TYPE_JSON);
    req.setBody(jsonBody);
    req.setTimeout(120000);
    return req;
  }

  private static HttpResponse executeSendToS3(HttpRequest req) {
    Integer attempts = 0;
    HttpResponse lastRes;
    while (attempts <= MAX_RETRIES) {
      attempts++;
      try {
        lastRes = attemptSend(req);
        if (is2xx(lastRes)) {
          return lastRes;
        }
        if (attempts <= MAX_RETRIES && isRetryable(lastRes.getStatusCode())) {
          continue;
        }
        logNon2xxFailure(req, lastRes);
        return lastRes;
      } catch (System.CalloutException e) {
        lastRes = handleCalloutException(e, attempts, req);
      } catch (Exception e) {
        logGeneralExceptionAndRethrow(e);
      }
    }
    return lastRes;
  }

  private static HttpResponse attemptSend(HttpRequest req) {
    return new Http().send(req);
  }

  private static void logNon2xxFailure(HttpRequest req, HttpResponse res) {
    logCalloutFailureAndFlush(
      'HTTP ' + res.getStatusCode() + ' - ' + res.getStatus(),
      req,
      res
    );
  }

  private static HttpResponse handleCalloutException(
    System.CalloutException e,
    Integer attempts,
    HttpRequest req
  ) {
    if (attempts <= MAX_RETRIES) {
      return null;
    }
    logCalloutFailureAndFlush(e.getMessage(), req, null);
    throw e;
  }

  private static void logGeneralExceptionAndRethrow(Exception e) {
    DataVault_Error_Logger.logError(
      DataVault_Error_Logger.buildContextFromException(
        e,
        'DataVaultIntegrationService',
        'sendToS3'
      )
    );
    DataVault_Error_Logger.flush();
    throw e;
  }

  private static Boolean isRetryable(Integer statusCode) {
    return RETRYABLE_STATUS_CODES.contains(statusCode);
  }

  private static Boolean is2xx(HttpResponse res) {
    Integer code = res.getStatusCode();
    return code >= 200 && code < 300;
  }

  private static void logCalloutFailureAndFlush(
    String message,
    HttpRequest req,
    HttpResponse res
  ) {
    DataVault_Error_Logger.CalloutFailureInput input = new DataVault_Error_Logger.CalloutFailureInput(
      message,
      'DataVaultIntegrationService',
      'sendToS3'
    );
    input.req = req;
    input.res = res;
    DataVault_Error_Logger.logCalloutFailure(input);
    DataVault_Error_Logger.flush();
  }
}
