/**
 * @description
 * This exception is used to represent package-specific business,
 * configuration, and security validation errors within the DataVault
 * export framework.
 *
 * Design Purpose:
 *  - Provides a strongly-typed exception to distinguish package-level
 *    failures from generic system exceptions.
 *  - Enables structured error handling across batch, scheduler,
 *    controller, and integration layers.
 *  - Improves maintainability by centralizing package-specific
 *    exception signaling.
 *
 * Architectural Role:
 *  - Thrown for configuration validation failures.
 *  - Thrown for security enforcement violations (CRUD/FLS).
 *  - Thrown for integration-related validation errors.
 *  - Logged via DataVault_Error_Logger where appropriate.
 *
 * Security & AppExchange Considerations:
 *  - Does not expose sensitive information.
 *  - Does not perform DML, callouts, or state mutation.
 *  - Used only as a signaling mechanism.
 *  - Complies with Salesforce exception handling best practices.
 *
 * Usage Guidelines:
 *  - Should be thrown only for controlled, package-defined error
 *    conditions.
 *  - Should not be used for system-level exceptions unless wrapped.
 *  - Should be logged through DataVault_Error_Logger when appropriate.
 *
 * This class supports clear separation between platform exceptions
 * and managed package business exceptions.
 */
public with sharing class DataVault_PackageException extends Exception {
}
