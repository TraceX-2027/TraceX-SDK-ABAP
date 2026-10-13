CLASS ltc_tracex_t230 DEFINITION FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS test_buffer_fifo_eviction  FOR TESTING.
    METHODS test_buffer_clear          FOR TESTING.
    METHODS test_client_buffer_enqueue FOR TESTING.
    METHODS test_batch_url_builder     FOR TESTING.
ENDCLASS.



CLASS ltc_tracex_t230 IMPLEMENTATION.

  METHOD test_buffer_fifo_eviction.
    DATA(lo_buffer) = NEW zcl_tracex_buffer( ).
    lo_buffer->clear( ).

    DO 105 TIMES.
      DATA(lv_idx) = sy-index.
      lo_buffer->enqueue(
        iv_event_id     = |evt_{ lv_idx }|
        iv_payload_json = |\{"index":{ lv_idx }\}| ).
    ENDDO.

    cl_abap_unit_assert=>assert_equals(
      act = lo_buffer->get_count( )
      exp = 100
      msg = 'Buffer must cap items at 100' ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_buffer->get_dropped_count( )
      exp = 5
      msg = 'Dropped count must equal 5 after 105 enqueues' ).

    DATA(lt_items) = lo_buffer->peek_all( ).
    READ TABLE lt_items INDEX 1 INTO DATA(ls_first).
    cl_abap_unit_assert=>assert_equals(
      act = ls_first-event_id
      exp = 'evt_6'
      msg = 'Oldest event in buffer must be evt_6' ).
  ENDMETHOD.


  METHOD test_buffer_clear.
    DATA(lo_buffer) = NEW zcl_tracex_buffer( ).
    lo_buffer->enqueue(
      iv_event_id     = 'evt_test'
      iv_payload_json = '{"test":true}' ).

    lo_buffer->clear( ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_buffer->get_count( )
      exp = 0
      msg = 'Buffer must be empty after clear' ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_buffer->get_dropped_count( )
      exp = 0
      msg = 'Dropped count must reset to 0 after clear' ).
  ENDMETHOD.


  METHOD test_client_buffer_enqueue.
    DATA(lo_client) = zcl_tracex_client=>create(
      iv_project_key = 'tracex_live_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' ).

    DATA(lo_buf) = lo_client->get_buffer( ).
    lo_buf->clear( ).

    lo_client->capture_message(
      iv_message = 'Test message for buffering'
      iv_level   = 'warning' ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_buf->get_count( )
      exp = 1
      msg = 'Buffer must contain 1 enqueued event' ).
  ENDMETHOD.


  METHOD test_batch_url_builder.
    DATA(lo_http) = NEW zcl_tracex_http(
      iv_base_url    = 'https://tracex-edge-ingest.kareemadel10110.workers.dev/api/v1'
      iv_project_key = 'tracex_live_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' ).

    DATA(lv_url) = lo_http->build_full_url( 'crashes/batch' ).

    cl_abap_unit_assert=>assert_equals(
      act = lv_url
      exp = 'https://tracex-edge-ingest.kareemadel10110.workers.dev/api/v1/crashes/batch'
      msg = 'Batch URL must point to /api/v1/crashes/batch' ).
  ENDMETHOD.

ENDCLASS.
