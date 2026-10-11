CLASS zcx_tracex_error DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES if_t100_message .
    INTERFACES if_t100_dyn_msg .
    CONSTANTS:
      BEGIN OF network_failure,
        msgid TYPE symsgid VALUE 'ZTRACEX',
        msgno TYPE symsgno VALUE '001',
        attr1 TYPE scx_attrname VALUE 'MV_ERROR_DETAIL',
        attr2 TYPE scx_attrname VALUE '',
        attr3 TYPE scx_attrname VALUE '',
        attr4 TYPE scx_attrname VALUE '',
      END OF network_failure,

      BEGIN OF unauthorized_401,
        msgid TYPE symsgid VALUE 'ZTRACEX',
        msgno TYPE symsgno VALUE '002',
        attr1 TYPE scx_attrname VALUE 'MV_ERROR_DETAIL',
        attr2 TYPE scx_attrname VALUE '',
        attr3 TYPE scx_attrname VALUE '',
        attr4 TYPE scx_attrname VALUE '',
      END OF unauthorized_401,

      BEGIN OF rate_limited_429,
        msgid TYPE symsgid VALUE 'ZTRACEX',
        msgno TYPE symsgno VALUE '003',
        attr1 TYPE scx_attrname VALUE 'MV_RETRY_AFTER',
        attr2 TYPE scx_attrname VALUE '',
        attr3 TYPE scx_attrname VALUE '',
        attr4 TYPE scx_attrname VALUE '',
      END OF rate_limited_429,

      BEGIN OF payload_invalid_400,
        msgid TYPE symsgid VALUE 'ZTRACEX',
        msgno TYPE symsgno VALUE '004',
        attr1 TYPE scx_attrname VALUE 'MV_ERROR_DETAIL',
        attr2 TYPE scx_attrname VALUE '',
        attr3 TYPE scx_attrname VALUE '',
        attr4 TYPE scx_attrname VALUE '',
      END OF payload_invalid_400.

    DATA mv_http_status  TYPE i READ-ONLY .
    DATA mv_retry_after  TYPE i READ-ONLY .
    DATA mv_error_detail TYPE string READ-ONLY .

    METHODS constructor
      IMPORTING
        !textid         LIKE if_t100_message=>t100key OPTIONAL
        !previous       LIKE previous OPTIONAL
        !iv_http_status TYPE i OPTIONAL
        !iv_retry_after TYPE i OPTIONAL
        !iv_error_detail TYPE string OPTIONAL .

    METHODS get_text REDEFINITION .

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcx_tracex_error IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    CALL METHOD super->constructor
      EXPORTING
        previous = previous.

    CLEAR me->textid.
    IF textid IS INITIAL.
      if_t100_message~t100key = if_t100_message=>default_textid.
    ELSE.
      if_t100_message~t100key = textid.
    ENDIF.

    me->mv_http_status  = iv_http_status.
    me->mv_retry_after  = iv_retry_after.
    me->mv_error_detail = iv_error_detail.
  ENDMETHOD.

  METHOD get_text.
    IF mv_error_detail IS NOT INITIAL.
      CASE if_t100_message~t100key.
        WHEN network_failure.
          result = |TraceX Network Failure: { mv_error_detail }|.
        WHEN unauthorized_401.
          result = |TraceX Unauthorized (401): Invalid or missing API Key. { mv_error_detail }|.
        WHEN rate_limited_429.
          result = |TraceX Rate Limited (429): Quota exceeded. Retry after { mv_retry_after } seconds.|.
        WHEN payload_invalid_400.
          result = |TraceX Payload Invalid (400): { mv_error_detail }|.
        WHEN OTHERS.
          result = |TraceX Error: { mv_error_detail }|.
      ENDCASE.
    ELSE.
      result = super->get_text( ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
