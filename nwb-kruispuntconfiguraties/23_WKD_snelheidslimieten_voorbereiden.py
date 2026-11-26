import geopandas as gpd
import pandas as pd
gpd.options.io_engine = "pyogrio"
import os
os.environ["PYOGRIO_USE_ARROW"] = "1"

# INPUT
# selectie infrastructuur binnen deze bbox (xmin, ymin, xmax, ymax) 
bbox = (190000, 465000, 200000, 475000)
snelheden_file = '00 Data/WKD/WKD_max_snelheden 01-01-2026/01-01-2026/Snelheden.gpkg'
output_file = '02 Tussenresultaten/23_WKD_snelheden_20260101_selectie.gpkg'

gdf_snelheden = gpd.read_file(snelheden_file, bbox=bbox)

# MAXSHD opschonen.
gdf_snelheden.loc[(gdf_snelheden['MAXSHD'] == 'NVT') & (gdf_snelheden['BST_CODE'].isin(['FP','VZ','VP'])),'MAXSHD'] = gdf_snelheden['BST_CODE']

gdf_snelheden.to_file(output_file, driver='GPKG')
