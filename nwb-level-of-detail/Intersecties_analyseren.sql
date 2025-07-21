---------------------------------------------------------------------------------------------------------------
-- INTERSECTIES ANALYSEREN
---------------------------------------------------------------------------------------------------------------

-- INTERSECTIES ANALYSEREN
-- parameter hanteren
DROP TABLE IF EXISTS intersecties_met_teveel_wegmenten;
CREATE TABLE intersecties_met_teveel_wegmenten AS
SELECT * 
FROM intersecties 
WHERE aantal_links > :maximaal_aantal_links_per_intersectie;