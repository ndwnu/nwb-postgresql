---------------------------------------------------------------------------------------------------------------
-- PARALLEL LOPENDE WEGMENTEN SAMENVOEGEN MET HOOFDRIJBAAN
---------------------------------------------------------------------------------------------------------------

-- OVERZICHT SUB BLOKKEN:
-- 1) PARALLEL LOPENDE WEGMENTEN DETECTEREN
-- 2) WEGMENTEN KOPPELEN AAN HOOFDRIJBAAN DIE WAREN VERBONDEN AAN VERWIJDERDE PARALLELLE WEGMENTEN
-- 3) WEGMENTEN UPDATEN 
-- 4) INTERSECTIES UPDATEN
-- 5) KOUDE AANSLUITINGEN DETECTEREN
-- 6) WEGMENTEN UPDATEN 
-- 7) INTERSECTIES UPDATEN
-- 8) WEGMENTEN DISSOLVEN
-- 9) WEGMENTEN SAMENVOEGEN
-- 10) WEGMENTEN UPDATEN 
-- 11) INTERSECTIES UPDATEN

---------------------------------------------------------------------------------------------------------------
-- PARALLEL LOPENDE WEGMENTEN DETECTEREN
---------------------------------------------------------------------------------------------------------------
-- FUNCTIE WEGMENTEN MET DEZELFDE BEGIN-EN EINDPUNTEN SELECTEREN UITVOEREN
SELECT wegmenten_onderverdelen('wegmenten', 'nee');

-- VERBINDINGSWEGEN MET HOOFDRIJBAAN SELECTEREN 
DROP TABLE IF EXISTS wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan;
CREATE TABLE wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan AS
SELECT *
FROM wegmenten_zelfde
WHERE (bst_code IN ('VWG', 'PAR')
	  AND (bst_code_buurman = '' OR bst_code_buurman = 'HR' OR bst_code_buurman = 'RB'));

-- VERBINDINGSWEGEN MET ZELFDE HOOFDRIJBAAN VERWIJDEREN
-- MITS DE HOOFDRIJBAAN 2 RICHTINGEN IS
DELETE FROM wegmenten wegmenten
USING wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan verbindingswegen
WHERE wegmenten.wegment_id = verbindingswegen.wegment_id 
      AND verbindingswegen.jte_id_beg = wegmenten.jte_id_beg 
	  AND verbindingswegen.jte_id_end = wegmenten.jte_id_end;
	  
-- KOPPELINGSTABEL UPDATEN
UPDATE koppelingstabel_wegvakken_wegmenten_juncties_intersecties koppeling
SET wegment_id = samengevoegd.wegment_id_buurman
FROM wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan samengevoegd
WHERE koppeling.wegment_id = samengevoegd.wegment_id;
	  
-- FUNCTIE FIETSPADEN VERWIJDEREN UITVOEREN 
SELECT verwijderen_fietspaden_langs_hoofdrijbaan(:fietspaden_samenvoegen);

-- VRIJE RECHTSAFFERS RICHTING RIJKSWEGEN DETECTEREN EN VERWIJDEREN
DROP TABLE IF EXISTS wegmenten_vrije_rechtsaffers_rijkswegen;
CREATE TABLE wegmenten_vrije_rechtsaffers_rijkswegen AS
SELECT DISTINCT links.*,
                links2.wegment_id AS wegment_id2,
                links3.wegment_id AS wegment_id3,
                links3.jte_id_beg AS wegment_id3_beg,
                links3.jte_id_end AS wegment_id3_end				
FROM wegmenten links
LEFT JOIN wegmenten links2 ON links.jte_id_end = links2.jte_id_beg 
LEFT JOIN wegmenten links3 ON links.jte_id_end = links3.jte_id_end
WHERE links.wegment_id <> links2.wegment_id
      AND links.wegment_id <> links3.wegment_id
	  AND links2.wegment_id <> links3.wegment_id
	  AND links2.bst_code IN ('OPR', 'PST') 
	  AND links3.bst_code IN ('OPR', 'PST') 
	  AND links.rijrichtng = 'H'
	  AND links.bst_code NOT IN ('AFR', 'OPR','HR')
UNION ALL
SELECT DISTINCT links.*,
                links2.wegment_id AS wegment_id2,
                links3.wegment_id AS wegment_id3,
                links3.jte_id_beg AS wegment_id3_beg,
                links3.jte_id_end AS wegment_id3_end				
FROM wegmenten links
LEFT JOIN wegmenten links2 ON links.jte_id_beg = links2.jte_id_beg 
LEFT JOIN wegmenten links3 ON links.jte_id_beg = links3.jte_id_end
WHERE links.wegment_id <> links2.wegment_id 
      AND links.wegment_id <> links3.wegment_id
	  AND links2.wegment_id <> links3.wegment_id
	  AND links2.bst_code IN ('AFR', 'PST') 
	  AND links3.bst_code IN ('AFR', 'PST') 
	  AND links.rijrichtng = 'H'
	  AND links.bst_code NOT IN ('AFR', 'OPR', 'HR');

-- VRIJE RECHTSAFFER DAADWERKELIJK VERWIJDEREN 	  
DELETE FROM wegmenten wegmenten
USING wegmenten_vrije_rechtsaffers_rijkswegen vrije_rechtsaffers
WHERE wegmenten.wegment_id = vrije_rechtsaffers.wegment_id;

-- KOPPELINGSTABEL UPDATEN
UPDATE koppelingstabel_wegvakken_wegmenten_juncties_intersecties koppeling
SET wegment_id = samengevoegd.wegment_id3,
    intersectie_beg = samengevoegd.wegment_id3_beg,
	intersectie_end = samengevoegd.wegment_id3_end
FROM wegmenten_vrije_rechtsaffers_rijkswegen samengevoegd
WHERE koppeling.wegment_id = samengevoegd.wegment_id;
  
-- WEGEN DIE AAN BEIDE KANTEN ZIJN VERBONDEN AAN LINKS DIE OOK MET ELKAAR ZIJN VERBONDEN VERWIJDEREN
DROP TABLE IF EXISTS wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan_parallel;
CREATE TABLE wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan_parallel AS
SELECT DISTINCT links.*,
       beginpunt.wegment_id AS beginpunt_wegment_id,
	   beginpunt.jte_id_beg AS beginpunt_jte_id_beg,
	   beginpunt.jte_id_end AS beginpunt_jte_id_end,			 
	   eindpunt.wegment_id AS eindpunt_wegment_id,
	   eindpunt.jte_id_beg AS eindpunt_jte_id_beg,
	   eindpunt.jte_id_end AS eindpunt_jte_id_end
FROM wegmenten links
LEFT JOIN wegmenten rijkswegen ON links.jte_id_end = rijkswegen.jte_id_beg
LEFT JOIN wegmenten beginpunt ON links.jte_id_beg = beginpunt.jte_id_beg OR links.jte_id_beg = beginpunt.jte_id_end
LEFT JOIN wegmenten eindpunt ON links.jte_id_end = eindpunt.jte_id_beg OR links.jte_id_end = eindpunt.jte_id_end
WHERE links.bst_code IN ('VWG', 'PAR')
      AND (links.stt_naam = beginpunt.stt_naam OR links.stt_naam = eindpunt.stt_naam)
      AND 
	  ((links.jte_id_beg = beginpunt.jte_id_beg 
      AND links.jte_id_end = eindpunt.jte_id_end
	  AND beginpunt.jte_id_end = eindpunt.jte_id_beg)
	  OR (links.jte_id_beg = beginpunt.jte_id_end 
      AND links.jte_id_end = eindpunt.jte_id_end
	  AND beginpunt.jte_id_beg = eindpunt.jte_id_beg)
	  OR (links.jte_id_beg = beginpunt.jte_id_beg 
      AND links.jte_id_end = eindpunt.jte_id_beg
	  AND beginpunt.jte_id_end = eindpunt.jte_id_end)
	  OR (links.jte_id_beg = beginpunt.jte_id_end 
      AND links.jte_id_end = eindpunt.jte_id_end
	  AND beginpunt.jte_id_beg = eindpunt.jte_id_beg)
	  OR (links.jte_id_end = beginpunt.jte_id_beg 
      AND links.jte_id_beg = eindpunt.jte_id_end
	  AND beginpunt.jte_id_end = eindpunt.jte_id_beg)
	  OR (links.jte_id_end = beginpunt.jte_id_end 
      AND links.jte_id_beg = eindpunt.jte_id_end
	  AND beginpunt.jte_id_beg = eindpunt.jte_id_beg)
	  OR (links.jte_id_end = beginpunt.jte_id_beg 
      AND links.jte_id_beg = eindpunt.jte_id_beg
	  AND beginpunt.jte_id_end = eindpunt.jte_id_end)
	  OR (links.jte_id_end = beginpunt.jte_id_end 
      AND links.jte_id_beg = eindpunt.jte_id_end
	  AND beginpunt.jte_id_beg = eindpunt.jte_id_beg));
	  
UPDATE wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan_parallel A
SET beginpunt_wegment_id = -999,
    beginpunt_jte_id_beg = -999,
    beginpunt_jte_id_end = -999
FROM wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan_parallel B
WHERE A.beginpunt_wegment_id = B.wegment_id;

UPDATE wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan_parallel A
SET eindpunt_wegment_id = -999,
    eindpunt_jte_id_beg = -999,
    eindpunt_jte_id_end = -999
FROM wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan_parallel B
WHERE A.eindpunt_wegment_id = B.wegment_id;

-- PARALLELWEGEN DAADWERKELIJK VERWIJDEREN
DELETE FROM wegmenten wegmenten
USING wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan_parallel verbindingswegen
WHERE wegmenten.wegment_id = verbindingswegen.wegment_id
      AND verbindingswegen.jte_id_beg = wegmenten.jte_id_beg 
	  AND verbindingswegen.jte_id_end = wegmenten.jte_id_end;
	  
-- KOPPELINGSTABEL UPDATEN
UPDATE koppelingstabel_wegvakken_wegmenten_juncties_intersecties koppeling
SET wegment_id = samengevoegd.beginpunt_wegment_id,
    intersectie_beg = samengevoegd.beginpunt_jte_id_beg,
	intersectie_end = samengevoegd.beginpunt_jte_id_end
FROM wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan_parallel samengevoegd
WHERE koppeling.wegment_id = samengevoegd.wegment_id AND samengevoegd.beginpunt_wegment_id > -999;

-- KOPPELINGSTABEL UPDATEN
UPDATE koppelingstabel_wegvakken_wegmenten_juncties_intersecties koppeling
SET wegment_id = samengevoegd.eindpunt_wegment_id,
    intersectie_beg = samengevoegd.eindpunt_jte_id_beg,
	intersectie_end = samengevoegd.eindpunt_jte_id_end
FROM wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan_parallel samengevoegd
WHERE koppeling.wegment_id = samengevoegd.wegment_id AND samengevoegd.eindpunt_wegment_id > -999;

-----------------------------------------------------------------------------------------------------------------
---- WEGMENTEN KOPPELEN AAN HOOFDRIJBAAN DIE WAREN VERBONDEN AAN VERWIJDERDE PARALLELLE WEGMENTEN
-----------------------------------------------------------------------------------------------------------------
--  WEGEN SELECTEREN DIE VERBONDEN ZIJN AAN PARALLELLE WEGMENTEN DIE ZIJN SAMENGEVOEGD MET DE HOOFDRIJBAAN
DROP TABLE IF EXISTS wegmenten_verbonden_aan_parallelwegen;
CREATE TABLE wegmenten_verbonden_aan_parallelwegen AS
WITH losse_knopen AS (SELECT jte_id_beg AS knoop 
                     FROM wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan_parallel
					 UNION ALL 
					 SELECT jte_id_end AS knoop 
                     FROM wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan_parallel),
	aantal_knopen AS (SELECT count(knoop) AS aantal,
	                         knoop 
					  FROM losse_knopen
					  GROUP BY knoop)
SELECT links.*,
       'beginpunt' AS locatie,
	   links.jte_id_beg AS knoop,
	   ST_StartPoint(links.geom) AS geom_node,
	   null::geometry AS geom_buffer_rondom_vertex,
	   null::float AS hoek
FROM wegmenten links
LEFT JOIN wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan_parallel verbindingswegen ON links.wegment_id = verbindingswegen.wegment_id
LEFT JOIN aantal_knopen ON links.jte_id_beg = aantal_knopen.knoop
LEFT JOIN intersecties ON links.jte_id_beg = intersecties.knoop
WHERE aantal_knopen.aantal = 2 
      AND verbindingswegen.geom IS NULL
      AND intersecties.aantal_links = 3
UNION ALL 
SELECT links.*,
       'eindpunt' AS locatie,
	   links.jte_id_end AS knoop,
	   ST_EndPoint(links.geom) AS geom_node,
	   null::geometry AS geom_buffer_rondom_vertex,
	   null::float AS hoek
FROM wegmenten links
LEFT JOIN wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan_parallel verbindingswegen ON links.wegment_id = verbindingswegen.wegment_id
LEFT JOIN aantal_knopen ON links.jte_id_end = aantal_knopen.knoop
LEFT JOIN intersecties ON links.jte_id_end = intersecties.knoop
WHERE aantal_knopen.aantal = 2 
      AND verbindingswegen.geom IS NULL
      AND intersecties.aantal_links = 3;

UPDATE wegmenten_verbonden_aan_parallelwegen  SET geom_buffer_rondom_vertex = ST_Intersection(geom, ST_Buffer(geom_node,0.05)); -- buffer tbv bepalen hoek
UPDATE wegmenten_verbonden_aan_parallelwegen  SET hoek = degrees(ST_Azimuth(ST_StartPoint(geom_buffer_rondom_vertex), ST_Endpoint(geom_buffer_rondom_vertex)));
  
-- SCANLIJNEN MAKEN DIE DOORLOPEN VANAF BEGIN-EINDPUNT SELECTIE WEGEN HIERBOVEN 
DROP TABLE IF EXISTS wegmenten_verbonden_aan_parallelwegen_scanlijn;
CREATE TABLE wegmenten_verbonden_aan_parallelwegen_scanlijn AS 
SELECT *,
       (CASE WHEN locatie = 'beginpunt' THEN 
	    ST_MakeLine(ST_TRANSLATE(geom_node, sin(radians(hoek+180)) * :koude_afstand, cos(radians(hoek+180)) * :koude_afstand),
	    geom_node) 
		ELSE ST_MakeLine(geom_node,
	    ST_TRANSLATE(geom_node, sin(radians(hoek)) * :koude_afstand, cos(radians(hoek)) * :koude_afstand)) 
		END) AS geom_scanlijn
FROM wegmenten_verbonden_aan_parallelwegen;

CREATE INDEX ON wegmenten_verbonden_aan_parallelwegen_scanlijn USING GIST(geom_scanlijn);

-- SCANLIJNEN INTERSECTEN MET HOOFDRIJBAAN (WAARM PARALLELBAAN MEE IS SAMENGEVOEGD)
DROP TABLE IF EXISTS wegmenten_verbonden_aan_parallelwegen_scanlijn_intersect;
CREATE TABLE wegmenten_verbonden_aan_parallelwegen_scanlijn_intersect AS 
SELECT DISTINCT scanlijn.*,
       ST_Intersection(scanlijn.geom_scanlijn, links.geom) AS intersectie,
	   ST_Centroid(ST_Union(scanlijn.geom_node, ST_Intersection(scanlijn.geom_scanlijn, links.geom))) AS nieuwe_intersectie,
	   links.wegment_id AS wegment_id_overkant,
	   links.bst_code AS bst_code_overkant
FROM wegmenten_verbonden_aan_parallelwegen_scanlijn scanlijn
LEFT JOIN wegmenten links ON ST_Intersects(scanlijn.geom_scanlijn, links.geom)
LEFT JOIN wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan_parallel parallel ON scanlijn.knoop = parallel.jte_id_beg OR scanlijn.knoop = parallel.jte_id_end
WHERE parallel.beginpunt_wegment_id = links.wegment_id OR parallel.eindpunt_wegment_id = links.wegment_id;

-- INTERSECTIE ID TOEVOEGEN
ALTER TABLE wegmenten_verbonden_aan_parallelwegen_scanlijn_intersect ADD COLUMN intersectie_id SERIAL;

WITH hoogste_knoop AS (SELECT MAX(knoop) AS hoogste_knoop FROM intersecties)
UPDATE wegmenten_verbonden_aan_parallelwegen_scanlijn_intersect
SET intersectie_id  = intersectie_id + hoogste_knoop.hoogste_knoop
FROM hoogste_knoop;	

-----------------------------------------------------------------------------------------------------------------
---- WEGMENTEN UPDATEN
-----------------------------------------------------------------------------------------------------------------
-- WEGMENTEN SPLITSEN
DROP TABLE IF EXISTS wegmenten_split;
CREATE TABLE wegmenten_split AS 
SELECT links.*
FROM wegmenten links
LEFT JOIN wegmenten_verbonden_aan_parallelwegen_scanlijn_intersect intersects ON links.wegment_id = intersects.wegment_id_overkant
WHERE intersects.wegment_id_overkant IS NULL
UNION ALL 
SELECT 0 AS jte_id_beg,
	   0 AS jte_id_end,
	   links.rijrichtng,
	   links.stt_naam,
	   links.bst_code,
	   links.rpe_code,
	   links.wegbehsrt,
       (ST_Dump(ST_CollectionHomogenize(ST_Split(links.geom, intersects.geom_scanlijn)))).geom AS geom,
	   0 AS wegment_id
FROM wegmenten links
LEFT JOIN wegmenten_verbonden_aan_parallelwegen_scanlijn_intersect intersects ON links.wegment_id = intersects.wegment_id_overkant
WHERE intersects.wegment_id_overkant IS NOT NULL;

ALTER TABLE wegmenten_split ADD COLUMN wegment_id2 SERIAL;

-- WEGMENTEN SNAPPEN DIE NIET MEER ZIJN VERBONDEN
-- LINKS SNAPPEN NAAR NIEUWE INTERSECTIE
UPDATE wegmenten_split links
SET geom = ST_SetPoint(links.geom, 0, nodes.intersectie)
FROM wegmenten_verbonden_aan_parallelwegen_scanlijn_intersect  nodes
WHERE links.wegment_id = nodes.wegment_id AND nodes.locatie = 'beginpunt';
 
UPDATE wegmenten_split links
SET geom = ST_SetPoint(links.geom, -1, nodes.intersectie)
FROM wegmenten_verbonden_aan_parallelwegen_scanlijn_intersect  nodes
WHERE links.wegment_id = nodes.wegment_id AND nodes.locatie = 'eindpunt';

-- KNOPEN BIJWERKEN
UPDATE wegmenten_split links 
SET jte_id_beg = nodes.intersectie_id
FROM wegmenten_verbonden_aan_parallelwegen_scanlijn_intersect  nodes
WHERE ST_Equals(ST_StartPoint(links.geom), nodes.intersectie);

UPDATE wegmenten_split links 
SET jte_id_end = nodes.intersectie_id
FROM wegmenten_verbonden_aan_parallelwegen_scanlijn_intersect  nodes
WHERE ST_Equals(ST_EndPoint(links.geom), nodes.intersectie);

UPDATE wegmenten_split links 
SET jte_id_beg = nodes.knoop
FROM intersecties nodes
WHERE ST_Equals(ST_StartPoint(links.geom), nodes.geom) AND jte_id_beg = 0;

UPDATE wegmenten_split links 
SET jte_id_end = nodes.knoop
FROM intersecties nodes
WHERE ST_Equals(ST_EndPoint(links.geom), nodes.geom) AND jte_id_end = 0;

-- UNIEK ID BIJWERKEN
WITH hoogste_id AS (SELECT MAX(wegment_id) AS hoogste_id FROM wegmenten)
UPDATE wegmenten_split
SET wegment_id2 = wegment_id2 + hoogste_id.hoogste_id + 1
FROM hoogste_id
WHERE wegment_id = 0;

-- KOPPELINGSTABEL UPDATEN
UPDATE koppelingstabel_wegvakken_wegmenten_juncties_intersecties koppeling
SET wegment_id = samengevoegd.wegment_id2,
    intersectie_beg = samengevoegd.jte_id_beg,
	intersectie_end = samengevoegd.jte_id_beg
FROM wegmenten_split samengevoegd
WHERE samengevoegd.wegment_id = 0 AND ST_DWithin(ST_LineInterpolatePoint(koppeling.wvk_geom,0.5), samengevoegd.geom, 0.1);

-- NIEUWE WEGMENTID OVERZETTEN NAAR JUIST VELD
UPDATE wegmenten_split
SET wegment_id = wegment_id2
WHERE wegment_id = 0;

-- TABEL MET WEGMENTEN VERVANGEN DOOR GESPLITTE TABEL
DROP TABLE IF EXISTS wegmenten;
CREATE TABLE wegmenten AS
SELECT jte_id_beg,
	   jte_id_end,
	   rijrichtng,
	   stt_naam,
	   bst_code,
	   rpe_code,
	   wegbehsrt,
       geom,
	   wegment_id
FROM wegmenten_split;

CREATE INDEX ON wegmenten USING GIST(geom);
CREATE INDEX ON wegmenten USING BTREE(wegment_id);

---------------------------------------------------------------------------------------------------------------
-- INTERSECTIES UPDATEN
---------------------------------------------------------------------------------------------------------------
-- FUNCTIE INTERSECTIES GENEREREN AANROEPEN 
SELECT intersecties_genereren();

---------------------------------------------------------------------------------------------------------------
-- KOUDE AANSLUITINGEN DETECTEREN
---------------------------------------------------------------------------------------------------------------
-- GESCHEIDEN WEGMENTEN DETECTEREN
-- RPE_CODE MOET ZIJN INGEVULD
DROP TABLE IF EXISTS wegmenten_gescheiden_rijbanen;
CREATE TABLE wegmenten_gescheiden_rijbanen AS
SELECT *
FROM wegmenten
WHERE (rpe_code <> '#' OR rpe_code IN ('L', 'R', 'N', 'O', 'W', 'Z')) 
--      AND rijrichtng = 'H' 
	  AND wegbehsrt <> 'R' 
	  AND bst_code IN ('','HR', 'RB');

CREATE INDEX ON wegmenten_gescheiden_rijbanen USING GIST(geom);

-- WEGMENTEN SELECTEREN DIE GEEN ONDERDEEL IS VAN BOVENSTAANDE SELECTIE, MAAR ER WEL AAN VAST ZIT (3 LINKS)
-- INCLUSIEF AZIMUTH BEPALING VAN EERSTE/LAATSTE METER
-- MOGEN NIET IN UITZONDERINGSVLAKKEN VOORKOMEN
DROP TABLE IF EXISTS wegmenten_gescheiden_rijbanen_met_3_links;
CREATE TABLE wegmenten_gescheiden_rijbanen_met_3_links AS
SELECT DISTINCT foo.wegment_id,
                foo.node,
                foo.jte_id_beg,
				foo.jte_id_end,
				foo.rijrichtng,
				foo.bst_code,
				foo.rpe_code,
				foo.stt_naam,
				foo.wegbehsrt,
				foo.geom,
				foo.geom_node,
				foo.geom_buffer_rondom_vertex,
				foo.hoek,
				foo.aangepast,
				(CASE WHEN buurman1 < buurman2 THEN buurman1 
				ELSE buurman2
				END) AS buurman1,
	             (CASE WHEN buurman1 < buurman2 THEN buurman2 
				ELSE buurman1
				END) AS buurman2,
                foo.locatie			
FROM 
(SELECT links.*,
       ST_StartPoint(links.geom) AS geom_node,
	   links.jte_id_beg AS node,
	   null::geometry AS geom_buffer_rondom_vertex,
	   null::float AS hoek,
	   0 AS aangepast,
	   beginpunt.wegment_id AS buurman1,
	   eindpunt.wegment_id AS buurman2,
	   'beginpunt' AS locatie
FROM wegmenten links
LEFT JOIN intersecties knopen ON links.jte_id_beg = knopen.knoop
LEFT JOIN wegmenten_gescheiden_rijbanen selectie ON links.wegment_id = selectie.wegment_id
LEFT JOIN wegmenten_gescheiden_rijbanen beginpunt ON links.jte_id_beg = beginpunt.jte_id_beg OR links.jte_id_beg = beginpunt.jte_id_end
LEFT JOIN wegmenten_gescheiden_rijbanen eindpunt ON links.jte_id_beg = eindpunt.jte_id_beg OR links.jte_id_beg = eindpunt.jte_id_end
LEFT JOIN uitzonderingsvlak ON ST_DWithin(uitzonderingsvlak.geom, links.geom, 0.001)
WHERE knopen.aantal_links = 3
      AND (links.wegbehsrt <> 'R' OR (links.wegbehsrt = 'R' AND links.bst_code IN ('AFR', 'OPR', 'VBI')))
      AND (selectie.wegment_id IS NULL OR (selectie.stt_naam <> beginpunt.stt_naam AND selectie.stt_naam <> eindpunt.stt_naam)) 
      AND beginpunt.wegment_id <> eindpunt.wegment_id
	  AND beginpunt.wegment_id IS NOT NULL
	  AND eindpunt.wegment_id IS NOT NULL
	  AND uitzonderingsvlak.geom IS NULL
UNION ALL 
SELECT links.*,
       ST_EndPoint(links.geom) AS geom_node,
	   links.jte_id_end AS node,
	   null::geometry AS geom_buffer_rondom_vertex,
	   null::float AS hoek,
	   0 AS aangepast,
	   beginpunt.wegment_id AS buurman1,
	   eindpunt.wegment_id AS buurman2,
       'eindpunt' AS locatie	   
FROM wegmenten links
LEFT JOIN intersecties knopen ON links.jte_id_end = knopen.knoop
LEFT JOIN wegmenten_gescheiden_rijbanen selectie ON links.wegment_id = selectie.wegment_id
LEFT JOIN wegmenten_gescheiden_rijbanen beginpunt ON links.jte_id_end = beginpunt.jte_id_beg OR links.jte_id_end = beginpunt.jte_id_end
LEFT JOIN wegmenten_gescheiden_rijbanen eindpunt ON links.jte_id_end = eindpunt.jte_id_beg OR links.jte_id_end = eindpunt.jte_id_end
LEFT JOIN uitzonderingsvlak ON ST_DWithin(uitzonderingsvlak.geom, links.geom, 0.001)
WHERE knopen.aantal_links = 3
      AND (links.wegbehsrt <> 'R' OR (links.wegbehsrt = 'R' AND links.bst_code IN ('AFR', 'OPR', 'VBI')))
      AND (selectie.wegment_id IS NULL OR (selectie.stt_naam <> beginpunt.stt_naam AND selectie.stt_naam <> eindpunt.stt_naam)) 
      AND beginpunt.wegment_id <> eindpunt.wegment_id
	  AND beginpunt.wegment_id IS NOT NULL
	  AND eindpunt.wegment_id IS NOT NULL 
	  AND uitzonderingsvlak.geom IS NULL)foo;
	  
UPDATE wegmenten_gescheiden_rijbanen_met_3_links SET geom_buffer_rondom_vertex = ST_Intersection(geom, ST_Buffer(geom_node,0.05)); -- buffer tbv bepalen hoek
UPDATE wegmenten_gescheiden_rijbanen_met_3_links SET hoek = degrees(ST_Azimuth(ST_StartPoint(geom_buffer_rondom_vertex), ST_Endpoint(geom_buffer_rondom_vertex)));

-- SCANLIJNEN MAKEN DIE DOORLOPEN VANAF BEGIN-EINDPUNT
DROP TABLE IF EXISTS wegmenten_gescheiden_rijbanen_met_3_links_scanlijn;
CREATE TABLE wegmenten_gescheiden_rijbanen_met_3_links_scanlijn AS
SELECT *,
       (CASE WHEN locatie = 'beginpunt' THEN 
	    ST_MakeLine(ST_TRANSLATE(geom_node, sin(radians(hoek+180)) * :koude_afstand, cos(radians(hoek+180)) * :koude_afstand),
	    geom_node) 
		ELSE ST_MakeLine(geom_node,
	    ST_TRANSLATE(geom_node, sin(radians(hoek)) * :koude_afstand, cos(radians(hoek)) * :koude_afstand)) 
		END) AS geom_scanlijn
FROM wegmenten_gescheiden_rijbanen_met_3_links;

CREATE INDEX ON wegmenten_gescheiden_rijbanen_met_3_links_scanlijn  USING GIST(geom_scanlijn);

-- SCANLIJNEN INTERSECTEN MET ANDERE GESCHEIDEN RIJBAAN
DROP TABLE IF EXISTS wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect;
CREATE TABLE wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect AS
SELECT scanlijn.*,
       ST_Intersection(scanlijn.geom_scanlijn, links.geom) AS intersectie,
	   ST_Centroid(ST_Union(scanlijn.geom_node, ST_Intersection(scanlijn.geom_scanlijn, links.geom))) AS nieuwe_intersectie,
	   links.wegment_id AS wegment_id_overkant,
	   links.bst_code AS bst_code_overkant
FROM wegmenten_gescheiden_rijbanen_met_3_links_scanlijn scanlijn
LEFT JOIN wegmenten_gescheiden_rijbanen links ON ST_Intersects(scanlijn.geom_scanlijn, links.geom)
WHERE scanlijn.wegment_id <> links.wegment_id
      AND scanlijn.buurman1 <> links.wegment_id
	  AND scanlijn.buurman2 <> links.wegment_id;

CREATE INDEX ON wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect USING GIST(intersectie);
CREATE INDEX ON wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect USING GIST(nieuwe_intersectie);

UPDATE wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect hr
SET nieuwe_intersectie = vbw.nieuwe_intersectie
FROM wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect vbw
WHERE hr.wegment_id = vbw.wegment_id AND vbw.bst_code_overkant IN ('','HR', 'RB') AND hr.bst_code_overkant IN ('VBW', 'PAR', 'VWG');
	  
DROP TABLE IF EXISTS wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect_middelpunt;
CREATE TABLE wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect_middelpunt AS
WITH statistieken AS (SELECT wegment_id,
                             bst_code_overkant,
							 count(*) AS aantal
					  FROM wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect
					  GROUP BY wegment_id, bst_code_overkant)
SELECT wegment_id,
       ST_Union(intersectie) AS intersectie,
	   count(*) AS aantal_intersecties,
	   ST_Centroid(ST_Union(intersectie)) AS nieuwe_intersectie
FROM wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect
WHERE bst_code NOT IN ('VWG', 'PAR')
GROUP BY wegment_id, geom_node;

UPDATE wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect intersects
SET nieuwe_intersectie = meerdere.nieuwe_intersectie
FROM wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect_middelpunt meerdere
WHERE intersects.wegment_id = meerdere.wegment_id AND meerdere.aantal_intersecties > 1;
   
-- INTERSECTIE ID TOEVOEGEN
ALTER TABLE wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect ADD COLUMN intersectie_id SERIAL;

WITH hoogste_knoop AS (SELECT MAX(knoop) AS hoogste_knoop FROM intersecties)
UPDATE wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect
SET intersectie_id  = intersectie_id + hoogste_knoop.hoogste_knoop
FROM hoogste_knoop;	

---------------------------------------------------------------------------------------------------------------
-- WEGMENTEN UPDATEN 
---------------------------------------------------------------------------------------------------------------
-- LINK OVERKANT SPLITSEN 
DROP TABLE IF EXISTS wegmenten_gescheiden_rijbanen_overkant_splits;
CREATE TABLE wegmenten_gescheiden_rijbanen_overkant_splits AS
WITH merge_scanlijnen AS (SELECT wegment_id_overkant,
                                 ST_Union(geom_scanlijn) AS geom_scanlijn
                          FROM wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect
						  GROUP BY wegment_id_overkant)
SELECT links.wegment_id,
       0 AS jte_id_beg,
	   0 AS jte_id_end,
	   links.rijrichtng,
	   links.bst_code,
	   links.rpe_code,
	   links.stt_naam,
	   links.wegbehsrt,
       (ST_Dump(ST_CollectionHomogenize(ST_Split(links.geom, intersects.geom_scanlijn)))).geom AS geom
FROM wegmenten links
LEFT JOIN merge_scanlijnen intersects ON links.wegment_id = intersects.wegment_id_overkant
WHERE intersects.wegment_id_overkant IS NOT NULL;

CREATE INDEX ON wegmenten_gescheiden_rijbanen_overkant_splits USING GIST(geom);

ALTER TABLE wegmenten_gescheiden_rijbanen_overkant_splits ADD COLUMN wegment_id2 SERIAL;

-- WEGMENT_ID INVULLEN
WITH hoogste_id AS (SELECT MAX(wegment_id) AS hoogste_id FROM wegmenten)
UPDATE wegmenten_gescheiden_rijbanen_overkant_splits
SET wegment_id2 = wegment_id2 + hoogste_id.hoogste_id
FROM hoogste_id;

-- KNOPEN BIJWERKEN
UPDATE wegmenten_gescheiden_rijbanen_overkant_splits links 
SET jte_id_beg = nodes.node
FROM wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect nodes
WHERE ST_Equals(ST_StartPoint(links.geom), nodes.intersectie);

UPDATE wegmenten_gescheiden_rijbanen_overkant_splits links 
SET jte_id_end = nodes.node
FROM wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect nodes
WHERE ST_Equals(ST_EndPoint(links.geom), nodes.intersectie);

UPDATE wegmenten_gescheiden_rijbanen_overkant_splits links 
SET jte_id_beg = nodes.knoop
FROM intersecties nodes
WHERE ST_Equals(ST_StartPoint(links.geom), nodes.geom);

UPDATE wegmenten_gescheiden_rijbanen_overkant_splits links 
SET jte_id_end = nodes.knoop
FROM intersecties nodes
WHERE ST_Equals(ST_EndPoint(links.geom), nodes.geom);

-- GESPLITSTE LINKS SAMENVOEGEN MET TUSSENRESULTAAT
DROP TABLE IF EXISTS wegmenten_versimpeld;
CREATE TABLE wegmenten_versimpeld AS
SELECT links.*
FROM wegmenten links
LEFT JOIN wegmenten_gescheiden_rijbanen_overkant_splits splits ON links.wegment_id = splits.wegment_id
WHERE splits.wegment_id IS NULL
UNION ALL
SELECT jte_id_beg,
       jte_id_end,
	   'B' AS rijrichtng,
	   stt_naam,
	   bst_code,
	   rpe_code,
	   wegbehsrt,
	   geom,
	   wegment_id2 AS wegment_id
FROM wegmenten_gescheiden_rijbanen_overkant_splits;

-- WEGMENTEN OVERNEMEN VAN WEGMENTEN VERSIMPELD
DROP TABLE IF EXISTS wegmenten;
CREATE TABLE wegmenten AS
SELECT *
FROM wegmenten_versimpeld;

-- LINKS SNAPPEN NAAR NIEUWE INTERSECTIE
UPDATE wegmenten links
SET geom = ST_SetPoint(links.geom, 0, nodes.nieuwe_intersectie)
FROM wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect nodes
WHERE links.jte_id_beg = nodes.node;
 
UPDATE wegmenten links
SET geom = ST_SetPoint(links.geom, -1, nodes.nieuwe_intersectie)
FROM wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect nodes
WHERE links.jte_id_end = nodes.node;

UPDATE wegmenten links
SET jte_id_beg = nodes.intersectie_id
FROM wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect nodes
WHERE links.jte_id_beg = nodes.node;

UPDATE wegmenten links
SET jte_id_end = nodes.intersectie_id
FROM wegmenten_gescheiden_rijbanen_met_3_links_scanlijn_intersect nodes
WHERE links.jte_id_end = nodes.node;

CREATE INDEX ON wegmenten USING GIST(geom);

---------------------------------------------------------------------------------------------------------------
-- INTERSECTIES UPDATEN 
---------------------------------------------------------------------------------------------------------------
-- FUNCTIE INTERSECTIES GENEREREN AANROEPEN 
SELECT intersecties_genereren();

---------------------------------------------------------------------------------------------------------------
-- WEGMENTEN DISSOLVEN
---------------------------------------------------------------------------------------------------------------
-- FUNCTIE WEGMENTEN DISSOLVEN AANROEPEN
SELECT wegmenten_dissolven('wegment_id2','wegmenten', 'wegmenten_dissolve', 'intersecties');  -- opgeven nieuwe kolonmaam, input tabel en output tabel

---------------------------------------------------------------------------------------------------------------
-- WEGMENTEN SAMENVOEGEN
---------------------------------------------------------------------------------------------------------------
-- FUNCTIE WEGMENTEN ONDERVERDELEN AANROEPEN
-- OUTPUT ZIJN ZELFDE EN NIET ZELFDE WEGMENTEN
-- en dit keer worden relevante verbindingswegen verwijderd (indien deze gelijk zijn aan de hoofdrijbaan)
SELECT wegmenten_onderverdelen('wegmenten_dissolve', 'ja');

-- FUNCTIE DEZELFDE WEGMENTEN SAMENVOEGEN AANROEPEN
-- wegmenten met verschillende bst_codes kunnen ook worden samengevoegd
SELECT dezelfde_wegmenten_samenvoegen('nee');
 	  
---------------------------------------------------------------------------------------------------------------
-- WEGMENTEN UPDATEN 
---------------------------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS wegmenten;
CREATE TABLE wegmenten AS
SELECT jte_id_beg,
	   jte_id_end,
	   'B' AS rijrichtng,
	   stt_naam,
	   bst_code,
	   rpe_code,
	   wegbehsrt,
       geom,
	   wegment_id
FROM wegmenten_zelfde_centerline
UNION ALL
SELECT 
       links.jte_id_beg,
	   links.jte_id_end,
	   links.rijrichtng,
	   links.stt_naam,
	   links.bst_code,
	   links.rpe_code,
	   links.wegbehsrt,
       links.geom,
	   links.wegment_id
FROM wegmenten_niet_zelfde links
LEFT JOIN wegmenten_zelfde_centerline centerline ON links.wegment_id = centerline.wegment_id_zelf OR links.wegment_id = centerline.wegment_id_buurman
WHERE centerline.wegment_id IS NULL
UNION ALL
SELECT DISTINCT
       links.jte_id_beg,
	   links.jte_id_end,
	   links.rijrichtng,
	   links.stt_naam,
	   links.bst_code,
	   links.rpe_code,
	   links.wegbehsrt,
       links.geom,
	   links.wegment_id
FROM wegmenten_zelfde links
LEFT JOIN wegmenten_zelfde_centerline centerline ON links.wegment_id = centerline.wegment_id_zelf OR links.wegment_id = centerline.wegment_id_buurman
WHERE centerline.wegment_id IS NULL;

CREATE INDEX ON wegmenten USING GIST(geom);
CREATE INDEX ON wegmenten USING BTREE(wegment_id);

---------------------------------------------------------------------------------------------------------------
-- WEGMENTEN DISSOLVEN
---------------------------------------------------------------------------------------------------------------
-- FUNCTIE WEGMENTEN DISSOLVEN AANROEPEN
SELECT wegmenten_dissolven('wegment_id2','wegmenten', 'wegmenten_dissolve', 'intersecties');  -- opgeven nieuwe kolonmaam, input tabel en output tabel

---------------------------------------------------------------------------------------------------------------
-- WEGMENTEN SAMENVOEGEN
---------------------------------------------------------------------------------------------------------------
-- FUNCTIE WEGMENTEN ONDERVERDELEN AANROEPEN
-- OUTPUT ZIJN ZELFDE EN NIET ZELFDE WEGMENTEN
-- en dit keer worden relevante verbindingswegen verwijderd (indien deze gelijk zijn aan de hoofdrijbaan)
SELECT wegmenten_onderverdelen('wegmenten_dissolve', 'nee');

-- FUNCTIE DEZELFDE WEGMENTEN SAMENVOEGEN AANROEPEN
-- wegmenten met verschillende bst_codes kunnen ook worden samengevoegd
SELECT dezelfde_wegmenten_samenvoegen('nee');
 	  
---------------------------------------------------------------------------------------------------------------
-- WEGMENTEN UPDATEN 
---------------------------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS wegmenten;
CREATE TABLE wegmenten AS
SELECT jte_id_beg,
	   jte_id_end,
	   'B' AS rijrichtng,
	   stt_naam,
	   bst_code,
	   rpe_code,
	   wegbehsrt,
       geom,
	   wegment_id
FROM wegmenten_zelfde_centerline
UNION ALL
SELECT 
       links.jte_id_beg,
	   links.jte_id_end,
	   links.rijrichtng,
	   links.stt_naam,
	   links.bst_code,
	   links.rpe_code,
	   links.wegbehsrt,
       links.geom,
	   links.wegment_id
FROM wegmenten_niet_zelfde links
LEFT JOIN wegmenten_zelfde_centerline centerline ON links.wegment_id = centerline.wegment_id_zelf OR links.wegment_id = centerline.wegment_id_buurman
WHERE centerline.wegment_id IS NULL
UNION ALL
SELECT DISTINCT
       links.jte_id_beg,
	   links.jte_id_end,
	   links.rijrichtng,
	   links.stt_naam,
	   links.bst_code,
	   links.rpe_code,
	   links.wegbehsrt,
       links.geom,
	   links.wegment_id
FROM wegmenten_zelfde links
LEFT JOIN wegmenten_zelfde_centerline centerline ON links.wegment_id = centerline.wegment_id_zelf OR links.wegment_id = centerline.wegment_id_buurman
WHERE centerline.wegment_id IS NULL;

CREATE INDEX ON wegmenten USING GIST(geom);
CREATE INDEX ON wegmenten USING BTREE(wegment_id);

----------------------------------------------------
-- INTERSECTIES UPDATEN 
----------------------------------------------------
-- FUNCTIE INTERSECTIES GENEREREN AANROEPEN 
SELECT intersecties_genereren();