----------------------------------------------------------------------------------------------------------
-- BLOK 1: RELEVANTE LINKS BUITENLAND NETWERKEN SELECTEREN 
----------------------------------------------------------------------------------------------------------
-- in dit blok worden de relevante links uit de buitenland netwerken geselecteerd
-- en tevens voorzien van de juiste attributen 

-- INDEXEN GENEREREN 
CREATE INDEX ON nwb_december USING GIST(geom);
CREATE INDEX ON nwb_december USING BTREE(wvk_id);
CREATE INDEX ON wkd_wegencategorisering USING BTREE(wvk_id);
CREATE INDEX ON wkd_rvm USING BTREE(wvk_id);

CREATE INDEX ON studiegebied USING GIST(geom);

CREATE INDEX ON vlaanderen USING GIST(geom);

CREATE INDEX ON planet_osm_line USING BTREE(osm_id);
CREATE INDEX ON nl_2po_4pgr USING GIST(geom_way);
CREATE INDEX ON nl_2po_4pgr USING BTREE(osm_id);

-- VLAANDEREN 
DROP TABLE IF EXISTS vlaanderen_relevant;
CREATE TABLE vlaanderen_relevant AS 
SELECT 
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
    vlaanderen.geom         
FROM vlaanderen 
INNER JOIN studiegebied ON vlaanderen.geom && studiegebied.geom AND ST_DWithin(vlaanderen.geom, studiegebied.geom, 0.01)
WHERE studiegebied.gebied = 'Vlaanderen'
	  AND ( "b_wk_oidn" <> 0 OR "e_wk_oidn" <> 0 ) -- NODE ID mag niet gelijk zijn aan 0
	  AND lblwegcat NOT IN ('niet gekend','niet van toepassing')
      AND lblmorf NOT IN ('wandel- of fietsweg, niet toegankelijk voor andere voertuigen','dienstweg');

-- OSM
DROP TABLE IF EXISTS osm_relevant;
CREATE TABLE osm_relevant AS 
SELECT DISTINCT
    'OSM' AS bron,
    - (abs(osm.osm_id::NUMERIC) * 10 + 2) AS wvk_id, -- OSM wegvakken krijgen een negatief nummer
    - (abs(source::NUMERIC) * 10 + 2) AS jte_id_beg, -- OSM wegvakken krijgen een negatief nummer
    - (abs(target::NUMERIC) * 10 + 2) AS jte_id_end, -- OSM wegvakken krijgen een negatief nummer
    'RB' AS bst_code,                                -- Hernoem de OSM fclass naar Nederlandse bst_code
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
FROM nl_2po_4pgr osm  
INNER JOIN studiegebied ON studiegebied.geom && ST_Transform(osm.geom_way, 28992) AND ST_DWithin(ST_Transform(osm.geom_way, 28992), studiegebied.geom, 0.01)
LEFT JOIN planet_osm_line pbf ON osm.osm_id = pbf.osm_id 
WHERE studiegebied.gebied = 'OSM';

CREATE INDEX ON osm_relevant USING GIST(geom);

ALTER TABLE osm_relevant ADD COLUMN uniek_id SERIAL;
UPDATE osm_relevant
SET uniek_id = - (abs(uniek_id::NUMERIC) * 10 + 2);

----------------------------------------------------------------------------------------------------------
-- BLOK 2: NWB SAMENVOEGEN MET RELEVANTE LINKS BUITENLAND 
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
	    WHEN rvm.rvm_soort = 'RVM' THEN 3                                              -- reverse -- klopt nog niet, nu nieuwe waardes
        WHEN wegcat.weg_cat IN ('regionale weg','stadshoofdweg') THEN 4                -- reverse 
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
FROM nwb_december nwb
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
-- BLOK 3: LINKS BIJ GRENSGEBIEDEN GOED VERKNOPEN 
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
-- BLOK 4: CHECKS & VERBETERINGEN
----------------------------------------------------------------------------------------------------------
-- CHECK 1: ROUTEERBAARHEID BIJ GRENS
-- NEDERLANDSE KNOPEN BIJ GRENS DETECTEREN ZONDER VERBINDING
-- binnen 20 meter van studiegebied buitenland en doodlopend
DROP TABLE IF EXISTS check_1_putten_bij_grens;
CREATE TABLE check_1_putten_bij_grens AS
SELECT DISTINCT nwb.*
FROM (SELECT * FROM nwb_buitenland_nodes WHERE bron = 'NWB') nwb
LEFT JOIN nwb_buitenland_verbindingen verbindingen ON nwb.node = verbindingen.node_a
LEFT JOIN (SELECT * FROM nwb_buitenland_nodes WHERE bron <> 'NWB') buitenland ON ST_DWithin(nwb.geom, buitenland.geom, 20)
WHERE verbindingen.node_a IS NULL
      AND nwb.aantal = 1 				
      AND buitenland.geom IS NOT NULL;
	  
CREATE INDEX ON check_1_putten_bij_grens USING GIST(geom);

-- OVERGANGEN IN HET OSM NETWERK DETECTEREN (VALIDATIE)
DROP TABLE IF EXISTS check_1_osm_grensovergangen;
CREATE TABLE check_1_osm_grensovergangen AS
WITH osm_incl_land 	AS (SELECT osm_id,
                               source,
                               target,				   
							   gebied,
							   ST_Transform(osm.geom_way, 28992) AS geom									   
						FROM nl_2po_4pgr osm 
						LEFT JOIN studiegebied ON ST_DWithin(ST_LineInterpolatePoint(ST_Transform(osm.geom_way, 28992),0.5),studiegebied.geom,0.01)),
	 osm_nodes 	   	AS (SELECT source AS node_id, 
	                           osm_id, 
							   gebied,
                               ST_StartPoint(geom) AS geom								
						FROM osm_incl_land
						UNION ALL
						SELECT target AS node_id, 
							   osm_id, 
							   gebied,
                               ST_EndPoint(geom) AS geom		 
						FROM osm_incl_land),
	 node_gebieden AS  (SELECT node_id,
							   array_agg(DISTINCT gebied) FILTER (WHERE gebied IS NOT NULL) AS gebieden,
							   array_agg(DISTINCT osm_id) FILTER (WHERE osm_id IS NOT NULL) AS edge_ids
						FROM osm_nodes
						GROUP BY node_id),
	 grens_nodes   AS 	(SELECT node_id,
								gebieden,
								edge_ids,
								cardinality(gebieden) AS n_gebieden
						FROM node_gebieden
						WHERE cardinality(gebieden) >= 2)
SELECT DISTINCT grens_nodes.*,
				osm_nodes.geom
FROM grens_nodes 
LEFT JOIN osm_nodes ON grens_nodes.node_id = osm_nodes.node_id;

-- O.B.V. DEZE CHECK BIJ DE MEEST BELANGRIJKE OVERGANGEN TOCH NOG VERBINDINGEN GEMAAKT 
-- dit gedaan door de geometrie van het vlaams/osm linkje te verlengen zodat hij binnen 5 meter ligt van de NWB link 
UPDATE nwb_buitenland
SET geom = ST_SetPoint(geom,ST_NPoints(geom) - 1,ST_SetSRID(ST_MakePoint(181607.87,335255.58), 28992)),
    jte_id_end = 600120613
WHERE orig_id = -3459431;

UPDATE nwb_buitenland
SET geom = ST_SetPoint(geom,0,ST_SetSRID(ST_MakePoint(176824.405,307279.652), 28992)),
    jte_id_beg = 353014011
WHERE orig_id = -323657242;

UPDATE nwb_buitenland
SET geom = ST_SetPoint(geom,ST_NPoints(geom) - 1,ST_SetSRID(ST_MakePoint(176841.531,307283.843), 28992)),
    jte_id_end = 353014012
WHERE orig_id = -10945253692;

UPDATE nwb_buitenland
SET geom = ST_SetPoint(geom,0,ST_SetSRID(ST_MakePoint(201946.876,347344.600), 28992)),
    jte_id_beg = 403094005
WHERE orig_id = -12276776792;

UPDATE nwb_buitenland
SET geom = ST_SetPoint(geom,ST_NPoints(geom) - 1,ST_SetSRID(ST_MakePoint(201950.181,347344.792), 28992)),
    jte_id_end = 403094005
WHERE orig_id = -67507652;

UPDATE nwb_buitenland
SET geom = ST_SetPoint(geom,0,ST_SetSRID(ST_MakePoint(267938.03,481919.97), 28992)),
    jte_id_beg = 535363062
WHERE orig_id = -14292421582;

-- CHECK 2: LINKS MET DEZELFDE BEGIN EN EINDKNOOP VERWIJDEREN 
-- locaties in het OSM (doodlopende straatjes)
DROP TABLE IF EXISTS check_2_loop_verwijderd;
CREATE TABLE check_2_loop_verwijderd AS
SELECT 
    jte_id_beg,
    jte_id_end,
    geom
FROM nwb_buitenland
WHERE jte_id_beg = jte_id_end;

DELETE FROM nwb_buitenland WHERE jte_id_beg = jte_id_end;
        
----------------------------------------------------------------------------------------------------------
-- BLOK 5: NWB BUITENLAND MET RELEVANTE KOLOMMEN GENEREREN
----------------------------------------------------------------------------------------------------------
-- alleen relevante kolommen blijven over
DROP TABLE IF EXISTS nwb_buitenland_eindresultaat;
CREATE TABLE nwb_buitenland_eindresultaat AS 
SELECT bron,
	   orig_id,
       wvk_id::INTEGER,
	   jte_id_beg::INTEGER,
	   jte_id_end::INTEGER,
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
	   jte_id_beg::INTEGER,
	   jte_id_end::INTEGER,
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
	   nwb.jte_id_beg::INTEGER,
	   nwb.jte_id_end::INTEGER,
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

-- CHECKS
-- SELECT count(*) FROM  nwb_buitenland_eindresultaat: 2617009
-- SELECT count(*), wvk_id FROM nwb_buitenland_eindresultaat GROUP BY wvk_id ORDER BY count(*) DESC:  2617009

-- SELECT count(*) FROM  nwb_buitenland_eindresultaat_5km: 1762813
-- SELECT count(*), wvk_id FROM nwb_buitenland_eindresultaat_5km GROUP BY wvk_id ORDER BY count(*) DESC:  1762813


----------------------------------------------------------------------------------------------------------
-- BLOK 6: VERSCHILANALYSE EERDERE VERSIES
----------------------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS verschilanalyse_nwb_buitenland;
CREATE TABLE verschilanalyse_nwb_buitenland AS
SELECT nieuw.geom,
       nieuw.wvk_id,
	   nieuw.jte_id_beg,
	   nieuw.jte_id_end,
       'niet in oud' AS soort
FROM nwb_buitenland_eindresultaat nieuw 
LEFT JOIN nwb_buitenland_oktober.nwb_buitenland oud ON nieuw.orig_id = oud.orig_id 
WHERE oud.geom IS NULL
UNION ALL 
SELECT oud.geom,
       oud.wvk_id,
	   oud.jte_id_beg,
	   oud.jte_id_end,
       'niet in nieuw' AS soort
FROM nwb_buitenland_oktober.nwb_buitenland oud  
LEFT JOIN nwb_buitenland_eindresultaat nieuw ON nieuw.orig_id = oud.orig_id 
WHERE nieuw.geom IS NULL;


SELECT count(*), fow FROM nwb_buitenland_eindresultaat GROUP BY fow
UNION ALL 
SELECT count(*), fow FROM nwb_buitenland_oktober.nwb_buitenland GROUP BY fow;

SELECT count(*), frc FROM nwb_buitenland_eindresultaat GROUP BY frc
UNION ALL 
SELECT count(*), frc FROM nwb_buitenland_oktober.nwb_buitenland GROUP BY frc;

DROP TABLE IF EXISTS verschilanalyse_nwb_buitenland_versies;
CREATE TABLE verschilanalyse_nwb_buitenland_versies AS
SELECT totaal.*
FROM nwb_buitenland_eindresultaat totaal 
LEFT JOIN nwb_buitenland_eindresultaat_5km stukje ON totaal.wvk_id = stukje.wvk_id 
WHERE stukje.wvk_id IS NULL;