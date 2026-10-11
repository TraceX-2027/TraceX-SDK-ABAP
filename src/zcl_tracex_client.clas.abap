CLASS zcl_tracex_client DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE .

  PUBLIC SECTION.
    CONSTANTS co_default_base_url TYPE string
      VALUE 'https://tracex-edge-ingest.kareemadel10110.workers.dev/api/v1'.
    CONSTANTS co_default_timeout  TYPE i VALUE 3.

    DATA mv_project_id  TYPE string READ-ONLY .
    DATA mv_project_key TYPE string READ-ONLY .
    DATA mv_base_url    TYPE string READ-ONLY .
    DATA mv_environment TYPE string READ-ONLY .
    DATA mv_timeout_sec TYPE i READ-ONLY .

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
        !iv_project_id  TYPE clike
      RETURNING
        VALUE(ro_client) TYPE REF TO zcl_tracex_client
      RAISING
        zcx_tracex_error .

  PROTECTED SECTION.
  PRIVATE SECTION.
    METHODS constructor
      IMPORTING
        !iv_project_key TYPE string
        !iv_project_id  TYPE string OPTIONAL
        !iv_base_url    TYPE string
        !iv_environment TYPE string
        !iv_timeout_sec TYPE i
      RAISING
        zcx_tracex_error .
ENDCLASS.

CLASS zcl_tracex_client IMPLEMENTATION.

  METHOD create.
    DATA(lv_key) = condense( val = CONV string( iv_project_key ) ).
    DATA(lv_proj) = COND string( WHEN iv_project_id IS NOT INITIAL
                                 THEN condense( val = CONV string( iv_project_id ) )
                                 ELSE '' ).
    DATA(lv_url) = COND string( WHEN iv_base_url IS NOT INITIAL
                                THEN condense( val = CONV string( iv_base_url ) )
                                ELSE co_default_base_url ).
    DATA(lv_env) = COND string( WHEN iv_environment IS NOT INITIAL
                                THEN condense( val = CONV string( iv_environment ) )
                                ELSE 'Production' ).
    DATA(lv_timeout) = COND i( WHEN iv_timeout_sec > 0
                               THEN iv_timeout_sec
                               ELSE co_default_timeout ).

    ro_client = NEW zcl_tracex_client(
      iv_project_key = lv_key
      iv_project_id  = lv_proj
      iv_base_url    = lv_url
      iv_environment = lv_env
      iv_timeout_sec = lv_timeout ).
  ENDMETHOD.

  METHOD create_from_config.
    " 1. Retrieve verified, cached configuration
    DATA(ls_config) = zcl_tracex_config=>get_config( iv_project_id ).

    " 2. Instantiate client via factory method
    ro_client = create(
      iv_project_key = ls_config-api_key
      iv_project_id  = ls_config-project_id
      iv_base_url    = ls_config-base_url
      iv_environment = ls_config-environment
      iv_timeout_sec = ls_config-timeout_sec ).
  ENDMETHOD.

  METHOD constructor.
    " Validate Project Key presence
    IF iv_project_key IS INITIAL.
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          textid          = zcx_tracex_error=>unauthorized_401
          mv_error_detail = 'TraceX Project Key is required.'.
    ENDIF.

    " Validate Project Key prefix (support live and test keys)
    IF NOT ( iv_project_key CP 'tracex_live_*' OR iv_project_key CP 'tracex_test_*' ).
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          textid          = zcx_tracex_error=>unauthorized_401
          mv_error_detail = 'TraceX Project Key is malformed. It must start with tracex_live_ or tracex_test_'.
    ENDIF.

    " Validate Base URL
    IF iv_base_url IS INITIAL.
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          textid          = zcx_tracex_error=>payload_invalid_400
          mv_error_detail = 'Base URL cannot be empty.'.
    ENDIF.

    me->mv_project_key = iv_project_key.
    me->mv_project_id  = iv_project_id.
    me->mv_base_url    = iv_base_url.
    me->mv_environment = iv_environment.
    me->mv_timeout_sec = iv_timeout_sec.
  ENDMETHOD.

ENDCLASS.
