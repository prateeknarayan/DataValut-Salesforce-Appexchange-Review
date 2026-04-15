/**
 * @description
 * Dedicated test class for DataVault_PackageException to ensure coverage is tracked.
 *
 * AppExchange considerations: Pure unit test; no DML; no SeeAllData.
 */
@IsTest
private class DataVault_PackageExceptionTest {
  /**
   * @description
   * Verifies the exception can be thrown with a message and caught.
   */
  @IsTest
  static void throwWithMessageIsCatchable() {
    Boolean caught = false;
    try {
      throw new DataVault_PackageException('Config missing');
    } catch (DataVault_PackageException e) {
      caught = true;
      System.assertEquals(
        'Config missing',
        e.getMessage(),
        'Message should match'
      );
    }
    System.assert(caught, 'Exception must be catchable');
  }

  /**
   * @description
   * Verifies the exception can be thrown without a message.
   */
  @IsTest
  static void throwWithoutMessageIsCatchable() {
    Boolean caught = false;
    try {
      throw new DataVault_PackageException();
    } catch (DataVault_PackageException e) {
      caught = true;
    }
    System.assert(caught, 'No-arg exception must be catchable');
  }

  /**
   * @description
   * Verifies the exception can wrap a cause exception.
   */
  @IsTest
  static void throwWithCausePreservesCause() {
    Exception cause = new IllegalArgumentException('root cause');
    Boolean caught = false;
    try {
      DataVault_PackageException ex = new DataVault_PackageException('wrapper');
      ex.initCause(cause);
      throw ex;
    } catch (DataVault_PackageException e) {
      caught = true;
      System.assertEquals(
        'root cause',
        e.getCause().getMessage(),
        'Cause should be preserved'
      );
    }
    System.assert(caught, 'Exception with cause must be catchable');
  }
}
