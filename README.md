# TraceX SDK for SAP ABAP

Official SAP ABAP SDK for the **TraceX** Real-Time Application Performance Monitoring & Crash Analytics Platform.

Designed for Clean Core ABAP (SAP S/4HANA Cloud, SAP BTP ABAP Environment, and SAP S/4HANA On-Premise 2020+).

---

## 🚀 Key Features

* **Zero-Overhead Session Breadcrumbs**: In-memory FIFO ring buffer (`ZCL_TRACEX_BREADCRUMBS`) capturing up to 50 chronological diagnostics.
* **Bounded Offline Event Buffer**: Resilient crash queue (`ZCL_TRACEX_BUFFER`) with automatic FIFO eviction capped at 100 events.
* **Persistent Cluster Storage**: DDIC cluster table `ZTRACEX_BUFFER` preserving offline telemetry across work process boundaries.
* **Batch Telemetry Ingestion**: High-throughput batch dispatch via `/api/v1/crashes/batch` (`ZCL_TRACEX_HTTP->send_batch`).
* **Non-Blocking Asynchronous qRFC Dispatch**: Remote-enabled function module `Z_TRACEX_SEND_CRASH_ASYNC` executing in background task without degrading user transaction response times.
* **Automated Flush Scheduled Job**: Background report `ZTRACEX_FLUSH_BUFFER` for automated periodic buffer clearance.
* **Automatic Forensic Harvesting**: Gathers host OS, system ID, client mandt, program, transaction context, and full ABAP execution call stack.
* **PII & Credential Redaction**: Built-in sanitization stripping Bearer tokens, passwords, and sensitive keys from breadcrumb payloads.

---

## 🔒 SAP Transaction STRUST SSL Setup Guide

Because the TraceX Edge Ingestion Gateway uses secure HTTPS (`https://tracex-edge-ingest...`), the SAP Application Server must trust the Edge SSL Root Certificate Authority (CA).

Follow these steps to configure SSL trust in your SAP system:

### Step 1: Obtain the Root Certificate
1. Open your browser and navigate to the TraceX Edge Ingestion endpoint:
   `https://tracex-edge-ingest.kareemadel10110.workers.dev`
2. Click the lock icon in your browser address bar -> **Connection is secure** -> **Certificate is valid**.
3. In the Certificate Hierarchy tab, select the Root CA (`ISRG Root X1` or `DigiCert Global Root CA`).
4. Export / Download the certificate in **Base-64 encoded X.509 (.CER)** or **PEM** format.

### Step 2: Import Certificate in STRUST
1. Log into your SAP GUI and open transaction **`STRUST`** (Trust Manager).
2. Switch to change mode by clicking the **Display <-> Change** toggle button (`Ctrl + F1`).
3. In the left navigation tree, double-click on:
   * **`SSL client SSL Client Standard (DFAULT)`** (if using standard client PSE), OR
   * **`SSL client (Anonymous)`** (`ANONYM`).
4. In the bottom section **Certificate**, click the **Import Certificate** button (icon with an arrow pointing into a folder).
5. Browse and select your exported `.cer` file and click **Open**.
6. The certificate details will display in the Certificate section.
7. Click the **Add to Certificate List** button.
8. Verify that the Root CA now appears in the **Certificate List** table.
9. Click **Save** (`Ctrl + S`).

### Step 3: Restart ICM (Internet Communication Manager)
1. Open transaction **`SMICM`** (ICM Monitor).
2. From the menu bar, navigate to **Administration** -> **ICM** -> **Restart** -> **Yes**.
3. Verify that the ICM status returns to **Running (Green)**.

---

## 🛠️ Quick Start

### 1. Initialize Client via Configuration Table
```abap
" Instantiates client using credentials from database table ZTRACEX_CONFIG
DATA(lo_tracex) = zcl_tracex_client=>create_from_config( iv_project_id = 'PROJECT_UUID' ).
```

### 2. Record Diagnostic Breadcrumbs
```abap
lo_tracex->add_breadcrumb(
  iv_category = 'ui.action'
  iv_action   = 'SUBMIT_ORDER'
  iv_target   = 'BTN_CHECKOUT'
  iv_data     = 'order_id=98721'
).
```

### 3. Capture Caught Exceptions
```abap
TRY.
    " Business logic that may fail
    DATA(lv_result) = 10 / 0.
  CATCH cx_sy_zerodivide INTO DATA(lx_error).
    lo_tracex->capture_exception( lx_error ).
ENDTRY.
```

### 4. Log Tagged Messages & Flush Offline Queue
```abap
" Records warning log message into offline buffer
lo_tracex->capture_message(
  iv_message = 'Payment gateway latency exceeded 2000ms'
  iv_level   = 'warning'
).

" Executes batch flush to TraceX cloud ingest
DATA(lv_flushed) = lo_tracex->flush( ).
```

---

## 📦 Package Hierarchy & Architecture

| Object Name | Object Type | Description |
|---|---|---|
| `ZCL_TRACEX_CLIENT` | Class | Main TraceX Client Facade |
| `ZCL_TRACEX_HTTP` | Class | Resilient Telemetry HTTP Ingestion Client |
| `ZCL_TRACEX_BUFFER` | Class | In-Memory Bounded FIFO Offline Crash Queue |
| `ZCL_TRACEX_BREADCRUMBS` | Class | Forensic Breadcrumbs Ring Buffer |
| `ZCL_TRACEX_FORENSICS` | Class | Host & Environment Metadata Collector |
| `ZCL_TRACEX_SERIALIZER` | Class | Strict JSON Serializer with ISO-8601 Timestamps |
| `ZCL_TRACEX_CONFIG` | Class | Secure Configuration Reader with Table Buffer |
| `ZTRACEX_CONFIG` | DDIC Table | Tenant & Project Credentials Storage Table |
| `ZTRACEX_BUFFER` | DDIC Table | Persistent Offline Crash Event Storage |
| `Z_TRACEX_SEND_CRASH_ASYNC` | Function Module | Non-Blocking Background qRFC Dispatcher |
| `ZTRACEX_FLUSH_BUFFER` | Report | Scheduled Periodic Batch Flush Job |
| `ZCX_TRACEX_ERROR` | Exception Class | Typed SDK Exception Class |

---

## 🧪 Testing

Execute automated ABAP Unit test suites via ADT (`Ctrl + Shift + F10`) or console runners (`F9`):
* `ZCL_TRACEX_TEST_T228`: Configuration, Serializer, and Ingestion tests.
* `ZCL_TRACEX_TEST_T229`: Forensic Context, Breadcrumb Eviction, and PII Redaction tests.
* `ZCL_TRACEX_TEST_T230`: Offline Buffer FIFO, Batch Flush, and Endpoint Resolution tests.
