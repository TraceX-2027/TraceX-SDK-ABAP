CLASS ltc_tracex_t228 DEFINITION FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS test_serialize_defaults FOR TESTING.
    METHODS test_client_validation   FOR TESTING.
    METHODS test_timestamp_iso       FOR TESTING.
    METHODS test_url_builder_guard   FOR TESTING.
ENDCLASS.



CLASS ltc_tracex_t228 IMPLEMENTATION.

  METHOD test_serialize_defaults.
    DATA ls_payload TYPE zcl_tracex_serializer=>ty_crash_payload.
    ls_payload-project_key    = 'tracex_live_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'.
    ls_payload-exception_type = 'CX_SY_ZERODIVIDE'.
    ls_payload-error_message  = 'Division by zero simulated'.
    ls_payload-stack_trace    = 'Test Stack Line 1'.

    DATA(lv_json) = zcl_tracex_serializer=>serialize_crash( ls_payload ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lv_json
      msg = 'Serialized JSON must not be initial' ).

    cl_abap_unit_assert=>assert_true(
      act = boolc( lv_json CS '"platform":"abap"' )
      msg = 'Payload must include platform abap' ).

    cl_abap_unit_assert=>assert_true(
      act = boolc( lv_json CS '"language":"abap"' )
      msg = 'Payload must include language abap' ).

    cl_abap_unit_assert=>assert_true(
      act = boolc( lv_json CS '"exception_type":"CX_SY_ZERODIVIDE"' )
      msg = 'Payload must preserve clean exception type' ).
  ENDMETHOD.


  METHOD test_client_validation.
    " 1. Test invalid key prefix rejected
    TRY.
        DATA(lo_invalid) = zcl_tracex_client=>create( iv_project_key = 'invalid_prefix_key' ).
        cl_abap_unit_assert=>fail( msg = 'Invalid key must throw zcx_tracex_error' ).
      CATCH zcx_tracex_error INTO DATA(lx_err).
        cl_abap_unit_assert=>assert_equals(
          act = lx_err->if_t100_message~t100key
          exp = zcx_tracex_error=>unauthorized_401 ).
    ENDTRY.

    " 2. Test valid test key accepted
    TRY.
        DATA(lo_valid) = zcl_tracex_client=>create( iv_project_key = 'tracex_test_samplekey12345' ).
        cl_abap_unit_assert=>assert_bound(
          act = lo_valid
          msg = 'Client must be bound for tracex_test_ key' ).
      CATCH zcx_tracex_error.
        cl_abap_unit_assert=>fail( msg = 'tracex_test_ prefix must be accepted' ).
    ENDTRY.
  ENDMETHOD.


  METHOD test_timestamp_iso.
    DATA(lv_ts) = zcl_tracex_serializer=>format_iso_timestamp( ).
    cl_abap_unit_assert=>assert_not_initial( act = lv_ts ).
    cl_abap_unit_assert=>assert_true(
      act = boolc( lv_ts CP '++++-++-++T++:++:++*Z' )
      msg = 'Timestamp must conform to strict ISO 8601 UTC with Z suffix' ).
  ENDMETHOD.


  METHOD test_url_builder_guard.
    " Test that HTTP client handles empty base url without short dump
    DATA(lo_http) = NEW zcl_tracex_http(
      iv_base_url    = ''
      iv_project_key = 'tracex_live_testkey'
    ).
    cl_abap_unit_assert=>assert_bound( act = lo_http ).
  ENDMETHOD.

ENDCLASS.
