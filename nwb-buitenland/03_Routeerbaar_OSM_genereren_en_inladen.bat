REM ############################################## GENERIEKE INSTELLINGEN ##################################################################################
REM POSTGRES INSTELLINGEN
SET PGHOST=localhost
SET PGPORT=5432
SET PGDATABASE=db_022054_NWB_Buitenland
SET PGUSER=postgres
SET PGPASSWORD=postgres
SET POSTGRES_BIN=c:\Program Files\PostgreSQL\15\bin

REM ############################################## NETWERKEN OSM MERGEN (M.B.V. OSMIUM) ####################################################################
cd d:\Projects\022054_2025_NWB_Buitenland\Data\03_OSM\februari_2026
osmium merge niedersachsen-260205.osm.pbf nordrhein-westfalen-260205.osm.pbf belgium-260205.osm.pbf netherlands-260205.osm.pbf -o osm_gemerged.osm.pbf

REM ############################################## CLIPPEN MET STUDIEGEBIED (M.B.V. OSMIUM) ################################################################
REM studiegebied omzetten naar geojson
cd d:\Projects\022054_2025_NWB_Buitenland\Scripts\osm_routeerbaar
ogr2ogr -f GeoJSON -s_srs EPSG:28992 -t_srs EPSG:4326 -makevalid studiegebied.geojson "d:\Projects\022054_2025_NWB_Buitenland\Data\04_Studiegebied\Studiegebied_dissolve.shp"
REM en gebruiken om pbf te clippen
cd d:\Projects\022054_2025_NWB_Buitenland\Scripts\osm_routeerbaar
osmium extract -p studiegebied.geojson d:\Projects\022054_2025_NWB_Buitenland\Data\03_OSM\februari_2026\osm_gemerged.osm.pbf -o studiegebied_osm.osm.pbf

REM ############################################## ROUTEERBAAR NETWERK MAKEN (M.B.V. OSM2PO) ###############################################################
cd d:\Projects\022054_2025_NWB_Buitenland\Scripts\osm_routeerbaar
java -Xmx1g -jar "d:\Projects\022054_2025_NWB_Buitenland\Scripts\osm2po\osm2po-core-5.2.43-signed.jar" config=d:\Projects\022054_2025_NWB_Buitenland\Scripts\osm2po\osm2po.config prefix=routeerbaar "d:\Projects\022054_2025_NWB_Buitenland\Scripts\osm_routeerbaar\studiegebied_osm.osm.pbf" postp.0.class=de.cm.osm2po.plugins.postp.PgRoutingWriter

REM ############################################## ROUTEERBAAR NETWERK INLADEN #############################################################################
REM Routeerbaar sql inladen
psql -U postgres -d db_022054_NWB_Buitenland -f d:\Projects\022054_2025_NWB_Buitenland\Scripts\osm_routeerbaar\routeerbaar\routeerbaar_2po_4pgr.sql
REM Extensie hstore toevoegen aan database
psql -U postgres -d db_022054_NWB_Buitenland -c "CREATE EXTENSION IF NOT EXISTS hstore;"
REM pbf inladen voor extra attributen 
"c:\Users\hkh\osm2pgsql-bin\osm2pgsql.exe" -c -d db_022054_NWB_Buitenland -U postgres -H localhost -S "d:\Projects\022054_2025_NWB_Buitenland\Scripts\osm2po\osm2pgsql-style.style" --hstore "d:\Projects\022054_2025_NWB_Buitenland\Scripts\osm_routeerbaar\studiegebied_osm.osm.pbf"
pause
