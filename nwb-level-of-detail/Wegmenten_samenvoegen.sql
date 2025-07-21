---------------------------------------------------------------------------------------------------------------
-- WEGMENTEN SAMENVOEGEN
---------------------------------------------------------------------------------------------------------------

-- OVERZICHT SUB BLOKKEN:
-- 1) WEGMENTEN SAMENVOEGEN
-- 2) WEGMENTEN UPDATEN
-- 3) INTERSECTIES GENEREREN
-- 4) KOPPELINGSTABEL UPDATEN

---------------------------------------------------------------------------------------------------------------
-- WEGMENTEN SAMENVOEGEN
---------------------------------------------------------------------------------------------------------------
-- FUNCTIE WEGMENTEN ONDERVERDELEN UITVOEREN
-- OUTPUT ZIJN ZELFDE EN NIET ZELFDE WEGMENTEN
SELECT wegmenten_onderverdelen('wegmenten', 'nee');

-- FUNCTIE DEZELFDE WEGMENTEN SAMENVOEGEN AANROEPEN
-- alleen wegmenten met dezelfde bst_codes worden samengevoegd
SELECT dezelfde_wegmenten_samenvoegen('ja');
											  	  
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
-- INTERSECTIES GENEREREN
---------------------------------------------------------------------------------------------------------------
-- FUNCTIE INTERSECTIES GENEREREN UITVOEREN 
-- zodat het aantal wegmenten per intersectie wordt geupdate
SELECT intersecties_genereren();

---------------------------------------------------------------------------------------------------------------
-- KOPPELINGSTABEL UPDATEN
---------------------------------------------------------------------------------------------------------------
-- UPDATEN WEGMENTEN DIE ZIJN SAMENGEVOEGD
UPDATE koppelingstabel_wegvakken_wegmenten_juncties_intersecties koppeling
SET wegment_id = samengevoegd.wegment_id, 
    intersectie_beg = samengevoegd.jte_id_beg,
	intersectie_end = samengevoegd.jte_id_end
FROM wegmenten_zelfde_centerline samengevoegd
WHERE koppeling.wegment_id = samengevoegd.wegment_id_zelf;

UPDATE koppelingstabel_wegvakken_wegmenten_juncties_intersecties koppeling
SET wegment_id = samengevoegd.wegment_id,
    intersectie_beg = samengevoegd.jte_id_beg,
	intersectie_end = samengevoegd.jte_id_end
FROM wegmenten_zelfde_centerline samengevoegd
WHERE koppeling.wegment_id = samengevoegd.wegment_id_buurman;