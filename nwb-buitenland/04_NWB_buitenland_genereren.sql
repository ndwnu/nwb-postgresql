----------------------------------------------------------------------------------------------------------
-- BLOK 1: VOORBEREIDING
----------------------------------------------------------------------------------------------------------
-- in dit blok worden indexen gegenereerd

-- INDEXEN GENEREREN NWB
CREATE INDEX ON nwb USING GIST(geom);
CREATE INDEX ON nwb USING BTREE(wvk_id);
CREATE INDEX ON wkd_wegencategorisering USING BTREE(wvk_id);
CREATE INDEX ON wkd_rvm USING BTREE(wvk_id);

-- INDEX GENEREREN VLAANDEREN 
CREATE INDEX ON vlaanderen USING GIST(geom);

-- INDEX GENEREREN OSM 
CREATE INDEX ON planet_osm_line USING BTREE(osm_id);
CREATE INDEX ON routeerbaar_2po_4pgr USING GIST(geom_way);
CREATE INDEX ON routeerbaar_2po_4pgr USING BTREE(osm_id);

-- INDEX GENEREREN HULPBESTANDEN 
CREATE INDEX ON studiegebied USING GIST(geom);
CREATE INDEX ON grensovergangen USING GIST(geom);
CREATE INDEX ON uitsluitingen USING GIST(geom);

-- ANALYSEREN VAN BRONBESTANDEN
ANALYZE nwb; 
ANALYZE vlaanderen;
ANALYSE routeerbaar_2po_4pgr; 
ANALYZE studiegebied;

-- GRENSOVERGANGEN GENEREREN 
-- zijn later nodig voor het afknippen van buitenland links
DROP TABLE IF EXISTS grensovergangen_lijn;
CREATE TABLE grensovergangen_lijn AS  
SELECT a.gebied AS gebied_a,
       b.gebied AS gebied_b,
	   ST_Intersection(ST_Buffer(a.geom,0.01),ST_Buffer(b.geom,0.01)) AS geom
FROM studiegebied a
JOIN studiegebied b ON a.gebied < b.gebied
WHERE ST_Intersects(a.geom, b.geom);

CREATE INDEX ON grensovergangen_lijn USING GIST(geom);

----------------------------------------------------------------------------------------------------------
-- BLOK 2: VLAANDEREN NETWERK VOORBEREIDEN
----------------------------------------------------------------------------------------------------------
-- in dit blok worden de relevante links uit het netwerk van Vlaanderen geselecteerd
-- en tevens voorzien van de juiste attributen 

-- SELECTIE VAN WEGVAKKEN MAKEN O.B.V. STUDIEGEBIED
DROP TABLE IF EXISTS vlaanderen_relevant;
CREATE TABLE vlaanderen_relevant AS 
SELECT DISTINCT
    'Vlaams register' AS bron,
    - (abs(ws_oidn) * 10 + 1) AS wvk_id,        --Vlaamse wegvakken krijgen een negatief nummer
    - (abs(b_wk_oidn)  * 10 + 1) AS jte_id_beg, --Vlaamse nodes krijgen een negatief nummer
    - (abs(e_wk_oidn)  * 10 + 1) AS jte_id_end, --Vlaamse nodes krijgen een negatief nummer
    (CASE
		WHEN lblmorf = 'in- of uitrit van een dienst' THEN 'RB'
		WHEN lblmorf = 'in- of uitrit van een parking' THEN 'PP'
		WHEN lblmorf = 'verkeersplein' THEN 'HR'
		WHEN lblmorf = 'niet gekend' THEN 'RB'
		WHEN lblmorf = 'speciale verkeerssituatie' THEN 'RB'
		WHEN lblmorf = 'parallelweg' THEN 'PAR'
		WHEN lblmorf = 'op- of afrit, behorende tot een gelijkgrondse verbinding' THEN 'OPR'
		WHEN lblmorf = 'autosnelweg' THEN 'HR'
		WHEN lblmorf = 'op- of afrit, behorende tot een niet-gelijkgrondse verbinding' THEN 'OPR'
		WHEN lblmorf = 'ventwe' THEN 'PAR'
		WHEN lblmorf = 'rotonde' THEN 'NRB'
		WHEN lblmorf = 'weg met gescheiden rijbanen die geen autosnelweg is' THEN 'HR'
		WHEN lblmorf = 'weg bestaande uit één rijbaan' THEN 'RB'
		ELSE 'RB'                               -- fall back
    END) AS bst_code,                           -- Hernoem de Vlaamse kolom lblmorf naar de Nederlandse bst_code
    'B' AS rijrichtng,
    rstrnm AS stt_naam,
	(CASE
		WHEN lblwegcat = 'europese hoofdweg' THEN 1
		WHEN lblwegcat = 'vlaamse hoofdweg' THEN 2
		WHEN lblwegcat IN ('regionale weg','interlokale weg') THEN 3
		WHEN lblwegcat = 'lokale ontsluitingsweg' THEN 4
		WHEN lblwegcat = 'lokale weg type 1' THEN 5
		WHEN lblwegcat IN ('lokale weg type 2','lokale weg type 3','lokale erftoegangsweg','niet gekend','niet van toepassing') THEN 6
		ELSE -99
	END) AS frc,
	(CASE 
		WHEN lblmorf = 'autosnelweg' THEN 1     -- MOTORWAY
		WHEN lblmorf = 'weg met gescheiden rijbanen die geen autosnelweg is' THEN 2 -- MULTIPLE_CARRIAGEWAY
		WHEN lblmorf = 'weg bestaande uit één rijbaan' THEN 3 -- SINGLE_CARRIAGEWAY
		WHEN lblmorf = 'rotonde' THEN 4 -- ROUNDABOUT
		WHEN lblmorf = 'verkeersplein' THEN 5 -- TRAFFICSQUARE
		WHEN lblmorf IN ('op- of afrit, behorende tot een gelijkgrondse verbinding',
						'op- of afrit, behorende tot een niet-gelijkgrondse verbinding',
						'in- of uitrit van een dienst',
						'in- of uitrit van een parking') THEN 6 -- SLIPROAD
		WHEN lblmorf IN ('aardeweg','dienstweg','niet gekend','parallelweg','speciale verkeerssituatie','tramweg, niet toegankelijk voor andere voertuigen',
						'veer','ventweg','voetgangerszone','wandel- of fietsweg, niet toegankelijk voor andere voertuigen') THEN 7 -- OTHER
		ELSE 0 -- UNDEFINED (voor alles wat niet gemapt is)
	END) AS fow,
    ST_Force2D(vlaanderen.geom) AS geom -- 2D geometrie maken         
FROM vlaanderen
INNER JOIN studiegebied ON ST_Intersects(vlaanderen.geom, studiegebied.geom)
WHERE studiegebied.gebied = 'Vlaanderen'
	  AND ( "b_wk_oidn" <> 0 OR "e_wk_oidn" <> 0 ) -- NODE ID mag niet gelijk zijn aan 0
	  AND lblwegcat NOT IN ('niet gekend','niet van toepassing')
      AND lblmorf NOT IN ('wandel- of fietsweg, niet toegankelijk voor andere voertuigen','dienstweg');

CREATE INDEX ON vlaanderen_relevant USING GIST(geom);

-- WEGVAKKEN DIE INTERSECTEN MET UITSLUITINGSVLAKKEN WEER VERWIJDEREN 
DELETE FROM vlaanderen_relevant
USING uitsluitingen 
WHERE ST_Intersects(vlaanderen_relevant.geom, uitsluitingen.geom);

----------------------------------------------------------------------------------------------------------
-- BLOK 3: OSM NETWERK VOORBEREIDEN
----------------------------------------------------------------------------------------------------------
-- in dit blok worden de relevante links uit het netwerk van OSM geselecteerd
-- en tevens voorzien van de juiste attributen

-- SELECTIE VAN OSM LINKS MAKEN O.B.V. STUDIEGEBIED
DROP TABLE IF EXISTS osm_relevant;
CREATE TABLE osm_relevant AS 
SELECT DISTINCT
    'OSM' AS bron,
    - (abs(osm.osm_id::NUMERIC) * 10 + 2) AS wvk_id, 			-- OSM wegvakken krijgen een negatief nummer
    - (abs(osm.osm_source_id::NUMERIC) * 10 + 2) AS jte_id_beg, -- OSM wegvakken krijgen een negatief nummer
    - (abs(osm.osm_target_id::NUMERIC) * 10 + 2) AS jte_id_end, -- OSM wegvakken krijgen een negatief nummer
    'RB' AS bst_code,                                			-- Hernoem de OSM fclass naar Nederlandse bst_code
    (CASE WHEN reverse_cost <> 1000000 THEN 'B'
          WHEN reverse_cost = 1000000 THEN 'H'
	END) AS rijrichtng,
    NULL AS stt_naam,
	(CASE WHEN pbf.highway IN ('motorway', 'motorway_link') THEN 1 
          WHEN pbf.highway IN ('trunk', 'trunk_link') THEN 2 
		  WHEN pbf.highway IN ('primary', 'primary_link') THEN 3 
		  WHEN pbf.highway IN ('secondary', 'secondary_link') THEN 4
		  WHEN pbf.highway IN ('tertiary', 'tertiary_link', 'residential') THEN 5
		  WHEN pbf.highway IN ('unclassified', 'road', 'living_street', 'service') THEN 6
		  WHEN pbf.highway IS NULL THEN 6
		  ELSE -99
	END)::NUMERIC AS frc,
		(CASE WHEN pbf.junction IN ('roundabout', 'circular') THEN 4
		  WHEN pbf.highway IN ('motorway') THEN 1 
          WHEN pbf.highway IN ('trunk' ) THEN 2 
		  WHEN pbf.highway IN ('primary', 'secondary', 'tertiary', 'residential', 'road', 'unclassified' ) THEN 3 
          WHEN pbf.highway IN ('motorway_link', 'trunk_link', 'primary_link', 'secondary_link', 'tertiary_link') THEN 6
		  WHEN pbf.highway IN ('living_street', 'service') THEN 7
		  ELSE 7
	END)::NUMERIC  AS fow,
	pbf.highway,
	pbf.junction,
    ST_Transform(osm.geom_way, 28992) AS geom
FROM routeerbaar_2po_4pgr osm  
INNER JOIN studiegebied ON ST_Intersects(ST_Transform(osm.geom_way, 28992), studiegebied.geom)
LEFT JOIN planet_osm_line pbf ON osm.osm_id = pbf.osm_id 
WHERE studiegebied.gebied = 'OSM';

CREATE INDEX ON osm_relevant USING GIST(geom);

ALTER TABLE osm_relevant ADD COLUMN uniek_id SERIAL;
UPDATE osm_relevant
SET uniek_id = - (abs(uniek_id::NUMERIC) * 10 + 2);

-- KNOPEN GENEREREN BIJ OSM WEGVAKKEN 
-- deze zijn later nodig
DROP TABLE IF EXISTS osm_relevant_nodes;
CREATE TABLE osm_relevant_nodes AS
SELECT node_id, 
	   ST_Length(ST_LongestLine(ST_Collect(geom), ST_Collect(geom))) AS max_distance_tussen_nodes, 
	   ST_Centroid(ST_Collect(geom)) AS geom
 FROM (SELECT jte_id_beg AS node_id, 
              ST_StartPoint(geom) AS geom
       FROM osm_relevant
       UNION ALL   
       SELECT jte_id_end AS node_id, 
	          ST_EndPoint(geom) AS geom
       FROM osm_relevant)nodes
GROUP BY node_id;

CREATE INDEX ON osm_relevant_nodes USING GIST(geom);

-- WEGVAKKEN DIE INTERSECTEN MET UITSLUITINGSVLAKKEN WEER VERWIJDEREN 
DELETE FROM osm_relevant
USING uitsluitingen 
WHERE ST_Intersects(osm_relevant.geom, uitsluitingen.geom);

-- WEGVAKKEN SPLITTEN BIJ GRENSOVERGANG
-- OSM wegvakken lopen soms wat verder door en idealiter worden ze gesplitst bij de grens
-- hierdoor worden ze vaker geautomatiseerd verknoopt aan het NWB 	
DROP TABLE IF EXISTS osm_relevant_splits;
CREATE TABLE osm_relevant_splits AS  
SELECT DISTINCT osm_relevant.bron, 
                osm_relevant.wvk_id, 
				osm_relevant.jte_id_beg, 
				osm_relevant.jte_id_end, 
				osm_relevant.bst_code, 
				osm_relevant.rijrichtng, 
				osm_relevant.stt_naam, 
				osm_relevant.frc, 
				osm_relevant.fow, 
				osm_relevant.highway, 
				osm_relevant.junction,
                (ST_Dump(ST_Split(osm_relevant.geom,grensovergangen_lijn.geom))).geom AS geom,
				osm_relevant.uniek_id,
				osm_relevant.geom AS geom_oud,
				0 AS verwijderen
FROM osm_relevant
LEFT JOIN grensovergangen_lijn ON ST_Intersects(osm_relevant.geom, grensovergangen_lijn.geom) 
WHERE grensovergangen_lijn.gebied_a = 'Nederland' AND grensovergangen_lijn.gebied_b = 'OSM';

-- WEGVAKGEDEELTEN IN NEDERLAND CODEREN OM TE VERWIJDEREN 
-- o.b.v. middelpunt analyseren of het wegvakgedeelte in Nederland ligt en deze verwijderen 
UPDATE osm_relevant_splits osm
SET verwijderen = 1 
FROM studiegebied
WHERE ST_Length(osm.geom) < 0.11
      OR (ST_Intersects(ST_LineInterpolatePoint(osm.geom, 0.5), studiegebied.geom) AND studiegebied.gebied = 'Nederland');

-- WEGVAKKEN CODEREN ALS UNIEK_ID NIET MEER UNIEK IS
-- dit zijn wegvakken die meerdere keren de grens overgaan en die daardoor uit meerdere wegvakgedeelten bestaan. 
UPDATE osm_relevant_splits osm
SET verwijderen = 1
WHERE ctid IN (SELECT ctid
			   FROM (SELECT
                     ctid,
                     ROW_NUMBER() OVER (PARTITION BY uniek_id ORDER BY ctid) AS rn
			   FROM osm_relevant_splits
			   WHERE verwijderen = 0) t
			   WHERE rn > 1);

-- WEGVAKKEN DIE VOORKOMEN IN GESPLITSTE VARIANT VERWIJDEREN 
DELETE FROM osm_relevant
USING osm_relevant_splits
WHERE osm_relevant.uniek_id = osm_relevant_splits.uniek_id;

-- WEGVAKKEN MET CODERING VERWIJDEREN = 1 OOK DAADWERKELIJK VERWIJDEREN 
DELETE FROM osm_relevant_splits 
WHERE verwijderen = 1;
 			   
-- BIJ OVERGEBLVEN GESPLITSTE WEGVAKKEN DE KNOOP LEEGMAKEN DIE NIET MEER OP DE ORIGINELE PLEK LIGT 
UPDATE osm_relevant_splits links 
SET jte_id_beg = 0 
FROM osm_relevant_nodes nodes 
WHERE links.jte_id_beg = nodes.node_id AND NOT ST_DWithin(ST_StartPoint(links.geom), nodes.geom, 0.1);

UPDATE osm_relevant_splits links 
SET jte_id_end = 0 
FROM osm_relevant_nodes nodes 
WHERE links.jte_id_end = nodes.node_id AND NOT ST_DWithin(ST_EndPoint(links.geom), nodes.geom, 0.1);

-- NIEUWE KNOPEN GENEREREN 
DROP TABLE IF EXISTS osm_relevant_splits_nodes;
CREATE TABLE osm_relevant_splits_nodes AS
SELECT geom
 FROM (SELECT jte_id_beg AS node_id, 
              ST_StartPoint(geom) AS geom
       FROM osm_relevant_splits 
	   WHERE jte_id_beg = 0
       UNION ALL   
       SELECT jte_id_end AS node_id, 
	          ST_EndPoint(geom) AS geom
       FROM osm_relevant_splits
	   WHERE jte_id_end = 0)nodes
GROUP BY geom;   

-- NIEUW ID AAN TOEVOEGEN 
-- aangezien de knopen worden genummerd vanaf 1 zijn nu in principe niet overlappend tov 
ALTER TABLE osm_relevant_splits_nodes ADD COLUMN node_id SERIAL;

-- NIEUWE NODES TOEVOEGEN AAN GESPLISTE WEGVAKKEN 
UPDATE osm_relevant_splits links 
SET jte_id_beg = -(abs(nodes.node_id::NUMERIC) * 10 + 2) 
FROM osm_relevant_splits_nodes nodes 
WHERE ST_DWithin(ST_StartPoint(links.geom), nodes.geom, 0.1);

UPDATE osm_relevant_splits links 
SET jte_id_end = -(abs(nodes.node_id::NUMERIC) * 10 + 2) 
FROM osm_relevant_splits_nodes nodes 
WHERE ST_DWithin(ST_EndPoint(links.geom), nodes.geom, 0.1);

-- GESPLITSTE WEGVAKKEN MET GOEDE KNOPEN WEER TOEVOEGEN AAN HOOFDBESTAND
INSERT INTO osm_relevant
SELECT bron, 
       wvk_id,
	   jte_id_beg, 
	   jte_id_end, 
	   bst_code, 
	   rijrichtng, 
	   stt_naam, 
	   frc, 
	   fow, 
	   highway, 
	   junction,
       geom,
	   uniek_id
FROM osm_relevant_splits;

----------------------------------------------------------------------------------------------------------
-- BLOK 4: NWB SAMENVOEGEN MET RELEVANTE LINKS BUITENLAND 
----------------------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS nwb_buitenland;
CREATE TABLE nwb_buitenland AS 
SELECT
  'NWB' AS bron,
  nwb.wvk_id AS orig_id,
  nwb.wvk_id,
  nwb.wvk_begdat,
  nwb.jte_id_beg,
  nwb.jte_id_end,
  nwb.wegbehsrt,
  nwb.wegnummer,
  nwb.wegdeelltr,
  nwb.hecto_lttr,
  nwb.bst_code,
  nwb.rpe_code,
  nwb.admrichtng,
  nwb.rijrichtng,
  nwb.stt_naam,
  nwb.stt_bron,
  nwb.wpsnaam,
  nwb.gme_id,
  nwb.gme_naam,
  nwb.hnrstrlnks,
  nwb.hnrstrrhts,
  nwb.e_hnr_lnks,
  nwb.e_hnr_rhts,
  nwb.l_hnr_lnks,
  nwb.l_hnr_rhts,
  nwb.begafstand,
  nwb.endafstand,
  nwb.beginkm,
  nwb.eindkm,
  nwb.pos_tv_wol,
  nwb.wegbehcode,
  nwb.wegbehnaam,
  nwb.distrcode,
  nwb.distrnaam,
  nwb.dienstcode,
  nwb.dienstnaam,
  nwb.wegtype,
  nwb.wgtype_oms,
  nwb.routeltr,
  nwb.routenr,
  nwb.routeltr2,
  nwb.routenr2,
  nwb.routeltr3,
  nwb.routenr3,
  nwb.routeltr4,
  nwb.routenr4,
  nwb.wegnr_aw,
  nwb.wegnr_hmp,
  nwb.geobron_id,
  nwb.geobron_nm,
  nwb.bronjaar,
  nwb.openlr,
  nwb.bag_orl,
  (CASE WHEN nwb.bst_code IN ('BU','RP','BUS','FP','OVB','VDV','VDF','VP','VZ') THEN 7 -- categorie is ontoegankelijk voor auto
        WHEN wegcat.weg_cat = 'autosnelweg' THEN 1 
        WHEN wegcat.weg_cat = 'autoweg' THEN 2
	    WHEN rvm.rvm_soort IN ('RVM-overig', 'RVM-autosnelweg', 'TEN-T-uitgebreid', 'TEN-T-kernnetwerk') THEN 3		
        WHEN wegcat.weg_cat IN ('regionale weg','stadshoofdweg') THEN 4                
		WHEN wegcat.weg_cat	IN	('onverharde weg','erf','verzorgingsplaats') OR nwb.bst_code IN ('BVP','PKP','PKB','PP','PBK','PC','PR') then 6 
        ELSE 5
  END) AS frc,
  (CASE WHEN nwb.fow IS NOT NULL THEN nwb.fow 
        ELSE '7' 
   END)::NUMERIC	AS fow,
  nwb.alt_naam AS alt_naam,
  nwb.alt_nr AS alt_nr,
  nwb.rel_hoogte,
  nwb.geom
FROM nwb 
LEFT JOIN (SELECT DISTINCT ON (wvk_id) wvk_id, weg_cat FROM wkd_wegencategorisering ORDER BY wvk_id) wegcat ON nwb.wvk_id = wegcat.wvk_id
LEFT JOIN wkd_rvm rvm ON nwb.wvk_id = rvm.wvk_id
UNION ALL
SELECT 
  bron,
  wvk_id AS orig_id,
  wvk_id,
  NULL AS wvk_begdat,
  jte_id_beg,
  jte_id_end,
  NULL AS wegbehsrt,
  NULL AS wegnummer,
  NULL AS wegdeelltr,
  NULL AS hecto_lttr,
  bst_code,
  NULL AS rpe_code,
  NULL AS admrichtng,
  rijrichtng,
  stt_naam,
  NULL AS stt_bron,
  NULL AS wpsnaam,
  NULL AS gme_id,
  NULL AS gme_naam,
  NULL AS hnrstrlnks,
  NULL AS hnrstrrhts,
  NULL AS e_hnr_lnks,
  NULL AS e_hnr_rhts,
  NULL AS l_hnr_lnks,
  NULL AS l_hnr_rhts,
  NULL AS begafstand,
  NULL AS endafstand,
  NULL AS beginkm,
  NULL AS eindkm,
  NULL AS pos_tv_wol,
  NULL AS wegbehcode,
  NULL AS wegbehnaam,
  NULL AS distrcode,
  NULL AS distrnaam,
  NULL AS dienstcode,
  NULL AS dienstnaam,
  NULL AS wegtype,
  NULL AS wgtype_oms,
  NULL AS routeltr,
  NULL AS routenr,
  NULL AS routeltr2,
  NULL AS routenr2,
  NULL AS routeltr3,
  NULL AS routenr3,
  NULL AS routeltr4,
  NULL AS routenr4,
  NULL AS wegnr_aw,
  NULL AS wegnr_hmp,
  NULL AS geobron_id,
  NULL AS geobron_nm,
  NULL AS bronjaar,
  NULL AS openlr,
  NULL AS bag_orl,
  frc,
  fow,
  NULL AS alt_naam,
  NULL AS alt_nr,
  NULL AS rel_hoogte,
  geom
FROM vlaanderen_relevant 
UNION ALL
SELECT 
  bron,
  wvk_id AS orig_id,
  uniek_id AS wvk_id,
  NULL AS wvk_begdat,
  jte_id_beg,
  jte_id_end,
  NULL AS wegbehsrt,
  NULL AS wegnummer,
  NULL AS wegdeelltr,
  NULL AS hecto_lttr,
  bst_code,
  NULL AS rpe_code,
  NULL AS admrichtng,
  rijrichtng,
  stt_naam,
  NULL AS stt_bron,
  NULL AS wpsnaam,
  NULL AS gme_id,
  NULL AS gme_naam,
  NULL AS hnrstrlnks,
  NULL AS hnrstrrhts,
  NULL AS e_hnr_lnks,
  NULL AS e_hnr_rhts,
  NULL AS l_hnr_lnks,
  NULL AS l_hnr_rhts,
  NULL AS begafstand,
  NULL AS endafstand,
  NULL AS beginkm,
  NULL AS eindkm,
  NULL AS pos_tv_wol,
  NULL AS wegbehcode,
  NULL AS wegbehnaam,
  NULL AS distrcode,
  NULL AS distrnaam,
  NULL AS dienstcode,
  NULL AS dienstnaam,
  NULL AS wegtype,
  NULL AS wgtype_oms,
  NULL AS routeltr,
  NULL AS routenr,
  NULL AS routeltr2,
  NULL AS routenr2,
  NULL AS routeltr3,
  NULL AS routenr3,
  NULL AS routeltr4,
  NULL AS routenr4,
  NULL AS wegnr_aw,
  NULL AS wegnr_hmp,
  NULL AS geobron_id,
  NULL AS geobron_nm,
  NULL AS bronjaar,
  NULL AS openlr,
  NULL AS bag_orl,
  frc,
  fow,
  NULL AS alt_naam,
  NULL AS alt_nr,
  NULL AS rel_hoogte,
  geom
FROM osm_relevant; 

CREATE INDEX ON nwb_buitenland USING GIST (geom);
CREATE INDEX ON nwb_buitenland USING BTREE (jte_id_beg);
CREATE INDEX ON nwb_buitenland USING BTREE (jte_id_end);

----------------------------------------------------------------------------------------------------------
-- BLOK 5: LINKS BIJ GRENSGEBIEDEN GOED VERKNOPEN 
----------------------------------------------------------------------------------------------------------
-- KNOPEN GENEREREN
-- van alleen autotoegankelijke links 
DROP TABLE IF EXISTS nwb_buitenland_nodes;
CREATE TABLE nwb_buitenland_nodes AS
SELECT bron, 
       node, 
	   ST_Centroid(ST_Collect(geom))::geometry(Point, 28992) AS geom,
       COUNT(*) AS aantal
FROM (
		SELECT bron,
			jte_id_beg AS node,
			ST_StartPoint(geom) AS geom 
		FROM nwb_buitenland
		WHERE bst_code NOT IN ('BU','RP','BUS','FP','OVB','VDV','VDF','VP','VZ')
		UNION ALL 
		SELECT bron,
			jte_id_end AS node,
			ST_EndPoint(geom) AS geom 
		FROM nwb_buitenland
		WHERE bst_code NOT IN ('BU','RP','BUS','FP','OVB','VDV','VDF','VP','VZ'))foo
GROUP BY bron, node;

CREATE INDEX ON nwb_buitenland_nodes USING GIST (geom);
  
-- NEDERLANDSE KNOPEN VERBINDEN AAN BUITENLANDSE KNOPEN
-- binnen 5 meter
DROP TABLE IF EXISTS nwb_buitenland_verbindingen;
CREATE TABLE nwb_buitenland_verbindingen AS
SELECT DISTINCT 
  a.bron  AS bron_a,
  a.node  AS node_a,
  b.bron  AS bron_b,
  b.node  AS node_b,
  ST_MakeLine(a.geom, b.geom)::geometry(LineString, 28992) AS geom,
  ST_Distance(a.geom, b.geom) AS afstand_m
FROM nwb_buitenland_nodes a
CROSS JOIN LATERAL (
  SELECT b.*
  FROM nwb_buitenland_nodes b
  WHERE a.bron <> b.bron 
    AND b.geom && ST_Expand(a.geom, 5)
  ORDER BY a.geom <-> b.geom
  LIMIT 1
) b
WHERE a.bron = 'NWB' AND b.bron IN ('Vlaams register', 'OSM') 
      AND ST_DWithin(a.geom, b.geom, 5);

CREATE INDEX ON nwb_buitenland_verbindingen USING GIST(geom);
CREATE INDEX ON nwb_buitenland_verbindingen USING BTREE(node_b);

-- VERBINDINGEN TERUGVERTALEN NAAR TABEL MET LINKS 
UPDATE nwb_buitenland links 
SET jte_id_beg = node_a 
FROM nwb_buitenland_verbindingen verbindingen
WHERE links.bron <> 'NWB' 
      AND links.jte_id_beg = node_b;

UPDATE nwb_buitenland links 
SET jte_id_end = node_a 
FROM nwb_buitenland_verbindingen verbindingen
WHERE links.bron <> 'NWB' 
      AND links.jte_id_end = node_b;

----------------------------------------------------------------------------------------------------------
-- BLOK 6: CHECKS
----------------------------------------------------------------------------------------------------------
-- CHECK 1: ROUTEERBAARHEID BIJ GRENS
-- o.b.v. grensovergangen (vooraf gedefinieerde vlakken waar autoverkeer tussen NL en buitenland plaatsvindt)
-- detecteren waar grensovergangen missen of juiste extra zijn gemaakt
-- en bij extra grensovergangen ook onderscheid of deze wel binnen 5m liggen van bestaande grensovergang
DROP TABLE IF EXISTS check_1_grensovergangen;
CREATE TABLE check_1_grensovergangen AS
SELECT  (CASE WHEN grensovergangen.categorie = 1 THEN 'missende overgang, maar niet cruciaal'
              ELSE 'missende overgang'
              END) AS soort,
        grensovergangen.geom AS geom
FROM grensovergangen
LEFT JOIN nwb_buitenland_nodes nodes ON ST_Intersects(grensovergangen.geom, nodes.geom) 
LEFT JOIN nwb_buitenland_verbindingen verbindingen ON nodes.node = verbindingen.node_a
WHERE verbindingen.node_a IS NULL AND nodes.bron = 'NWB'
UNION ALL 
SELECT  (CASE WHEN ST_Intersects(ST_Buffer(buffer.geom,5), nodes.geom) IS NOT NULL THEN 'nieuwe overgang dicht bij bestaande overgang'
			  ELSE 'nieuwe overgang' 
		      END) AS soort_extra,
        ST_Buffer(nodes.geom, 5) AS geom
FROM nwb_buitenland_nodes nodes
LEFT JOIN grensovergangen ON ST_Intersects(grensovergangen.geom, nodes.geom)
LEFT JOIN grensovergangen buffer ON ST_Intersects(ST_Buffer(buffer.geom,5), nodes.geom)
LEFT JOIN nwb_buitenland_verbindingen verbindingen ON nodes.node = verbindingen.node_a
WHERE verbindingen.node_a IS NOT NULL AND grensovergangen.geom IS NULL;

-- O.B.V. DEZE CHECK BIJ DE MEEST BELANGRIJKE OVERGANGEN TOCH NOG VERBINDINGEN GEMAAKT 
-- dit gedaan door de geometrie van het vlaams/osm linkje te verlengen zodat hij binnen 5 meter ligt van de NWB link
-- en het knoopnummer van het NWB wegvak overgenomen
-- dit is in een csv bestand opgeslagen. 
UPDATE nwb_buitenland netwerk
SET geom = ST_SetPoint(netwerk.geom,
					   CASE WHEN aanpassing = 'begin' THEN 0
							WHEN aanpassing = 'eind'  THEN ST_NPoints(netwerk.geom) - 1
							END,
					   ST_SetSRID(ST_MakePoint(handmatig.x, handmatig.y), 28992)),
    jte_id_beg = COALESCE(handmatig.jte_id_beg, netwerk.jte_id_beg),
    jte_id_end = COALESCE(handmatig.jte_id_end, netwerk.jte_id_end)
FROM grensovergangen_handmatige_verbindingen handmatig
WHERE netwerk.orig_id = handmatig.orig_id;

-- CHECK 2: LINKS MET DEZELFDE BEGIN EN EINDKNOOP VERWIJDEREN 
-- tot nu toe locaties in het OSM (doodlopende straatjes)
DROP TABLE IF EXISTS check_2_loop_verwijderd;
CREATE TABLE check_2_loop_verwijderd AS
SELECT 
    jte_id_beg,
    jte_id_end,
    geom
FROM nwb_buitenland
WHERE jte_id_beg = jte_id_end;

DELETE FROM nwb_buitenland WHERE jte_id_beg = jte_id_end;

-- CHECK 3: KNOPEN ANALYSE
-- analyse of de knopen in het netwerk maar op 1 locatie voorkomen
-- ook de bron in beschouwing nemen 
DROP TABLE IF EXISTS check_3_knopen_analyse;
CREATE TABLE check_3_knopen_analyse AS
SELECT node_id,
       string_agg(DISTINCT bron, ';') AS bronnen,
	   ST_Length(ST_LongestLine(ST_Collect(geom), ST_Collect(geom))) AS max_distance_tussen_nodes, 
	   ST_Centroid(ST_Collect(geom)) AS geom	   
 FROM (SELECT jte_id_beg AS node_id,
              bron, 
              ST_StartPoint(geom) AS geom
       FROM nwb_buitenland
       UNION ALL   
       SELECT jte_id_end AS node_id,
              bron,	   
	          ST_EndPoint(geom) AS geom
       FROM nwb_buitenland)nodes
GROUP BY node_id;

-- ALLEEN KNOPEN MET GROTE AFWIJKINGEN BEHOUDEN 
-- bij grens mag maximale afwijking van 5 meter voorkomen, hier wordt ook rekening mee gehouden
DELETE FROM check_3_knopen_analyse WHERE max_distance_tussen_nodes < 0.1 AND bronnen = 'NWB' 
                                         OR max_distance_tussen_nodes < 5 AND bronnen <> 'NWB';

-- CHECK 4: STATISTIEKEN GENEREREN 
-- statistieken van fow en frc genereren per bron 
DROP TABLE IF EXISTS check_4_statistieken;
CREATE TABLE check_4_statistieken AS
SELECT 	'--------------------------- AANTAL WEGVAKKEN -------------------------------------------',
		NULL::integer AS aantal
UNION ALL
SELECT 	'totaal aantal wegvakken', 
		count(*) FROM nwb_buitenland
UNION ALL
SELECT 	'totaal aantal unieke wvk_ids', 
		COUNT(DISTINCT wvk_id) FROM nwb_buitenland
UNION ALL
SELECT 	'totaal aantal NWB wegvakken', 
		count(*) FROM nwb_buitenland WHERE bron = 'NWB'
UNION ALL
SELECT 	'totaal aantal OSM wegvakken', 
		count(*) FROM nwb_buitenland WHERE bron = 'OSM'
UNION ALL
SELECT 	'totaal aantal Vlaamse wegvakken', 
		count(*) FROM nwb_buitenland WHERE bron = 'Vlaams register'
UNION ALL
SELECT 	'--------------------------- FRC -------------------------------------------------------',
		NULL::integer AS aantal
UNION ALL
SELECT 	'totaal aantal NWB wegvakken met FRC code 1',
		count(*) FROM nwb_buitenland WHERE bron = 'NWB' AND frc = 1
UNION ALL
SELECT 	'totaal aantal NWB wegvakken met FRC code 2',
		count(*) FROM nwb_buitenland WHERE bron = 'NWB' AND frc = 2
UNION ALL
SELECT 	'totaal aantal NWB wegvakken met FRC code 3',
		count(*) FROM nwb_buitenland WHERE bron = 'NWB' AND frc = 3
UNION ALL
SELECT 	'totaal aantal NWB wegvakken met FRC code 4',
		count(*) FROM nwb_buitenland WHERE bron = 'NWB' AND frc = 4
UNION ALL
SELECT 	'totaal aantal NWB wegvakken met FRC code 5',
		count(*) FROM nwb_buitenland WHERE bron = 'NWB' AND frc = 5
UNION ALL
SELECT 	'totaal aantal NWB wegvakken met FRC code 6',
		count(*) FROM nwb_buitenland WHERE bron = 'NWB' AND frc = 6
UNION ALL
SELECT 	'totaal aantal OSM wegvakken met FRC code 1',
		count(*) FROM nwb_buitenland WHERE bron = 'OSM' AND frc = 1
UNION ALL
SELECT 	'totaal aantal OSM wegvakken met FRC code 2',
		count(*) FROM nwb_buitenland WHERE bron = 'OSM' AND frc = 2
UNION ALL
SELECT 	'totaal aantal OSM wegvakken met FRC code 3',
		count(*) FROM nwb_buitenland WHERE bron = 'OSM' AND frc = 3
UNION ALL
SELECT 	'totaal aantal OSM wegvakken met FRC code 4',
		count(*) FROM nwb_buitenland WHERE bron = 'OSM' AND frc = 4
UNION ALL
SELECT 	'totaal aantal OSM wegvakken met FRC code 5',
		count(*) FROM nwb_buitenland WHERE bron = 'OSM' AND frc = 5
UNION ALL
SELECT 	'totaal aantal OSM wegvakken met FRC code 6',
		count(*) FROM nwb_buitenland WHERE bron = 'OSM' AND frc = 6
UNION ALL
SELECT 	'totaal aantal Vlaamse wegvakken met FRC code 1',
		count(*) FROM nwb_buitenland WHERE bron = 'Vlaams register' AND frc = 1
UNION ALL
SELECT 	'totaal aantal Vlaamse wegvakken met FRC code 2',
		count(*) FROM nwb_buitenland WHERE bron = 'Vlaams register' AND frc = 2
UNION ALL
SELECT 	'totaal aantal Vlaamse wegvakken met FRC code 3',
		count(*) FROM nwb_buitenland WHERE bron = 'Vlaams register' AND frc = 3
UNION ALL
SELECT 	'totaal aantal Vlaamse wegvakken met FRC code 4',
		count(*) FROM nwb_buitenland WHERE bron = 'Vlaams register' AND frc = 4
UNION ALL
SELECT 	'totaal aantal Vlaamse wegvakken met FRC code 5',
		count(*) FROM nwb_buitenland WHERE bron = 'Vlaams register' AND frc = 5
UNION ALL
SELECT 	'totaal aantal Vlaamse wegvakken met FRC code 6',
		count(*) FROM nwb_buitenland WHERE bron = 'Vlaams register' AND frc = 6
UNION ALL
SELECT 	'--------------------------- FOW -------------------------------------------------------',
		NULL::integer AS aantal
UNION ALL
SELECT 	'totaal aantal NWB wegvakken met FOW code 1',
		count(*) FROM nwb_buitenland WHERE bron = 'NWB' AND fow = 1
UNION ALL
SELECT 	'totaal aantal NWB wegvakken met FOW code 2',
		count(*) FROM nwb_buitenland WHERE bron = 'NWB' AND fow = 2
UNION ALL
SELECT 	'totaal aantal NWB wegvakken met FOW code 3',
		count(*) FROM nwb_buitenland WHERE bron = 'NWB' AND fow = 3
UNION ALL
SELECT 	'totaal aantal NWB wegvakken met FOW code 4',
		count(*) FROM nwb_buitenland WHERE bron = 'NWB' AND fow = 4
UNION ALL
SELECT 	'totaal aantal NWB wegvakken met FOW code 5',
		count(*) FROM nwb_buitenland WHERE bron = 'NWB' AND fow = 5
UNION ALL
SELECT 	'totaal aantal NWB wegvakken met FOW code 6',
		count(*) FROM nwb_buitenland WHERE bron = 'NWB' AND fow = 6
UNION ALL
SELECT 	'totaal aantal NWB wegvakken met FOW code 7',
		count(*) FROM nwb_buitenland WHERE bron = 'NWB' AND fow = 7
UNION ALL
SELECT 	'totaal aantal OSM wegvakken met FOW code 1',
		count(*) FROM nwb_buitenland WHERE bron = 'OSM' AND fow = 1
UNION ALL
SELECT 	'totaal aantal OSM wegvakken met FOW code 2',
		count(*) FROM nwb_buitenland WHERE bron = 'OSM' AND fow = 2
UNION ALL
SELECT 	'totaal aantal OSM wegvakken met FOW code 3',
		count(*) FROM nwb_buitenland WHERE bron = 'OSM' AND fow = 3
UNION ALL
SELECT 	'totaal aantal OSM wegvakken met FOW code 4',
		count(*) FROM nwb_buitenland WHERE bron = 'OSM' AND fow = 4
UNION ALL
SELECT 	'totaal aantal OSM wegvakken met FOW code 5',
		count(*) FROM nwb_buitenland WHERE bron = 'OSM' AND fow = 5
UNION ALL
SELECT 	'totaal aantal OSM wegvakken met FOW code 6',
		count(*) FROM nwb_buitenland WHERE bron = 'OSM' AND fow = 6
UNION ALL
SELECT 	'totaal aantal OSM wegvakken met FOW code 7',
		count(*) FROM nwb_buitenland WHERE bron = 'OSM' AND fow = 7
UNION ALL
SELECT 	'totaal aantal Vlaamse wegvakken met FOW code 1',
		count(*) FROM nwb_buitenland WHERE bron = 'Vlaams register' AND fow = 1
UNION ALL
SELECT 	'totaal aantal Vlaamse wegvakken met FOW code 2',
		count(*) FROM nwb_buitenland WHERE bron = 'Vlaams register' AND fow = 2
UNION ALL
SELECT 	'totaal aantal Vlaamse wegvakken met FOW code 3',
		count(*) FROM nwb_buitenland WHERE bron = 'Vlaams register' AND fow = 3
UNION ALL
SELECT 	'totaal aantal Vlaamse wegvakken met FOW code 4',
		count(*) FROM nwb_buitenland WHERE bron = 'Vlaams register' AND fow = 4
UNION ALL
SELECT 	'totaal aantal Vlaamse wegvakken met FOW code 5',
		count(*) FROM nwb_buitenland WHERE bron = 'Vlaams register' AND fow = 5
UNION ALL
SELECT 	'totaal aantal Vlaamse wegvakken met FOW code 6',
		count(*) FROM nwb_buitenland WHERE bron = 'Vlaams register' AND fow = 6
UNION ALL
SELECT 	'totaal aantal Vlaamse wegvakken met FOW code 7',
		count(*) FROM nwb_buitenland WHERE bron = 'Vlaams register' AND fow = 7
UNION ALL
SELECT 	'--------------------------- TOPOLOGIE -------------------------------------------------------',
		NULL::integer AS aantal
UNION ALL
SELECT 	'aantal wegvakken met knopen 0',
		count(*) FROM nwb_buitenland WHERE jte_id_beg = 0 OR jte_id_end = 0
UNION ALL
SELECT 	'aantal knopen in Nederland die op meerdere locaties voorkomen (meer dan 0.1m afstand)',
		count(*) FROM check_3_knopen_analyse WHERE bronnen = 'NWB'
UNION ALL
SELECT 	'aantal knopen in die op meerdere locaties voorkomen (meer dan 5m afstand)',
		count(*) FROM check_3_knopen_analyse WHERE max_distance_tussen_nodes > 5;
		
----------------------------------------------------------------------------------------------------------
-- BLOK 7: NWB BUITENLAND MET RELEVANTE KOLOMMEN GENEREREN
----------------------------------------------------------------------------------------------------------
-- alleen relevante kolommen blijven over
DROP TABLE IF EXISTS nwb_buitenland_eindresultaat;
CREATE TABLE nwb_buitenland_eindresultaat AS 
SELECT bron,
	   orig_id,
       wvk_id::INTEGER,
	   jte_id_beg::BIGINT,
	   jte_id_end::BIGINT,
	   wegbehsrt,
	   wegnummer,
	   wegdeelltr,
	   hecto_lttr,
	   bst_code,
	   rpe_code,
	   admrichtng,
	   rijrichtng,
	   stt_naam,
	   wpsnaam,
	   gme_naam,
       wegbehcode,
	   wegbehnaam,
	   bag_orl,
	   frc::INTEGER,
	   fow::INTEGER, 
	   alt_naam,
	   rel_hoogte,
	   geom 
FROM nwb_buitenland;

CREATE INDEX ON nwb_buitenland_eindresultaat USING GIST(geom);
CREATE INDEX ON nwb_buitenland_eindresultaat USING BTREE(orig_id);
CREATE INDEX ON nwb_buitenland_eindresultaat USING BTREE(jte_id_beg);
CREATE INDEX ON nwb_buitenland_eindresultaat USING BTREE(jte_id_end);

-- BUFFER VAN STUDIEGEBIED MAKEN 
DROP TABLE IF EXISTS studiegebied_buffer;
CREATE TABLE studiegebied_buffer AS 
SELECT ST_Buffer(geom, 5000) AS geom 
FROM studiegebied 
WHERE gebied = 'Nederland';

CREATE INDEX ON studiegebied_buffer USING GIST(geom);

-- BUFFER GEBRUIKEN OM SELECTIE VAN WEGVAKKEN TE MAKEN VOOR VARIANT MET BUITENLAND LINKS BINNEN 5 KM VAN NEDERLANDSE GRENS
DROP TABLE IF EXISTS nwb_buitenland_eindresultaat_5km;
CREATE TABLE nwb_buitenland_eindresultaat_5km AS 
SELECT bron,
	   orig_id,
       wvk_id::INTEGER,
	   jte_id_beg::BIGINT,
	   jte_id_end::BIGINT,
	   wegbehsrt,
	   wegnummer,
	   wegdeelltr,
	   hecto_lttr,
	   bst_code,
	   rpe_code,
	   admrichtng,
	   rijrichtng,
	   stt_naam,
	   wpsnaam,
	   gme_naam,
       wegbehcode,
	   wegbehnaam,
	   bag_orl,
	   frc::INTEGER,
	   fow::INTEGER, 
	   alt_naam,
	   rel_hoogte,
	   geom 
FROM nwb_buitenland nwb
WHERE bron = 'NWB'
UNION ALL
SELECT nwb.bron,
	   nwb.orig_id,
       nwb.wvk_id::INTEGER,
	   nwb.jte_id_beg::BIGINT,
	   nwb.jte_id_end::BIGINT,
	   nwb.wegbehsrt,
	   nwb.wegnummer,
	   nwb.wegdeelltr,
	   nwb.hecto_lttr,
	   nwb.bst_code,
	   nwb.rpe_code,
	   nwb.admrichtng,
	   nwb.rijrichtng,
	   nwb.stt_naam,
	   nwb.wpsnaam,
	   nwb.gme_naam,
       nwb.wegbehcode,
	   nwb.wegbehnaam,
	   nwb.bag_orl,
	   nwb.frc::INTEGER,
	   nwb.fow::INTEGER, 
	   nwb.alt_naam,
	   nwb.rel_hoogte,
	   nwb.geom 
FROM nwb_buitenland nwb
LEFT JOIN studiegebied_buffer studiegebied ON studiegebied.geom && nwb.geom AND ST_Intersects(studiegebied.geom, nwb.geom)
WHERE nwb.bron <> 'NWB' AND studiegebied.geom IS NOT NULL;

----------------------------------------------------------------------------------------------------------
-- BLOK 8: VERSCHILANALYSE EERDERE VERSIES
----------------------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS verschilanalyse_nwb_buitenland;
CREATE TABLE verschilanalyse_nwb_buitenland AS
SELECT nieuw.geom,
       nieuw.wvk_id,
	   nieuw.jte_id_beg,
	   nieuw.jte_id_end,
       'niet in oud' AS soort
FROM nwb_buitenland_eindresultaat nieuw 
LEFT JOIN resultaten.nwb_buitenland_eindresultaat oud ON nieuw.orig_id = oud.orig_id 
WHERE oud.geom IS NULL
UNION ALL 
SELECT oud.geom,
       oud.wvk_id,
	   oud.jte_id_beg,
	   oud.jte_id_end,
       'niet in nieuw' AS soort
FROM resultaten.nwb_buitenland_eindresultaat oud  
LEFT JOIN nwb_buitenland_eindresultaat nieuw ON nieuw.orig_id = oud.orig_id 
WHERE nieuw.geom IS NULL;