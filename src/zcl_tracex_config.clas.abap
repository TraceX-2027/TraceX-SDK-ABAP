CLASS zcl_tracex_config DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE .

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_config,
        project_id  TYPE string,
        api_key     TYPE string,
        base_url    TYPE string,
        environment TYPE string,
        timeout_sec TYPE i,
        is_active   TYPE abap_bool,
      END OF ty_config .

    TYPES ty_config_tt TYPE HASHED TABLE OF ty_config WITH UNIQUE KEY project_id .

    CLASS-METHODS get_config
      IMPORTING
        !iv_project_id   TYPE clike
      RETURNING
        VALUE(rs_config) TYPE ty_config
      RAISING
        zcx_tracex_error .

    CLASS-METHODS clear_cache .

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-DATA gt_cache TYPE ty_config_tt .

    CLASS-METHODS read_from_db
      IMPORTING
        !iv_project_id   TYPE string
      RETURNING
        VALUE(rs_config) TYPE ty_config
      RAISING
        zcx_tracex_error .

    CLASS-METHODS validate_config
      IMPORTING
        !is_config TYPE ty_config
      RAISING
        zcx_tracex_error .
ENDCLASS.

CLASS zcl_tracex_config IMPLEMENTATION.

  METHOD get_config.
    DATA(lv_project_id) = condense( val = CONV string( iv_project_id ) ).

    IF lv_project_id IS INITIAL.
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          textid          = zcx_tracex_error=>payload_invalid_400
          mv_error_detail = 'Project ID cannot be empty.'.
    ENDIF.

    " 1. Check in-memory session cache
    READ TABLE gt_cache WITH TABLE KEY project_id = lv_project_id INTO rs_config.
    IF sy-subrc = 0.
      RETURN.
    ENDIF.

    " 2. Read from Database
    rs_config = read_from_db( lv_project_id ).

    " 3. Validate configuration rules
    validate_config( rs_config ).

    " 4. Store in session cache
    INSERT rs_config INTO TABLE gt_cache.
  ENDMETHOD.

  METHOD clear_cache.
    CLEAR gt_cache.
  ENDMETHOD.

  METHOD read_from_db.
    SELECT SINGLE project_id, api_key, base_url, environment, timeout_sec, is_active
      FROM ztracex_config
      WHERE project_id = @iv_project_id
      INTO @DATA(ls_db).

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          textid          = zcx_tracex_error=>payload_invalid_400
          mv_error_detail = |No configuration found for Project ID: { iv_project_id }|.
    ENDIF.

    rs_config-project_id  = condense( val = CONV string( ls_db-project_id ) ).
    rs_config-api_key     = condense( val = CONV string( ls_db-api_key ) ).
    rs_config-base_url    = condense( val = CONV string( ls_db-base_url ) ).
    rs_config-environment = condense( val = CONV string( ls_db-environment ) ).
    rs_config-timeout_sec = ls_db-timeout_sec.
    rs_config-is_active   = ls_db-is_active.
  ENDMETHOD.

  METHOD validate_config.
    " Active flag check
    IF is_config-is_active <> abap_true.
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          textid          = zcx_tracex_error=>payload_invalid_400
          mv_error_detail = |TraceX configuration is inactive for project: { is_config-project_id }|.
    ENDIF.

    " API Key presence
    IF is_config-api_key IS INITIAL.
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          textid          = zcx_tracex_error=>unauthorized_401
          mv_error_detail = 'TraceX API Key is missing in configuration.'.
    ENDIF.

    " API Key prefix validation (supports live and test keys)
    IF NOT ( is_config-api_key CP 'tracex_live_*' OR is_config-api_key CP 'tracex_test_*' ).
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          textid          = zcx_tracex_error=>unauthorized_401
          mv_error_detail = 'TraceX API Key is malformed. It must start with tracex_live_ or tracex_test_'.
    ENDIF.

    " Base URL check
    IF is_config-base_url IS INITIAL.
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          textid          = zcx_tracex_error=>payload_invalid_400
          mv_error_detail = 'Base URL cannot be empty in configuration.'.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
