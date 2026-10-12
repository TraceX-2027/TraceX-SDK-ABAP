CLASS zcl_tracex_http DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_ingest_response,
        status      TYPE string,
        event_id    TYPE string,
        received_at TYPE string,
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

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA mv_base_url    TYPE string .
    DATA mv_project_key TYPE string .
    DATA mv_timeout_sec TYPE i .

    METHODS build_full_url
      RETURNING
        VALUE(rv_url) TYPE string .
ENDCLASS.

CLASS zcl_tracex_http IMPLEMENTATION.

  METHOD constructor.
    me->mv_base_url    = condense( val = iv_base_url ).
    me->mv_project_key = condense( val = iv_project_key ).
    me->mv_timeout_sec = COND i( WHEN iv_timeout_sec > 0 THEN iv_timeout_sec ELSE 3 ).
  ENDMETHOD.

  METHOD build_full_url.
    DATA(lv_url) = condense( val = me->mv_base_url ).

    IF lv_url CP '*/api/v1' OR lv_url CP '*/api/v1/'.
      IF substring( val = lv_url off = strlen( lv_url ) - 1 len = 1 ) = '/'.
        rv_url = |{ lv_url }crashes|.
      ELSE.
        rv_url = |{ lv_url }/crashes|.
      ENDIF.
    ELSE.
      IF substring( val = lv_url off = strlen( lv_url ) - 1 len = 1 ) = '/'.
        rv_url = |{ lv_url }api/v1/crashes|.
      ELSE.
        rv_url = |{ lv_url }/api/v1/crashes|.
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

    DATA(lv_target_url) = build_full_url( ).

    TRY.
        " 1. Create Cloud HTTP destination and client
        DATA(lo_destination) = cl_http_destination_provider=>create_by_url( lv_target_url ).
        DATA(lo_http_client) = cl_web_http_client_manager=>create_by_http_destination( lo_destination ).

        " 2. Configure request headers according to TraceX API Specification
        DATA(lo_request) = lo_http_client->get_http_request( ).
        lo_request->set_header_field( i_name = 'Content-Type' i_value = 'application/json' ).
        lo_request->set_header_field( i_name = 'X-TraceX-Key' i_value = me->mv_project_key ).
        lo_request->set_text( iv_json_payload ).

        " 3. Dispatch POST request
        DATA(lo_response) = lo_http_client->execute( if_web_http_client=>post ).
        DATA(ls_status)   = lo_response->get_status( ).

        " 4. Evaluate HTTP status code
        CASE ls_status-code.
          WHEN 202.
            " Ingestion Accepted
            TRY.
                /ui2/cl_json=>deserialize(
                  EXPORTING
                    json = lo_response->get_text( )
                  CHANGING
                    data = rs_response ).
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

        " Close connection cleanly
        lo_http_client->close( ).

      CATCH zcx_tracex_error INTO DATA(lx_tracex).
        RAISE EXCEPTION lx_tracex.

      CATCH cx_root INTO DATA(lx_unexpected).
        RAISE EXCEPTION TYPE zcx_tracex_error
          EXPORTING
            textid          = zcx_tracex_error=>network_failure
            mv_error_detail = |Network communication failed: { lx_unexpected->get_text( ) }|.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
