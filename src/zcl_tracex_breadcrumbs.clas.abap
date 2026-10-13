CLASS zcl_tracex_breadcrumbs DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_breadcrumb,
        sequence_order TYPE i,
        timestamp      TYPE string,
        category       TYPE string,
        action         TYPE string,
        target         TYPE string,
        data           TYPE string,
      END OF ty_breadcrumb,

      tt_breadcrumbs TYPE STANDARD TABLE OF ty_breadcrumb WITH DEFAULT KEY.

    CONSTANTS mc_max_capacity TYPE i VALUE 50.

    CLASS-METHODS get_instance
      RETURNING
        VALUE(ro_instance) TYPE REF TO zcl_tracex_breadcrumbs.

    METHODS constructor.

    METHODS add_breadcrumb
      IMPORTING
        !iv_category TYPE string OPTIONAL
        !iv_action   TYPE string OPTIONAL
        !iv_target   TYPE string OPTIONAL
        !iv_data     TYPE string OPTIONAL.

    METHODS get_breadcrumbs
      RETURNING
        VALUE(rt_breadcrumbs) TYPE tt_breadcrumbs.

    METHODS clear.

    METHODS get_count
      RETURNING
        VALUE(rv_count) TYPE i.

    METHODS redact_sensitive_info
      IMPORTING
        !iv_text           TYPE string
      RETURNING
        VALUE(rv_redacted) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-DATA go_instance TYPE REF TO zcl_tracex_breadcrumbs.
    DATA mt_breadcrumbs    TYPE tt_breadcrumbs.
    DATA mv_sequence_order TYPE i VALUE 0.
ENDCLASS.



CLASS zcl_tracex_breadcrumbs IMPLEMENTATION.

  METHOD get_instance.
    IF go_instance IS NOT BOUND.
      go_instance = NEW zcl_tracex_breadcrumbs( ).
    ENDIF.
    ro_instance = go_instance.
  ENDMETHOD.


  METHOD constructor.
    CLEAR mt_breadcrumbs.
    mv_sequence_order = 0.
  ENDMETHOD.


  METHOD add_breadcrumb.
    " 1. Length clamping & sanitization (Max 255 chars)
    DATA(lv_category) = condense( val = iv_category ).
    IF strlen( lv_category ) > 255.
      lv_category = substring( val = lv_category off = 0 len = 255 ).
    ENDIF.

    DATA(lv_action) = condense( val = iv_action ).
    IF strlen( lv_action ) > 255.
      lv_action = substring( val = lv_action off = 0 len = 255 ).
    ENDIF.

    DATA(lv_target) = condense( val = iv_target ).
    IF strlen( lv_target ) > 255.
      lv_target = substring( val = lv_target off = 0 len = 255 ).
    ENDIF.

    " 2. M3: Redact sensitive credentials in data payload without breaking JSON syntax
    DATA(lv_data) = redact_sensitive_info( iv_data ).

    " 3. Monotonic increment of sequence order
    mv_sequence_order = mv_sequence_order + 1.

    " 4. Safe FIFO Ring Buffer eviction (Max 50 items)
    WHILE lines( mt_breadcrumbs ) >= mc_max_capacity.
      DELETE mt_breadcrumbs INDEX 1.
    ENDWHILE.

    " 5. M1: Strict ISO-8601 UTC timestamp with millisecond precision and Z suffix
    DATA(lv_iso) = zcl_tracex_serializer=>format_iso_timestamp( ).

    " 6. Append safe breadcrumb to buffer
    APPEND VALUE ty_breadcrumb(
      sequence_order = mv_sequence_order
      timestamp      = lv_iso
      category       = lv_category
      action         = lv_action
      target         = lv_target
      data           = lv_data
    ) TO mt_breadcrumbs.
  ENDMETHOD.


  METHOD get_breadcrumbs.
    rt_breadcrumbs = mt_breadcrumbs.
  ENDMETHOD.


  METHOD clear.
    CLEAR mt_breadcrumbs.
    mv_sequence_order = 0.
  ENDMETHOD.


  METHOD get_count.
    rv_count = lines( mt_breadcrumbs ).
  ENDMETHOD.


  METHOD redact_sensitive_info.
    IF iv_text IS INITIAL.
      rv_redacted = iv_text.
      RETURN.
    ENDIF.

    rv_redacted = iv_text.

    " Redact Bearer tokens
    rv_redacted = replace(
      val  = rv_redacted
      pcre = '(?i)(Bearer\s+)[A-Za-z0-9\-\._~\+\/]+=*'
      with = '$1[REDACTED]'
      occ  = 0 ).

    " M3: Exclude quotes and curly braces from matching characters: [^\s,;"'\}]+
    rv_redacted = replace(
      val  = rv_redacted
      pcre = '(?i)("?(?:Password|Pwd|Passphrase)"?\s*[:=]\s*"?)[^\s,;"''\}]+'
      with = '$1[REDACTED]'
      occ  = 0 ).

    rv_redacted = replace(
      val  = rv_redacted
      pcre = '(?i)("?(?:api[_-]?key|x-api-key|apikey|access[_-]?key|token|secret)"?\s*[:=]\s*"?)[^\s,;"''\}]+'
      with = '$1[REDACTED]'
      occ  = 0 ).
  ENDMETHOD.

ENDCLASS.
