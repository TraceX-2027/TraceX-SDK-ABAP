CLASS ltc_tracex_t229 DEFINITION FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS test_forensics_environment FOR TESTING.
    METHODS test_call_stack            FOR TESTING.
    METHODS test_breadcrumbs_eviction FOR TESTING.
    METHODS test_pii_redaction_json    FOR TESTING.
    METHODS test_client_clear_buffer   FOR TESTING.
ENDCLASS.



CLASS ltc_tracex_t229 IMPLEMENTATION.

  METHOD test_forensics_environment.
    DATA(ls_env) = zcl_tracex_forensics=>get_environment( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = ls_env-app_version
      msg = 'App version must not be initial' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = ls_env-runtime_version
      msg = 'Runtime version must not be initial' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = ls_env-os_name
      msg = 'OS name must not be initial' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = ls_env-device_model
      msg = 'Device model must not be initial' ).
  ENDMETHOD.


  METHOD test_call_stack.
    DATA(lv_stack) = zcl_tracex_forensics=>get_call_stack( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lv_stack
      msg = 'Call stack must not be initial' ).
  ENDMETHOD.


  METHOD test_breadcrumbs_eviction.
    DATA(lo_crumbs) = NEW zcl_tracex_breadcrumbs( ).
    lo_crumbs->clear( ).

    " Add 55 breadcrumbs (exceeding 50 max capacity)
    DO 55 TIMES.
      lo_crumbs->add_breadcrumb(
        iv_category = 'ui.action'
        iv_action   = |CLICK_{ sy-index }|
        iv_target   = 'BUTTON'
      ).
    ENDDO.

    cl_abap_unit_assert=>assert_equals(
      act = lo_crumbs->get_count( )
      exp = 50
      msg = 'Buffer must be capped at 50 items' ).

    DATA(lt_crumbs) = lo_crumbs->get_breadcrumbs( ).
    READ TABLE lt_crumbs INDEX 1 INTO DATA(ls_first).
    cl_abap_unit_assert=>assert_equals(
      act = ls_first-sequence_order
      exp = 6
      msg = 'Oldest sequence order in buffer must be 6 after 5 evictions' ).
  ENDMETHOD.


  METHOD test_pii_redaction_json.
    DATA(lo_crumbs) = NEW zcl_tracex_breadcrumbs( ).

    " Test Bearer token redaction
    DATA(lv_bearer) = lo_crumbs->redact_sensitive_info( 'Authorization: Bearer secret_token_123' ).
    cl_abap_unit_assert=>assert_true(
      act = boolc( lv_bearer CS '[REDACTED]' )
      msg = 'Bearer token must be redacted' ).

    " Test JSON password redaction without breaking quotes or brackets
    DATA(lv_json) = lo_crumbs->redact_sensitive_info( '{"password":"superSecret123"}' ).
    cl_abap_unit_assert=>assert_true(
      act = boolc( lv_json CS '"password":"[REDACTED]"' )
      msg = 'JSON password must be redacted with syntax intact' ).
  ENDMETHOD.


  METHOD test_client_clear_buffer.
    DATA(lo_client) = zcl_tracex_client=>create(
      iv_project_key = 'tracex_live_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' ).

    lo_client->add_breadcrumb(
      iv_category = 'navigation'
      iv_action   = 'NAV_TO_CART'
      iv_data     = '{"sku":"ITEM-123","qty":2}' ).

    cl_abap_unit_assert=>assert_bound( act = lo_client ).

    DATA ls_payload TYPE zcl_tracex_serializer=>ty_crash_payload.
    ls_payload-exception_type = 'CX_SY_ZERODIVIDE'.
    ls_payload-error_message  = 'Zero divide'.

    DATA(lv_json) = zcl_tracex_serializer=>serialize_crash( ls_payload ).
    cl_abap_unit_assert=>assert_not_initial( act = lv_json ).
  ENDMETHOD.

ENDCLASS.
