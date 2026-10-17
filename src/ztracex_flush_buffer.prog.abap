*&---------------------------------------------------------------------*
*& Report ztracex_flush_buffer
*&---------------------------------------------------------------------*
*& TraceX Offline Event Buffer Batch Flush Scheduled Job Report
*&---------------------------------------------------------------------*
REPORT ztracex_flush_buffer.

PARAMETERS: p_proj TYPE c LENGTH 36 OBLIGATORY DEFAULT 'default'.

START-OF-SELECTION.
  WRITE: / '=== TraceX Scheduled Buffer Flush Engine ==='.

  " 1. Read pending records from persistent cluster table ZTRACEX_BUFFER
  DATA lt_buffer TYPE STANDARD TABLE OF ztracex_buffer WITH DEFAULT KEY.
  SELECT * FROM ztracex_buffer
    WHERE client = @sy-mandt
    ORDER BY enqueued_at ASCENDING
    INTO TABLE @lt_buffer.

  IF lines( lt_buffer ) = 0.
    WRITE: / 'No pending offline events found in ZTRACEX_BUFFER. Exiting.'.
    RETURN.
  ENDIF.

  WRITE: / |Found { lines( lt_buffer ) } events pending batch flush.|.

  " 2. Obtain client configuration
  TRY.
      DATA(lo_client) = zcl_tracex_client=>create_from_config( iv_project_id = p_proj ).
    CATCH zcx_tracex_error INTO DATA(lx_cfg).
      WRITE: / |Configuration error for project { p_proj }: { lx_cfg->get_text( ) }|.
      RETURN.
  ENDTRY.

  " 3. Enqueue events into client buffer and execute flush
  DATA(lo_mem_buf) = lo_client->get_buffer( ).
  LOOP AT lt_buffer INTO DATA(ls_item).
    lo_mem_buf->enqueue(
      iv_event_id     = ls_item-event_id
      iv_payload_json = ls_item-payload_json
    ).
  ENDLOOP.

  DATA(lv_flushed) = lo_client->flush( ).

  IF lv_flushed = abap_true.
    " Delete successfully flushed events from persistent table
    DELETE FROM ztracex_buffer WHERE client = @sy-mandt.
    COMMIT WORK.
    WRITE: / 'Successfully flushed all events to TraceX ingest and cleared ZTRACEX_BUFFER.'.
  ELSE.
    WRITE: / 'Batch flush failed. Events preserved in ZTRACEX_BUFFER for subsequent retry.'.
  ENDIF.
