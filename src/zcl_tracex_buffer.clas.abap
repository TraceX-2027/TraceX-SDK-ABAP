CLASS zcl_tracex_buffer DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    CONSTANTS mc_max_capacity TYPE i VALUE 100.

    TYPES:
      BEGIN OF ty_buffered_event,
        event_id     TYPE string,
        payload_json TYPE string,
        enqueued_at  TYPE string,
        retry_count  TYPE i,
      END OF ty_buffered_event,
      tt_buffered_events TYPE STANDARD TABLE OF ty_buffered_event WITH DEFAULT KEY.

    CLASS-METHODS get_instance
      RETURNING
        VALUE(ro_instance) TYPE REF TO zcl_tracex_buffer.

    METHODS constructor.

    METHODS enqueue
      IMPORTING
        !iv_payload_json TYPE string
        !iv_event_id     TYPE string OPTIONAL.

    METHODS peek_all
      RETURNING
        VALUE(rt_events) TYPE tt_buffered_events.

    METHODS clear.

    METHODS get_count
      RETURNING
        VALUE(rv_count) TYPE i.

    METHODS get_dropped_count
      RETURNING
        VALUE(rv_count) TYPE i.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-DATA go_instance TYPE REF TO zcl_tracex_buffer.
    DATA mt_buffer         TYPE tt_buffered_events.
    DATA mv_dropped_count  TYPE i VALUE 0.
    DATA mv_sequence_order TYPE i VALUE 0.
ENDCLASS.



CLASS zcl_tracex_buffer IMPLEMENTATION.

  METHOD get_instance.
    IF go_instance IS NOT BOUND.
      go_instance = NEW zcl_tracex_buffer( ).
    ENDIF.
    ro_instance = go_instance.
  ENDMETHOD.


  METHOD constructor.
    CLEAR mt_buffer.
    mv_dropped_count  = 0.
    mv_sequence_order = 0.
  ENDMETHOD.


  METHOD enqueue.
    IF iv_payload_json IS INITIAL.
      RETURN.
    ENDIF.

    " 1. Enforce bounded FIFO queue: drop oldest item if max capacity reached
    WHILE lines( mt_buffer ) >= mc_max_capacity.
      DELETE mt_buffer INDEX 1.
      mv_dropped_count = mv_dropped_count + 1.
    ENDWHILE.

    " 2. M1: Strict ISO-8601 UTC timestamp with millisecond precision and Z suffix
    DATA(lv_iso) = zcl_tracex_serializer=>format_iso_timestamp( ).

    mv_sequence_order = mv_sequence_order + 1.
    DATA(lv_id) = condense( val = iv_event_id ).
    IF lv_id IS INITIAL.
      lv_id = |evt_{ mv_sequence_order }|.
    ENDIF.

    " 3. Append to internal buffer
    APPEND VALUE ty_buffered_event(
      event_id     = lv_id
      payload_json = iv_payload_json
      enqueued_at  = lv_iso
      retry_count  = 0
    ) TO mt_buffer.
  ENDMETHOD.


  METHOD peek_all.
    rt_events = mt_buffer.
  ENDMETHOD.


  METHOD clear.
    CLEAR mt_buffer.
    mv_dropped_count  = 0.
    mv_sequence_order = 0.
  ENDMETHOD.


  METHOD get_count.
    rv_count = lines( mt_buffer ).
  ENDMETHOD.


  METHOD get_dropped_count.
    rv_count = mv_dropped_count.
  ENDMETHOD.

ENDCLASS.
