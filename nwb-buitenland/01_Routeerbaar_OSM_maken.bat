REM ############################################## GENERIEKE INSTELLINGEN ##################################################################################
REM POSTGRES INSTELLINGEN
SET PGHOST=localhost
SET PGPORT=5432
SET PGDATABASE=db_022054_NWB_Buitenland
SET PGUSER=postgres
SET PGPASSWORD=postgres
SET POSTGRES_BIN=c:\Program Files\PostgreSQL\15\bin

REM REM ############################################## NETWERKEN OSM MERGEN ####################################################################################
REM REM DOWNLOADS MAKEN VIA: 
REM cd d:\Projects\022054_2025_NWB_Buitenland\Scripts\OSM_routerbaar_maken
REM osmium merge niedersachsen-251203.osm.pbf nordrhein-westfalen-251203.osm.pbf belgium-251203.osm.pbf netherlands-251203.osm.pbf -o osm_gemerged.osm.pbf

REM REM ############################################## CLIPPEN MET STUDIEGEBIED ################################################################################
REM REM studiegebied omzetten naar geojson en gebruiken om relevante links van osm te selecteren
REM cd d:\Projects\022054_2025_NWB_Buitenland\Scripts\OSM_routerbaar_maken 
REM ogr2ogr -f GeoJSON -s_srs EPSG:28992 -t_srs EPSG:4326 -makevalid studiegebied.geojson "d:\Projects\022054_2025_NWB_Buitenland\Data\03_Studiegebied\Studiegebied_polygon.shp"
REM cd d:\Projects\022054_2025_NWB_Buitenland\Scripts\OSM_routerbaar_maken  
REM osmium extract -p studiegebied.geojson osm_gemerged.osm.pbf -o studiegebied_osm.osm.pbf
REM 
REM REM ############################################## ROUTEERBAAR NETWERK MAKEN ###############################################################################
REM REM routeerbaar maken 
REM cd d:\Projects\022054_2025_NWB_Buitenland\Scripts\OSM_routerbaar_maken  
REM java -Xmx12g -jar "c:\Users\hkh\OSM\osm2po-core-5.2.43-signed.jar" config=d:\Projects\022054_2025_NWB_Buitenland\Scripts\OSM_routerbaar_maken\osm2po.config prefix=nl "d:\Projects\022054_2025_NWB_Buitenland\Scripts\OSM_routerbaar_maken\studiegebied_osm.osm.pbf" postp.0.class=de.cm.osm2po.plugins.postp.PgRoutingWriter
REM 
REM REM ############################################## ROUTEERBAAR NETWERK INLADEN #############################################################################
REM REM routeerbaar netwerk inladen
REM psql -U postgres -d db_022054_NWB_Buitenland -f d:\Projects\022054_2025_NWB_Buitenland\Scripts\OSM_routerbaar_maken\nl\nl_2po_4pgr.sql
REM REM pbf inladen voor extra attributen 
"c:\Users\hkh\osm2pgsql-bin\osm2pgsql.exe" -c -d db_022054_NWB_Buitenland -U postgres -H localhost -S "osm2pgsql-style.style" --hstore "d:\Projects\022054_2025_NWB_Buitenland\Scripts\OSM_routerbaar_maken\studiegebied_osm.osm.pbf"
pause