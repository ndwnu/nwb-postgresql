REM ############################################## GENERIEKE INSTELLINGEN ##################################################################################
REM POSTGRES INSTELLINGEN
SET PGHOST=xxx
SET PGPORT=xxx
SET PGDATABASE=xxx
SET PGUSER=xxx
SET PGPASSWORD=xxx
SET POSTGRES_BIN=xxx

REM PYTHON INSTELLINGEN
SET PYTHON_PATH=xxx
REM LOCATIE SCRIPTS (EINDIGEN MET \)
SET SQL_SCRIPT_LOCATION=xx

REM ############################################## DATA INLADEN ############################################################################################
REM NWB VERSIE
REM verwijzen naar een shapebestand van de wegvakken van een nwb versie
shp2pgsql -d -I -S -D -s  28992 "xxx" wegvakken | psql
REM UITZONDERINGSGEBIEDEN 
REM eventuele uitzonderingsgebieden (vlakken) waarbinnen niet mag worden versimpeld. Alleen wegvakken die geheel binnen het gebied vallen worden niet versimpeld
shp2pgsql -d -I -S -D -s  28992 "xxx" uitzonderingsvlak| psql

REM ############################################## PARAMETERS OPGEVEN ######################################################################################
REM welke bst_code moeten uitgesloten worden? 
REM voorzie elke bst_code van ' voor/erna en scheidt ze met een ,  
REM indien alle bst_codes meegenomen moeten worden, vul 'nee' in. 
SET bst_codes_niet_meenemen='FP', 'BVP', 'VP', 'VZ', 'RP', 'BUS', 'BU', 'BST', 'PP', 'PKP', 'PKB', 'PC', 'PR', 'TN', 'OVB', 'CADO'
REM gemeentenaam opgeven
REM voorzie elke gemeentenaam van ' voor/erna en scheidt ze met een ,  
SET gemeenten='Deventer'
REM clusterafstand in meters opgeven			   
SET clusterafstand=25
REM indien fietspaden samengevoegd moeten worden met hoofdrijbaan 'ja' invullen, anders 'nee'
SET fietspaden_samenvoegen='ja'
REM afstand tot wanneer koude aansluitingen aan de overzijde gekoppeld mogen worden
SET koude_afstand=40
REM maximaal aantal links per intersectie (waarschuwingsfunctie)
SET maximaal_aantal_links_per_intersectie=4

REM ############################################## FUNCTIES INLADEN ############################################################################################
psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% -f "%SQL_SCRIPT_LOCATION%Functies.sql"

REM ############################################## VOORBEREIDING WEGVAKKEN ########################################################################################
REM er is 1 script waarmee gestart moet worden:
REM - voorbereiden van wegmenten en intersecties
psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% -v gemeenten="%gemeenten%" -v bst_codes_niet_meenemen="%bst_codes_niet_meenemen%"  -f "%SQL_SCRIPT_LOCATION%Voorbereiding.sql"
        
REM ############################################## ONAFHANKELIJKE SCRIPTS ########################################################################################
REM er zijn drie scripts die onafhankelijk van elkaar werken:
REM - intersecties samenvoegen: 				intersecties worden samengevoegd o.b.v. een clusterafstand
REM - wegmenten samenvoegen: 					wegmenten met dezelfde bst_code en dezelfde intersecties worden samengevoegd
REM - parallel lopende wegmenten samenvoegen:	wegmenten met bst_code par/vwg worden samengevoegd met de hoofdrijbaan, 
REM 											indien gewenst worden ook fietspaden samengevoegd met de hoofdrijbaan,
REM 											wegmenten die verbonden zijn aan deze parallelwegmenten worden verbonden aan de hoofdrijbaanwegmenten,
REM 											wegmenten die maar aan 1 rijrichting van de gescheiden rijbanen structuur zijn verbonden, worden ook aan de overkant gekoppeld
REM    											tot slot worden dezelfde wegmenten worden weer samengevoegd

psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% -v clusterafstand=%clusterafstand% -f "%SQL_SCRIPT_LOCATION%Intersecties_samenvoegen.sql"
psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% -f "%SQL_SCRIPT_LOCATION%Wegmenten_samenvoegen.sql"
psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% -v koude_afstand=%koude_afstand% -v fietspaden_samenvoegen=%fietspaden_samenvoegen% -f "%SQL_SCRIPT_LOCATION%Parallel_lopende_wegmenten_samenvoegen.sql"
psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% -v clusterafstand=%clusterafstand% -f "%SQL_SCRIPT_LOCATION%Intersecties_samenvoegen.sql"
psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% -f "%SQL_SCRIPT_LOCATION%Wegmenten_samenvoegen.sql"

REM ############################################## INTERSECTIES ANALYSEREN #######################################################################################
psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% -v maximaal_aantal_links_per_intersectie=%maximaal_aantal_links_per_intersectie% -f "%SQL_SCRIPT_LOCATION%Intersecties_analyseren.sql" 
pause      