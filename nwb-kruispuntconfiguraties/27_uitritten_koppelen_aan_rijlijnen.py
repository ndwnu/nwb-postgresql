import geopandas as gpd
gpd.options.io_engine = "pyogrio"
import os
os.environ["PYOGRIO_USE_ARROW"] = "1"
from collections import *
import datetime
import rtree
import math

# INPUT
drempels_file = '00 Data/2025_drempels/2025_drempels.gpkg'
rijlijnen_file = '02 Tussenresultaten/11_NWB_20260101_rijlijnen_auto_en_fiets.gpkg'

output_file = '02 Tussenresultaten/27_rijlijnen_met_drempels.gpkg'


gdf_drempels = gpd.read_file(drempels_file,
                             layer = 'wegvaksegmenten')


gdf_drempels = gdf_drempels[gdf_drempels['typering'] == 'uitrit']
gdf_drempels.reset_index(inplace=True)


gdf_rijlijnen = gpd.read_file(rijlijnen_file)
gdf_rijlijnen.set_index('rijlijn_index', inplace=True)

# spatial index aanmaken voor wegvakken
def generator_function(gdf):
    for i, geo in enumerate(gdf['geometry']):
        yield (i, geo.bounds, None)
drempel_spatial_index = rtree.index.Index(generator_function(gdf_drempels))

results = []
for i_rijlijn in gdf_rijlijnen.index:
    rijlijn_geo = gdf_rijlijnen.at[i_rijlijn,'geometry']
    
    result = drempel_spatial_index.intersection(rijlijn_geo.bounds)

    for i_drempel in result:
        drempel_geo = gdf_drempels.at[i_drempel,'geometry']

        drempel_a = drempel_geo.interpolate(0.0)
        drempel_b = drempel_geo.interpolate(1.0,normalized=True)

        if drempel_a.distance(rijlijn_geo) < 1.0 and drempel_b.distance(rijlijn_geo) < 1.0:
            pos = 0.5 * (rijlijn_geo.project(drempel_a) + rijlijn_geo.project(drempel_b))

            result = {'rijlijn_index': i_rijlijn,
                      'uitrit_pos': pos,
                      'geometry': rijlijn_geo.interpolate(pos)}
            results.append(result)
gpd.GeoDataFrame(results,crs=gdf_rijlijnen.crs).to_file(output_file,driver='GPKG')
