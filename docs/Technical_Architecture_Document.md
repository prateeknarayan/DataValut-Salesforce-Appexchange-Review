# Data Vault — Technical Architecture Document

### AppExchange Security Review Submission

**Package Name:** Data Vault  
**Version:** 1.0  
**Platform:** Salesforce (Managed Package)  
**Cloud Integration:** AWS S3 (via Salesforce Named Credentials)  
**Document Purpose:** AppExchange Security Review — Technical Architecture Reference

---

## Table of Contents

1. [Technical Overview](#1-technical-overview)
2. [Technology Stack](#2-technology-stack)
3. [Core Components](#3-core-components)
4. [End-to-End Flow](#4-end-to-end-flow)
5. [Scheduling Architecture](#5-scheduling-architecture)
6. [Data Handling & Processing](#6-data-handling--processing)
7. [Security Architecture](#7-security-architecture)
8. [Error Handling & Logging](#8-error-handling--logging)
9. [Governor Limits & Optimization](#9-governor-limits--optimization)
10. [Scalability & Extensibility](#10-scalability--extensibility)
11. [AppExchange Review Readiness](#11-appexchange-review-readiness)

---

## 1. Technical Overview

### 1.1 High-Level Architecture Summary

Data Vault is a Salesforce managed package that performs scheduled, incremental backups of Salesforce SObject records to AWS S3. The architecture is intentionally minimal and secure: it uses no external dependencies beyond Salesforce-native Named Credentials, relies entirely on the Salesforce platform for authentication and credential management, and stores no secrets of any kind inside the package.

The core execution path is:

```
User (LWC UI)
    → DataVaultExportConfigController (Apex Controller)
    → DataVaultExportConfigLogic (Business Logic)
    → DataVaultExportScheduler (Schedulable)
    → DataVaultExportBatch (Batch Apex + Callout)
    → AWS S3 (via Named Credential)
    → DataVault_Error_Log__c (on failure)
```

All data operations — SOQL queries, DML inserts, and record updates — are performed with full CRUD and FLS enforcement. Every Apex class is declared `with sharing`, and all SOQL queries include `WITH USER_MODE` to respect org-level sharing rules and field-level security.

### 1.2 Design Principles

| Principle               | Implementation                                                                       |
| ----------------------- | ------------------------------------------------------------------------------------ |
| Zero credential storage | Named Credential API name only; no URLs, keys, or tokens in package                  |
| Least privilege         | Permission Set grants only necessary object, field, class, and tab access            |
| Defense in depth        | CRUD checks + FLS stripInaccessible + WITH USER_MODE SOQL + with sharing             |
| Incremental by default  | Timestamp-based watermark prevents redundant data export                             |
| Fail-safe logging       | Error buffer never throws; logs are always attempted even under DML limits           |
| Single org-level config | One config record per org (Hierarchy Custom Setting) — no tenant cross-contamination |
| Async execution         | Batch Apex isolates callout and DML from synchronous user sessions                   |

### 1.3 Multi-Tenant Considerations

Data Vault is designed to operate safely within Salesforce's multi-tenant architecture:

- **Config isolation**: `DataVault_Export_Configs__c` is a Hierarchy Custom Setting scoped to `SetupOwnerId = OrganizationId`. Each subscriber org gets its own configuration record — no shared state between orgs.
- **No static state**: No static variables persist across transaction boundaries or between subscriber orgs.
- **Namespace-safe**: All components are prefixed/namespaced. No hardcoded record IDs anywhere in the codebase.
- **Sharing enforced**: `with sharing` on all classes ensures each org's record-level sharing model is respected.
- **Governor limits respected**: All batch, callout, DML, and SOQL operations include proactive limit checks to prevent failures that could cascade across tenants.

---

## 2. Technology Stack

### 2.1 Apex

**Why used:** Apex is the only server-side execution environment available in Salesforce. It provides direct access to SOQL, DML, HTTP callouts, and platform scheduling primitives. Data Vault uses Apex exclusively for all business logic — no JavaScript remoting, no external middleware.

**Role in Data Vault:**

- Enforces CRUD/FLS before every data operation
- Constructs FLS-safe dynamic SOQL using Schema.describe()
- Serializes SObject records to JSON for S3 upload
- Manages the batch lifecycle (start → execute → finish)
- Handles all error capture and log persistence

### 2.2 Salesforce Scheduler (Schedulable Interface)

**Why used:** Salesforce's built-in scheduler is the only way to reliably execute recurring server-side logic inside the platform. It is fully managed, fault-tolerant for scheduling, and does not require any external trigger or cron service.

**Role in Data Vault:**

- `DataVaultExportScheduler` implements `Schedulable` and is scheduled via `System.schedule()` with CRON expression `"0 59 23 * * ?"` (daily at 11:59 PM UTC)
- Serves as the single entry point for all automated export runs, regardless of cloud platform
- Delegates to `Database.executeBatch(new DataVaultExportBatch(), 200)` — it does not perform any data operations itself

### 2.3 Named Credentials

**Why used:** Named Credentials are Salesforce's secure, platform-managed mechanism for storing external endpoint URLs and authentication details (OAuth tokens, API keys, certificates). They prevent credential exposure in Apex code and eliminate the need for any secret storage within the managed package.

**Role in Data Vault:**

- The subscriber admin creates the Named Credential in their Salesforce Setup (not done by the package)
- The package stores only the Named Credential's **API name** (a string like `"MyS3Bucket"`) in `DataVault_Export_Configs__c.Named_Credential_Name__c`
- At callout time, Apex constructs the endpoint as `callout:{namedCredentialName}/{objectApiName}/{timestamp}.json` — the platform resolves the actual URL, injects auth headers, and manages certificate trust at runtime
- The managed package **never has visibility** into the endpoint URL, access key, secret key, or any AWS IAM credential

### 2.4 AWS S3 (Cloud Storage Target)

**Why used:** AWS S3 is the initial and currently only supported cloud storage platform. It provides durable, scalable, cost-effective object storage accessible via standard HTTP PUT operations — making it straightforward to integrate from Apex callouts.

**Role in Data Vault:**

- Receives JSON payloads via HTTP PUT at path `/ObjectApiName/timestamp.json`
- Each batch chunk generates one PUT request
- S3 bucket, endpoint, and IAM configuration are entirely managed by the subscriber — the package has no visibility into the bucket structure, policies, or access configuration

### 2.5 JSON Serialization

**Why used:** JSON is the universal interchange format for REST APIs, including S3 object uploads. Salesforce's `JSON.serialize()` natively handles SObject serialization.

**Role in Data Vault:**

- `JSON.serialize(scope)` is called in `DataVaultExportBatch.execute()` on the batch scope (a `List<SObject>`)
- Prior to serialization, `Security.stripInaccessible(AccessType.READABLE, records)` is applied to ensure no inaccessible fields are included in the payload
- Result: a JSON array of field-value maps for all accessible fields on each record

### 2.6 SOQL with CRUD/FLS Enforcement

**Why used:** Salesforce requires that managed packages respect the running user's field- and object-level permissions. Unguarded SOQL can expose data the user is not permitted to see, which violates AppExchange Security Review requirements.

**Role in Data Vault:**

- `DataVaultObjectAccessHelper.buildSecureQuery()` dynamically constructs `SELECT {accessible_fields} FROM {object}` using only fields where `field.getDescribe().isAccessible() == true`
- Object names are validated via `Schema.getGlobalDescribe()` — never interpolated from raw user input
- All config queries use `WITH USER_MODE` to enforce org sharing rules and FLS at the database level
- `Security.stripInaccessible()` is applied as a second layer on all read, update, and insert operations

---

## 3. Core Components

### 3.1 Apex Classes

---

#### `DataVaultExportConfigController`

| Attribute      | Detail                                                           |
| -------------- | ---------------------------------------------------------------- |
| Sharing        | `with sharing`                                                   |
| Layer          | UI Controller (AuraEnabled)                                      |
| Responsibility | Exposes LWC-facing methods; bridges LWC and business logic layer |

**Why it exists:** Salesforce requires a dedicated `@AuraEnabled` controller to connect LWC components to server-side Apex. This class is intentionally thin — it delegates all logic to the service and logic layers and handles only serialization of LWC inputs.

**Methods:**

- `getCloudPlatformOptions()` [cacheable] — Returns active cloud platform metadata for the platform dropdown
- `getConfig()` [cacheable] — Returns org-level config as a typed `ConfigDTO`
- `getReadableObjectOptions()` — Returns SObjects the running user can read and query (non-cacheable, user-context sensitive)
- `validateNamedCredentialConnection(namedCredentialName)` — Triggers a HEAD request to validate the Named Credential
- `saveAndStartJobFromMap(Map<String,String>)` — Accepts LWC map input and delegates to config logic
- `disableOrEnableExport(Boolean)` — Toggles `Is_Export_Enabled__c`

**Interactions:** Delegates to `DataVaultExportConfigLogic`, `DataVaultExportConfigService`, `DataVaultIntegrationService`.

---

#### `DataVaultExportConfigLogic`

| Attribute      | Detail                                                                          |
| -------------- | ------------------------------------------------------------------------------- |
| Sharing        | `with sharing`                                                                  |
| Layer          | Business Logic                                                                  |
| Responsibility | Orchestrates config save, validation, scheduling, and enable/disable operations |

**Why it exists:** Separates business rules from the controller layer. Ensures all save operations go through validation before persisting or scheduling.

**Key operations:**

- `saveAndStartJob(SaveConfigInput)` — Validates inputs via `DataVaultExportConfigValidator`, persists config via DML ("insert/update as user"), schedules `DataVaultExportScheduler` via `System.schedule()`
- `disableOrEnableExport(Boolean)` — Updates `Is_Export_Enabled__c` with FLS strip
- `scheduleExportJob()` — Calls `System.schedule('DataVault Daily Export', '0 59 23 * * ?', new DataVaultExportScheduler())`

**Interactions:** Uses `DataVaultExportConfigValidator`, `DataVault_Security_Utility`, `DataVaultObjectAccessHelper`.

---

#### `DataVaultExportConfigService`

| Attribute      | Detail                                    |
| -------------- | ----------------------------------------- |
| Sharing        | `with sharing`                            |
| Layer          | Read-Only Data Service                    |
| Responsibility | All read-only config and metadata queries |

**Why it exists:** Centralizes all read operations. Controllers and logic classes never issue SOQL directly — they go through this service, ensuring consistent FLS enforcement and query patterns.

**Key operations:**

- `getCloudPlatformOptions()` — Queries `DataVault_Cloud_Platform__mdt WHERE Is_Active__c = TRUE WITH USER_MODE ORDER BY Display_Order__c`
- `getConfig()` — Retrieves org-level config via `DataVault_Security_Utility.getConfigRecord()`
- `getReadableObjectOptions()` — Delegates to `DataVaultObjectAccessHelper.getReadableObjectOptions()`

---

#### `DataVaultExportConfigValidator`

| Attribute      | Detail                                  |
| -------------- | --------------------------------------- |
| Sharing        | `with sharing`                          |
| Layer          | Validation                              |
| Responsibility | All input validation before config save |

**Why it exists:** Prevents invalid state from being persisted. Ensures the cloud platform is active and exists in metadata, the Named Credential name is non-blank, the object is non-blank, and the object is readable/queryable by the user.

**Key operations:**

- `validateSaveInputs(SaveConfigInput)` — Throws `AuraHandledException` with specific messages on any validation failure; returns trimmed API value on success
- `isValidCloudPlatform(apiValue)` — Queries `DataVault_Cloud_Platform__mdt WHERE Api_Value__c = :apiValue AND Is_Active__c = TRUE WITH USER_MODE LIMIT 1`

---

#### `DataVaultExportScheduler`

| Attribute      | Detail                                                 |
| -------------- | ------------------------------------------------------ |
| Sharing        | `with sharing`                                         |
| Layer          | Scheduling / Entry Point                               |
| Implements     | `Schedulable`                                          |
| Responsibility | Scheduled entry point; loads config and enqueues batch |

**Why it exists:** Salesforce's `Schedulable` interface requires a dedicated class. This class is intentionally minimal — it validates config state and delegates to the batch class. No data operations are performed here.

**Execution:**

1. Queries org config via `DataVault_Security_Utility` (CRUD-checked)
2. Verifies `Is_Export_Enabled__c == true`
3. Calls `Database.executeBatch(new DataVaultExportBatch(), 200)`
4. All exceptions logged via `DataVault_Error_Logger`, then rethrown

---

#### `DataVaultExportBatch`

| Attribute      | Detail                                                                        |
| -------------- | ----------------------------------------------------------------------------- |
| Sharing        | `with sharing`                                                                |
| Layer          | Async Execution / Callout                                                     |
| Implements     | `Database.Batchable<SObject>`, `Database.Stateful`, `Database.AllowsCallouts` |
| Responsibility | Core export logic: query records, serialize, PUT to S3, update run stats      |

**Why it exists:** Apex Batch is required to handle large data volumes within governor limits. `Database.AllowsCallouts` enables HTTP operations within batch execute. `Database.Stateful` allows error/success counts to accumulate across execute() chunks.

**Lifecycle:**

- `start()` — Validates SOQL limits, builds FLS-safe query via `DataVaultObjectAccessHelper.buildSecureQuery()`, applies incremental WHERE clause if `Last_Run_Completed__c` is set
- `execute()` — Checks callout and heap limits, serializes scope to JSON, calls `DataVaultIntegrationService.sendToS3()`, accumulates success/error counts
- `finish()` — Checks DML limits, computes `Last_Run_Status__c` ("Success" / "Partial Success" / "Failed"), updates config record "as user", flushes error log buffer

---

#### `DataVaultIntegrationService`

| Attribute      | Detail                             |
| -------------- | ---------------------------------- |
| Sharing        | `with sharing`                     |
| Layer          | Integration / Callout              |
| Responsibility | All HTTP communication with AWS S3 |

**Why it exists:** Isolates all callout logic. No other class constructs `HttpRequest` or calls `Http.send()`. This ensures callout security is auditable in a single location.

**Key operations:**

- `sendToS3(namedCredentialName, objectApiName, jsonBody)` — Constructs PUT request, executes with retry logic (max 2 retries for 429/502/503/504), returns response
- `validateNamedCredentialConnection(namedCredentialName)` — Issues HEAD request to verify Named Credential resolves correctly
- Endpoint pattern: `callout:{namedCredentialName}/{objectApiName}/{System.currentTimeMillis()}.json`
- Timeout: 120,000 ms
- All callout failures logged via `DataVault_Error_Logger.logCalloutFailure()`

---

#### `DataVaultObjectAccessHelper`

| Attribute      | Detail                                                                               |
| -------------- | ------------------------------------------------------------------------------------ |
| Sharing        | `with sharing`                                                                       |
| Layer          | Security / Describe Utility                                                          |
| Responsibility | Schema describe operations, FLS-safe query construction, object accessibility checks |

**Why it exists:** Centralizes all Schema.describe() logic. Prevents SOQL injection by never allowing raw user input into dynamic queries. All field names used in SOQL are sourced exclusively from Schema describe results.

**Key operations:**

- `buildSecureQuery(objectApiName)` — Validates object via `getGlobalDescribe()`, builds SELECT of accessible fields only
- `getReadableObjectOptions()` — Returns objects where `isAccessible() && isQueryable()`
- `getReadableFieldApiNames(objectApiName)` — Returns `List<String>` of fields where `f.getDescribe().isAccessible()`
- `stripInaccessibleFields(accessType, records)` — Wrapper around `Security.stripInaccessible()`
- Caching: Global describe cached; per-object describe results cached to minimize describe calls

---

#### `DataVault_Security_Utility`

| Attribute      | Detail                                                     |
| -------------- | ---------------------------------------------------------- |
| Sharing        | `with sharing`                                             |
| Layer          | Security Enforcement                                       |
| Responsibility | Centralized CRUD checks and FLS stripInaccessible wrappers |

**Why it exists:** A single, auditable class for all security enforcement. AppExchange reviewers can verify security posture by examining one class. No business logic resides here — only access checks and field stripping.

**CRUD check methods:**

- `isConfigReadable()`, `isConfigUpdatable()`, `isConfigReadWrite()` — Schema.sObjectType checks on `DataVault_Export_Configs__c`
- `isCloudPlatformMetadataReadable()` — Check on `DataVault_Cloud_Platform__mdt`
- `isLoggerCreatable()` — Check on `DataVault_Error_Log__c`

**FLS strip methods:**

- `stripConfigReadable(record)` — `Security.stripInaccessible(AccessType.READABLE, ...)`
- `stripConfigUpdatable(record)` — `Security.stripInaccessible(AccessType.UPDATABLE, ...)`
- `stripConfigCreatable(record)` — `Security.stripInaccessible(AccessType.CREATABLE, ...)`
- `stripErrorLogCreatable(records)` — Bulk strip for error log inserts

**Config retrieval:**

- `getConfigRecord()` — `SELECT ... FROM DataVault_Export_Configs__c WHERE SetupOwnerId = :UserInfo.getOrganizationId() WITH USER_MODE LIMIT 1`

---

#### Error Logging Framework (`DataVault_Error_Logger`, `DataVault_Error_LogBuffer`, `DataVault_Error_LogRecordBuilder`, `DataVault_Error_LogContext`, `DataVault_Error_StackParser`)

| Attribute      | Detail                                                               |
| -------------- | -------------------------------------------------------------------- |
| Sharing        | All `with sharing`                                                   |
| Layer          | Observability / Error Persistence                                    |
| Responsibility | Structured capture, buffering, and persistence of all runtime errors |

**Why these exist:** A buffered, structured logging framework prevents a single DML insert per error (which would exhaust DML limits in a batch). The layered design — context builder → record builder → buffer → flush — separates concerns cleanly and makes logging auditable.

Detailed behavior described in [Section 8](#8-error-handling--logging).

---

#### `DataVault_PackageException`

| Attribute      | Detail                           |
| -------------- | -------------------------------- |
| Sharing        | `with sharing`                   |
| Layer          | Exception Signaling              |
| Responsibility | Package-specific typed exception |

**Why it exists:** Using a named exception subclass allows callers to catch package-specific errors distinctly from general Salesforce platform exceptions. Used for config validation failures, security enforcement violations, and integration errors.

---

### 3.2 Custom Settings

#### `DataVault_Export_Configs__c` — Hierarchy Custom Setting

**Why Custom Setting (not Custom Object):** Hierarchy Custom Settings have built-in org/profile/user scoping, do not consume data storage per record in the same way, and are ideal for single-record org-level configuration. Querying by `SetupOwnerId = OrganizationId` guarantees one org-level record per org.

| Field                       | Type      | Purpose                                   |
| --------------------------- | --------- | ----------------------------------------- |
| `Object_API_Name__c`        | Text(250) | SObject to back up                        |
| `Named_Credential_Name__c`  | Text(250) | API name of subscriber's Named Credential |
| `Cloud_Platform__c`         | Text(80)  | Platform identifier (e.g., "AWS_S3")      |
| `Is_Export_Enabled__c`      | Checkbox  | Controls whether scheduler triggers batch |
| `Last_Run_Completed__c`     | DateTime  | Incremental backup watermark timestamp    |
| `Last_Run_Success_Count__c` | Number    | Records successfully exported in last run |
| `Last_Run_Error_Count__c`   | Number    | Records that failed in last run           |
| `Last_Run_Status__c`        | Text(20)  | "Success" / "Partial Success" / "Failed"  |

---

### 3.3 Custom Metadata Type

#### `DataVault_Cloud_Platform__mdt`

**Why Custom Metadata (not picklist):** Custom Metadata Types are deployable, version-controlled, and extensible without code changes. New cloud platforms can be added as metadata records — not code releases — making the architecture forward-compatible with future integrations.

**Visibility:** Protected (subscriber orgs cannot modify metadata records)

| Field              | Type      | Purpose                                  |
| ------------------ | --------- | ---------------------------------------- |
| `Api_Value__c`     | Text(80)  | Unique API identifier (e.g., "AWS_S3")   |
| `Is_Active__c`     | Checkbox  | Controls visibility in platform dropdown |
| `Display_Order__c` | Number(3) | Sort order in UI                         |

**Deployed record:** `DataVault_Cloud_Platform.AWS_S3` (`Api_Value__c = "AWS_S3"`, `Is_Active__c = true`, `Display_Order__c = 1`)

---

### 3.4 Custom Object

#### `DataVault_Error_Log__c`

**Why Custom Object (not Platform Event or Big Object):** Custom objects support standard list views, tab display, SOQL querying, and DML — all of which are required for the Error Logs tab. Platform Events would not be queryable via SOQL for historical review.

**Object Sharing Model:** ReadWrite  
**External Sharing Model:** Private  
**Name Field:** Auto-number (`ERR-{0000}`)

| Field                | Type               | Purpose                                               |
| -------------------- | ------------------ | ----------------------------------------------------- |
| `Error_Type__c`      | Picklist           | "Callout Failure" or "General Apex Exception"         |
| `Error_Message__c`   | Long Text(131,072) | Error detail (truncated to 32KB)                      |
| `Stack_Trace__c`     | Long Text(131,072) | Apex stack trace or callout debug (truncated to 32KB) |
| `Apex_Class_Name__c` | Text(255)          | Origin class                                          |
| `Method_Name__c`     | Text(255)          | Origin method                                         |
| `Timestamp__c`       | DateTime           | UTC error timestamp                                   |

---

### 3.5 Lightning Web Component

#### `dataVaultExportConfig`

**Why LWC (not Aura/Visualforce):** LWC is Salesforce's current-generation UI framework, offering reactive data binding, wire adapters for cached server calls, and native Lightning Design System integration. It is the recommended approach for all new AppExchange UI development.

**Targets:** `lightning__Tab`, `lightning__HomePage`  
**API Version:** 62.0

**Architecture:**

- `@wire(getCloudPlatformOptions)` and `@wire(getConfig)` load cached data on component init — no extra round-trips on page reload
- `getReadableObjectOptions()` is called imperatively (non-cached) only when the user enters edit mode — prevents stale object lists
- `saveAndStartJobFromMap()` serializes all config fields into a `Map<String,String>` before passing to Apex (LWC cannot pass typed objects directly to `@AuraEnabled` methods)
- State machine: `isLocked` (view mode) / edit mode with explicit `Edit` button click
- Loading states: `configLoaded` and `cloudPlatformOptionsLoaded` both required before spinner clears — prevents partial renders

---

### 3.6 Permission Set

#### `DataVault_Permission_Set`

**Why Permission Set (not Profile):** Permission Sets are the AppExchange-standard way to grant additional access without modifying subscriber profiles. Subscribers assign the set to specific users.

**Grants access to:**

- App visibility: `Data_Vault`
- Tabs: `DataVault_Config` (Visible), `DataVault_Error_Log__c` (Visible)
- Custom Setting: `DataVault_Export_Configs__c` (read/edit)
- Custom Metadata: `DataVault_Cloud_Platform__mdt` (read)
- Custom Object: `DataVault_Error_Log__c` (Create, Read, Edit, Delete — no ViewAll, no ModifyAll)
- Field permissions: All `DataVault_Error_Log__c` fields (read + edit)
- Apex class access: All 15 production classes + test infrastructure classes

**Notable omissions (intentional):**

- No `ViewAll` or `ModifyAll` on any object — users see only records they own or that are shared
- No access to standard objects — the package does not modify or access standard org data beyond what the running user already has permission to read

---

### 3.7 Custom Labels

| Label API Name                 | Value                      | Purpose                                                                                |
| ------------------------------ | -------------------------- | -------------------------------------------------------------------------------------- |
| `DataVaultPermissionSetName`   | `DataVault_Permission_Set` | Used in test setup to dynamically look up permission set by name — no hardcoded string |
| `DataVaultTestUserProfileName` | `System Administrator`     | Used in test setup to look up test user profile by name — org-agnostic                 |

**Why Custom Labels for test values:** Prevents hardcoded strings in test classes. In subscriber orgs where profiles may be renamed, the label value can be adjusted without a code release.

---

## 4. End-to-End Flow

### 4.1 Step-by-Step Execution

#### Step 1 — User Opens Config Tab

- LWC `dataVaultExportConfig` loads
- Two `@wire` adapters fire in parallel:
  - `getCloudPlatformOptions()` → calls `DataVaultExportConfigService.getCloudPlatformOptions()` → queries `DataVault_Cloud_Platform__mdt WHERE Is_Active__c = TRUE WITH USER_MODE` → returns `[{label: "AWS S3", value: "AWS_S3"}]`
  - `getConfig()` → calls `DataVaultExportConfigService.getConfig()` → calls `DataVault_Security_Utility.getConfigRecord()` → queries `DataVault_Export_Configs__c WHERE SetupOwnerId = :OrganizationId WITH USER_MODE LIMIT 1`
- Component renders in locked (read-only) mode once both wires resolve

#### Step 2 — User Clicks Edit

- `isLocked = false`; form fields become editable
- `getReadableObjectOptions()` called imperatively → `DataVaultObjectAccessHelper.getReadableObjectOptions()` → uses `Schema.getGlobalDescribe()` to enumerate all SObjects → filters to those where `isAccessible() && isQueryable()` → returns labeled list for the Object combobox

#### Step 3 — User Selects Platform, Named Credential, Object

- Cloud Platform combobox filtered from metadata (only active platforms shown)
- Named Credential name entered as free text (must match a credential the subscriber has created in Setup)
- Object combobox filtered to user-accessible SObjects only

#### Step 4 — User Clicks "Save & Schedule Export"

- LWC calls `saveAndStartJobFromMap({cloudPlatform, namedCredentialName, objectApiName})` imperatively
- `DataVaultExportConfigController.saveAndStartJobFromMap()` receives map, constructs `SaveConfigInput` DTO
- Delegates to `DataVaultExportConfigLogic.saveAndStartJob(input)`

#### Step 5 — Validation

- `DataVaultExportConfigValidator.validateSaveInputs(input)` executes:
  - Cloud platform non-blank → checked against `DataVault_Cloud_Platform__mdt` WHERE `Api_Value__c = :value AND Is_Active__c = TRUE`
  - Named Credential name non-blank
  - Object API name non-blank → verified as readable and queryable via `DataVaultObjectAccessHelper.isObjectReadable()`
  - If any check fails: `AuraHandledException` thrown with specific user-facing message
- If valid: `DataVaultIntegrationService.validateNamedCredentialConnection(namedCredentialName)` issues HEAD request to verify Named Credential resolves

#### Step 6 — Config Persisted

- `DataVault_Security_Utility.isConfigReadWrite()` checked (CRUD)
- If no existing config record: `insert as user` after `stripConfigCreatable()`
- If existing: `update as user` after `stripConfigUpdatable()`
- Sets `Is_Export_Enabled__c = true`
- Config record name: `"Default"` (org-level Hierarchy Custom Setting)

#### Step 7 — Scheduler Created

- `DataVaultExportConfigLogic.scheduleExportJob()` calls:
  ```apex
  System.schedule('DataVault Daily Export', '0 59 23 * * ?', new DataVaultExportScheduler());
  ```
- No immediate execution occurs — the scheduler will fire at the next 11:59 PM UTC
- In test context: batch is executed immediately via `Database.executeBatch()` to allow test assertions

#### Step 8 — Scheduler Fires (11:59 PM UTC Daily)

- `DataVaultExportScheduler.execute(SchedulableContext)` runs
- CRUD checks: `isConfigReadable()` and `isConfigUpdatable()` verified
- Config queried via `DataVault_Security_Utility.getConfigRecord()`
- `Is_Export_Enabled__c` verified — if false, execution stops silently
- `Database.executeBatch(new DataVaultExportBatch(), 200)` called

#### Step 9 — Batch Start Phase

- `DataVaultExportBatch.start()` executes:
  - SOQL limit check (`Limits.getLimitQueries() - Limits.getQueries() >= 1`)
  - Config read to get `objectApiName`, `namedCredentialName`, `Last_Run_Completed__c`
  - `currentRunStarted = System.now()` captured (used as next watermark)
  - `DataVaultObjectAccessHelper.buildSecureQuery(objectApiName)` called:
    - Validates object via `Schema.getGlobalDescribe().get(objectApiName)`
    - Retrieves accessible field names: `[f for f in describe.fields.getMap().values() if f.getDescribe().isAccessible()]`
    - Builds: `SELECT {accessible_fields} FROM {objectApiName}`
    - If `Last_Run_Completed__c` not null: appends `WHERE (LastModifiedDate >= {ts} OR CreatedDate >= {ts})`
    - Timestamp formatted as `formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')`
  - Returns `Database.getQueryLocator(query)`

#### Step 10 — Batch Execute Phase (repeated per chunk of 200 records)

- `DataVaultExportBatch.execute(context, scope)` executes per chunk:
  - Callout limit check (`Limits.getLimitCallouts() - Limits.getCallouts() >= 1`)
  - Heap limit check (fails if < 500KB remaining heap)
  - `Security.stripInaccessible(AccessType.READABLE, scope)` applied — removes any fields the user cannot read
  - `JSON.serialize(scope)` produces JSON array
  - `DataVaultIntegrationService.sendToS3(namedCredentialName, objectApiName, jsonBody)` called

#### Step 11 — HTTP Callout to AWS S3

- `DataVaultIntegrationService.sendToS3()`:
  - Constructs `HttpRequest`:
    - Method: `PUT`
    - Endpoint: `callout:{namedCredentialName}/{objectApiName}/{System.currentTimeMillis()}.json`
    - Header: `Content-Type: application/json`
    - Body: JSON string
    - Timeout: 120,000 ms
  - Executes: `new Http().send(req)`
  - **Retry loop** (max 2 retries):
    - On `CalloutException`: logged and rethrown after retries exhausted
    - On status 429, 502, 503, 504: retried
    - On other non-2xx: logged as callout failure, counted as error
  - On 2xx: success count incremented in batch
  - Platform resolves Named Credential → injects real endpoint URL + auth headers before network transmission

#### Step 12 — Batch Finish Phase

- `DataVaultExportBatch.finish()` executes:
  - DML limit check before writing
  - Computes `Last_Run_Status__c`:
    - `errorCount == 0` → `"Success"`
    - `errorCount > 0 && successCount > 0` → `"Partial Success"`
    - `successCount == 0` → `"Failed"`
  - Updates config record "as user" with:
    - `Last_Run_Status__c`
    - `Last_Run_Success_Count__c`
    - `Last_Run_Error_Count__c`
    - `Last_Run_Completed__c = currentRunStarted`
  - `DataVault_Error_Logger.flush()` called — forces remaining buffered error logs to DB

#### Step 13 — UI Reflects Last Run

- Next time user visits Config tab, `@wire(getConfig)` returns updated config including last run stats
- Status badge, success/error counts, and completion timestamp displayed in read-only Last Run section

---

## 5. Scheduling Architecture

### 5.1 Scheduler Creation

`System.schedule('DataVault Daily Export', '0 59 23 * * ?', new DataVaultExportScheduler())` is called inside `DataVaultExportConfigLogic.saveAndStartJob()`. This registers a named scheduled job in the subscriber org's Apex Scheduled Jobs.

### 5.2 Why 11:59 PM

The schedule fires at 11:59 PM UTC daily, chosen to:

- Run during low-traffic hours in most enterprise time zones
- Complete before day rollover, keeping backup timestamps day-aligned
- Avoid conflicts with other typical scheduled jobs (often at midnight)

### 5.3 Job Management

- Job name: `"DataVault Daily Export"` — consistent, auditable name visible in Setup > Apex Jobs
- The package does not abort or re-create the scheduled job on subsequent saves — idempotency is managed by checking for an existing job before scheduling
- If the subscriber manually aborts the job, clicking "Save & Schedule Export" again re-creates it

### 5.4 Idempotency

- Config is always upserted (insert or update based on existing `SetupOwnerId` lookup)
- Scheduler creation is guarded — attempting to schedule when a job with the same name already exists is handled gracefully
- Incremental timestamp (`Last_Run_Completed__c`) is written only in `finish()`, and only to the value captured at `start()` — ensuring the watermark moves forward monotonically

### 5.5 Failure Handling

- If the batch fails mid-execution, `finish()` still runs and writes partial counts + `"Partial Success"` or `"Failed"` status
- The scheduler itself does not retry failed batches — the next daily run will pick up from the last successful watermark
- `DataVault_Error_Logger.flush()` in `finish()` ensures error logs are persisted even when the batch transaction encounters late exceptions

---

## 6. Data Handling & Processing

### 6.1 Record Querying

All SOQL for record export is constructed dynamically by `DataVaultObjectAccessHelper.buildSecureQuery()`:

1. Object name validated against `Schema.getGlobalDescribe()` — never interpolated raw
2. Field list built exclusively from `Schema.describe().fields.getMap().values()` where `isAccessible() == true`
3. Result: `SELECT {accessible_fields} FROM {objectApiName}` with optional incremental WHERE clause
4. Query executed via `Database.getQueryLocator()` — enables batch chunking across all matching records

### 6.2 Incremental Logic

```
First run:  Last_Run_Completed__c = null → no WHERE clause → all records exported
Subsequent: WHERE (LastModifiedDate >= {Last_Run_Completed__c} OR CreatedDate >= {Last_Run_Completed__c})
```

- `currentRunStarted` captured at `start()` ensures the watermark reflects when the batch began, not when it finished
- Both `CreatedDate` and `LastModifiedDate` checked — captures records created after last run AND records existing before last run but modified since
- Timestamp stored in UTC via `formatGmt()` — no timezone ambiguity

### 6.3 Serialization

- `Security.stripInaccessible(AccessType.READABLE, scope)` applied before `JSON.serialize()`
- Ensures the JSON payload contains only fields the running user is permitted to read
- Output: JSON array of SObject maps — standard, schema-agnostic format

### 6.4 Payload Structure (AWS S3)

```
S3 Path:   /{ObjectApiName}/{timestamp_millis}.json
Method:    PUT
Body:      [ { "Id": "...", "Name": "...", "CustomField__c": "..." }, ... ]
Auth:      Resolved by Named Credential at platform level
```

Each batch chunk of 200 records produces one PUT request and one S3 object. Multiple chunks from the same batch run produce multiple S3 objects under the same object path.

### 6.5 Governor Limit Handling

See [Section 9](#9-governor-limits--optimization) for full details.

---

## 7. Security Architecture

This section is the primary security reference for AppExchange Security Review.

### 7.1 No Credential Storage in Package

**Principle:** The managed package stores zero secrets, tokens, keys, or endpoint URLs.

**Implementation:**

- The subscriber admin creates a Named Credential in their own Salesforce Setup — this is entirely outside the managed package's scope
- The package stores only the Named Credential's **API name** (a plain string identifier like `"MyS3Bucket"`) in `DataVault_Export_Configs__c.Named_Credential_Name__c`
- At callout time, the endpoint is constructed as `callout:{namedCredentialName}/...` — Salesforce resolves this at the platform level, injecting the real URL, authentication headers (AWS IAM signature, OAuth token, or API key), and SSL certificate trust — **none of which are visible to Apex code**
- `HttpRequest.toString()` and response inspection in error logs use only status codes and truncated body text — no auth headers are ever logged

### 7.2 Named Credential Usage

- Named Credentials prevent credential exposure in code (eliminating hardcoded secrets)
- Named Credentials are managed in Salesforce Setup (not accessible to the managed package)
- The package validates the Named Credential by issuing a HEAD request — it verifies connectivity without exposing credential details
- If the Named Credential is deleted or misconfigured, the callout fails with a `CalloutException` — logged and surfaced to the user as an error, not a silent failure

### 7.3 CRUD/FLS Enforcement — Multi-Layer Approach

Data Vault uses three independent layers of data access control:

**Layer 1 — CRUD Checks (Schema.sObjectType)**

```apex
// Before any DML or SOQL:
DataVault_Security_Utility.isConfigReadable()      // .isAccessible()
DataVault_Security_Utility.isConfigUpdatable()     // .isUpdateable()
DataVault_Security_Utility.isLoggerCreatable()     // .isCreateable()
```

If a CRUD check fails, the operation is aborted and an `AuraHandledException` or logged exception is raised — no data operation proceeds.

**Layer 2 — FLS Stripping (Security.stripInaccessible)**

```apex
// Before DML:
Security.stripInaccessible(AccessType.READABLE, records)
Security.stripInaccessible(AccessType.UPDATABLE, records)
Security.stripInaccessible(AccessType.CREATABLE, records)
```

Even if a record is returned by SOQL, field values the user cannot access are stripped before any processing or serialization.

**Layer 3 — WITH USER_MODE SOQL**

```apex
SELECT ... FROM DataVault_Export_Configs__c WHERE ... WITH USER_MODE LIMIT 1
SELECT ... FROM DataVault_Cloud_Platform__mdt WHERE ... WITH USER_MODE
```

`WITH USER_MODE` enforces the running user's sharing rules and FLS at the database level — independent of class-level sharing declarations.

### 7.4 Sharing Model — `with sharing` Universal Declaration

Every production Apex class is declared `with sharing`. This ensures:

- Record-level visibility respects the running user's sharing rules
- In Batch Apex (which runs as the scheduling user), sharing is enforced for the user who set up the config
- No class runs in an elevated sharing context
- No class uses `without sharing` — zero bypass of sharing rules in this package

### 7.5 Dynamic SOQL — SOQL Injection Prevention

`DataVaultObjectAccessHelper.buildSecureQuery()` never interpolates user-supplied strings directly into SOQL:

- Object name is validated against `Schema.getGlobalDescribe().keySet()` — only valid SObject API names proceed
- Field names in SELECT are sourced **only** from `Schema.describe()` results — no user input reaches field names
- The incremental timestamp is formatted via `Datetime.formatGmt()` and embedded as a literal — not a bind variable (safe because it is system-generated, not user-supplied)
- No dynamic SOQL ever accepts free-form user text

### 7.6 Data Exposure Prevention

- The UI never displays Named Credential details, endpoint URLs, or AWS credentials
- `ConfigDTO` returned to LWC contains only: cloud platform, credential API name, object API name, enable flag, and last run statistics — no sensitive fields
- Error logs capture only error messages, stack traces, class/method names, and timestamps — no record data, no credentials, no field values from exported records
- JSON payloads sent to S3 include only fields the running user can read — `Security.stripInaccessible()` applied before serialization
- No record data is stored inside Salesforce after export — records are streamed to S3 and the payload is not persisted in the org

### 7.7 Callout Security

- All callouts use `callout:` prefix — platform handles SSL/TLS termination and certificate trust
- No self-signed certificates accepted unless explicitly configured by the subscriber in Named Credential setup
- HTTP timeout set to 120 seconds — prevents indefinite connection hold
- Retry only on transient infrastructure errors (429, 502, 503, 504) — not on auth failures (401, 403) or client errors (4xx), which would indicate misconfiguration, not transience

### 7.8 Multi-Tenant Isolation

- Config scoped to `SetupOwnerId = UserInfo.getOrganizationId()` — query always returns only the current org's config
- No static variables used for cross-request state
- No custom settings or metadata records shared across subscriber orgs
- Metadata type records (`DataVault_Cloud_Platform__mdt`) are marked **Protected** — subscribers cannot read or modify them programmatically
- Permission Set grants access only to package-specific components — no access to standard org objects or data

### 7.9 Apex Class Visibility

- All `@AuraEnabled` methods are on `DataVaultExportConfigController` — a single, auditable surface
- Internal service classes (`DataVaultExportConfigLogic`, `DataVaultExportConfigService`, `DataVaultObjectAccessHelper`, etc.) have no `@AuraEnabled` methods — they cannot be called directly from LWC or external API consumers
- `DataVault_PackageException` is used for security violation signals — it is a typed exception that propagates intentionally, never silently swallowed

---

## 8. Error Handling & Logging

### 8.1 Logging Framework Architecture

The error logging system is a multi-layer, buffered pipeline:

```
Exception / Callout Failure
    → DataVault_Error_Logger.logError() / logCalloutFailure()
    → DataVault_Error_LogContext (data holder)
    → DataVault_Error_LogRecordBuilder.build() (sObject construction)
    → DataVault_Error_LogBuffer.add() (in-memory accumulation)
    → DataVault_Error_LogBuffer.maybeFlush() (threshold check)
    → [Threshold met or explicit flush()]
    → DataVault_Security_Utility.isLoggerCreatable() (CRUD check)
    → Security.stripInaccessible(CREATABLE, logs)
    → insert as user [bulk DML]
    → DataVault_Error_Log__c records
```

### 8.2 Error Capture Points

| Location                             | Error Type      | Trigger                                   |
| ------------------------------------ | --------------- | ----------------------------------------- |
| `DataVaultIntegrationService`        | Callout Failure | Non-2xx HTTP status after retries         |
| `DataVaultIntegrationService`        | Callout Failure | `CalloutException` thrown                 |
| `DataVaultExportBatch.execute()`     | Apex Exception  | Heap limit exceeded, unexpected exception |
| `DataVaultExportBatch.finish()`      | Apex Exception  | DML limit exceeded, update failure        |
| `DataVaultExportScheduler.execute()` | Apex Exception  | Config unreadable, batch enqueue failure  |

### 8.3 Callout Failure Detail

When a callout fails, `DataVault_Error_Logger.logCalloutFailure(CalloutFailureInput)` is called with:

- Error message
- Apex class and method name
- Optional `HttpRequest` (headers, truncated body — max 16KB)
- Optional `HttpResponse` (status code, status text, truncated body — max 16KB)

This detail is formatted into `Stack_Trace__c` on `DataVault_Error_Log__c` — enabling precise reproduction of the failure condition without exposing credentials (auth headers are never included).

### 8.4 Buffer Flush Strategy

`DataVault_Error_LogBuffer` auto-flushes when:

- Buffer accumulates ≥ 100 records
- DML rows used + buffer size ≥ `Limits.getLimitDmlRows() - 1`
- DML statements used ≥ `Limits.getLimitDmlStatements() - 1`

`DataVault_Error_Logger.flush()` is explicitly called in `DataVaultExportBatch.finish()` to guarantee all buffered logs are written before the batch transaction closes.

### 8.5 Resilience Properties

- `DataVault_Error_LogBuffer.flush()` catches `DmlException` internally — logging never throws and never interrupts the main execution path
- CRUD check (`isLoggerCreatable()`) performed before every flush — if the user cannot create error logs, the flush is silently skipped (logs not lost; they remain in buffer until context ends)
- String truncation in `DataVault_Error_LogRecordBuilder` ensures no `StringException` from field length violations:
  - `Error_Message__c`: max 32,768 chars
  - `Stack_Trace__c`: max 32,768 chars
  - `Apex_Class_Name__c` / `Method_Name__c`: max 255 chars

### 8.6 Stack Trace Parsing

`DataVault_Error_StackParser.parse()` extracts class and method name from the first line of the Apex stack trace (format: `ClassName.methodName: line N`), populating `Apex_Class_Name__c` and `Method_Name__c` on the log record — enabling targeted filtering in the Error Logs tab.

### 8.7 Observability

- `DataVault_Error_Log__c` records are visible via the **DataVault Error Logs** tab
- Auto-number name field (`ERR-{0000}`) provides a chronological reference ID
- `Timestamp__c` enables time-range filtering
- `Error_Type__c` picklist enables filtering by failure category (callout vs. Apex exception)
- Full stack trace stored for deep debugging without org access

---

## 9. Governor Limits & Optimization

### 9.1 SOQL Limits

| Check Location                                 | Check Logic                                           | Action on Breach                                |
| ---------------------------------------------- | ----------------------------------------------------- | ----------------------------------------------- |
| `DataVaultExportBatch.start()`                 | `Limits.getLimitQueries() - Limits.getQueries() >= 1` | Throws `DataVault_PackageException`, logs error |
| `DataVault_Security_Utility.getConfigRecord()` | SOQL query limit check before execution               | Throws `DataVault_PackageException`             |

- Dynamic SOQL for record export uses a single `Database.getQueryLocator()` — batch platform manages cursor pagination, not the package
- Metadata queries (`DataVault_Cloud_Platform__mdt`) are cacheable — the Apex platform may cache these automatically

### 9.2 Callout Limits

| Check Location                   | Check Logic                                             | Action on Breach                                |
| -------------------------------- | ------------------------------------------------------- | ----------------------------------------------- |
| `DataVaultExportBatch.execute()` | `Limits.getLimitCallouts() - Limits.getCallouts() >= 1` | Logs error, skips chunk, increments error count |

- Batch size of 200 records = 1 callout per execute() chunk
- `Database.AllowsCallouts` declared on batch class — required for callouts in batch execute()
- Retry logic (max 2 retries) uses the same callout slot — total possible callouts per execute(): 3 (on persistent transient errors)

### 9.3 DML Limits

| Check Location                               | Check Logic                                                       | Action on Breach                |
| -------------------------------------------- | ----------------------------------------------------------------- | ------------------------------- |
| `DataVaultExportBatch.finish()`              | `Limits.getLimitDmlStatements() - Limits.getDmlStatements() >= 1` | Logs error, skips config update |
| `DataVault_Error_LogBuffer.canSafelyFlush()` | DML rows + buffer size vs. limit; DML statements vs. limit        | Defers flush                    |

- Error log inserts use bulk DML (`insert as user [list]`) — one DML statement for up to 100 records
- Config update in `finish()` uses a single DML statement for one record

### 9.4 Heap Limits

| Check Location                   | Check Logic                                                    | Action on Breach        |
| -------------------------------- | -------------------------------------------------------------- | ----------------------- |
| `DataVaultExportBatch.execute()` | `Limits.getHeapSize() < (Limits.getLimitHeapSize() - 500_000)` | Logs error, skips chunk |

- 500KB heap buffer reserved before serialization — prevents `LimitException` from JSON serialization of large record batches
- Batch size of 200 records is chosen to balance throughput against heap consumption

### 9.5 Bulkification

- `DataVaultExportBatch` processes records in chunks of 200 (configurable at enqueue time)
- Error log buffer accumulates up to 100 records before flushing — single DML per 100 errors
- `DataVaultObjectAccessHelper.getReadableFieldApiNames()` caches describe results per object — eliminates repeated describe calls across execute() chunks
- No record-by-record DML anywhere in the codebase

### 9.6 Async Processing Choice

**Why Batch Apex (not Queueable or Future):**

- Batch Apex is the only async mechanism that supports `Database.AllowsCallouts` AND handles large result sets via cursor-based pagination (`Database.QueryLocator`)
- `Database.Stateful` allows accumulation of success/error counts across all execute() calls
- A Queueable chain could theoretically replace this, but would require recursive re-enqueuing per chunk and lacks native query cursor support
- Future methods have a single callout limit per invocation — not suitable for multi-chunk exports

---

## 10. Scalability & Extensibility

### 10.1 Adding New Cloud Providers

The architecture is designed for zero-code-change platform addition:

1. A new `DataVault_Cloud_Platform__mdt` metadata record is deployed (e.g., `Api_Value__c = "Azure_Blob"`)
2. `DataVaultExportConfigController.getCloudPlatformOptions()` automatically includes it in the UI dropdown (filtered by `Is_Active__c = TRUE`)
3. `DataVaultIntegrationService` is extended with a platform-specific `send()` implementation
4. The batch class calls the integration service — routing to the correct platform is handled by the `Cloud_Platform__c` value on the config record
5. The user flow, config storage, scheduling, and error logging are entirely unchanged

The Custom Metadata approach means new platforms are a **metadata + integration class change**, not a UI or architecture change.

### 10.2 Scaling for Large Data Volumes

- Batch size of 200 is a starting point — it can be adjusted in `DataVaultExportScheduler` without code changes if heap or callout behavior requires tuning
- `Database.QueryLocator` supports up to 50 million records — the batch framework handles all chunking and cursor management
- Incremental backup (timestamp watermark) ensures each daily run processes only changed records — volume stays bounded to daily change rate, not total org data volume
- For very high-volume objects (millions of records/day), the batch size can be decreased to 50 or 100 to reduce per-execute heap consumption

### 10.3 Future-Proof Design

| Design Decision                     | Future Benefit                                                       |
| ----------------------------------- | -------------------------------------------------------------------- |
| Custom Metadata for platforms       | New platforms without schema changes                                 |
| Hierarchy Custom Setting for config | Per-profile/per-user config levels possible without schema changes   |
| Layered service architecture        | Individual layers replaceable without touching UI or scheduler       |
| Buffered error logging              | High-volume error scenarios handled without DML limit risk           |
| Named Credential abstraction        | Any auth mechanism (OAuth, API key, cert) supportable per-credential |

---

## 11. AppExchange Review Readiness

### 11.1 Security Review Compliance Summary

| Security Requirement       | Data Vault Implementation                                                     | Status    |
| -------------------------- | ----------------------------------------------------------------------------- | --------- |
| No hardcoded credentials   | Named Credential API name only — no URLs, keys, or tokens                     | COMPLIANT |
| CRUD enforcement           | Schema.sObjectType checks before every DML and SOQL operation                 | COMPLIANT |
| FLS enforcement            | Security.stripInaccessible() + dynamic field describe + WITH USER_MODE        | COMPLIANT |
| Sharing model respected    | All classes `with sharing`; no `without sharing` declarations                 | COMPLIANT |
| No SOQL injection          | Object/field names sourced only from Schema.describe(); no user input in SOQL | COMPLIANT |
| No XSS                     | No Visualforce; LWC uses `{property}` binding (auto-escaped by framework)     | COMPLIANT |
| No sensitive data exposure | No credentials in UI, logs, or error messages                                 | COMPLIANT |
| Callout security           | All callouts via Named Credentials; platform handles SSL/TLS                  | COMPLIANT |
| Async safety               | Batch Apex with explicit limit checks; stateful error accumulation            | COMPLIANT |
| Permission model           | Permission Set with minimum necessary permissions; no ViewAll/ModifyAll       | COMPLIANT |
| Multi-tenant isolation     | Org-scoped config; no shared state; no hardcoded IDs                          | COMPLIANT |
| Error handling             | All exceptions caught, logged, and surfaced without exposing internals        | COMPLIANT |

### 11.2 Why This Package Is Secure

**Credential Architecture:** The package has a structural guarantee against credential exposure. Because Named Credentials are resolved by the Salesforce platform at the HTTP layer — after Apex code has constructed the request and before the network connection is made — Apex code in this package is architecturally incapable of reading the actual endpoint URL, access key, or authentication token. The Named Credential API name stored in the custom setting is an opaque string identifier, not a credential.

**Data Access Integrity:** Data Vault implements a three-layer FLS/CRUD defense: explicit Schema-based CRUD checks before operations, `Security.stripInaccessible()` before all DML and serialization, and `WITH USER_MODE` in all SOQL. This is not a single-point check — all three layers must pass independently. A user with read access to an object but no access to a specific field will have that field stripped from both the Salesforce DML operation and the S3 JSON payload.

**No Privilege Escalation:** All Apex classes declare `with sharing`. There is no path through the codebase that elevates to a without-sharing context. The batch class runs as the user who configured the export — not as an elevated system user. The Permission Set grants only the access necessary to operate the app's components; it grants no access to standard org data beyond what the user already has.

**Audit Trail:** Every error — callout failure, Apex exception, limit breach — is captured with full context (class, method, timestamp, message, stack trace) and persisted to `DataVault_Error_Log__c`. This provides a complete audit trail for security incident investigation without storing any exported record data or credentials in the log.

### 11.3 Salesforce Best Practices Adherence

- **LWC over legacy frameworks:** Uses LWC (API version 62.0) exclusively — no Aura Components, no Visualforce
- **Named Credentials for all callouts:** No hardcoded endpoints or credentials anywhere
- **Batch Apex for async processing:** Correct async primitive for the volume and callout requirements
- **Custom Metadata for configuration:** Deployable, version-controlled platform configuration
- **Hierarchy Custom Setting for org config:** Correct primitive for single-record org-level settings
- **Permission Set for access control:** AppExchange standard — no profile modifications
- **Typed exceptions:** `DataVault_PackageException` for intentional package-level error signaling
- **Null-safe describe operations:** All Schema.describe() calls include null checks for org-agnostic safety
- **Auto-number name field on error log:** Prevents duplicate name conflicts on high-volume error inserts

### 11.4 Test Coverage

All 15 production Apex classes have corresponding test classes. The test suite includes:

- Happy-path coverage for all major flows (save, schedule, batch run, error logging)
- Negative-path coverage for validation failures, CRUD violations, and callout failures
- Mock callout implementations covering: HTTP 200 success, HTTP 500 server error, HTTP 503 service unavailable, `CalloutException`
- Test user setup with explicit Permission Set assignment — tests run in realistic permission context
- `System.runAs()` used for permission-context-sensitive tests

The package is submitted with test coverage meeting and exceeding the 75% minimum requirement.

---

_Document prepared for AppExchange Security Review submission._  
_All architectural claims in this document are directly reflected in the deployed package source code._
