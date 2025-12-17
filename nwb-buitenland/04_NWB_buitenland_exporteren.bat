REM -------------------------------------------------------------------------------------------
REM ALGEMENE INSTELLINGEN
REM -------------------------------------------------------------------------------------------

SET PGHOST=localhost
SET PGPORT=5432
SET PGDATABASE=db_022054_NWB_Buitenland
SET PGUSER=postgres
SET PGPASSWORD=postgres
SET POSTGRES_BIN=c:\Program Files\PostgreSQL\15\bin

REM -------------------------------------------------------------------------------------------
REM NWB BUITENLAND EXPORTEREN
REM -------------------------------------------------------------------------------------------
pgsql2shp -f "d:\Projects\022054_2025_NWB_Buitenland\Scripts\resultaat\NWB_buitenland_20251210.shp" -h %PGHOST% -p %PGPORT% -u %PGUSER% -P %PGPASSWORD% -d %PGDATABASE% "SELECT * FROM nwb_buitenland_eindresultaat"
pgsql2shp -f "d:\Projects\022054_2025_NWB_Buitenland\Scripts\resultaat\NWB_buitenland_20251210_5km.shp" -h %PGHOST% -p %PGPORT% -u %PGUSER% -P %PGPASSWORD% -d %PGDATABASE% "SELECT * FROM nwb_buitenland_eindresultaat_5km"