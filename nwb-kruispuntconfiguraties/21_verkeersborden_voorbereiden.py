import geopandas as gpd
import pandas as pd
gpd.options.io_engine = "pyogrio"
import os
os.environ["PYOGRIO_USE_ARROW"] = "1"

# INPUT
# selectie infrastructuur binnen deze bbox (xmin, ymin, xmax, ymax) 
bbox = (190000, 465000, 200000, 475000)

voorrangsborden = ['B1','B3','B4','B5','B6','B7']
extra_borden = ['D1', # rotonde
                'D2', # o.a. voor verkeerseiland
                'L2', # voetgangersoversteek
                ]
ndw_verkeersborden_file = '00 Data/Verkeersbordenbestand/20260409/verkeersborden_actueel_beeld.csv.gz'


df_borden = pd.read_csv(ndw_verkeersborden_file)
gdf_borden = gpd.GeoDataFrame(df_borden, geometry=gpd.points_from_xy(df_borden.rdX,df_borden.rdY),crs='EPSG:28992')
gdf_borden.drop(columns=['externalId', 'bgtCode','expectedPlacedOn','zoneCode','expectedRemovedOn','removedOn',
                         'trafficOrderUrl'],inplace=True)

gdf_borden = gdf_borden[gdf_borden['rvvCode'].isin(voorrangsborden+extra_borden)]
gdf_borden.reset_index(inplace=True)
indices = list(gdf_borden.sindex.intersection(bbox))
gdf_borden = gdf_borden.iloc[indices]

gdf_borden.to_file('02 Tussenresultaten/21_Verkeersborden_20260409.gpkg', driver='GPKG')
