import geopandas as gpd
import pandas as pd
gpd.options.io_engine = "pyogrio"
import os
os.environ["PYOGRIO_USE_ARROW"] = "1"


# INPUT
# selectie infrastructuur binnen deze bbox (xmin, ymin, xmax, ymax) 
bbox = (190000, 465000, 200000, 475000)

wegcategorie_file = '00 Data/WKD/20260101 wegcategorisering/WKD_WEG_CATV2.gpkg'
output_file = '02 Tussenresultaten/25_WKD_wegcat_20260101_selectie.gpkg'

gdf_wegcategorie = gpd.read_file(wegcategorie_file, bbox=bbox)

df_interpretatie = pd.read_csv('01 Invoer/WKD_Wegcategorisering_interpretatie.csv',
                                 index_col = 'Nieuwe benaming')
gdf_wegcategorie['Indeling'] = gdf_wegcategorie['WEG_CAT'].map(df_interpretatie['Indeling GOW-ETW'].to_dict().get)

gdf_wegcategorie.to_file(output_file, driver='GPKG')
