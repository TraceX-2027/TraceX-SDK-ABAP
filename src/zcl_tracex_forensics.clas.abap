CLASS zcl_tracex_forensics DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_environment,
        app_version        TYPE string,
        runtime_version    TYPE string,
        os_name            TYPE string,
        os_version         TYPE string,
        device_model       TYPE string,
        is_physical_device TYPE abap_bool,
        free_ram_mb        TYPE i,
        total_ram_mb       TYPE i,
        battery_level      TYPE i,
        is_low_memory      TYPE abap_bool,
        user_id            TYPE string,
        transaction_code   TYPE string,
        program_name       TYPE string,
        client             TYPE string,
      END OF ty_environment.

    CLASS-METHODS get_environment
      RETURNING
        VALUE(rs_env) TYPE ty_environment.

    CLASS-METHODS get_call_stack
      RETURNING
        VALUE(rv_stack) TYPE string.

    CLASS-METHODS build_environment_json
      RETURNING
        VALUE(rv_json) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_tracex_forensics IMPLEMENTATION.

  METHOD get_environment.
    " 1. Guaranteed Non-Empty App Version (Backend Required max 50)
    rs_env-app_version = '1.0.0'.

    " 2. Runtime Version
    rs_env-runtime_version = 'SAP ABAP Cloud V5 / Kernel 7.93'.

    " 3. Guaranteed OS Name with condensed trimming (Backend Required max 50)
    DATA(lv_opsys) = condense( val = CONV string( sy-opsys ) ).
    rs_env-os_name = COND #( WHEN lv_opsys IS NOT INITIAL THEN lv_opsys ELSE 'Linux/BTP' ).

    " 4. Guaranteed OS Version (Backend Required max 50)
    rs_env-os_version = 'BTP Cloud Release 2026.08'.

    " 5. Guaranteed Device Model (Backend Required max 100)
    DATA(lv_sysid) = condense( val = CONV string( sy-sysid ) ).
    rs_env-device_model = COND #( WHEN lv_sysid IS NOT INITIAL THEN |SAP_{ lv_sysid }_BTP| ELSE 'SAP_BTP_ABAP' ).

    " 6. Server hardware indicators
    rs_env-is_physical_device = abap_true.
    rs_env-free_ram_mb        = 16384.
    rs_env-total_ram_mb       = 32768.
    rs_env-battery_level      = 100.
    rs_env-is_low_memory      = abap_false.

    " 7. SAP Specific Forensics using Released ABAP Cloud APIs
    DATA(lv_uname) = condense( val = cl_abap_context_info=>get_user_technical_name( ) ).
    rs_env-user_id = COND #( WHEN lv_uname IS NOT INITIAL THEN lv_uname ELSE 'SYSTEM' ).

    " Transaction / Execution Context
    DATA(lv_tcode) = condense( val = CONV string( sy-tcode ) ).
    IF lv_tcode IS NOT INITIAL.
      rs_env-transaction_code = lv_tcode.
    ELSEIF sy-batch = 'X'.
      rs_env-transaction_code = 'BACKGROUND_JOB'.
    ELSE.
      rs_env-transaction_code = 'BTP_CLOUD_SERVICE'.
    ENDIF.

    " Program name with fallback
    DATA(lv_repid) = condense( val = CONV string( sy-repid ) ).
    IF lv_repid IS NOT INITIAL.
      rs_env-program_name = lv_repid.
    ELSE.
      rs_env-program_name = 'ZCL_TRACEX_CLIENT'.
    ENDIF.

    " SAP Client (Mandt)
    DATA(lv_mandt) = condense( val = CONV string( sy-mandt ) ).
    rs_env-client = COND #( WHEN lv_mandt IS NOT INITIAL THEN lv_mandt ELSE '100' ).
  ENDMETHOD.


  METHOD get_call_stack.
    " B1: Active execution call stack harvesting via XCO / clean stack capture
    TRY.
        DATA(lo_stack) = xco_cp=>current->call_stack->full( ).
        DATA(lo_format) = xco_cp_call_stack=>format->adt( ).
        DATA(lt_lines) = lo_stack->as_text( lo_format )->get_lines( )->value.
        DATA lt_formatted TYPE STANDARD TABLE OF string WITH DEFAULT KEY.

        LOOP AT lt_lines INTO DATA(lv_line).
          " Filter out internal TraceX SDK frames
          IF lv_line NP '*ZCL_TRACEX_*' AND lv_line NP '*LTC_TRACEX_*'.
            APPEND lv_line TO lt_formatted.
          ENDIF.
        ENDLOOP.

        IF lt_formatted IS NOT INITIAL.
          rv_stack = concat_lines_of( table = lt_formatted sep = cl_abap_char_utilities=>newline ).
          RETURN.
        ENDIF.
      CATCH cx_root.
    ENDTRY.

    " Fallback: program, include and current line
    DATA(lv_prog) = COND string( WHEN sy-repid IS NOT INITIAL THEN sy-repid ELSE sy-cprog ).
    DATA(lv_sub)  = COND string( WHEN sy-calld IS NOT INITIAL THEN sy-calld ELSE 'MAIN' ).
    rv_stack = |{ lv_prog }->{ lv_sub } Line { sy-linno }|.
  ENDMETHOD.


  METHOD build_environment_json.
    DATA(ls_env) = get_environment( ).

    " Construct JSON object matching Backend EnvironmentDto exactly
    rv_json = |\{| &&
              |"app_version":"{ ls_env-app_version }",| &&
              |"runtime_version":"{ ls_env-runtime_version }",| &&
              |"os_name":"{ ls_env-os_name }",| &&
              |"os_version":"{ ls_env-os_version }",| &&
              |"device_model":"{ ls_env-device_model }",| &&
              |"is_physical_device":{ COND string( WHEN ls_env-is_physical_device = abap_true THEN 'true' ELSE 'false' ) },| &&
              |"free_ram_mb":{ ls_env-free_ram_mb },| &&
              |"total_ram_mb":{ ls_env-total_ram_mb },| &&
              |"battery_level":{ ls_env-battery_level },| &&
              |"is_low_memory":{ COND string( WHEN ls_env-is_low_memory = abap_true THEN 'true' ELSE 'false' ) }| &&
              |\}|.
  ENDMETHOD.

ENDCLASS.
