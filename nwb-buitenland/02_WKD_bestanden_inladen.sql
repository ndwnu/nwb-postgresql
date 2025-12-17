-- WKD RVM INLADEN 
DROP TABLE IF EXISTS wkd_rvm; 
CREATE TABLE wkd_rvm 
(WVK_ID INTEGER,
BEGINDAT DATE,
RVM_SOORT TEXT);

COPY wkd_rvm FROM 'd:\Projects\022054_2025_NWB_Buitenland\Data\01_NWB\December_2025\wkd_023-RVM.csv' WITH (FORMAT csv, HEADER true, DELIMITER ';');

-- WKD WEGENCATEGORISERING INLADEN
DROP TABLE IF EXISTS wkd_wegencategorisering;
CREATE TABLE wkd_wegencategorisering
(WVK_ID INTEGER,
BEGINDAT DATE,
VAN INTEGER,
TOT INTEGER,
WEG_CAT TEXT);

COPY wkd_wegencategorisering FROM 'd:\Projects\022054_2025_NWB_Buitenland\Data\01_NWB\December_2025\wkd_034-WEG_CATV2.csv' WITH (FORMAT csv, HEADER true, DELIMITER ';');