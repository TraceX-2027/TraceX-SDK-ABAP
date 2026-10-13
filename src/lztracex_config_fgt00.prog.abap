*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZTRACEX_CONFIG..................................*
DATA:  BEGIN OF status_ztracex_config                .   "state vector
         INCLUDE STRUCTURE vimstatus.
DATA:  END OF status_ztracex_config                .
CONTROLS: tctrl_ztracex_config
            TYPE tableview USING SCREEN '0001'.
*.........table declarations:.................................*
TABLES: *ztracex_config                .
TABLES: ztracex_config                 .
