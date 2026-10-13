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
  ENDMETHOD.


  METHOD create.
    DATA(lv_key) = condense( CONV string( iv_project_key ) ).

    " N2: Strict project key validation (tracex_live_* or tracex_test_*)
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
    " B1: Restore create_from_config factory method (static call)
    DATA(ls_config) = zcl_tracex_config=>get_config( iv_project_id ).

    ro_client = create(
      iv_project_key = ls_config-api_key
      iv_project_id  = ls_config-project_id
      iv_base_url    = ls_config-base_url
      iv_environment = ls_config-environment
      iv_timeout_sec = ls_config-timeout_sec
    ).
  ENDMETHOD.


  METHOD send_crash.
    DATA(lv_json) = zcl_tracex_serializer=>serialize_crash( is_payload ).

    " M3: Propagate configured timeout
    DATA(lo_http) = NEW zcl_tracex_http(
      iv_base_url    = me->mv_base_url
      iv_project_key = me->mv_project_key
      iv_timeout_sec = me->mv_timeout_sec
    ).

    " N3: Return ingestion response
    rs_response = lo_http->send_payload( lv_json ).
  ENDMETHOD.


  METHOD capture_exception.
    IF ix_exception IS INITIAL.
      RETURN.
    ENDIF.

    DATA ls_payload TYPE zcl_tracex_serializer=>ty_crash_payload.
    ls_payload-project_key = me->mv_project_key.

    " M2: Strip internal technical \CLASS= prefix
    DATA(lv_raw_type) = cl_abap_classdescr=>get_class_name( ix_exception ).
    IF lv_raw_type CP '\CLASS=*'.
      ls_payload-exception_type = substring( val = lv_raw_type off = 7 ).
    ELSE.
      ls_payload-exception_type = lv_raw_type.
    ENDIF.

    ls_payload-error_message = ix_exception->get_text( ).
    ls_payload-stack_trace   = 'Captured Exception Stack'.

    " N3: Return ingestion response
    rs_response = me->send_crash( ls_payload ).
  ENDMETHOD.

ENDCLASS.
