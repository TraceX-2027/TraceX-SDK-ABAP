CLASS zcl_tracex_http DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_ingest_response,
        status           TYPE string,
        event_id         TYPE string,
        events_processed TYPE i,
        received_at      TYPE string,
      END OF ty_ingest_response .

    METHODS constructor
      IMPORTING
        !iv_base_url    TYPE string
        !iv_project_key TYPE string
        !iv_timeout_sec TYPE i DEFAULT 3 .

    METHODS send_payload
      IMPORTING
        !iv_json_payload   TYPE string
      RETURNING
        VALUE(rs_response) TYPE ty_ingest_response
      RAISING
        zcx_tracex_error .

    METHODS send_batch
      IMPORTING
        !iv_batch_json     TYPE string
      RETURNING
        VALUE(rs_response) TYPE ty_ingest_response
      RAISING
        zcx_tracex_error .

    METHODS build_full_url
      IMPORTING
        !iv_path      TYPE string DEFAULT 'crashes'
      RETURNING
        VALUE(rv_url) TYPE string .

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA mv_base_url    TYPE string .
    DATA mv_project_key TYPE string .
    DATA mv_timeout_sec TYPE i .
ENDCLASS.



CLASS zcl_tracex_http IMPLEMENTATION.

  METHOD constructor.
    me->mv_base_url    = condense( val = iv_base_url ).
    me->mv_project_key = condense( val = iv_project_key ).
    me->mv_timeout_sec = COND i( WHEN iv_timeout_sec > 0 THEN iv_timeout_sec ELSE 3 ).
  ENDMETHOD.


  METHOD build_full_url.
    DATA(lv_url) = condense( val = me->mv_base_url ).
    DATA(lv_target_path) = COND string( WHEN iv_path IS NOT INITIAL THEN iv_path ELSE 'crashes' ).

    IF lv_url IS INITIAL.
      lv_url = zcl_tracex_client=>co_default_base_url.
    ENDIF.

    IF lv_target_path = 'crashes' AND ( lv_url CP '*/crashes' OR lv_url CP '*/crashes/' ).
      rv_url = lv_url.
      RETURN.
    ENDIF.

    IF lv_url CP '*/api/v1' OR lv_url CP '*/api/v1/'.
      IF substring( val = lv_url off = strlen( lv_url ) - 1 len = 1 ) = '/'.
        rv_url = |{ lv_url }{ lv_target_path }|.
      ELSE.
        rv_url = |{ lv_url }/{ lv_target_path }|.
      ENDIF.
    ELSE.
      IF substring( val = lv_url off = strlen( lv_url ) - 1 len = 1 ) = '/'.
        rv_url = |{ lv_url }api/v1/{ lv_target_path }|.
      ELSE.
        rv_url = |{ lv_url }/api/v1/{ lv_target_path }|.
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD send_payload.
    IF iv_json_payload IS INITIAL.
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          textid          = zcx_tracex_error=>payload_invalid_400
          mv_error_detail = 'Telemetry payload cannot be empty.'.
    ENDIF.

    DATA(lv_target_url) = build_full_url( 'crashes' ).

    DATA lo_http_client TYPE REF TO if_web_http_client.

    TRY.
        DATA(lo_destination) = cl_http_destination_provider=>create_by_url( lv_target_url ).
        lo_http_client = cl_web_http_client_manager=>create_by_http_destination( lo_destination ).

        DATA(lo_request) = lo_http_client->get_http_request( ).
        lo_request->set_header_field( i_name = 'Content-Type' i_value = 'application/json' ).
        lo_request->set_header_field( i_name = 'X-TraceX-Key' i_value = me->mv_project_key ).
        lo_request->set_header_field( i_name = 'X-TraceX-Timeout' i_value = |{ me->mv_timeout_sec }| ).
        lo_request->set_header_field( i_name = 'Request-Timeout' i_value = |{ me->mv_timeout_sec }| ).
        lo_request->set_text( iv_json_payload ).

        DATA(lo_response) = lo_http_client->execute( if_web_http_client=>post ).
        DATA(ls_status)   = lo_response->get_status( ).

        CASE ls_status-code.
          WHEN 202 OR 200 OR 201.
            TRY.
                /ui2/cl_json=>deserialize(
                  EXPORTING
                    json        = lo_response->get_text( )
                    pretty_name = /ui2/cl_json=>pretty_mode-low_case
                  CHANGING
                    data        = rs_response ).
              CATCH cx_root.
                rs_response-status = 'accepted'.
            ENDTRY.

          WHEN 401.
            RAISE EXCEPTION TYPE zcx_tracex_error
              EXPORTING
                textid          = zcx_tracex_error=>unauthorized_401
                mv_http_status  = 401
                mv_error_detail = |Unauthorized (401): Invalid or inactive TraceX API Key.|.

          WHEN 429.
            DATA(lv_retry) = lo_response->get_header_field( 'Retry-After' ).
            DATA(lv_retry_sec) = COND i( WHEN lv_retry IS NOT INITIAL AND lv_retry CO '0123456789'
                                         THEN CONV i( lv_retry )
                                         ELSE 60 ).
            RAISE EXCEPTION TYPE zcx_tracex_error
              EXPORTING
                textid          = zcx_tracex_error=>rate_limited_429
                mv_http_status  = 429
                mv_retry_after  = lv_retry_sec
                mv_error_detail = |Rate limit exceeded (429). Retry after { lv_retry_sec } seconds.|.

          WHEN 400.
            RAISE EXCEPTION TYPE zcx_tracex_error
              EXPORTING
                textid          = zcx_tracex_error=>payload_invalid_400
                mv_http_status  = 400
                mv_error_detail = |Payload Invalid (400): { lo_response->get_text( ) }|.

          WHEN OTHERS.
            RAISE EXCEPTION TYPE zcx_tracex_error
              EXPORTING
                textid          = zcx_tracex_error=>network_failure
                mv_http_status  = ls_status-code
                mv_error_detail = |TraceX Ingest failed with HTTP { ls_status-code }: { ls_status-reason }|.
        ENDCASE.

        lo_http_client->close( ).

      CLEANUP.
        IF lo_http_client IS BOUND.
          TRY.
              lo_http_client->close( ).
            CATCH cx_root.
          ENDTRY.
        ENDIF.
    ENDTRY.
  ENDMETHOD.


  METHOD send_batch.
    IF iv_batch_json IS INITIAL.
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          textid          = zcx_tracex_error=>payload_invalid_400
          mv_error_detail = 'Batch payload cannot be empty.'.
    ENDIF.

    DATA(lv_target_url) = build_full_url( 'crashes/batch' ).

    DATA lo_http_client TYPE REF TO if_web_http_client.

    TRY.
        DATA(lo_destination) = cl_http_destination_provider=>create_by_url( lv_target_url ).
        lo_http_client = cl_web_http_client_manager=>create_by_http_destination( lo_destination ).

        DATA(lo_request) = lo_http_client->get_http_request( ).
        lo_request->set_header_field( i_name = 'Content-Type' i_value = 'application/json' ).
        lo_request->set_header_field( i_name = 'X-TraceX-Key' i_value = me->mv_project_key ).
        lo_request->set_header_field( i_name = 'X-TraceX-Timeout' i_value = |{ me->mv_timeout_sec }| ).
        lo_request->set_header_field( i_name = 'Request-Timeout' i_value = |{ me->mv_timeout_sec }| ).
        lo_request->set_text( iv_batch_json ).

        DATA(lo_response) = lo_http_client->execute( if_web_http_client=>post ).
        DATA(ls_status)   = lo_response->get_status( ).

        CASE ls_status-code.
          WHEN 202 OR 200 OR 201.
            TRY.
                /ui2/cl_json=>deserialize(
                  EXPORTING
                    json        = lo_response->get_text( )
                    pretty_name = /ui2/cl_json=>pretty_mode-low_case
                  CHANGING
                    data        = rs_response ).
              CATCH cx_root.
                rs_response-status = 'accepted'.
            ENDTRY.

          WHEN 401.
            RAISE EXCEPTION TYPE zcx_tracex_error
              EXPORTING
                textid          = zcx_tracex_error=>unauthorized_401
                mv_http_status  = 401
                mv_error_detail = |Unauthorized (401): Invalid or inactive TraceX API Key on batch.|.

          WHEN 429.
            DATA(lv_retry) = lo_response->get_header_field( 'Retry-After' ).
            DATA(lv_retry_sec) = COND i( WHEN lv_retry IS NOT INITIAL AND lv_retry CO '0123456789'
                                         THEN CONV i( lv_retry )
                                         ELSE 60 ).
            RAISE EXCEPTION TYPE zcx_tracex_error
              EXPORTING
                textid          = zcx_tracex_error=>rate_limited_429
                mv_http_status  = 429
                mv_retry_after  = lv_retry_sec
                mv_error_detail = |Rate limit exceeded on batch ingestion (429). Retry after { lv_retry_sec } seconds.|.

          WHEN 400.
            RAISE EXCEPTION TYPE zcx_tracex_error
              EXPORTING
                textid          = zcx_tracex_error=>payload_invalid_400
                mv_http_status  = 400
                mv_error_detail = |Batch Payload Invalid (400): { lo_response->get_text( ) }|.

          WHEN OTHERS.
            RAISE EXCEPTION TYPE zcx_tracex_error
              EXPORTING
                textid          = zcx_tracex_error=>network_failure
                mv_http_status  = ls_status-code
                mv_error_detail = |TraceX Batch Ingest failed with HTTP { ls_status-code }: { ls_status-reason }|.
        ENDCASE.

        lo_http_client->close( ).

      CLEANUP.
        IF lo_http_client IS BOUND.
          TRY.
              lo_http_client->close( ).
            CATCH cx_root.
          ENDTRY.
        ENDIF.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
