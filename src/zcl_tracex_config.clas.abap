CLASS zcl_tracex_config DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    TYPES ty_config TYPE ztracex_config.

    CLASS-METHODS get_config
      IMPORTING
        !iv_project_id   TYPE clike
      RETURNING
        VALUE(rs_config) TYPE ty_config
      RAISING
        zcx_tracex_error.

    CLASS-METHODS validate_config
      IMPORTING
        !is_config TYPE ty_config
      RAISING
        zcx_tracex_error.

    CLASS-METHODS clear_cache.

  PROTECTED SECTION.
  PRIVATE SECTION.

    TYPES:
      BEGIN OF ty_cache_entry,
        project_id TYPE ztracex_config-project_id,
        config     TYPE ty_config,
      END OF ty_cache_entry,
      ty_t_cache TYPE HASHED TABLE OF ty_cache_entry WITH UNIQUE KEY project_id.

    CLASS-DATA gt_cache TYPE ty_t_cache.

    CONSTANTS co_default_url     TYPE string VALUE 'https://tracex-edge-ingest.kareemadel10110.workers.dev/api/v1'.
    CONSTANTS co_default_timeout TYPE i VALUE 3.

ENDCLASS.



CLASS zcl_tracex_config IMPLEMENTATION.

  METHOD get_config.
    DATA lv_project_id TYPE ztracex_config-project_id.
    lv_project_id = iv_project_id.

    IF lv_project_id IS INITIAL.
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          textid          = zcx_tracex_error=>payload_invalid_400
          iv_error_detail = 'Project ID cannot be empty'.
    ENDIF.

    " 1. Search in application memory cache first (Zero DB overhead)
    READ TABLE gt_cache WITH TABLE KEY project_id = lv_project_id INTO DATA(ls_cached).
    IF sy-subrc = 0.
      rs_config = ls_cached-config.
      RETURN.
    ENDIF.

    " 2. Read from database table if not in cache
    SELECT SINGLE *
      FROM ztracex_config
      WHERE project_id = @lv_project_id
      INTO @rs_config.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          textid          = zcx_tracex_error=>payload_invalid_400
          iv_error_detail = |Configuration for Project ID '{ lv_project_id }' not found in ZTRACEX_CONFIG|.
    ENDIF.

    " 3. Fill defaults if fields are empty
    IF rs_config-base_url IS INITIAL.
      rs_config-base_url = co_default_url.
    ENDIF.

    IF rs_config-timeout_sec <= 0.
      rs_config-timeout_sec = co_default_timeout.
    ENDIF.

    " 4. Validate configuration integrity
    validate_config( rs_config ).

    " 5. Cache the verified configuration in memory
    INSERT VALUE #( project_id = lv_project_id config = rs_config ) INTO TABLE gt_cache.

  ENDMETHOD.


  METHOD validate_config.

    " Verify Active flag
    IF is_config-is_active <> 'X' AND is_config-is_active <> 'x'.
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          textid          = zcx_tracex_error=>unauthorized_401
          iv_error_detail = |Project '{ is_config-project_id }' is disabled (IS_ACTIVE <> 'X')|.
    ENDIF.

    " Verify API Key is provided
    IF is_config-api_key IS INITIAL.
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          textid          = zcx_tracex_error=>unauthorized_401
          iv_error_detail = 'TraceX API Key is required.'.
    ENDIF.

    " Verify API Key prefix adheres to TraceX live key standard
    IF NOT ( is_config-api_key CP 'tracex_live_*' ).
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          textid          = zcx_tracex_error=>unauthorized_401
          iv_error_detail = 'TraceX API Key is malformed. It must start with tracex_live_'.
    ENDIF.

  ENDMETHOD.


  METHOD clear_cache.
    CLEAR gt_cache.
  ENDMETHOD.

ENDCLASS.
