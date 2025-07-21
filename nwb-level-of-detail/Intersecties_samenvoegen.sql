---------------------------------------------------------------------------------------------------------------
-- INTERSECTIES SAMENVOEGEN 
---------------------------------------------------------------------------------------------------------------

-- OVERZICHT SUB BLOKKEN:
-- 1) ROTONDES VERSIMPELEN
-- 2) INTERSECTIES CLUSTEREN
-- 3) RELEVANTE CLUSTERS DETECTEREN EN NIEUWE INTERSECTIES GENEREREN
-- 4) WEGMENTEN SNAPPEN NAAR NIEUWE INTERSECTIES
-- 5) WEGMENTEN UPDATEN
-- 6) INTERSECTIES UPDATEN
-- 7) KOPPELINGSTABEL UPDATEN

---------------------------------------------------------------------------------------------------------------
-- ROTONDES VERSIMPELEN
---------------------------------------------------------------------------------------------------------------

-- FUNCTIE ROTONDES VERSIMPELEN AANROEPEN
SELECT rotondes_versimpelen();

-----------------------------------------------------------------------------------------------------------------
---- INTERSECTIES CLUSTEREN
-----------------------------------------------------------------------------------------------------------------
---- INTERSECTIES CLUSTERS (VOORSELECTIE)
DROP TABLE IF EXISTS intersecties_selectie;
CREATE TABLE intersecties_selectie AS
SELECT knoop, 
       aantal_links,
	   geom AS geom_knoop,
	   ST_ClusterDBSCAN(geom, :clusterafstand, 2) OVER () AS cluster_id					-- parameter clusterafstand
FROM intersecties 
WHERE aantal_links > 1;

-- INTERSECTIES DIE GEEN ONDERDEEL UITMAKEN VAN CLUSTERS VERWIJDEREN
DELETE FROM intersecties_selectie WHERE cluster_id IS NULL;

-- INTERSECTIES DIE ONDERDEEL UITMAKEN VAN ROTONDES VERWIJDEREN 
DELETE FROM intersecties_selectie 
USING wegmenten 
WHERE (intersecties_selectie.knoop = wegmenten.jte_id_beg AND wegmenten.bst_code IN ('NRB', 'TRB', 'MRB', 'TRB', 'GRB')) 
      OR (intersecties_selectie.knoop = wegmenten.jte_id_end AND wegmenten.bst_code IN ('NRB', 'TRB', 'MRB', 'TRB', 'GRB')); 

-- CLUSTER ID VELD WEER VERWIJDEREN EN INDEX AANMAKEN
ALTER TABLE intersecties_selectie DROP COLUMN IF EXISTS cluster_id;
CREATE INDEX ON intersecties_selectie USING GIST(geom_knoop);

-- FUNCTIE INTERSECTIES CLUSTEREN AANROEPEN
-- maakt gebruik van een parameter clusterafstand 
-- deze parameter wordt in de batch file ingevuld
SELECT intersecties_clusteren(:clusterafstand);

---------------------------------------------------------------------------------------------------------------
-- RELEVANTE CLUSTERS DETECTEREN EN NIEUWE INTERSECTIES GENEREREN
---------------------------------------------------------------------------------------------------------------
-- WEGMENTEN SELECTEREN DIE AAN CLUSTERS VASTZITTEN
DROP TABLE IF EXISTS wegmenten_clusters;
CREATE TABLE wegmenten_clusters AS
SELECT DISTINCT * FROM
(SELECT links.*,
       0 AS fietspaden_naast_hoofdrijbaan,
       intersecties.cluster_id
FROM wegmenten links
LEFT JOIN intersecties_clusters intersecties ON links.jte_id_beg = intersecties.knoop
WHERE intersecties.cluster_id IS NOT NULL
UNION ALL
SELECT links.*,
       0 AS fietspaden_naast_hoofdrijbaan,
       intersecties.cluster_id
FROM wegmenten links
LEFT JOIN intersecties_clusters intersecties ON links.jte_id_end = intersecties.knoop
WHERE intersecties.cluster_id IS NOT NULL)foo; 

-- CODEREN OF ER FIETSPADEN EN NORMALE WEGEN IN ZITTEN MET DEZELDE STRAATNAAM
UPDATE wegmenten_clusters
SET fietspaden_naast_hoofdrijbaan = 1
FROM
	(SELECT A.cluster_id
	 FROM wegmenten_clusters A, wegmenten_clusters B 
	 WHERE A.cluster_id = B.cluster_id 
		AND A.wegment_id <> B.wegment_id
		AND A.bst_code = 'FP' 
		AND B.bst_code NOT IN ('FP', 'VP'))foo
WHERE wegmenten_clusters.cluster_id = foo.cluster_id;	   

-- STATISTIEKEN GENEREREN
-- ALLE LINKS
DROP TABLE IF EXISTS wegmenten_clusters_statistieken;
CREATE TABLE wegmenten_clusters_statistieken AS
SELECT cluster_id,
       count(*) AS aantal,
       ST_Union(geom) AS geom	   
FROM wegmenten_clusters 
GROUP BY cluster_id;
 
-- ALLE LINKS MET RPE_CODE OF EENRICHTINGSLINK OF MET COMBINATIE VAN FIETSPAD/GEEN_FIETSPAD
DROP TABLE IF EXISTS wegmenten_clusters_relevant;
CREATE TABLE wegmenten_clusters_relevant AS
SELECT cluster_id, 
       jte_id_beg,
	   jte_id_end,
	   bst_code,
       geom 
FROM wegmenten_clusters 
WHERE (rpe_code <> '#' OR rpe_code IN ('L', 'R', 'N', 'O', 'W', 'Z')) OR (rijrichtng = 'H') OR fietspaden_naast_hoofdrijbaan = 1;

DROP TABLE IF EXISTS wegmenten_clusters_statistieken_relevant;
CREATE TABLE wegmenten_clusters_statistieken_relevant AS
SELECT cluster_id, 
       count(*) AS aantal,
       ST_Union(geom) AS geom 
FROM wegmenten_clusters_relevant 
GROUP BY cluster_id;

-- DETECTEREN OF BIJ DE RELEVANTE WEGMENTEN OF ER WEL VERSCHIL ZIT IN DE RPE_CODE (BIJV. L/R OF N/Z OF W/O)
DROP TABLE IF EXISTS wegmenten_clusters_statistieken_relevant_group;
CREATE TABLE wegmenten_clusters_statistieken_relevant_group AS
SELECT cluster_id,
	   count(*) AS aantal_group,
	   rpe_code,
	   ST_Union(geom) AS geom 
FROM wegmenten_clusters 
WHERE (rpe_code <> '#' OR rpe_code IN ('L', 'R', 'N', 'O', 'W', 'Z')) OR (rijrichtng = 'H')
GROUP BY cluster_id, rpe_code;

DROP TABLE IF EXISTS wegmenten_clusters_statistieken_relevant_group_ss;
CREATE TABLE wegmenten_clusters_statistieken_relevant_group_ss AS
SELECT count(*) AS aantal,
       cluster_id
FROM wegmenten_clusters_statistieken_relevant_group
GROUP BY cluster_id;

-- STATISTIEKEN TERUGKOPPELEN EN CLUSTERS SELECTEREN MET MINIMAAL 3 LINKS MET RPE_CODE OF EENRICHTING EN VARIATIE IN RPE_CODE
DROP TABLE IF EXISTS intersecties_clusters_relevant;
CREATE TABLE intersecties_clusters_relevant AS
SELECT clusters.*,
       statistieken1.aantal AS aantal_links_in_cluster,
	   statistieken2.aantal AS aantal_relevante_links_in_cluster,
	   statistieken3.aantal AS variatie_rpe_code
FROM intersecties_clusters clusters
LEFT JOIN wegmenten_clusters wegmenten USING (cluster_id)
LEFT JOIN wegmenten_clusters_statistieken statistieken1 USING (cluster_id)
LEFT JOIN wegmenten_clusters_statistieken_relevant statistieken2 USING (cluster_id)
LEFT JOIN wegmenten_clusters_statistieken_relevant_group_ss statistieken3 USING (cluster_id)
WHERE clusters.aantal_links > 2
      AND (((clusters.cluster_id IS NOT NULL)
	      AND statistieken2.aantal > 2 
	      AND statistieken3.aantal > 1)
		  OR (wegmenten.fietspaden_naast_hoofdrijbaan = 1));

-- INTERSECTIES BIJ RELEVANTE CLUSTERS GENEREREN
-- fietspaden buiten beschouwing laten zodat nieuwe intersectie bij de auto rijbanen komt
DROP TABLE IF EXISTS nieuwe_intersecties;
CREATE TABLE nieuwe_intersecties AS
SELECT intersecties.cluster_id,
       intersecties.aantal_links_in_cluster,
	   intersecties.aantal_relevante_links_in_cluster,
	   intersecties.variatie_rpe_code,
	   ST_Centroid(ST_Union(intersecties.geom)) AS geom,
       ST_Buffer(ST_ConvexHull(ST_Union(intersecties.geom)),1) AS geom_envelop   
FROM intersecties_clusters_relevant intersecties
LEFT JOIN wegmenten_clusters_relevant selectie ON intersecties.knoop = selectie.jte_id_beg OR intersecties.knoop = selectie.jte_id_end
WHERE selectie.geom IS NOT NULL AND selectie.bst_code <> 'FP'
GROUP BY intersecties.cluster_id, intersecties.aantal_links_in_cluster, intersecties.aantal_relevante_links_in_cluster, intersecties.variatie_rpe_code;

-- MIDDELPUNTEN TERUGKOPPELEN NAAR BESTAANDE NODES
DROP TABLE IF EXISTS nieuwe_intersecties_inclusief_oude_node;
CREATE TABLE nieuwe_intersecties_inclusief_oude_node AS
SELECT clusters.*,
       intersecties.geom AS geom_intersectie
FROM intersecties_clusters clusters
LEFT JOIN nieuwe_intersecties intersecties ON clusters.cluster_id = intersecties.cluster_id
WHERE intersecties.cluster_id IS NOT NULL;

-- MIDDELPUNTEN OVERSCHRIJVEN ALS EEN ROTONDE AANWEZIG IS IN HET CLUSTER
-- DAN IS DE ROTONDE HET MIDDELPUNT
UPDATE nieuwe_intersecties_inclusief_oude_node node
SET geom_intersectie = rotonde.geom
FROM (SELECT intersecties.knoop,
             intersecties.geom,
			 intersecties.cluster_id
	 FROM nieuwe_intersecties_inclusief_oude_node intersecties
	 LEFT JOIN rotondes_nodes_middelpunt rotondes ON intersecties.knoop = rotondes.intersectie_id
	 WHERE rotondes.intersectie_id IS NOT NULL)rotonde
WHERE node.cluster_id = rotonde.cluster_id;

-- NIEUWE INTERSECTIES VERWIJDEREN INDIEN DEZE NIET AANGEPAST MOGEN WORDEN (UITZONDERINGSGEBIED)
DELETE FROM nieuwe_intersecties_inclusief_oude_node nieuw
USING (SELECT DISTINCT cluster_id 
       FROM nieuwe_intersecties_inclusief_oude_node nieuw 
	   LEFT JOIN knopen_studiegebied_uitgezonderd uitzonderen ON nieuw.knoop = uitzonderen.knoop
	   WHERE uitzonderen.knoop IS NOT NULL)foo
WHERE nieuw.cluster_id = foo.cluster_id;

---------------------------------------------------------------------------------------------------------------
-- WEGMENTEN SNAPPEN NAAR NIEUWE INTERSECTIES
---------------------------------------------------------------------------------------------------------------
-- WEGMENTEN SELECTEREN DIE GEHEEL IN CLUSTER LIGGEN
DROP TABLE IF EXISTS wegmenten_geheel_in_cluster;
CREATE TABLE wegmenten_geheel_in_cluster AS
SELECT links.*,
       cluster_begin.cluster_id AS knoop
FROM wegmenten links
LEFT JOIN nieuwe_intersecties_inclusief_oude_node cluster_begin ON links.jte_id_beg = cluster_begin.knoop
LEFT JOIN nieuwe_intersecties_inclusief_oude_node cluster_eind ON links.jte_id_end = cluster_eind.knoop
WHERE cluster_begin.cluster_id = cluster_eind.cluster_id;

-- WEGMENTEN SELECTEREN DIE AAN 1 ZIJDE DOODLOPEN ZIJN EN AAN ANDERE KANT AAN WEGMENT VAST ZIT DIE GEHEEL IN CLUSTER LIGT
DROP TABLE IF EXISTS wegmenten_doodlopend_uiteinde_cluster;
CREATE TABLE wegmenten_doodlopend_uiteinde_cluster AS
SELECT links.*,
       wegment_in_cluster.knoop
FROM wegmenten links
LEFT JOIN wegmenten_geheel_in_cluster wegment_in_cluster ON links.jte_id_end = wegment_in_cluster.jte_id_beg OR links.jte_id_end = wegment_in_cluster.jte_id_end
LEFT JOIN intersecties intersecties ON links.jte_id_beg = intersecties.knoop
WHERE intersecties.aantal_links = 1 AND wegment_in_cluster.wegment_id IS NOT NULL 
UNION ALL  
SELECT links.*,
       wegment_in_cluster.knoop
FROM wegmenten links
LEFT JOIN wegmenten_geheel_in_cluster wegment_in_cluster ON links.jte_id_beg = wegment_in_cluster.jte_id_beg OR links.jte_id_beg = wegment_in_cluster.jte_id_end
LEFT JOIN intersecties intersecties ON links.jte_id_end = intersecties.knoop
WHERE intersecties.aantal_links = 1 AND wegment_in_cluster.wegment_id IS NOT NULL;

-- WEGMENTEN VERWIJDEREN DIE GEHEEL IN CLUSTER LIGGEN
DELETE FROM wegmenten links
USING wegmenten_geheel_in_cluster wegment_in_cluster
WHERE links.wegment_id = wegment_in_cluster.wegment_id;

-- DOODLOPENDE WEGMENTEN VERWIJDEREN DIE VASTZITTEN AAN WEGVAK DIE GEHEEL IN CLUSTER VALT
DELETE FROM wegmenten links
USING wegmenten_doodlopend_uiteinde_cluster wegment_doodlopend_in_cluster
WHERE links.wegment_id = wegment_doodlopend_in_cluster.wegment_id;

-- TOE- EN AFLEIDENDE WEGMENTEN VERLENGEN NAAR NIEUWE INTERSECTIE 
DROP TABLE IF EXISTS wegmenten_verlengd;
CREATE TABLE wegmenten_verlengd AS
SELECT wegment_id,
       (CASE WHEN intersectie_begin.knoop IS NULL THEN links.jte_id_beg
	   ELSE intersectie_begin.cluster_id
	   END) AS jte_id_beg,
	   (CASE WHEN intersectie_eind.knoop IS NULL THEN links.jte_id_end
	   ELSE intersectie_eind.cluster_id
	   END) AS jte_id_end,
       rijrichtng,
	   bst_code,
	   rpe_code,
	   stt_naam,
	   wegbehsrt,
	   (CASE WHEN intersectie_begin.knoop IS NULL AND intersectie_eind.knoop IS NULL THEN links.geom
        WHEN intersectie_begin.knoop IS NOT NULL AND intersectie_eind.knoop IS NULL THEN ST_LineMerge(ST_Union(ST_ShortestLine(intersectie_begin.geom_intersectie, ST_StartPoint(links.geom)), links.geom))
        WHEN intersectie_begin.knoop IS NULL AND intersectie_eind.knoop IS NOT NULL THEN ST_LineMerge(ST_Union(links.geom, ST_ShortestLine(ST_EndPoint(links.geom), intersectie_eind.geom_intersectie)))
        WHEN intersectie_begin.knoop IS NOT NULL AND intersectie_eind.knoop IS NOT NULL THEN ST_LineMerge(ST_Union(ST_Union(ST_ShortestLine(intersectie_begin.geom_intersectie, ST_StartPoint(links.geom)), links.geom), ST_ShortestLine(ST_EndPoint(links.geom), intersectie_eind.geom_intersectie)))
	    END) AS geom
FROM wegmenten links
LEFT JOIN nieuwe_intersecties_inclusief_oude_node intersectie_begin ON links.jte_id_beg = intersectie_begin.knoop
LEFT JOIN nieuwe_intersecties_inclusief_oude_node intersectie_eind ON links.jte_id_end = intersectie_eind.knoop;

CREATE INDEX ON wegmenten_verlengd USING GIST(geom);
CREATE INDEX ON wegmenten_verlengd USING BTREE(wegment_id);

UPDATE wegmenten_verlengd 
SET geom = ST_LineMerge(ST_Simplify(geom, 10))
WHERE ST_GeometryType(geom) = 'ST_MultiLineString';

DELETE FROM wegmenten_verlengd WHERE ST_GeometryType(geom) = 'ST_MultiLineString';

-- VORMPUNTEN GENEREREN VAN VERLENGDE WEGEN
DROP TABLE IF EXISTS wegmenten_verlengd_vormpunten;
CREATE TABLE wegmenten_verlengd_vormpunten AS
SELECT wegment_id, 
       jte_id_beg, 
	   jte_id_end, 
	   rijrichtng, 
	   stt_naam, 
	   bst_code, 
	   rpe_code, 
	   wegbehsrt, 
	   (ST_DumpPoints(geom)).geom AS geom_vertices,
	   ST_LineLocatePoint(geom,(ST_DumpPoints(geom)).geom) AS fractie
FROM wegmenten_verlengd;

CREATE INDEX ON wegmenten_verlengd_vormpunten USING GIST(geom_vertices);

-- EEN UNIEK ID TOEVOEGEN 
-- nodig voor de volgende stap (ivm statistieken)
ALTER TABLE wegmenten_verlengd_vormpunten ADD COLUMN tijdelijk_id SERIAL;

-- INDIEN WEGMENT EEN RONDJE IS DAN ZORGEN DAT ER OOK EEN VORPMUNT MET FRACTIE 1 VOORKOMT
-- er komen nu namelijk twee vormpunten met fractie 0 voor (feitelijk zijn dit het begin- en eindpunt)
WITH loops AS 	(SELECT wegment_id, 
				COUNT(*),
				MAX(tijdelijk_id) AS max_tijdelijk_id
				FROM wegmenten_verlengd_vormpunten 
				WHERE jte_id_beg = jte_id_end AND fractie = 0 
				GROUP BY wegment_id)
UPDATE wegmenten_verlengd_vormpunten vormpunten
SET fractie = 1
FROM loops
WHERE vormpunten.wegment_id = loops.wegment_id 
      AND vormpunten.tijdelijk_id = loops.max_tijdelijk_id;

-- VORMPUNTEN VERWIJDEREN DIE IN CONVEX HULL VALLEN VAN INTERSECTIES
DELETE FROM wegmenten_verlengd_vormpunten vormpunten
USING nieuwe_intersecties intersecties
WHERE ST_Intersects(vormpunten.geom_vertices, intersecties.geom_envelop) AND vormpunten.fractie NOT IN (0,1);

---------------------------------------------------------------------------------------------------------------
-- WEGMENTEN UPDATEN
---------------------------------------------------------------------------------------------------------------
-- BESTAANDE WEGMENTEN OVERSCHRIJVEN MET VERLENGDE WEGMENTEN
DROP TABLE IF EXISTS wegmenten;
CREATE TABLE wegmenten AS
SELECT jte_id_beg, 
	   jte_id_end, 
	   rijrichtng,
	   stt_naam, 
	   bst_code, 
	   rpe_code, 
	   wegbehsrt,
	   ST_MakeLine(geom_vertices ORDER BY fractie) AS geom,
	   wegment_id
FROM  (SELECT wegment_id, 
              jte_id_beg, 
	          jte_id_end, 
	          rijrichtng, 
	          bst_code, 
	          rpe_code, 
	          stt_naam, 
	          wegbehsrt,
			  fractie,
			  geom_vertices
	   FROM wegmenten_verlengd_vormpunten
	   ORDER BY wegment_id, fractie)foo
GROUP BY wegment_id, jte_id_beg, jte_id_end, rijrichtng, bst_code, rpe_code, stt_naam, wegbehsrt;

---------------------------------------------------------------------------------------------------------------
-- INTERSECTIES UPDATEN
---------------------------------------------------------------------------------------------------------------
-- FUNCTIE INTERSECTIES GENEREREN AANROEPEN 
SELECT intersecties_genereren();

---------------------------------------------------------------------------------------------------------------
-- KOPPELINGSTABEL UPDATEN
---------------------------------------------------------------------------------------------------------------
-- UPDATEN WEGMENTEN DIE GEHEEL BINNEN CLUSTER LIGGEN 
UPDATE koppelingstabel_wegvakken_wegmenten_juncties_intersecties koppeling
SET intersectie_beg = wegment_in_cluster.knoop,
    intersectie_end = wegment_in_cluster.knoop,
    wegment_id = 0
FROM wegmenten_geheel_in_cluster wegment_in_cluster
WHERE koppeling.wegment_id = wegment_in_cluster.wegment_id;

-- UPDATEN DOODLOPENDE WEGMENTEN BINNEN EEN CLUSTER
UPDATE koppelingstabel_wegvakken_wegmenten_juncties_intersecties koppeling
SET intersectie_beg = uiteinde_cluster.knoop,
    intersectie_end = uiteinde_cluster.knoop,
    wegment_id = 0
FROM wegmenten_doodlopend_uiteinde_cluster uiteinde_cluster
WHERE koppeling.wegment_id = uiteinde_cluster.wegment_id;

-- UPDATEN WEGMENTEN DIE ZIJN VERLENGD
UPDATE koppelingstabel_wegvakken_wegmenten_juncties_intersecties koppeling
SET wegment_id = verlengd.wegment_id,
    intersectie_beg = verlengd.jte_id_beg,
	intersectie_end = verlengd.jte_id_end
FROM wegmenten verlengd
WHERE koppeling.wegment_id = verlengd.wegment_id;