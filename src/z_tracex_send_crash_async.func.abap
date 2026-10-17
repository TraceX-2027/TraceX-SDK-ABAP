FUNCTION z_tracex_send_crash_async.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_PAYLOAD_JSON) TYPE STRING
*"     VALUE(IV_PROJECT_KEY) TYPE STRING
*"     VALUE(IV_BASE_URL) TYPE STRING OPTIONAL
*"     VALUE(IV_TIMEOUT_SEC) TYPE I DEFAULT 3
*"----------------------------------------------------------------------
  DATA lo_http TYPE REF TO zcl_tracex_http.
  lo_http = NEW zcl_tracex_http(
    iv_base_url    = iv_base_url
    iv_project_key = iv_project_key
    iv_timeout_sec = iv_timeout_sec
  ).

  TRY.
      lo_http->send_payload( iv_payload_json ).
    CATCH zcx_tracex_error.
      " If async transmission fails, persist payload to offline buffer
      DATA ls_buffer TYPE ztracex_buffer.
      ls_buffer-client       = sy-mandt.
      ls_buffer-event_id     = |evt_{ cl_abap_context_info=>get_system_time( ) }|.
      ls_buffer-project_key  = iv_project_key.
      ls_buffer-payload_json = iv_payload_json.
      ls_buffer-enqueued_at  = zcl_tracex_serializer=>format_iso_timestamp( ).
      ls_buffer-retry_count  = 1.
      INSERT ztracex_buffer FROM @ls_buffer.
      COMMIT WORK.
  ENDTRY.
ENDFUNCTION.
