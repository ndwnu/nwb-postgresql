REM ############################################## GENERIEKE INSTELLINGEN ##################################################################################
REM POSTGRES INSTELLINGEN
SET PGHOST=localhost
SET PGPORT=5432
SET PGDATABASE=db_022054_NWB_Buitenland
SET PGUSER=postgres
SET PGPASSWORD=postgres
SET POSTGRES_BIN=c:\Program Files\PostgreSQL\15\bin

REM ############################################## DATA INLADEN ############################################################################################
REM NWB 
shp2pgsql -I -D -S -s 28992  "d:\Projects\022054_2025_NWB_Buitenland\Data\01_NWB\December_2025\Wegvakken.shp" nwb_december | psql
REM Vlaanderen
shp2pgsql -I -D -S -s 31370:28992  "d:\Projects\022054_2025_NWB_Buitenland\Data\02_Vlaams_wegenregister\december_2025\Wegsegment.shp" vlaanderen | psql
REM Studiegebied
shp2pgsql -I -D -s 28992  "d:\Projects\022054_2025_NWB_Buitenland\Data\03_Studiegebied\Studiegebied_incl_NL_v2.shp" studiegebied | psql
pause