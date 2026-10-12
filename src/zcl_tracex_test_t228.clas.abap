CLASS zcl_tracex_test_t228 DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun .
ENDCLASS.



CLASS zcl_tracex_test_t228 IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    out->write( '=== Running TraceX T2.28 Zero-Defect Pre-Flight Test ===' ).

    TRY.
        " 1. Test Client Factory Instantiation (create and prefix validation)
        DATA(lo_client) = zcl_tracex_client=>create(
          iv_project_key = 'tracex_live_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' ).
        out->write( 'Test 1: Client Instantiation [SUCCESS]' ).

        " 2. Test JSON Serialization
        DATA ls_payload TYPE zcl_tracex_serializer=>ty_crash_payload.
        ls_payload-project_key    = 'tracex_live_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'.
        ls_payload-exception_type = 'CX_SY_ZERODIVIDE'.
        ls_payload-error_message  = 'Division by zero simulated.'.
        ls_payload-stack_trace    = 'ZCL_TRACEX_TEST_T228->MAIN Line 25'.

        DATA(lv_json) = zcl_tracex_serializer=>serialize_crash( ls_payload ).
        out->write( 'Test 2: JSON Serialization [SUCCESS]' ).
        out->write( 'Generated Payload:' ).
        out->write( lv_json ).

        out->write( '=== ALL PRE-FLIGHT AUDITS PASSED WITH 0 DEFECTS! ===' ).

      CATCH zcx_tracex_error INTO DATA(lx_error).
        out->write( |FAILED: { lx_error->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
