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

    DATA ls_payload TYPE zcl_tracex_serializer=>ty_crash_payload.
    ls_payload-project_key    = me->mv_project_key.
    DATA(lv_exc_name)         = cl_abap_classdescr=>get_class_name( ix_exception ).
    DATA(lv_type_str)         = CONV string( lv_exc_name ).
    SHIFT lv_type_str LEFT DELETING LEADING '\CLASS='.
    ls_payload-exception_type = lv_type_str.
    ls_payload-error_message  = ix_exception->get_text( ).
    ls_payload-stack_trace    = |Captured Exception: { lv_type_str }|.

    add_breadcrumb(
      iv_category = 'system'
      iv_action   = 'exception_caught'
      iv_target   = lv_type_str
      iv_data     = ls_payload-error_message ).

    me->send_crash( ls_payload ).
  ENDMETHOD.

  METHOD capture_message.
    IF iv_message IS INITIAL.
      RETURN.
    ENDIF.

    DATA ls_payload TYPE zcl_tracex_serializer=>ty_crash_payload.
    ls_payload-project_key    = me->mv_project_key.
    ls_payload-exception_type = |Log.{ iv_level }|.
    ls_payload-error_message  = iv_message.
    ls_payload-stack_trace    = |Log Message: { iv_message }|.

    add_breadcrumb(
      iv_category = 'log'
      iv_action   = iv_level
      iv_target   = 'capture_message'
      iv_data     = iv_message ).

    me->send_crash( ls_payload ).
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

ENDCLASS.
