CLASS zcl_tracex_client DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE .

  PUBLIC SECTION.
    CONSTANTS co_default_base_url TYPE string
      VALUE 'https://tracex-edge-ingest.kareemadel10110.workers.dev/api/v1'.
    CONSTANTS co_default_timeout TYPE i VALUE 3.

    TYPES:
      ty_breadcrumb     TYPE zcl_tracex_serializer=>ty_breadcrumb,
      ty_breadcrumbs_tt TYPE zcl_tracex_serializer=>ty_breadcrumbs_tt.

    DATA mv_project_id    TYPE string READ-ONLY .
    DATA mv_project_key   TYPE string READ-ONLY .
    DATA mv_base_url      TYPE string READ-ONLY .
    DATA mv_environment   TYPE string READ-ONLY .
    DATA mv_timeout_sec   TYPE i READ-ONLY .

    CLASS-METHODS create
      IMPORTING
        !iv_project_key TYPE clike
        !iv_project_id  TYPE clike OPTIONAL
        !iv_base_url    TYPE clike OPTIONAL
        !iv_environment TYPE clike OPTIONAL
        !iv_timeout_sec TYPE i OPTIONAL
      RETURNING
        VALUE(ro_client) TYPE REF TO zcl_tracex_client
      RAISING
        zcx_tracex_error .

    CLASS-METHODS create_from_config
      IMPORTING
        !iv_project_id   TYPE clike
      RETURNING
        VALUE(ro_client) TYPE REF TO zcl_tracex_client
      RAISING
        zcx_tracex_error .

    METHODS add_breadcrumb
      IMPORTING
        !iv_category TYPE string OPTIONAL
        !iv_action   TYPE string OPTIONAL
        !iv_target   TYPE string OPTIONAL
        !iv_data     TYPE string OPTIONAL.

    METHODS send_crash
      IMPORTING
        !is_payload        TYPE zcl_tracex_serializer=>ty_crash_payload
      RETURNING
        VALUE(rs_response) TYPE zcl_tracex_http=>ty_ingest_response
      RAISING
        zcx_tracex_error .

    METHODS capture_exception
      IMPORTING
        !ix_exception      TYPE REF TO cx_root
      RETURNING
        VALUE(rs_response) TYPE zcl_tracex_http=>ty_ingest_response
      RAISING
        zcx_tracex_error .

    METHODS capture_message
      IMPORTING
        !iv_message        TYPE string
        !iv_level          TYPE string DEFAULT 'info'
      RETURNING
        VALUE(rs_response) TYPE zcl_tracex_http=>ty_ingest_response
      RAISING
        zcx_tracex_error .

    METHODS flush
      RETURNING
        VALUE(rv_flushed) TYPE abap_bool.

    METHODS get_buffer
      RETURNING
        VALUE(ro_buffer) TYPE REF TO zcl_tracex_buffer.

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA mo_breadcrumbs TYPE REF TO zcl_tracex_breadcrumbs .
    DATA mo_buffer      TYPE REF TO zcl_tracex_buffer .

    METHODS constructor
      IMPORTING
        !iv_project_key TYPE string
        !iv_project_id  TYPE string OPTIONAL
        !iv_base_url    TYPE string
        !iv_environment TYPE string OPTIONAL
        !iv_timeout_sec TYPE i .
ENDCLASS.



CLASS zcl_tracex_client IMPLEMENTATION.

  METHOD constructor.
    me->mv_project_key  = iv_project_key.
    me->mv_project_id   = iv_project_id.
    me->mv_base_url     = iv_base_url.
    me->mv_environment  = COND string( WHEN iv_environment IS NOT INITIAL THEN iv_environment ELSE 'production' ).
    me->mv_timeout_sec  = iv_timeout_sec.
    me->mo_breadcrumbs  = zcl_tracex_breadcrumbs=>get_instance( ).
    me->mo_buffer       = zcl_tracex_buffer=>get_instance( ).
  ENDMETHOD.


  METHOD create.
    DATA(lv_key) = condense( CONV string( iv_project_key ) ).

    " Strict project key validation (tracex_live_* or tracex_test_*)
    IF lv_key IS INITIAL OR NOT ( lv_key CP 'tracex_live_*' OR lv_key CP 'tracex_test_*' ).
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          textid          = zcx_tracex_error=>unauthorized_401
          mv_error_detail = 'TraceX Project Key must start with tracex_live_ or tracex_test_'.
    ENDIF.

    DATA(lv_id) = condense( CONV string( iv_project_id ) ).

    DATA lv_url TYPE string.
    IF iv_base_url IS NOT INITIAL.
      lv_url = condense( CONV string( iv_base_url ) ).
    ELSE.
      lv_url = co_default_base_url.
    ENDIF.

    DATA lv_env TYPE string.
    IF iv_environment IS NOT INITIAL.
      lv_env = condense( CONV string( iv_environment ) ).
    ELSE.
      lv_env = 'production'.
    ENDIF.

    DATA lv_timeout TYPE i.
    IF iv_timeout_sec IS NOT INITIAL AND iv_timeout_sec > 0.
      lv_timeout = iv_timeout_sec.
    ELSE.
      lv_timeout = co_default_timeout.
    ENDIF.

    ro_client = NEW zcl_tracex_client(
      iv_project_key = lv_key
      iv_project_id  = lv_id
      iv_base_url    = lv_url
      iv_environment = lv_env
      iv_timeout_sec = lv_timeout
    ).
  ENDMETHOD.


  METHOD create_from_config.
    DATA(ls_config) = zcl_tracex_config=>get_config( iv_project_id ).

    ro_client = create(
      iv_project_key = ls_config-api_key
      iv_project_id  = ls_config-project_id
      iv_base_url    = ls_config-base_url
      iv_environment = ls_config-environment
      iv_timeout_sec = ls_config-timeout_sec
    ).
  ENDMETHOD.


  METHOD add_breadcrumb.
    IF me->mo_breadcrumbs IS NOT BOUND.
      me->mo_breadcrumbs = zcl_tracex_breadcrumbs=>get_instance( ).
    ENDIF.

    me->mo_breadcrumbs->add_breadcrumb(
      iv_category = iv_category
      iv_action   = iv_action
      iv_target   = iv_target
      iv_data     = iv_data
    ).
  ENDMETHOD.


  METHOD send_crash.
    DATA ls_merged_payload TYPE zcl_tracex_serializer=>ty_crash_payload.
    ls_merged_payload = is_payload.

    " 1. B2: Populate environment if missing
    IF ls_merged_payload-environment-app_version IS INITIAL.
      DATA(ls_env) = zcl_tracex_forensics=>get_environment( ).
      ls_merged_payload-environment-app_version        = ls_env-app_version.
      ls_merged_payload-environment-runtime_version    = ls_env-runtime_version.
      ls_merged_payload-environment-os_name            = ls_env-os_name.
      ls_merged_payload-environment-os_version         = ls_env-os_version.
      ls_merged_payload-environment-device_model       = ls_env-device_model.
      ls_merged_payload-environment-is_physical_device = ls_env-is_physical_device.
      ls_merged_payload-environment-free_ram_mb        = ls_env-free_ram_mb.
      ls_merged_payload-environment-total_ram_mb       = ls_env-total_ram_mb.
      ls_merged_payload-environment-battery_level      = ls_env-battery_level.
      ls_merged_payload-environment-is_low_memory      = ls_env-is_low_memory.
    ENDIF.

    " 2. B1: Harvest call stack if missing
    IF ls_merged_payload-stack_trace IS INITIAL OR ls_merged_payload-stack_trace = 'Unknown ABAP Stack (Empty)'.
      ls_merged_payload-stack_trace = zcl_tracex_forensics=>get_call_stack( ).
    ENDIF.

    " 3. Auto-inject breadcrumbs from session ring buffer if payload has none
    IF ls_merged_payload-breadcrumbs IS INITIAL AND me->mo_breadcrumbs IS BOUND.
      DATA(lt_ring_crumbs) = me->mo_breadcrumbs->get_breadcrumbs( ).

      LOOP AT lt_ring_crumbs INTO DATA(ls_rc).
        DATA ls_bc TYPE zcl_tracex_serializer=>ty_breadcrumb.
        ls_bc-sequence_order = sy-tabix.
        ls_bc-timestamp      = ls_rc-timestamp.
        ls_bc-category       = ls_rc-category.
        ls_bc-action         = ls_rc-action.
        ls_bc-target         = ls_rc-target.

        IF ls_rc-data IS NOT INITIAL.
          DATA lr_data TYPE REF TO data.
          DATA(lv_raw_data) = ls_rc-data.
          GET REFERENCE OF lv_raw_data INTO lr_data.
          ls_bc-data = lr_data.
        ENDIF.

        APPEND ls_bc TO ls_merged_payload-breadcrumbs.
      ENDLOOP.
    ENDIF.

    DATA(lv_json) = zcl_tracex_serializer=>serialize_crash( ls_merged_payload ).

    " 4. Dispatch via HTTP client with configured timeout
    DATA(lo_http) = NEW zcl_tracex_http(
      iv_base_url    = me->mv_base_url
      iv_project_key = me->mv_project_key
      iv_timeout_sec = me->mv_timeout_sec
    ).

    TRY.
        rs_response = lo_http->send_payload( lv_json ).
      CATCH zcx_tracex_error INTO DATA(lx_send_err).
        " Buffer event offline on failure
        IF me->mo_buffer IS BOUND.
          me->mo_buffer->enqueue( iv_payload_json = lv_json ).
        ENDIF.
        RAISE EXCEPTION lx_send_err.
    ENDTRY.

    " 5. M2: Clear breadcrumb ring buffer post-crash
    IF me->mo_breadcrumbs IS BOUND.
      me->mo_breadcrumbs->clear( ).
    ENDIF.
  ENDMETHOD.


  METHOD capture_exception.
    IF ix_exception IS INITIAL.
      RETURN.
    ENDIF.

    DATA ls_payload TYPE zcl_tracex_serializer=>ty_crash_payload.
    ls_payload-project_key = me->mv_project_key.

    DATA(lv_raw_type) = cl_abap_classdescr=>get_class_name( ix_exception ).
    IF lv_raw_type CP '\CLASS=*'.
      ls_payload-exception_type = substring( val = lv_raw_type off = 7 ).
    ELSE.
      ls_payload-exception_type = lv_raw_type.
    ENDIF.

    ls_payload-error_message = ix_exception->get_text( ).
    ls_payload-stack_trace   = zcl_tracex_forensics=>get_call_stack( ).

    DATA(ls_env) = zcl_tracex_forensics=>get_environment( ).
    ls_payload-environment-app_version        = ls_env-app_version.
    ls_payload-environment-runtime_version    = ls_env-runtime_version.
    ls_payload-environment-os_name            = ls_env-os_name.
    ls_payload-environment-os_version         = ls_env-os_version.
    ls_payload-environment-device_model       = ls_env-device_model.
    ls_payload-environment-is_physical_device = ls_env-is_physical_device.
    ls_payload-environment-free_ram_mb        = ls_env-free_ram_mb.
    ls_payload-environment-total_ram_mb       = ls_env-total_ram_mb.
    ls_payload-environment-battery_level      = ls_env-battery_level.
    ls_payload-environment-is_low_memory      = ls_env-is_low_memory.

    rs_response = me->send_crash( ls_payload ).
  ENDMETHOD.


  METHOD capture_message.
    IF iv_message IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lv_level) = condense( val = iv_level ).
    IF lv_level IS INITIAL.
      lv_level = 'info'.
    ENDIF.

    " 1. Record diagnostic breadcrumb
    add_breadcrumb(
      iv_category = 'log'
      iv_action   = lv_level
      iv_target   = 'capture_message'
      iv_data     = iv_message ).

    " 2. Assemble crash payload for message event
    DATA ls_payload TYPE zcl_tracex_serializer=>ty_crash_payload.
    ls_payload-project_key    = me->mv_project_key.
    ls_payload-exception_type = |Log.{ lv_level }|.
    ls_payload-error_message  = iv_message.
    ls_payload-stack_trace    = |Log Message: { iv_message }|.

    DATA(ls_env) = zcl_tracex_forensics=>get_environment( ).
    ls_payload-environment-app_version        = ls_env-app_version.
    ls_payload-environment-runtime_version    = ls_env-runtime_version.
    ls_payload-environment-os_name            = ls_env-os_name.
    ls_payload-environment-os_version         = ls_env-os_version.
    ls_payload-environment-device_model       = ls_env-device_model.
    ls_payload-environment-is_physical_device = ls_env-is_physical_device.
    ls_payload-environment-free_ram_mb        = ls_env-free_ram_mb.
    ls_payload-environment-total_ram_mb       = ls_env-total_ram_mb.
    ls_payload-environment-battery_level      = ls_env-battery_level.
    ls_payload-environment-is_low_memory      = ls_env-is_low_memory.

    DATA(lv_json) = zcl_tracex_serializer=>serialize_crash( ls_payload ).

    " 3. Enqueue into buffer for batch ingestion / offline queue
    IF me->mo_buffer IS BOUND.
      me->mo_buffer->enqueue( iv_payload_json = lv_json ).
    ENDIF.

    " 4. Attempt immediate dispatch
    DATA(lo_http) = NEW zcl_tracex_http(
      iv_base_url    = me->mv_base_url
      iv_project_key = me->mv_project_key
      iv_timeout_sec = me->mv_timeout_sec
    ).

    TRY.
        rs_response = lo_http->send_payload( lv_json ).
      CATCH zcx_tracex_error.
        " Event is safely buffered in mo_buffer
    ENDTRY.
  ENDMETHOD.


  METHOD flush.
    rv_flushed = abap_false.
    IF me->mo_buffer IS NOT BOUND.
      rv_flushed = abap_true.
      RETURN.
    ENDIF.

    DATA(lt_pending) = me->mo_buffer->peek_all( ).
    IF lines( lt_pending ) = 0.
      rv_flushed = abap_true.
      RETURN.
    ENDIF.

    DATA(lv_events_json) = `[`.
    DATA(lv_first) = abap_true.
    LOOP AT lt_pending INTO DATA(ls_item).
      IF lv_first = abap_true.
        lv_first = abap_false.
      ELSE.
        lv_events_json = lv_events_json && `,`.
      ENDIF.
      lv_events_json = lv_events_json && ls_item-payload_json.
    ENDLOOP.
    lv_events_json = lv_events_json && `]`.

    DATA(lv_batch_payload) = |\{"project_key":"{ me->mv_project_key }","events":{ lv_events_json }\}|.

    DATA(lo_http) = NEW zcl_tracex_http(
      iv_base_url    = me->mv_base_url
      iv_project_key = me->mv_project_key
      iv_timeout_sec = me->mv_timeout_sec
    ).

    TRY.
        DATA(ls_res) = lo_http->send_batch( lv_batch_payload ).
        IF ls_res-status = 'accepted'.
          me->mo_buffer->clear( ).
          rv_flushed = abap_true.
        ENDIF.
      CATCH zcx_tracex_error.
        rv_flushed = abap_false.
    ENDTRY.
  ENDMETHOD.


  METHOD get_buffer.
    ro_buffer = me->mo_buffer.
  ENDMETHOD.

ENDCLASS.
