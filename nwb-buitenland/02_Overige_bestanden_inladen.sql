-- WKD RVM INLADEN 
DROP TABLE IF EXISTS wkd_rvm;
CREATE TABLE wkd_rvm 
(WVK_ID INTEGER,
BEGINDAT DATE,
RVM_SOORT TEXT);

COPY wkd_rvm FROM 'd:\Projects\022054_2025_NWB_Buitenland\Data\01_NWB\januari_2026\wkd_023-RVM.csv' WITH (FORMAT csv, HEADER true, DELIMITER ';');

-- WKD WEGENCATEGORISERING INLADEN
DROP TABLE IF EXISTS wkd_wegencategorisering;
CREATE TABLE wkd_wegencategorisering
(WVK_ID INTEGER,
BEGINDAT DATE,
VAN INTEGER,
TOT INTEGER,
WEG_CAT TEXT);

COPY wkd_wegencategorisering FROM 'd:\Projects\022054_2025_NWB_Buitenland\Data\01_NWB\januari_2026\wkd_034-WEG_CATV2.csv' WITH (FORMAT csv, HEADER true, DELIMITER ';');

-- HANDMATIGE VERBINDINGEN INLADEN 
DROP TABLE IF EXISTS grensovergangen_handmatige_verbindingen;
CREATE TABLE grensovergangen_handmatige_verbindingen
(orig_id BIGINT,
aanpassing TEXT,
jte_id_beg BIGINT,
jte_id_end BIGINT,
x DOUBLE PRECISION,
Y DOUBLE PRECISION);

COPY grensovergangen_handmatige_verbindingen FROM 'd:\Projects\022054_2025_NWB_Buitenland\Data\05_Grensovergangen\Grensovergangen_handmatig.csv' WITH (FORMAT csv, HEADER true, DELIMITER ';');