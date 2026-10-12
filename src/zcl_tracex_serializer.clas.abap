CLASS zcl_tracex_serializer DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_environment,
        app_version        TYPE string,
        runtime_version    TYPE string,
        os_name            TYPE string,
        os_version         TYPE string,
        device_model       TYPE string,
        is_physical_device TYPE abap_bool,
        free_ram_mb        TYPE i,
        total_ram_mb       TYPE i,
        battery_level      TYPE i,
        is_low_memory      TYPE abap_bool,
      END OF ty_environment,

      BEGIN OF ty_breadcrumb,
        sequence_order TYPE i,
        timestamp      TYPE string,
        category       TYPE string,
        action         TYPE string,
        target         TYPE string,
        data           TYPE REF TO data,
      END OF ty_breadcrumb,

      ty_breadcrumbs_tt TYPE STANDARD TABLE OF ty_breadcrumb WITH DEFAULT KEY,

      BEGIN OF ty_crash_payload,
        project_key    TYPE string,
        platform       TYPE string,
        language       TYPE string,
        occurred_at    TYPE string,
        exception_type TYPE string,
        error_message  TYPE string,
        stack_trace    TYPE string,
        environment    TYPE ty_environment,
        breadcrumbs    TYPE ty_breadcrumbs_tt,
      END OF ty_crash_payload .

    CLASS-METHODS format_iso_timestamp
      RETURNING
        VALUE(rv_iso) TYPE string .

    CLASS-METHODS serialize_crash
      IMPORTING
        is_payload     TYPE ty_crash_payload
      RETURNING
        VALUE(rv_json) TYPE string .

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_tracex_serializer IMPLEMENTATION.

  METHOD format_iso_timestamp.
    DATA lv_ts TYPE timestampl.
    GET TIME STAMP FIELD lv_ts.
    " Strict ISO 8601 UTC with millisecond precision
    rv_iso = |{ lv_ts TIMESTAMP = ISO TIMEZONE = 'UTC' }|.
  ENDMETHOD.


  METHOD serialize_crash.
    DATA ls_payload TYPE ty_crash_payload.
    ls_payload = is_payload.

    " 1. Strict Contract Defaults for Backend (Platform & Language)
    IF ls_payload-platform IS INITIAL.
      ls_payload-platform = 'abap'.
    ENDIF.

    IF ls_payload-language IS INITIAL.
      ls_payload-language = 'abap'.
    ENDIF.

    " 2. Strict ISO 8601 UTC Timestamp with 'Z'
    IF ls_payload-occurred_at IS INITIAL.
      ls_payload-occurred_at = format_iso_timestamp( ).
    ENDIF.

    " 3. Guard Stack Trace against Backend [Required] validation
    IF ls_payload-stack_trace IS INITIAL.
      ls_payload-stack_trace = 'Unknown ABAP Stack (Empty)'.
    ENDIF.

    " 4. Guard Environment DTO against Backend [Required] validation
    IF ls_payload-environment-app_version IS INITIAL.
      ls_payload-environment-app_version = '1.0.0'.
    ENDIF.

    IF ls_payload-environment-runtime_version IS INITIAL.
      ls_payload-environment-runtime_version = 'ABAP Cloud 7.58+'.
    ENDIF.

    IF ls_payload-environment-os_name IS INITIAL.
      ls_payload-environment-os_name = 'SAP Kernel / Linux'.
    ENDIF.

    IF ls_payload-environment-os_version IS INITIAL.
      ls_payload-environment-os_version = '7.93'.
    ENDIF.

    IF ls_payload-environment-device_model IS INITIAL.
      ls_payload-environment-device_model = 'SAP BTP Application Server'.
    ENDIF.

    " 5. Serialize with snake_case naming convention
    rv_json = /ui2/cl_json=>serialize(
      data        = ls_payload
      pretty_name = /ui2/cl_json=>pretty_mode-low_case
    ).
  ENDMETHOD.

ENDCLASS.
