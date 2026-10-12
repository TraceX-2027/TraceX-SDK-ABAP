CLASS zcx_tracex_error DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    INTERFACES if_t100_message .

    CONSTANTS:
      BEGIN OF network_failure,
        msgid TYPE symsgid VALUE 'ZTRACEX',
        msgno TYPE symsgno VALUE '001',
        attr1 TYPE scx_attrname VALUE 'MV_ERROR_DETAIL',
        attr2 TYPE scx_attrname VALUE '',
        attr3 TYPE scx_attrname VALUE '',
        attr4 TYPE scx_attrname VALUE '',
      END OF network_failure .

    CONSTANTS:
      BEGIN OF unauthorized_401,
        msgid TYPE symsgid VALUE 'ZTRACEX',
        msgno TYPE symsgno VALUE '002',
        attr1 TYPE scx_attrname VALUE 'MV_ERROR_DETAIL',
        attr2 TYPE scx_attrname VALUE '',
        attr3 TYPE scx_attrname VALUE '',
        attr4 TYPE scx_attrname VALUE '',
      END OF unauthorized_401 .

    CONSTANTS:
      BEGIN OF rate_limited_429,
        msgid TYPE symsgid VALUE 'ZTRACEX',
        msgno TYPE symsgno VALUE '003',
        attr1 TYPE scx_attrname VALUE 'MV_RETRY_AFTER',
        attr2 TYPE scx_attrname VALUE '',
        attr3 TYPE scx_attrname VALUE '',
        attr4 TYPE scx_attrname VALUE '',
      END OF rate_limited_429 .

    CONSTANTS:
      BEGIN OF payload_invalid_400,
        msgid TYPE symsgid VALUE 'ZTRACEX',
        msgno TYPE symsgno VALUE '004',
        attr1 TYPE scx_attrname VALUE 'MV_ERROR_DETAIL',
        attr2 TYPE scx_attrname VALUE '',
        attr3 TYPE scx_attrname VALUE '',
        attr4 TYPE scx_attrname VALUE '',
      END OF payload_invalid_400 .

    DATA mv_http_status  TYPE i READ-ONLY .
    DATA mv_error_detail TYPE string READ-ONLY .
    DATA mv_retry_after  TYPE i READ-ONLY .

    METHODS constructor
      IMPORTING
        !textid          LIKE if_t100_message=>t100key OPTIONAL
        !previous        LIKE previous OPTIONAL
        !mv_http_status  TYPE i OPTIONAL
        !mv_error_detail TYPE string OPTIONAL
        !mv_retry_after  TYPE i OPTIONAL .

    METHODS get_text REDEFINITION .

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.

CLASS zcx_tracex_error IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_REC_ATTR ##ADT_SUPPRESS_GENERATION.
    super->constructor( previous = previous ).
    me->mv_http_status  = mv_http_status.
    me->mv_error_detail = mv_error_detail.
    me->mv_retry_after  = mv_retry_after.
    CLEAR me->textid.
    IF textid IS INITIAL.
      if_t100_message~t100key = if_t100_message=>default_textid.
    ELSE.
      if_t100_message~t100key = textid.
    ENDIF.
  ENDMETHOD.

  METHOD get_text.
    IF if_t100_message~t100key = rate_limited_429.
      result = |TraceX API Rate Limit exceeded (429). Retry after { mv_retry_after } seconds.|.
    ELSEIF mv_error_detail IS NOT INITIAL.
      result = mv_error_detail.
    ELSE.
      result = super->get_text( ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
