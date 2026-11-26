import geopandas as gpd
import pandas as pd
gpd.options.io_engine = "pyogrio"
import os
os.environ["PYOGRIO_USE_ARROW"] = "1"


# INPUT
# selectie infrastructuur binnen deze bbox (xmin, ymin, xmax, ymax) 
bbox = (190000, 465000, 200000, 475000)
verkeerstypen_file = '00 Data/WKD/20260101 verkeerstypen/WKD_VRKRSTPNV2.gpkg'
output_file = '02 Tussenresultaten/28_WKD_verkeerstypen_20260101_selectie.gpkg'

gdf_verkeerstypen = gpd.read_file(verkeerstypen_file, bbox=bbox)

gdf_verkeerstypen['Indeling'] = 'Fietsers_niet_toegestaan'
gdf_verkeerstypen.loc[gdf_verkeerstypen['FIETS_H'] == 'J','Indeling'] = 'Fietsers_toegestaan'
gdf_verkeerstypen.loc[gdf_verkeerstypen['FIETS_T'] == 'J','Indeling'] = 'Fietsers_toegestaan'

gdf_verkeerstypen.to_file(output_file, driver='GPKG')
