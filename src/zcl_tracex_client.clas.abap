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

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA mo_breadcrumbs TYPE REF TO zcl_tracex_breadcrumbs.

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
  ENDMETHOD.


  METHOD create.
    DATA(lv_key) = condense( iv_project_key ).
    IF lv_key IS INITIAL.
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          mv_error_detail = 'Project key cannot be empty.'.
    ENDIF.

    DATA lv_url TYPE string.
    IF iv_base_url IS NOT INITIAL.
      lv_url = iv_base_url.
    ELSE.
      lv_url = co_default_base_url.
    ENDIF.

    DATA lv_timeout TYPE i.
    IF iv_timeout_sec IS NOT INITIAL.
      lv_timeout = iv_timeout_sec.
    ELSE.
      lv_timeout = co_default_timeout.
    ENDIF.

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
    DATA ls_merged_payload TYPE zcl_tracex_serializer=>ty_crash_payload.
    ls_merged_payload = is_payload.

    " 1. Auto-inject Breadcrumbs if payload has none
    IF ls_merged_payload-breadcrumbs IS INITIAL AND me->mo_breadcrumbs IS BOUND.
      DATA(lt_ring_crumbs) = me->mo_breadcrumbs->get_breadcrumbs( ).
      LOOP AT lt_ring_crumbs INTO DATA(ls_rc).
        APPEND VALUE zcl_tracex_serializer=>ty_breadcrumb(
          sequence_order = ls_rc-sequence_order
          timestamp      = ls_rc-timestamp
          category       = ls_rc-category
          action         = ls_rc-action
          target         = ls_rc-target
        ) TO ls_merged_payload-breadcrumbs.
      ENDLOOP.
    ENDIF.

    " 2. Serialize to JSON
    DATA(lv_json) = zcl_tracex_serializer=>serialize_crash( ls_merged_payload ).

    " 3. Instantiate HTTP Client and dispatch
    DATA(lo_http) = NEW zcl_tracex_http(
      iv_base_url    = me->mv_base_url
      iv_project_key = me->mv_project_key
      iv_timeout_sec = me->mv_timeout_sec
    ).

    lo_http->send_payload( lv_json ).
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

    " Auto-record fatal event breadcrumb
    add_breadcrumb(
      iv_category = 'system'
      iv_action   = 'exception_caught'
      iv_target   = lv_type_str
      iv_data     = ls_payload-error_message ).

    me->send_crash( ls_payload ).
  ENDMETHOD.

ENDCLASS.
