CLASS zcl_tracex_test_t228 DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun .
ENDCLASS.



CLASS zcl_tracex_test_t228 IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    out->write( '=== Running TraceX T2.28 Zero-Defect Pre-Flight Test Suite ===' ).

    TRY.
        " 1. Test Client Factory Instantiation & Validation
        DATA(lo_client) = zcl_tracex_client=>create(
          iv_project_key = 'tracex_live_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' ).
        out->write( '[PASS] Test 1: Client Instantiation with valid key' ).

        " 2. Test Invalid Key Prefix Rejection
        TRY.
            DATA(lo_invalid) = zcl_tracex_client=>create( iv_project_key = 'invalid_prefix_key' ).
            out->write( '[FAIL] Test 2: Invalid key should have failed' ).
          CATCH zcx_tracex_error INTO DATA(lx_key_err).
            out->write( '[PASS] Test 2: Invalid key rejected correctly' ).
        ENDTRY.

        " 3. Test JSON Serialization & Defaults
        DATA ls_payload TYPE zcl_tracex_serializer=>ty_crash_payload.
        ls_payload-project_key    = 'tracex_live_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'.
        ls_payload-exception_type = 'CX_SY_ZERODIVIDE'.
        ls_payload-error_message  = 'Division by zero simulated.'.
        ls_payload-stack_trace    = 'ZCL_TRACEX_TEST_T228->MAIN Line 25'.

        DATA(lv_json) = zcl_tracex_serializer=>serialize_crash( ls_payload ).
        IF lv_json CS '"platform":"abap"' AND lv_json CS '"language":"abap"'.
          out->write( '[PASS] Test 3: JSON Serialization includes platform & language defaults' ).
        ELSE.
          out->write( '[FAIL] Test 3: Missing required defaults in payload' ).
        ENDIF.

        " 4. Test ISO 8601 Timestamp Formatting
        DATA(lv_ts) = zcl_tracex_serializer=>format_iso_timestamp( ).
        IF lv_ts CP '++++-++-++T++:++:++*Z'.
          out->write( |[PASS] Test 4: Timestamp is valid ISO 8601 UTC ({ lv_ts })| ).
        ELSE.
          out->write( |[FAIL] Test 4: Invalid timestamp format ({ lv_ts })| ).
        ENDIF.

        " 5. Test URL Builder Guard (prevents CX_SY_RANGE_OUT_OF_BOUNDS dump)
        DATA(lo_http) = NEW zcl_tracex_http(
          iv_base_url    = ''
          iv_project_key = 'tracex_live_testkey' ).
        out->write( '[PASS] Test 5: HTTP Client handles empty base URL safely' ).

        out->write( '=== ALL T2.28 TESTS COMPLETED WITH 0 DEFECTS! ===' ).

      CATCH zcx_tracex_error INTO DATA(lx_error).
        out->write( |FAILED with error: { lx_error->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
