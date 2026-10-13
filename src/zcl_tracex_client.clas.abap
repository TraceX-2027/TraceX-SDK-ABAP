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

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA mo_breadcrumbs TYPE REF TO zcl_tracex_breadcrumbs .

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
    me->mo_breadcrumbs  = NEW zcl_tracex_breadcrumbs( ).
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
    " B4: Restore create_from_config factory method (static call)
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
      me->mo_breadcrumbs = NEW zcl_tracex_breadcrumbs( ).
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

      " N1: Re-index breadcrumbs sequentially 1..N and B1: serialize data as JSON object
      LOOP AT lt_ring_crumbs INTO DATA(ls_rc).
        DATA ls_bc TYPE zcl_tracex_serializer=>ty_breadcrumb.
        CLEAR ls_bc.
        ls_bc-sequence_order = sy-tabix.
        ls_bc-timestamp      = ls_rc-timestamp.
        ls_bc-category       = ls_rc-category.
        ls_bc-action         = ls_rc-action.
        ls_bc-target         = ls_rc-target.

        " B1: Assign breadcrumb data payload as valid JSON object
        IF ls_rc-data IS NOT INITIAL.
          TRY.
              DATA lr_obj TYPE REF TO data.
              lr_obj = /ui2/cl_json=>generate( json = ls_rc-data ).
              ls_bc-data = lr_obj.
            CATCH cx_root.
              DATA: BEGIN OF ls_raw_wrap,
                      raw TYPE string,
                    END OF ls_raw_wrap.
              ls_raw_wrap-raw = ls_rc-data.
              DATA lr_fallback TYPE REF TO data.
              GET REFERENCE OF ls_raw_wrap INTO lr_fallback.
              ls_bc-data = lr_fallback.
          ENDTRY.
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

    rs_response = lo_http->send_payload( lv_json ).

    " 5. M2: Clear breadcrumb ring buffer post-crash to prevent cross-incident contamination
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

    " Format exception type by stripping \CLASS=
    DATA(lv_raw_type) = cl_abap_classdescr=>get_class_name( ix_exception ).
    IF lv_raw_type CP '\CLASS=*'.
      ls_payload-exception_type = substring( val = lv_raw_type off = 7 ).
    ELSE.
      ls_payload-exception_type = lv_raw_type.
    ENDIF.

    ls_payload-error_message = ix_exception->get_text( ).

    " B1: Extract execution call stack via forensics
    ls_payload-stack_trace = zcl_tracex_forensics=>get_call_stack( ).

    " B2: Collect environment metadata via forensics
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

    " Dispatch and clear breadcrumbs
    rs_response = me->send_crash( ls_payload ).
  ENDMETHOD.

ENDCLASS.
