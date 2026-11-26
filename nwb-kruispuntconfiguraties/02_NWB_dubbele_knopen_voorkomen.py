import pandas as pd
import geopandas as gpd
gpd.options.io_engine = "pyogrio"
import os
os.environ["PYOGRIO_USE_ARROW"] = "1"
from collections import *
from shapely.ops import substring

def parallele_lijnen_opschonen(gdf_dubbel, opvolgnummer, key_a, key_b):
    """ (JTE_BEG, JTE_END) combinaties die meerdere keren voorkomen
    worden voorkomen door betreffende wegvakken op te knippen.

    er worden nieuwe knoopnummers gegenereerd vanaf 'opvolgnummer'.
    """
    
    gdf_dubbel['Lengte'] = gdf_dubbel.length
    gdf_dubbel.sort_values(by='Lengte',ascending=True,inplace=True)
    
    results = []
    for (a,b), gdf_ab in gdf_dubbel.groupby('AB'):
        results.append(gdf_ab.iloc[0].to_dict()) # het kortste wegvak wordt niet opgeknipt

        # de andere wegvakken worden in het midden opgeknipt, waarbij nieuwe knoopnummers worden gegenereerd.
        for i in range(1,len(gdf_ab)):
            wegvak_dict = gdf_ab.iloc[i].to_dict()
            wegvak_geo = wegvak_dict['geometry']

            wegvak_1_geo = substring(wegvak_geo, 0.0, 0.5, normalized=True)
            wegvak_2_geo = substring(wegvak_geo, 0.5, 1.0, normalized=True)

            wegvak_1 = wegvak_dict.copy()
            wegvak_1['geometry'] = wegvak_1_geo
            wegvak_1[key_b] = opvolgnummer
            wegvak_1['WVK_pos_van'] = 0
            wegvak_1['WVK_pos_naar'] = round(wegvak_1_geo.length,0)
            results.append(wegvak_1)
            
            wegvak_2 = wegvak_dict.copy()
            wegvak_2['geometry'] = wegvak_2_geo
            wegvak_2[key_a] = opvolgnummer
            wegvak_2['WVK_pos_van'] = round(wegvak_2_geo.length,0)
            wegvak_2['WVK_pos_naar'] = round(wegvak_geo.length,0)
            results.append(wegvak_2)
            
            
            opvolgnummer += 1

    gdf = gpd.GeoDataFrame(results, crs=gdf_dubbel.crs)
    
    return gdf

# INPUT
netwerk_file = '02 Tussenresultaten/01_NWB_20260101_selectie.gpkg'
key_a = 'JTE_ID_BEG'
key_b = 'JTE_ID_END'
output_file = '02 Tussenresultaten/02_NWB_20260101_ontdubbeld.gpkg'
ontdubbel_file = '02 Tussenresultaten/02_NWB_20260101_opgeknipt.gpkg'

gdf_netwerk = gpd.read_file(netwerk_file)
gdf_netwerk['AB_origineel'] = gdf_netwerk[key_a].astype(str) + '_' + gdf_netwerk[key_b].astype(str)
gdf_netwerk['AB'] = list(zip(gdf_netwerk[key_a],gdf_netwerk[key_b]))

# identificeer AB-paren die meerdere keren voorkomen.
ab_aantallen = gdf_netwerk['AB'].value_counts()
ab_dubbel = ab_aantallen[ab_aantallen>1]

print('%d dubbele knopen' % len(ab_dubbel))

gdf_dubbel = gdf_netwerk[gdf_netwerk['AB'].isin(ab_dubbel.index)].copy()
gdf_niet_dubbel = gdf_netwerk[~gdf_netwerk['AB'].isin(ab_dubbel.index)]

# het hoogst voorkomende knoopnummer+1 wordt gebruikt om nieuwe knoopnummers te genereren.
opvolgnummer = max(list(gdf_netwerk[key_a]) + list(gdf_netwerk[key_b])) + 1

# knip wegvakken op om dubbele nummering te voorkomen.
gdf_dubbel = parallele_lijnen_opschonen(gdf_dubbel, opvolgnummer, key_a, key_b)

# schrijf het NWB netwerk inclusief opgeknipte wegvakken weg
gdf_netwerk = pd.concat([gdf_niet_dubbel, gdf_dubbel], ignore_index=True)
gdf_netwerk.drop(columns=['AB','WVK_pos_van','WVK_pos_naar'],inplace=True)
gdf_netwerk.to_file(output_file,driver='GPKG')


# schrijf los alleen de opgeknipte wegvakken weg.
gdf_opgeknipt = gdf_dubbel[~gdf_dubbel['WVK_pos_van'].isnull()].copy()
for c in gdf_opgeknipt.columns:
    if set(gdf_opgeknipt[c]) == set([None]): gdf_opgeknipt[c] = ''
gdf_opgeknipt.to_file(ontdubbel_file,driver='GPKG')
