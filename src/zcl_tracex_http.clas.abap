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

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA mv_base_url    TYPE string .
    DATA mv_project_key TYPE string .
    DATA mv_timeout_sec TYPE i .

    METHODS build_full_url
      IMPORTING
        !iv_path      TYPE string DEFAULT 'crashes'
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
        rv_url = |{ lv_url }{ iv_path }|.
      ELSE.
        rv_url = |{ lv_url }/{ iv_path }|.
      ENDIF.
    ELSE.
      IF substring( val = lv_url off = strlen( lv_url ) - 1 len = 1 ) = '/'.
        rv_url = |{ lv_url }api/v1/{ iv_path }|.
      ELSE.
        rv_url = |{ lv_url }/api/v1/{ iv_path }|.
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD send_payload.
    IF iv_json_payload IS INITIAL.
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          mv_error_detail = 'Telemetry payload cannot be empty.'.
    ENDIF.

    DATA(lv_target_url) = build_full_url( 'crashes' ).

    TRY.
        DATA(lo_destination) = cl_http_destination_provider=>create_by_url( lv_target_url ).
        DATA(lo_http_client) = cl_web_http_client_manager=>create_by_http_destination( lo_destination ).

        DATA(lo_request) = lo_http_client->get_http_request( ).
        lo_request->set_header_field( i_name = 'Content-Type' i_value = 'application/json' ).
        lo_request->set_header_field( i_name = 'X-TraceX-Key' i_value = me->mv_project_key ).
        lo_request->set_text( iv_json_payload ).

        DATA(lo_response) = lo_http_client->execute( if_web_http_client=>post ).
        DATA(ls_status)   = lo_response->get_status( ).

        CASE ls_status-code.
          WHEN 200 OR 201 OR 202.
            rs_response-status = 'accepted'.
          WHEN 401.
            RAISE EXCEPTION TYPE zcx_tracex_error
              EXPORTING
                mv_error_detail = |Unauthorized (401): Invalid or inactive TraceX API Key.|.
          WHEN 429.
            RAISE EXCEPTION TYPE zcx_tracex_error
              EXPORTING
                mv_error_detail = |Rate limit exceeded (429).|.
          WHEN OTHERS.
            RAISE EXCEPTION TYPE zcx_tracex_error
              EXPORTING
                mv_error_detail = |TraceX Ingest failed with HTTP { ls_status-code }.|.
        ENDCASE.

        lo_http_client->close( ).

      CATCH zcx_tracex_error INTO DATA(lx_tracex).
        RAISE EXCEPTION lx_tracex.
      CATCH cx_root INTO DATA(lx_unexpected).
        RAISE EXCEPTION TYPE zcx_tracex_error
          EXPORTING
            mv_error_detail = |Network communication failed: { lx_unexpected->get_text( ) }|.
    ENDTRY.
  ENDMETHOD.


  METHOD send_batch.
    IF iv_batch_json IS INITIAL.
      RAISE EXCEPTION TYPE zcx_tracex_error
        EXPORTING
          mv_error_detail = 'Batch payload cannot be empty.'.
    ENDIF.

    DATA(lv_target_url) = build_full_url( 'crashes/batch' ).

    TRY.
        DATA(lo_destination) = cl_http_destination_provider=>create_by_url( lv_target_url ).
        DATA(lo_http_client) = cl_web_http_client_manager=>create_by_http_destination( lo_destination ).

        DATA(lo_request) = lo_http_client->get_http_request( ).
        lo_request->set_header_field( i_name = 'Content-Type' i_value = 'application/json' ).
        lo_request->set_header_field( i_name = 'X-TraceX-Key' i_value = me->mv_project_key ).
        lo_request->set_text( iv_batch_json ).

        DATA(lo_response) = lo_http_client->execute( if_web_http_client=>post ).
        DATA(ls_status)   = lo_response->get_status( ).

        CASE ls_status-code.
          WHEN 200 OR 201 OR 202.
            rs_response-status = 'accepted'.
          WHEN 401.
            RAISE EXCEPTION TYPE zcx_tracex_error
              EXPORTING
                mv_error_detail = |Unauthorized (401): Invalid API Key on batch.|.
          WHEN 429.
            RAISE EXCEPTION TYPE zcx_tracex_error
              EXPORTING
                mv_error_detail = |Rate limit exceeded on batch ingestion (429).|.
          WHEN OTHERS.
            RAISE EXCEPTION TYPE zcx_tracex_error
              EXPORTING
                mv_error_detail = |TraceX Batch Ingest failed with HTTP { ls_status-code }.|.
        ENDCASE.

        lo_http_client->close( ).

      CATCH zcx_tracex_error INTO DATA(lx_tracex).
        RAISE EXCEPTION lx_tracex.
      CATCH cx_root INTO DATA(lx_unexpected).
        RAISE EXCEPTION TYPE zcx_tracex_error
          EXPORTING
            mv_error_detail = |Network communication failed on batch: { lx_unexpected->get_text( ) }|.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
