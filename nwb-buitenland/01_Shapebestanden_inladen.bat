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
shp2pgsql -d -I -D -S -s 28992  "d:\Projects\022054_2025_NWB_Buitenland\Data\01_NWB\februari_2026\Wegvakken.shp" nwb | psql
REM Vlaanderen
shp2pgsql -d -I -D -S -s 31370:28992  "d:\Projects\022054_2025_NWB_Buitenland\Data\02_Vlaams_wegenregister\februari_2026\Wegsegment.shp" vlaanderen | psql
REM Studiegebied
shp2pgsql -d -I -D -s 28992  "d:\Projects\022054_2025_NWB_Buitenland\Data\04_Studiegebied\Studiegebied.shp" studiegebied | psql
REM Grensovergangen 
shp2pgsql -d -I -D -s 28992  "d:\Projects\022054_2025_NWB_Buitenland\Data\05_Grensovergangen\Grensovergangen.shp" grensovergangen | psql
REM Uitsluitingen
shp2pgsql -d -I -D -s 28992  "d:\Projects\022054_2025_NWB_Buitenland\Data\06_Uitsluitingen\Uitsluitingen.shp" Uitsluitingen | psql
pause
