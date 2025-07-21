---------------------------------------------------------------------------------------------------------------
-- FUNCTIES
---------------------------------------------------------------------------------------------------------------

-- OVERZICHT FUNCTIES:
-- (1) WEGMENTEN DISSOLVEN 
-- (2) INTERSECTIES GENEREREN
-- (3) ROTONDES VERSIMPELEN
-- (4) INTERSECTIES CLUSTEREN
-- (5) WEGMENTEN ONDERVERDELEN
-- (6) VERWIJDEREN VAN FIETSPADEN LANGS HOOFDRIJBAAN
-- (7) DEZELFDE WEGMENTEN SAMENVOEGEN

---------------------------------------------------------------------------------------------------------------
-- (1) WEGMENTEN DISSOLVEN
---------------------------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS wegmenten_dissolven(text, text, text, text);
CREATE FUNCTION wegmenten_dissolven(kolomnaam text, tabelnaam_input text, tabelnaam_output text, tabelnaam_intersecties text) RETURNS void AS $$
BEGIN

	-- WEGMENTEN DISSOLVEN DOOR MIDDEL VAN DYNAMISCHE SQL VANWEGE PARAMETER
	IF kolomnaam = 'wegment_id' 
		THEN 
			EXECUTE format('
			DROP TABLE IF EXISTS %I;
			CREATE TABLE %I AS
			SELECT 0::NUMERIC AS jte_id_beg,
				0::NUMERIC AS jte_id_end,
				''?'' AS rijrichtng,
				''?'' AS stt_naam,
				''?'' AS bst_code,
				''?'' AS rpe_code,
				''?'' AS wegbehsrt,
				(ST_Dump(ST_LineMerge(ST_Collect(geom)))).geom AS geom 
			FROM %I;', tabelnaam_output, tabelnaam_output, tabelnaam_input);
		ELSE 
			EXECUTE format('
			DROP TABLE IF EXISTS %I;
			CREATE TABLE %I AS
			SELECT 0::NUMERIC AS jte_id_beg,
				0::NUMERIC AS jte_id_end,
				''?'' AS rijrichtng,
				''?'' AS stt_naam,
				''?'' AS bst_code,
				''?'' AS rpe_code,
				''?'' AS wegbehsrt,
				(ST_Dump(ST_LineMerge(ST_Collect(geom)))).geom AS geom,
				0::NUMERIC AS wegment_id
			FROM %I;', tabelnaam_output, tabelnaam_output, tabelnaam_input);		
	 END IF;
	
	-- EXTRA KOLOM AANMAKEN DOOR MIDDEL VAN DYNAMISCHE SQL VANWEGE PARAMETER
	EXECUTE format('
	ALTER TABLE %I ADD COLUMN %I SERIAL', tabelnaam_output, kolomnaam);
	
	-- INDEXES AANMAKEN DOOR MIDDEL VAN (DEELS) DYNAMISCHE SQL VANWEGE PARAMETER
	EXECUTE format('
	CREATE INDEX ON %I USING GIST(geom)', tabelnaam_output);
	EXECUTE format('
	CREATE INDEX ON %I USING BTREE(%I)',tabelnaam_output, kolomnaam);
	
	-- DIT GEDEELTE ALLEEN UITVOEREN MET KOLOMNAAM WEGMENT_ID2
	IF kolomnaam = 'wegment_id2' THEN
        -- WEGMENT ID TERUGKOPPELEN ALS DE GEOMETRIE ONGEWIJZIGD IS
		EXECUTE format('
        UPDATE %I dissolve
        SET wegment_id = origineel.wegment_id
        FROM %I origineel
        WHERE ST_Equals(dissolve.geom, origineel.geom);',tabelnaam_output, tabelnaam_input);

        -- WEGMENT ID INVULLEN INDIEN DEZE NOG 0 IS
		EXECUTE format('
        WITH hoogste_id AS (SELECT MAX(wegment_id) AS hoogste_id FROM %I)
        UPDATE %I dissolve
        SET wegment_id = wegment_id2 + hoogste_id.hoogste_id
        FROM hoogste_id
        WHERE wegment_id = 0;',tabelnaam_output, tabelnaam_output);
    END IF;
	
	-- RELEVANTE INFORMATIE WEER TERUGKOPPELEN VANUIT ORIGINEEL DOOR MIDDEL VAN DYNAMISCHE SQL VANWEGE PARAMETER
	-- rijrichtng, stt_naam, bst_code, rpe_code en wegbehsrt  
	EXECUTE format('
	UPDATE %I dissolve
	SET rijrichtng = origineel.rijrichtng,
		stt_naam = origineel.stt_naam,
		bst_code = origineel.bst_code,	
		rpe_code = origineel.rpe_code,
		wegbehsrt = origineel.wegbehsrt
	FROM %I origineel
	WHERE ST_DWithin(ST_LineInterpolatePoint(dissolve.geom, 0.5), origineel.geom, 0.1);', tabelnaam_output, tabelnaam_input);

	-- KNOPEN TOEKENEN AAN DISSOLVE 
	EXECUTE format('
	UPDATE %I dissolve
	SET jte_id_beg = knopen.knoop
	FROM %I knopen
	WHERE ST_DWithin(ST_StartPoint(dissolve.geom), knopen.geom, 0.1);', tabelnaam_output, tabelnaam_intersecties);

	EXECUTE format('	
	UPDATE %I dissolve
	SET jte_id_end = knopen.knoop
	FROM %I knopen
	WHERE ST_DWithin(ST_EndPoint(dissolve.geom), knopen.geom, 0.1);', tabelnaam_output, tabelnaam_intersecties);
	
END;
$$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------------
-- (2) INTERSECTIES GENEREREN
---------------------------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS intersecties_genereren();
CREATE FUNCTION intersecties_genereren() RETURNS void AS $$
BEGIN

	-- AANTAL LINKS PER KNOOP ANALYSEREN
	DROP TABLE IF EXISTS intersecties_statistieken;
	CREATE TABLE intersecties_statistieken AS
	SELECT knoop,
		sum(aantal) AS aantal_links,
		0.0::DOUBLE PRECISION  AS x_coordinaat,
		0.0::DOUBLE PRECISION  AS y_coordinaat   
	FROM (SELECT jte_id_beg AS knoop,
				count(jte_id_beg) AS aantal
		FROM wegmenten
		GROUP BY jte_id_beg
		UNION ALL
		SELECT jte_id_end AS knoop,
				count(jte_id_end) AS aantal
		FROM wegmenten
		GROUP BY jte_id_end)foo
	GROUP BY foo.knoop;
	
	-- COORDINATEN TOEVOEGEN
	UPDATE intersecties_statistieken intersecties
	SET x_coordinaat = (CASE when links.jte_id_beg = intersecties.knoop THEN ST_X(ST_StartPoint(geom))
						ELSE ST_X(ST_EndPoint(geom))
						END),
		y_coordinaat = (CASE when links.jte_id_beg = intersecties.knoop THEN ST_Y(ST_StartPoint(geom))
						ELSE ST_Y(ST_EndPoint(geom))
						END)			
	FROM wegmenten links
	WHERE intersecties.knoop = links.jte_id_beg OR intersecties.knoop = links.jte_id_end;
	
	UPDATE intersecties_statistieken intersecties
	SET x_coordinaat = ST_X(ST_StartPoint(geom)),
		y_coordinaat = ST_Y(ST_StartPoint(geom))		
	FROM wegmenten links
	WHERE intersecties.knoop = links.jte_id_beg;
	
	UPDATE intersecties_statistieken intersecties
	SET x_coordinaat = ST_X(ST_EndPoint(geom)),
		y_coordinaat = ST_Y(ST_EndPoint(geom))		
	FROM wegmenten links
	WHERE intersecties.knoop = links.jte_id_end;
	
	-- INTERSECTIE MET GEOMETRIE GENEREREN
	DROP TABLE IF EXISTS intersecties;
	CREATE TABLE intersecties AS
	SELECT knoop,
		aantal_links, 
		ST_MakePoint(x_coordinaat, y_coordinaat)::geometry(Point,28992) AS geom
	FROM intersecties_statistieken;
	
	CREATE INDEX ON intersecties USING GIST(geom);
	CREATE INDEX ON intersecties USING BTREE(knoop);

END;
$$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------------
-- (3) ROTONDES VERSIMPELEN
---------------------------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS rotondes_versimpelen();
CREATE FUNCTION rotondes_versimpelen() RETURNS void AS $$
BEGIN

    -- MIDDELPUNTEN EN VLAKKEN GENEREREN BIJ ROTONDES
    DROP TABLE IF EXISTS rotondes;
    CREATE TABLE rotondes AS
    SELECT  ST_Centroid((ST_Dump(ST_Polygonize(geom))).geom) AS middelpunt,
            (ST_Dump(ST_Polygonize(geom))).geom AS geom_vlak
    FROM wegmenten
    WHERE bst_code IN ('NRB', 'MRB', 'TRB', 'GRB');
    
    -- UNIEK ID TOEVOEGEN DIE VERDER GAAT BIJ HOOGSTE KNOOP
    ALTER TABLE rotondes ADD COLUMN intersectie_id SERIAL;

    WITH hoogste_knoop AS (SELECT MAX(knoop) AS hoogste_knoop FROM intersecties)
    UPDATE rotondes
    SET intersectie_id = intersectie_id + hoogste_knoop.hoogste_knoop
    FROM hoogste_knoop;

    -- NODES GENEREREN VAN ROTONDELINKS
    DROP TABLE IF EXISTS rotondes_nodes;
    CREATE TABLE rotondes_nodes AS
    SELECT  jte_id_beg AS node,
            ST_StartPoint(geom) AS geom
    FROM wegmenten
    WHERE bst_code IN ('NRB', 'MRB', 'TRB', 'GRB')
    UNION ALL
    SELECT  jte_id_end AS node,
            ST_EndPoint(geom) AS geom
    FROM wegmenten
    WHERE bst_code IN ('NRB', 'MRB', 'TRB', 'GRB');

    -- INFORMATIE VAN MIDDELPUNT TOEVOEGEN AAN NODES ROTONDELINKS
    DROP TABLE IF EXISTS rotondes_nodes_middelpunt;
    CREATE TABLE rotondes_nodes_middelpunt AS
    SELECT DISTINCT nodes.node,
                    middelpunt.middelpunt AS geom,
                    middelpunt.intersectie_id
    FROM rotondes_nodes nodes
    LEFT JOIN rotondes middelpunt ON ST_DWithin(nodes.geom, middelpunt.geom_vlak, 1)
    WHERE middelpunt.geom_vlak IS NOT NULL;
	
    -- ROTONDELINKS VERWIJDEREN INDIEN EEN MIDDELPUNT IS GEGENEREERT
    DELETE FROM wegmenten 
	USING rotondes 
	WHERE ST_DWithin(wegmenten.geom, rotondes.geom_vlak, 0.01) AND wegmenten.bst_code IN ('NRB', 'MRB', 'TRB', 'GRB');

    -- TOE- EN AFLEIDENDE WEGMENTEN ROTONDES VERLENGEN NAAR NIEUW MIDDELPUNT
    -- DE GEWIJZIGDE NODES INVOEREN
    UPDATE wegmenten links
    SET geom = ST_SetPoint(links.geom, 0, nodes.geom)
    FROM rotondes_nodes_middelpunt nodes
    WHERE links.jte_id_beg = nodes.node;
     
    UPDATE wegmenten links
    SET geom = ST_SetPoint(links.geom, -1, nodes.geom)
    FROM rotondes_nodes_middelpunt nodes
    WHERE links.jte_id_end = nodes.node;

    UPDATE wegmenten links
    SET jte_id_beg = nodes.intersectie_id
    FROM rotondes_nodes_middelpunt nodes
    WHERE links.jte_id_beg = nodes.node;

    UPDATE wegmenten links
    SET jte_id_end = nodes.intersectie_id
    FROM rotondes_nodes_middelpunt nodes
    WHERE links.jte_id_end = nodes.node;

    -- INDEX OP DE NIEUWE GEOMETRIE
    CREATE INDEX ON wegmenten USING GIST(geom);
	
	-- OUDE INTERSECTIES VERWIJDEREN
	DELETE FROM intersecties intersecties
	USING rotondes_nodes_middelpunt nodes_rotondes
	WHERE intersecties.knoop = nodes_rotondes.node;

	-- NIEUWE INTERSECTIES TOEVOEGEN
	INSERT INTO intersecties (knoop, aantal_links, geom)
	SELECT intersectie_id,
		COUNT(intersectie_id) AS aantal_links,
		geom
	FROM rotondes_nodes_middelpunt
	GROUP BY intersectie_id, geom;

CREATE INDEX ON intersecties USING GIST(geom);

END;
$$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------------
-- (4) INTERSECTIES CLUSTEREN
---------------------------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS intersecties_clusteren(clusterafstand INTEGER);
CREATE FUNCTION intersecties_clusteren(clusterafstand INTEGER) RETURNS void AS $$
DECLARE
    knoop_var integer;
    aantal_links_var integer;
    geom_knoop_var geometry(Point, 28992);
BEGIN

    -- EXTENSIE VOOR PGROUTING LADEN
    CREATE EXTENSION IF NOT EXISTS pgrouting;
	
	-- ROUTEERBAAR NETWERK MAKEN
	DROP TABLE IF EXISTS wegmenten_pgrouting;
	CREATE TABLE wegmenten_pgrouting AS
	SELECT wegment_id::INT AS id,
		jte_id_beg::INT AS source,
		jte_id_end::INT AS target,
		ST_Length(geom) AS cost,
		ST_Length(geom) AS reverse_cost,
		geom AS geom 
	FROM wegmenten;

	-- RESULTAAT TABEL MAKEN
	DROP TABLE IF EXISTS intersecties_relaties;
	CREATE TABLE intersecties_relaties
	( knoop integer,
	aantal_links integer,
	seq integer,
	cost double precision,
	agg_cost double precision,
	node integer,
	edge integer,
	geom_buurman geometry(Point, 28992),
	geom_knoop geometry(Point, 28992)
	);	
	
	-- LOOPEN DOOR NODES
    FOR knoop_var, aantal_links_var, geom_knoop_var IN 
	    SELECT *
          FROM intersecties_selectie
         ORDER BY knoop

	LOOP
		INSERT INTO intersecties_relaties
		SELECT knoop_var,
		       aantal_links_var,
		       foo.seq, 
		       foo.cost,
			   foo.agg_cost,
			   foo.node,
			   foo.edge,
			   knoop_tabel.geom_knoop AS geom_buurman,
			   geom_knoop_var AS geom_knoop
			FROM pgr_drivingDistance(
					'SELECT id::bigint AS id, 
					source::int, 
					target::int, 
					cost, 
					reverse_cost 
					FROM wegmenten_pgrouting', 
					knoop_var::int,
					clusterafstand::int) foo
			LEFT JOIN  intersecties_selectie knoop_tabel
			ON foo.node = knoop_tabel.knoop;
    END LOOP;
	
	CREATE INDEX ON intersecties_relaties USING GIST(geom_buurman);
	CREATE INDEX ON intersecties_relaties USING GIST(geom_knoop);
	
	-- DISSOLVEN VAN GEVONDEN NODES
	DROP TABLE IF EXISTS intersecties_relaties_dissolve;
	CREATE TABLE intersecties_relaties_dissolve AS
	SELECT knoop,
	       aantal_links,
	       ST_Union(geom_buurman) AS geom_omgeving,
		   geom_knoop
	FROM intersecties_relaties 
	GROUP BY knoop, aantal_links, geom_knoop;
	
	CREATE INDEX ON intersecties_relaties_dissolve USING GIST(geom_omgeving);
	CREATE INDEX ON intersecties_relaties_dissolve USING GIST(geom_knoop);
	
	-- GEOMETRIEEN SAMENVOEGEN TOT CLUSTERS
	DROP TABLE IF EXISTS intersecties_clusters;
	CREATE TABLE intersecties_clusters AS
	SELECT knoop,
	       aantal_links,
		   ST_ClusterDBSCAN(geom_omgeving, 0.01, 1) OVER () AS cluster_id,
		   geom_knoop AS geom
    FROM intersecties_relaties_dissolve;

	CREATE INDEX ON intersecties_clusters USING GIST(geom);	
	
	-- CLUSTER ID LATEN BEGINNEN VANAF HOOGSTE BESTAANDE INTERSECTIE NUMMER
	WITH hoogste_knoop AS (SELECT MAX(knoop) AS hoogste_knoop FROM intersecties)
	UPDATE intersecties_clusters
	SET cluster_id = cluster_id + hoogste_knoop.hoogste_knoop + 1
	FROM hoogste_knoop;		
	
END;
$$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------------
-- (5) WEGMENTEN ONDERVERDELEN
---------------------------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS wegmenten_onderverdelen(text, text);
CREATE FUNCTION wegmenten_onderverdelen(tabelnaam_input text, verbindingswegen_verwijderen text) RETURNS void AS $$
BEGIN

	-- WEGMENTEN MET DEZELFDE KNOPEN SELECTEREN
	EXECUTE format('
	DROP TABLE IF EXISTS wegmenten_zelfde;
	CREATE TABLE wegmenten_zelfde AS
	SELECT DISTINCT A.*,
					B.wegment_id AS wegment_id_buurman,
					B.bst_code AS bst_code_buurman,
					B.rijrichtng AS rijrichtng_buurman,
					B.jte_id_beg AS jte_id_beg_buurman,
					B.jte_id_end AS jte_id_end_buurman
	FROM %I A
	LEFT JOIN %I B ON (A.jte_id_beg = B.jte_id_end AND A.jte_id_end = B.jte_id_beg) OR (A.jte_id_beg = B.jte_id_beg AND A.jte_id_end = B.jte_id_end)
	WHERE A.wegment_id <> B.wegment_id OR A.jte_id_beg <> B.jte_id_beg OR A.jte_id_end <> B.jte_id_end
		AND ST_DWithin(ST_LineInterpolatePoint(A.geom,0.5), B.geom,40) 
		AND ST_DWithin(ST_LineInterpolatePoint(B.geom,0.5), A.geom,40);', tabelnaam_input, tabelnaam_input);
	
	CREATE INDEX ON wegmenten_zelfde USING GIST(geom);
	
	-- EVENTUELE VERBINDINGSWEGEN VERWIJDEREN IN SELECTIE	
	IF verbindingswegen_verwijderen = 'ja' 
		THEN 
			DROP TABLE IF EXISTS wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan;
			CREATE TABLE wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan AS
			SELECT *
			FROM wegmenten_zelfde
			WHERE (bst_code IN ('VWG', 'PAR')
				AND (bst_code_buurman = '' OR bst_code_buurman = 'HR' OR bst_code_buurman = 'RB' ));
			
			DELETE FROM wegmenten_zelfde zelfde
			USING wegmenten_zelfde_verbindingswegen_met_hoofdrijbaan verbindingswegen
			WHERE zelfde.wegment_id = verbindingswegen.wegment_id
				OR zelfde.wegment_id_buurman = verbindingswegen.wegment_id;	 
	END IF;
		
	-- OMGEKEERDE SELECTIE MAKEN
	EXECUTE format('
	DROP TABLE IF EXISTS wegmenten_niet_zelfde;
	CREATE TABLE wegmenten_niet_zelfde AS
	SELECT DISTINCT links.*
	FROM %I links
	LEFT JOIN wegmenten_zelfde zelfde ON links.wegment_id = zelfde.wegment_id
	WHERE zelfde.wegment_id IS NULL;', tabelnaam_input);

	CREATE INDEX ON wegmenten_niet_zelfde USING GIST(geom); 		

END;
$$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------------
-- (6) VERWIJDEREN VAN FIETSPADEN LANGS HOOFDRIJBAAN
---------------------------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS verwijderen_fietspaden_langs_hoofdrijbaan(text);
CREATE FUNCTION verwijderen_fietspaden_langs_hoofdrijbaan(fietspaden_samenvoegen text) RETURNS void AS $$
BEGIN

	-- CHECKEN OF FIETSPADEN VERWIJDERD MOETEN WORDEN
    IF fietspaden_samenvoegen != 'ja' THEN
        RETURN;
    END IF;
	
    -- TABEL MET KNOPEN CLUSTERS GENEREREN GEBASSEERD OP PARAMETER
	DROP TABLE IF EXISTS fietspaden_zelfde_met_hoofdrijbaan;
	CREATE TABLE fietspaden_zelfde_met_hoofdrijbaan AS
	SELECT *
	FROM wegmenten_zelfde
	WHERE (bst_code IN ('FP')
	      AND (bst_code_buurman = 'RB' OR bst_code_buurman = 'HR' OR bst_code_buurman = ''));
			  
	-- FIETSPADEN DAADWERKELIJK VERWIJDEREN
	DELETE FROM wegmenten wegmenten
	USING fietspaden_zelfde_met_hoofdrijbaan  fietspaden
    WHERE wegmenten.wegment_id = fietspaden.wegment_id 
	      AND fietspaden.jte_id_beg = wegmenten.jte_id_beg 
	      AND fietspaden.jte_id_end = wegmenten.jte_id_end;

	-- KOPPELINGSTABEL UPDATEN
	UPDATE koppelingstabel_wegvakken_wegmenten_juncties_intersecties koppeling
	SET wegment_id = samengevoegd.wegment_id_buurman
	FROM fietspaden_zelfde_met_hoofdrijbaan samengevoegd
	WHERE koppeling.wegment_id = samengevoegd.wegment_id;

END;
$$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------------
-- (7) DEZELFDE WEGMENTEN SAMENVOEGEN
---------------------------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS dezelfde_wegmenten_samenvoegen(text, text);
CREATE FUNCTION dezelfde_wegmenten_samenvoegen(zelfde_bst text, tabelnaam_wegment_id text) RETURNS void AS $$
BEGIN

	-- SCANLIJNEN MAKEN BIJ ELK VORMPUNT VAN SELECTIE VAN WEGMENTEN MET DEZELFDE BEGIN- EN EINDPUNTEN
	IF zelfde_bst = 'ja'
	THEN 
		DROP TABLE IF EXISTS wegmenten_zelfde_vormpunten;
		CREATE TABLE wegmenten_zelfde_vormpunten AS
		SELECT 	wegment_id,
				jte_id_beg,
				jte_id_end,
				rijrichtng,
				bst_code,
				rpe_code,
				stt_naam,
				wegbehsrt,
				wegment_id_buurman,
				bst_code_buurman,
					ST_Linelocatepoint(geom,(ST_DumpPoints(geom)).geom) AS fractie_tot_beginnode,
				(ST_DumpPoints(geom)).path[1] AS volgnummer,
				(ST_DumpPoints(geom)).geom AS geom,
				degrees(ST_Azimuth(ST_StartPoint(ST_Intersection(geom,ST_Buffer((ST_DumpPoints(geom)).geom,0.05))), ST_Endpoint(ST_Intersection(geom,ST_Buffer((ST_DumpPoints(geom)).geom,0.05))))) AS hoek
		FROM wegmenten_zelfde
		WHERE bst_code = bst_code_buurman;
	ELSE 
		DROP TABLE IF EXISTS wegmenten_zelfde_vormpunten;
		CREATE TABLE wegmenten_zelfde_vormpunten AS
		SELECT wegment_id,
				jte_id_beg,
				jte_id_end,
				rijrichtng,
				bst_code,
				rpe_code,
				stt_naam,
				wegbehsrt,
				wegment_id_buurman,
					ST_Linelocatepoint(geom,(ST_DumpPoints(geom)).geom) AS fractie_tot_beginnode,
				(ST_DumpPoints(geom)).path[1] AS volgnummer,
				(ST_DumpPoints(geom)).geom AS geom,
				degrees(ST_Azimuth(ST_StartPoint(ST_Intersection(geom,ST_Buffer((ST_DumpPoints(geom)).geom,0.05))), ST_Endpoint(ST_Intersection(geom,ST_Buffer((ST_DumpPoints(geom)).geom,0.05))))) AS hoek
		FROM wegmenten_zelfde;
	END IF;
	
	-- INDEX GENEREREN
	CREATE INDEX ON wegmenten_zelfde_vormpunten USING GIST(geom);

	-- M.U.V. BEGIN- EN EINDPUNTEN DE VORMPUNTEN OP DE KRUISPUNTVLAKKEN VERWIJDEREN
	DELETE FROM wegmenten_zelfde_vormpunten punten
	USING nieuwe_intersecties_inclusief_oude_node node
	WHERE ST_Intersects(punten.geom, ST_Buffer(node.geom, 10)) 
	      AND fractie_tot_beginnode NOT IN (0,1);
	
	-- VORMPUNTEN GENEREREN MIDDENIN DE WEGMENTEN O.B.V. SCANLIJNEN
	DROP TABLE IF EXISTS wegmenten_zelfde_vormpunten_midden;
	CREATE TABLE wegmenten_zelfde_vormpunten_midden AS
	SELECT DISTINCT A.wegment_id,
		A.wegment_id_buurman,
		A.fractie_tot_beginnode,
		A.volgnummer,
		A.jte_id_beg,
		A.jte_id_end,
		'B' AS rijrichtng,
		A.bst_code,
		A.rpe_code,
		A.stt_naam,
		A.wegbehsrt,
		(CASE WHEN A.fractie_tot_beginnode IN (0,1) THEN A.geom
		ELSE ST_Centroid(ST_LineInterpolatePoint(ST_ShortestLine(A.geom,ST_Intersection(ST_MakeLine(ST_TRANSLATE(A.geom, sin(radians(A.hoek-90)) * 25, cos(radians(A.hoek-90)) * 25),
	    ST_TRANSLATE(A.geom, sin(radians(A.hoek+90)) * 25, cos(radians(A.hoek+90)) * 25)) ,B.geom)),0.5))
		END) AS geom
	FROM wegmenten_zelfde_vormpunten A
	LEFT JOIN wegmenten_zelfde B ON A.wegment_id_buurman = B.wegment_id
	WHERE A.wegment_id < A.wegment_id_buurman OR (A.wegment_id = A.wegment_id_buurman AND A.jte_id_beg < A.jte_id_end);
	
	CREATE INDEX ON wegmenten_zelfde_vormpunten_midden USING GIST(geom);   
	
	-- LIJN MAKEN VAN DE VORMPUNTEN REKENING HOUDEN MET DE FRACTIE TOT BEGINNODE  
	DROP TABLE IF EXISTS wegmenten_zelfde_centerline;
	CREATE TABLE wegmenten_zelfde_centerline AS
	SELECT wegment_id AS wegment_id_zelf,
		wegment_id_buurman,
		jte_id_beg,
		jte_id_end,
		rijrichtng,
		bst_code,
		rpe_code,
		stt_naam,
		wegbehsrt,
		ST_MakeLine(geom ORDER BY fractie_tot_beginnode) AS geom
	FROM wegmenten_zelfde_vormpunten_midden
	GROUP BY wegment_id, wegment_id_buurman, jte_id_beg, jte_id_end, rijrichtng, bst_code, rpe_code, stt_naam, wegbehsrt;
	
	CREATE INDEX ON wegmenten_zelfde_centerline USING GIST(geom); 
	
	-- NIEUWE KOLOM MET WEGMENT ID TOEVOEGEN
	ALTER TABLE wegmenten_zelfde_centerline ADD COLUMN wegment_id SERIAL;
	
	-- UPDATEN WEGMENT ID'S
	-- VERDER TELLEND VANAF HOOGSTE WEGMENT ID DAT TOT NU TOE VOORKOMT
	EXECUTE format('
	WITH hoogste_id AS (SELECT MAX(wegment_id) AS hoogste_id FROM %I)
	UPDATE wegmenten_zelfde_centerline
	SET wegment_id = hoogste_id.hoogste_id + wegment_id
	FROM hoogste_id', tabelnaam_wegment_id);
	
	-- INDIEN WEGMENTEN ZIJN ONSTAAN MET DEZELFDE KNOPEN BLIJFT ER MAAR 1 BEHOUDEN
	DELETE FROM wegmenten_zelfde_centerline
    WHERE wegment_id NOT IN (
    SELECT MAX(wegment_id)
    FROM wegmenten_zelfde_centerline
    GROUP BY jte_id_beg, jte_id_end);
	
END;
$$ LANGUAGE plpgsql;