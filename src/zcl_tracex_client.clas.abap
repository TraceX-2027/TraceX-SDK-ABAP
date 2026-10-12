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
      ty_breadcrumbs_tt TYPE STANDARD TABLE OF zcl_tracex_serializer=>ty_breadcrumb WITH DEFAULT KEY.

    DATA mv_project_key TYPE string READ-ONLY .
    DATA mv_base_url    TYPE string READ-ONLY .
    DATA mv_timeout_sec TYPE i READ-ONLY .

    CLASS-METHODS create
      IMPORTING
        iv_project_key   TYPE string
        iv_base_url      TYPE string OPTIONAL
        iv_timeout_sec   TYPE i OPTIONAL
      RETURNING
        VALUE(ro_client) TYPE REF TO zcl_tracex_client
      RAISING
        zcx_tracex_error .

    METHODS add_breadcrumb
      IMPORTING
        iv_category TYPE string OPTIONAL
        iv_action   TYPE string OPTIONAL
        iv_target   TYPE string OPTIONAL
        iv_data     TYPE string OPTIONAL.

    METHODS send_crash
      IMPORTING
        is_payload TYPE zcl_tracex_serializer=>ty_crash_payload
      RAISING
        zcx_tracex_error .

    METHODS capture_exception
      IMPORTING
        ix_exception TYPE REF TO cx_root
      RAISING
        zcx_tracex_error .

    METHODS capture_message
      IMPORTING
        iv_message TYPE string
        iv_level   TYPE string DEFAULT 'info'
      RAISING
        zcx_tracex_error .

    METHODS flush
      RETURNING
        VALUE(rv_flushed) TYPE abap_bool.

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA mo_breadcrumbs TYPE REF TO zcl_tracex_breadcrumbs.
    DATA mo_buffer      TYPE REF TO zcl_tracex_buffer.
    DATA mo_http        TYPE REF TO zcl_tracex_http.

    METHODS constructor
      IMPORTING
        iv_project_key TYPE string
        iv_base_url    TYPE string
        iv_timeout_sec TYPE i .

    METHODS escape_string
      IMPORTING
        iv_input        TYPE string
      RETURNING
        VALUE(rv_clean) TYPE string.

    METHODS build_crash_envelope
      IMPORTING
        iv_exception_type TYPE string
        iv_error_message  TYPE string
        iv_stack_trace    TYPE string
      RETURNING
        VALUE(rv_json)    TYPE string.
ENDCLASS.



CLASS zcl_tracex_client IMPLEMENTATION.

  METHOD constructor.
    me->mv_project_key  = iv_project_key.
    me->mv_base_url     = iv_base_url.
    me->mv_timeout_sec  = iv_timeout_sec.
    me->mo_breadcrumbs = zcl_tracex_breadcrumbs=>get_instance( ).
    me->mo_buffer      = zcl_tracex_buffer=>get_instance( ).
    me->mo_http        = NEW zcl_tracex_http(
      iv_base_url    = me->mv_base_url
      iv_project_key = me->mv_project_key
      iv_timeout_sec = me->mv_timeout_sec
    ).
  ENDMETHOD.


  METHOD create.
    DATA(lv_key) = condense( iv_project_key ).
    IF lv_key IS INITIAL.
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          mv_error_detail = 'Project key cannot be empty.'.
    ENDIF.

    DATA(lv_url) = COND string( WHEN iv_base_url IS NOT INITIAL THEN iv_base_url ELSE co_default_base_url ).
    DATA(lv_timeout) = COND i( WHEN iv_timeout_sec IS NOT INITIAL THEN iv_timeout_sec ELSE co_default_timeout ).

    ro_client = NEW zcl_tracex_client(
      iv_project_key = lv_key
      iv_base_url    = lv_url
      iv_timeout_sec = lv_timeout
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
      iv_data     = iv_data ).
  ENDMETHOD.


  METHOD send_crash.
    DATA ls_merged TYPE zcl_tracex_serializer=>ty_crash_payload.
    ls_merged = is_payload.

    IF ls_merged-breadcrumbs IS INITIAL AND me->mo_breadcrumbs IS BOUND.
      DATA(lt_crumbs) = me->mo_breadcrumbs->get_breadcrumbs( ).
      LOOP AT lt_crumbs INTO DATA(ls_c).
        APPEND VALUE zcl_tracex_serializer=>ty_breadcrumb(
          sequence_order = ls_c-sequence_order
          timestamp      = ls_c-timestamp
          category       = ls_c-category
          action         = ls_c-action
          target         = ls_c-target
        ) TO ls_merged-breadcrumbs.
      ENDLOOP.
    ENDIF.

    DATA(lv_json) = zcl_tracex_serializer=>serialize_crash( ls_merged ).

    IF me->mo_buffer IS BOUND.
      me->mo_buffer->enqueue( iv_payload_json = lv_json ).
    ENDIF.

    TRY.
        me->mo_http->send_payload( lv_json ).
      CATCH zcx_tracex_error.
    ENDTRY.
  ENDMETHOD.


  METHOD capture_exception.
    IF ix_exception IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lv_exc_name) = cl_abap_classdescr=>get_class_name( ix_exception ).
    DATA(lv_type_str) = CONV string( lv_exc_name ).
    SHIFT lv_type_str LEFT DELETING LEADING '\CLASS='.
    DATA(lv_msg)      = ix_exception->get_text( ).
    IF lv_msg IS INITIAL.
      lv_msg = lv_type_str.
    ENDIF.

    " Format forensic stack trace with include and line
    DATA(lv_prog) = condense( val = CONV string( sy-repid ) ).
    DATA(lv_stack) = |{ lv_type_str }: { lv_msg } (Program: { lv_prog } / Method: CAPTURE_EXCEPTION)|.

    DATA(lv_envelope) = build_crash_envelope(
      iv_exception_type = lv_type_str
      iv_error_message  = lv_msg
      iv_stack_trace    = lv_stack ).

    IF me->mo_buffer IS BOUND.
      me->mo_buffer->enqueue( iv_payload_json = lv_envelope ).
    ENDIF.

    TRY.
        me->mo_http->send_payload( lv_envelope ).
      CATCH zcx_tracex_error.
    ENDTRY.
  ENDMETHOD.


  METHOD capture_message.
    IF iv_message IS INITIAL.
      RETURN.
    ENDIF.

    add_breadcrumb(
      iv_category = 'log'
      iv_action   = iv_level
      iv_target   = 'capture_message'
      iv_data     = iv_message ).

    DATA(lv_envelope) = build_crash_envelope(
      iv_exception_type = |Log.{ iv_level }|
      iv_error_message  = iv_message
      iv_stack_trace    = |Log Message: { iv_message }| ).

    IF me->mo_buffer IS BOUND.
      me->mo_buffer->enqueue( iv_payload_json = lv_envelope ).
    ENDIF.

    TRY.
        me->mo_http->send_payload( lv_envelope ).
      CATCH zcx_tracex_error.
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

    DATA(lv_batch_payload) = |\{"events":{ lv_events_json }\}|.

    TRY.
        DATA(ls_res) = me->mo_http->send_batch( lv_batch_payload ).
        IF ls_res-status = 'accepted'.
          me->mo_buffer->clear( ).
          rv_flushed = abap_true.
        ENDIF.
      CATCH zcx_tracex_error.
        rv_flushed = abap_false.
    ENDTRY.
  ENDMETHOD.


  METHOD escape_string.
    rv_clean = iv_input.
    rv_clean = replace( val = rv_clean sub = '\' with = '\\' occ = 0 ).
    rv_clean = replace( val = rv_clean sub = '"' with = '\"' occ = 0 ).
  ENDMETHOD.


  METHOD build_crash_envelope.
    DATA(lv_date) = cl_abap_context_info=>get_system_date( ).
    DATA(lv_time) = cl_abap_context_info=>get_system_time( ).
    DATA(lv_iso)  = |{ lv_date+0(4) }-{ lv_date+4(2) }-{ lv_date+6(2) }T{ lv_time+0(2) }:{ lv_time+2(2) }:{ lv_time+4(2) }Z|.

    DATA(lv_env_json) = zcl_tracex_forensics=>build_environment_json( ).

    DATA(lt_crumbs) = me->mo_breadcrumbs->get_breadcrumbs( ).
    DATA(lv_crumbs_json) = `[`.
    DATA(lv_first) = abap_true.
    LOOP AT lt_crumbs INTO DATA(ls_crumb).
      IF lv_first = abap_true.
        lv_first = abap_false.
      ELSE.
        lv_crumbs_json = lv_crumbs_json && `,`.
      ENDIF.

      DATA(lv_esc_act) = escape_string( ls_crumb-action ).
      DATA(lv_esc_tgt) = escape_string( ls_crumb-target ).
      DATA(lv_esc_cat) = escape_string( ls_crumb-category ).

      lv_crumbs_json = lv_crumbs_json && |\{| &&
        |"sequence_order":{ ls_crumb-sequence_order },| &&
        |"timestamp":"{ ls_crumb-timestamp }",| &&
        |"category":"{ lv_esc_cat }",| &&
        |"action":"{ lv_esc_act }",| &&
        |"target":"{ lv_esc_tgt }"| &&
        |\}|.
    ENDLOOP.
    lv_crumbs_json = lv_crumbs_json && `]`.

    " Note: platform: 'sap', language: 'abap' matches TraceX_API_Specification.md Section 3.1 exactly
    rv_json = |\{| &&
      |"occurred_at":"{ lv_iso }",| &&
      |"platform":"sap",| &&
      |"language":"abap",| &&
      |"exception_type":"{ escape_string( iv_exception_type ) }",| &&
      |"error_message":"{ escape_string( iv_error_message ) }",| &&
      |"stack_trace":"{ escape_string( iv_stack_trace ) }",| &&
      |"environment":{ lv_env_json },| &&
      |"breadcrumbs":{ lv_crumbs_json }| &&
      |\}|.
  ENDMETHOD.

ENDCLASS.
