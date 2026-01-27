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
pgsql2shp -f "d:\Projects\022054_2025_NWB_Buitenland\Resultaten\januari_2026\NWB_buitenland_20260126.shp" -h %PGHOST% -p %PGPORT% -u %PGUSER% -P %PGPASSWORD% -d %PGDATABASE% "SELECT * FROM nwb_buitenland_eindresultaat"
pgsql2shp -f "d:\Projects\022054_2025_NWB_Buitenland\Resultaten\januari_2026\NWB_buitenland_20260126_5km.shp" -h %PGHOST% -p %PGPORT% -u %PGUSER% -P %PGPASSWORD% -d %PGDATABASE% "SELECT * FROM nwb_buitenland_eindresultaat_5km"
REM 
REM REM -------------------------------------------------------------------------------------------
REM REM CHECKS EXPORTEREN
REM REM -------------------------------------------------------------------------------------------
pgsql2shp -f "d:\Projects\022054_2025_NWB_Buitenland\Checks\check_1_grensovergangen" -h %PGHOST% -p %PGPORT% -u %PGUSER% -P %PGPASSWORD% -d %PGDATABASE% "SELECT * FROM check_1_grensovergangen"
pgsql2shp -f "d:\Projects\022054_2025_NWB_Buitenland\Checks\check_2_loop_verwijderd" -h %PGHOST% -p %PGPORT% -u %PGUSER% -P %PGPASSWORD% -d %PGDATABASE% "SELECT * FROM check_2_loop_verwijderd"
pgsql2shp -f "d:\Projects\022054_2025_NWB_Buitenland\Checks\check_3_knopen_analyse.shp" -h %PGHOST% -p %PGPORT% -u %PGUSER% -P %PGPASSWORD% -d %PGDATABASE% "SELECT * FROM check_3_knopen_analyse"
psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% ^
  -c "\copy check_4_statistieken TO 'd:/Projects/022054_2025_NWB_Buitenland/Checks/check_4_statistieken.txt' WITH (FORMAT csv, DELIMITER E'\t', HEADER)"
pause