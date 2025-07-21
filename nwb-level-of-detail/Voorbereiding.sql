---------------------------------------------------------------------------------------------------------------
-- VOORBEREIDING WEGVAKKEN ALGEMEEN
---------------------------------------------------------------------------------------------------------------

-- OVERZICHT SUB BLOKKEN:
-- 1) WEGVAKKEN STUDIEGEBIED
-- 2) FILTEREN OP UITZONDERINGEN
-- 3) KNOPEN GENEREREN EN WEGVAKKEN GEOMETRISCH SNAPPEN 
-- 4) WEGMENTEN GENEREREN
-- 5) INTERSECTIES GENEREREN
-- 6) KOPPELINGSTABEL WEGVAKKEN EN WEGMENTEN EN INTERSECTIES
-- 7) KOPPELINGSTABEL UPDATEN

---------------------------------------------------------------------------------------------------------------
-- WEGVAKKEN STUDIEGEBIED
---------------------------------------------------------------------------------------------------------------
-- STUDIEGEBIED SELECTEREN O.B.V. GEMEENTENAAM
DROP TABLE IF EXISTS wegvakken_studiegebied;
CREATE TABLE wegvakken_studiegebied AS
SELECT *,
	   0 AS links_begin,
	   0 AS links_eind,
	   0 AS samenvoegen,
	   0 AS dissolve_id
FROM  wegvakken
WHERE gme_naam IN (:gemeenten)														-- parameter gemeenten
      AND bst_code NOT IN (:bst_codes_niet_meenemen);								-- parameter bst_codes_niet_meenemen

CREATE INDEX ON wegvakken_studiegebied USING GIST(geom);
		 
-- BST CODE NULL OP '' ZETTEN 
UPDATE wegvakken_studiegebied SET bst_code = '' WHERE bst_code IS NULL;

---------------------------------------------------------------------------------------------------------------
-- FILTEREN OP UITZONDERINGEN
---------------------------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS wegvakken_studiegebied_uitgezonderd;
CREATE TABLE wegvakken_studiegebied_uitgezonderd AS
SELECT DISTINCT wegvakken_studiegebied.* 
FROM wegvakken_studiegebied 
LEFT JOIN uitzonderingsvlak ON ST_Within(wegvakken_studiegebied.geom, uitzonderingsvlak.geom)
WHERE uitzonderingsvlak IS NOT NULL;

---------------------------------------------------------------------------------------------------------------
-- KNOPEN GENEREREN EN WEGVAKKEN GEOMETRISCH SNAPPEN 
---------------------------------------------------------------------------------------------------------------
-- KNOPEN ANALYSE OM WEGVAKKEN GEOMETRISCH TE OPTIMALISEREN
DROP TABLE IF EXISTS knopen_statistieken;
CREATE TABLE knopen_statistieken AS
SELECT knoop,
       sum(aantal) AS aantal_links,
	   0.0::DOUBLE PRECISION  AS x_coordinaat,
	   0.0::DOUBLE PRECISION  AS y_coordinaat   
FROM (SELECT jte_id_beg AS knoop,
             count(jte_id_beg) AS aantal
	  FROM wegvakken_studiegebied
	  GROUP BY jte_id_beg
	  UNION ALL
      SELECT jte_id_end AS knoop,
             count(jte_id_end) AS aantal
	  FROM wegvakken_studiegebied
	  GROUP BY jte_id_end)foo
GROUP BY foo.knoop;

-- COORDINATEN TOEVOEGEN
UPDATE knopen_statistieken knopen
SET x_coordinaat = (CASE when links.jte_id_beg = knopen.knoop THEN ST_X(ST_StartPoint(geom))
					ELSE ST_X(ST_EndPoint(geom))
					END),
	y_coordinaat = (CASE when links.jte_id_beg = knopen.knoop THEN ST_Y(ST_StartPoint(geom))
					ELSE ST_Y(ST_EndPoint(geom))
					END)			
FROM wegvakken_studiegebied links
WHERE knopen.knoop = links.jte_id_beg OR knopen.knoop = links.jte_id_end;

UPDATE knopen_statistieken knopen
SET x_coordinaat = ST_X(ST_StartPoint(geom)),
	y_coordinaat = ST_Y(ST_StartPoint(geom))		
FROM wegvakken_studiegebied links
WHERE knopen.knoop = links.jte_id_beg;

UPDATE knopen_statistieken knopen
SET x_coordinaat = ST_X(ST_EndPoint(geom)),
	y_coordinaat = ST_Y(ST_EndPoint(geom))		
FROM wegvakken_studiegebied links
WHERE knopen.knoop = links.jte_id_end;

-- INTERSECTIES MET GEOMETRIE GENEREREN
DROP TABLE IF EXISTS knopen;
CREATE TABLE knopen AS
SELECT knoop,
       aantal_links,
	   ST_MakePoint(x_coordinaat, y_coordinaat)::geometry(Point,28992) AS geom
FROM knopen_statistieken;

CREATE INDEX ON knopen USING GIST(geom);

-- OOK WEGVAKKEN GOED SNAPPEN (SOMS ZIJN ER KLEINE VERSCHILLEN)
UPDATE wegvakken_studiegebied links
SET geom = ST_SetPoint(links.geom, 0, knopen.geom)
FROM knopen knopen 
WHERE links.jte_id_beg = knopen.knoop;
 
UPDATE wegvakken_studiegebied links
SET geom = ST_SetPoint(links.geom, -1, knopen.geom)
FROM knopen knopen 
WHERE links.jte_id_end = knopen.knoop;

CREATE INDEX ON wegvakken_studiegebied USING GIST(geom);

-- FILTEREN WELKE KNOPEN NIET AANGEPAST MOGEN WORDEN 
DROP TABLE IF EXISTS knopen_studiegebied_uitgezonderd;
CREATE TABLE knopen_studiegebied_uitgezonderd AS
SELECT DISTINCT knopen.*
FROM knopen 
LEFT JOIN wegvakken_studiegebied_uitgezonderd beginknoop ON knopen.knoop = beginknoop.jte_id_beg
LEFT JOIN wegvakken_studiegebied_uitgezonderd eindknoop ON knopen.knoop = eindknoop.jte_id_end
WHERE beginknoop.jte_id_beg IS NOT NULL OR eindknoop.jte_id_end IS NOT NULL;

---------------------------------------------------------------------------------------------------------------
-- WEGMENTEN GENEREREN
---------------------------------------------------------------------------------------------------------------
-- FUNCTIE WEGMENTEN DISSOLVEN AANROEPEN
SELECT wegmenten_dissolven('wegment_id','wegvakken_studiegebied', 'wegmenten', 'knopen');  -- opgeven nieuwe kolonmaam en tabel

---------------------------------------------------------------------------------------------------------------
-- INTERSECTIES GENEREREN
---------------------------------------------------------------------------------------------------------------
-- FUNCTIE INTERSECTIES GENEREREN AANROEPEN 
SELECT intersecties_genereren();

---------------------------------------------------------------------------------------------------------------
-- KOPPELINGSTABEL WEGVAKKEN EN WEGMENTEN EN JUNCTIES EN INTERSECTIES
---------------------------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS koppelingstabel_wegvakken_wegmenten_juncties_intersecties;
CREATE TABLE koppelingstabel_wegvakken_wegmenten_juncties_intersecties AS
SELECT wvk_id,
       wvk_id AS wegment_id,
	   jte_id_beg,
	   jte_id_end,
	   jte_id_beg AS intersectie_beg,
	   jte_id_end AS intersectie_end,
	   geom AS wvk_geom
FROM wegvakken_studiegebied;

---------------------------------------------------------------------------------------------------------------
-- KOPPELINGSTABEL UPDATEN
---------------------------------------------------------------------------------------------------------------
UPDATE koppelingstabel_wegvakken_wegmenten_juncties_intersecties koppeling
SET wegment_id = wegment.wegment_id,
    intersectie_beg = wegment.jte_id_beg,
	intersectie_end = wegment.jte_id_end
FROM wegmenten wegment
WHERE ST_DWithin(ST_LineInterpolatePoint(koppeling.wvk_geom,0.5), wegment.geom, 0.1);