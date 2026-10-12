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

    DATA mv_project_id    TYPE string READ-ONLY .
    DATA mv_project_key   TYPE string READ-ONLY .
    DATA mv_base_url      TYPE string READ-ONLY .
    DATA mv_environment   TYPE string READ-ONLY .
    DATA mv_timeout_sec   TYPE i READ-ONLY .

    CLASS-METHODS create
      IMPORTING
        iv_project_key TYPE string
        iv_base_url    TYPE string OPTIONAL
        iv_timeout_sec TYPE i OPTIONAL
      RETURNING
        VALUE(ro_client) TYPE REF TO zcl_tracex_client
      RAISING
        zcx_tracex_error .

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
  ENDMETHOD.


  METHOD create.
    DATA(lv_key) = condense( iv_project_key ).
    IF lv_key IS INITIAL.
      RAISE EXCEPTION TYPE zcx_tracex_error.
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


  METHOD send_crash.
    DATA(lv_json) = zcl_tracex_serializer=>serialize_crash( is_payload ).

    DATA(lo_http) = NEW zcl_tracex_http(
      iv_base_url    = me->mv_base_url
      iv_project_key = me->mv_project_key
    ).

    lo_http->send_payload( lv_json ).
  ENDMETHOD.


  METHOD capture_exception.
    IF ix_exception IS INITIAL.
      RETURN.
    ENDIF.

    DATA ls_payload TYPE zcl_tracex_serializer=>ty_crash_payload.
    ls_payload-project_key    = me->mv_project_key.
    ls_payload-exception_type = cl_abap_classdescr=>get_class_name( ix_exception ).
    ls_payload-error_message  = ix_exception->get_text( ).
    ls_payload-stack_trace    = 'Captured Exception Stack'.

    me->send_crash( ls_payload ).
  ENDMETHOD.

ENDCLASS.
