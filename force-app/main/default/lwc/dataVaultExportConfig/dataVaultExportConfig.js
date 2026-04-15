/**
 * DataVault Export Configuration LWC
 *
 * Responsibilities:
 *  - Load existing export configuration
 *  - Allow admin to create or update configuration
 *  - Allow admin to enable or disable export execution
 *
 * Design notes (AppExchange):
 *  - No secrets are handled in the UI
 *  - All security enforcement happens server-side
 *  - Export enable/disable does NOT delete configuration
 *  - Object label is resolved server-side and returned with getConfig (synchronous, no extra wire call)
 */

import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";

import getConfig from "@salesforce/apex/DataVaultExportConfigController.getConfig";
import getCloudPlatformOptions from "@salesforce/apex/DataVaultExportConfigController.getCloudPlatformOptions";
import getReadableObjectOptions from "@salesforce/apex/DataVaultExportConfigController.getReadableObjectOptions";
import saveAndStartJob from "@salesforce/apex/DataVaultExportConfigController.saveAndStartJobFromMap";
import validateNamedCredentialConnection from "@salesforce/apex/DataVaultExportConfigController.validateNamedCredentialConnection";
import disableOrEnableExport from "@salesforce/apex/DataVaultExportConfigController.disableOrEnableExport";

export default class DataVaultExportConfig extends LightningElement {
  /* ========================
       State
       ======================== */

  cloudPlatform = "";
  cloudPlatformOptions = [];
  namedCredentialName = "";
  objectApiName = "";
  objectLabel = "";
  objectOptions = [];

  isLocked = true;
  isLoading = true;
  objectOptionsLoading = false;
  saveInProgress = false;

  isExportEnabled = true;

  lastRunSuccessCount = null;
  lastRunErrorCount = null;
  lastRunStatus = "";
  lastRunCompleted = null;

  wiredConfigResult;

  // Track both wires so the global spinner waits for both to resolve before showing the form
  configLoaded = false;
  cloudPlatformOptionsLoaded = false;

  /* ========================
       Wire: Load cloud platform options
       ======================== */

  @wire(getCloudPlatformOptions)
  wiredCloudPlatformOptions(result) {
    const { data, error } = result;
    if (data !== undefined || error !== undefined) {
      if (data) {
        this.cloudPlatformOptions = data;
      } else if (error) {
        this.dispatchToast(
          "Error loading cloud platforms",
          this.reduceError(error),
          "error"
        );
      }
      this.cloudPlatformOptionsLoaded = true;
      this.checkInitialLoadComplete();
    }
  }

  /* ========================
       Wire: Load config
       ======================== */

  @wire(getConfig)
  wiredConfig(result) {
    this.wiredConfigResult = result;
    const { data, error } = result;

    // Skip the initial loading state (data and error are both undefined)
    if (data === undefined && error === undefined) {
      return;
    }

    if (data) {
      this.cloudPlatform = data.cloudPlatform || "";
      this.namedCredentialName = data.namedCredentialName || "";
      this.objectApiName = data.objectApiName || "";
      this.objectLabel = data.objectLabel || "";
      this.isExportEnabled = data.isExportEnabled ?? true;
      this.lastRunSuccessCount =
        data.lastRunSuccessCount != null ? data.lastRunSuccessCount : null;
      this.lastRunErrorCount =
        data.lastRunErrorCount != null ? data.lastRunErrorCount : null;
      this.lastRunStatus = data.lastRunStatus || "";
      this.lastRunCompleted = data.lastRunCompleted || null;
      this.isLocked = true;
    } else if (error) {
      this.dispatchToast(
        "Error loading configuration",
        this.reduceError(error),
        "error"
      );
    } else {
      // data is null: no config exists yet — allow creation
      this.isLocked = false;
    }

    this.configLoaded = true;
    this.checkInitialLoadComplete();
  }

  /* ========================
       Data loading
       ======================== */

  loadObjectOptions() {
    this.objectOptionsLoading = true;
    getReadableObjectOptions()
      .then((data) => {
        this.objectOptions = data || [];
      })
      .catch((err) => {
        this.dispatchToast(
          "Error loading objects",
          this.reduceError(err),
          "error"
        );
      })
      .finally(() => {
        this.objectOptionsLoading = false;
      });
  }

  /* ========================
       Computed UI properties
       ======================== */

  get cloudPlatformPicklistOptions() {
    return [
      { label: "-- Select Cloud Platform --", value: "" },
      ...this.cloudPlatformOptions
    ];
  }

  get objectPicklistOptions() {
    if (this.isLocked) {
      // Single option built from getObjectInfo label — no bulk fetch needed in read-only mode
      return [{ label: this.objectDisplayLabel, value: this.objectApiName }];
    }
    return [{ label: "-- Select Object --", value: "" }, ...this.objectOptions];
  }

  // Spinner shown only during edit mode while options are loading
  get showObjectSpinner() {
    return !this.isLocked && this.objectOptionsLoading;
  }

  // Shows the human-readable label when available; falls back to API name while loading
  get objectDisplayLabel() {
    return this.objectLabel || this.objectApiName;
  }

  get showPlatformConfigFields() {
    return !!this.cloudPlatform;
  }

  get showEditAndToggleButtons() {
    return this.isLocked;
  }

  get showSaveButton() {
    return !this.isLocked;
  }

  get inputsDisabled() {
    return this.isLocked;
  }

  get disableSaveButton() {
    return (
      !this.cloudPlatform?.trim() ||
      !this.namedCredentialName?.trim() ||
      !this.objectApiName?.trim() ||
      this.saveInProgress
    );
  }

  get disableOrEnableExportButtonLabel() {
    return this.isExportEnabled ? "Disable Export" : "Enable Export";
  }

  get disableOrEnableExportButtonVariant() {
    return this.isExportEnabled ? "destructive" : "brand";
  }

  get showLastRunStatus() {
    return (
      this.isLocked &&
      (this.lastRunCompleted != null ||
        (this.lastRunStatus && this.lastRunStatus.length > 0))
    );
  }

  get lastRunStatusVariant() {
    if (this.lastRunStatus === "Success") return "success";
    if (this.lastRunStatus === "Partial Success") return "warning";
    if (this.lastRunStatus === "Failed") return "error";
    return "inverse";
  }

  get lastRunSuccessCountDisplay() {
    return this.lastRunSuccessCount != null ? this.lastRunSuccessCount : "0";
  }

  get lastRunErrorCountDisplay() {
    return this.lastRunErrorCount != null ? this.lastRunErrorCount : "0";
  }

  /* ========================
       Event handlers
       ======================== */

  handleCloudPlatformChange(event) {
    this.cloudPlatform = event.target.value || "";
    if (
      this.cloudPlatform &&
      !this.objectOptions.length &&
      !this.objectOptionsLoading
    ) {
      this.loadObjectOptions();
    }
  }

  handleNamedCredentialChange(event) {
    this.namedCredentialName = event.target.value || "";
  }

  handleObjectChange(event) {
    this.objectApiName = event.target.value || "";
  }

  handleEdit() {
    this.isLocked = false;
    if (this.cloudPlatform) {
      this.loadObjectOptions();
    }
  }

  handleSave() {
    if (this.disableSaveButton) {
      return;
    }

    this.isLoading = true;
    this.saveInProgress = true;

    // Validate Named Credential first (callout); then save (DML). Each Apex call is a separate transaction.
    validateNamedCredentialConnection({
      namedCredentialName: this.namedCredentialName.trim()
    })
      .then(() => {
        // Controller accepts a Map<String, String> instead of the wrapper directly.
        return saveAndStartJob({
          inputMap: {
            cloudPlatform: this.cloudPlatform.trim(),
            namedCredentialName: this.namedCredentialName.trim(),
            objectApiName: this.objectApiName.trim()
          }
        });
      })
      .then(() => {
        this.dispatchToast(
          "Success",
          "Configuration saved and export scheduled.",
          "success"
        );
        this.isLocked = true;
        this.isExportEnabled = true;
        return refreshApex(this.wiredConfigResult);
      })
      .catch((err) => {
        this.dispatchToast("Error", this.reduceError(err), "error");
      })
      .finally(() => {
        this.saveInProgress = false;
        this.isLoading = false;
      });
  }

  handleDisableOrEnableExport() {
    const newState = !this.isExportEnabled;
    this.isLoading = true;

    disableOrEnableExport({
      isExportEnabled: newState
    })
      .then(() => {
        this.dispatchToast(
          "Success",
          `Export ${this.isExportEnabled ? "disabled" : "enabled"}.`,
          "success"
        );
        return refreshApex(this.wiredConfigResult);
      })
      .catch((err) => {
        this.dispatchToast("Error", this.reduceError(err), "error");
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  /* ========================
       Helpers
       ======================== */

  checkInitialLoadComplete() {
    if (this.configLoaded && this.cloudPlatformOptionsLoaded) {
      this.isLoading = false;
    }
  }

  dispatchToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  reduceError(err) {
    if (!err) return "Unknown error";
    if (err.body?.message) return err.body.message;
    if (err.message) return err.message;
    return String(err);
  }
}
