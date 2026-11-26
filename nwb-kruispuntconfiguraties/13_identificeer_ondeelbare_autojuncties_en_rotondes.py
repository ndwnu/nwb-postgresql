import geopandas as gpd
gpd.options.io_engine = "pyogrio"
import os
os.environ["PYOGRIO_USE_ARROW"] = "1"
import networkx as nx
from collections import *
import datetime
import pandas as pd
from shapely.geometry import Point, MultiPoint, MultiLineString, LineString, mapping, shape
from shapely.ops import unary_union
from rtree import index
import math
import copy
import itertools

def knopen_clusters_naar_gdf(knoop_clusters, get_wvk, gdf_netwerk):
    """ verzamel voor juncties die samen een ondeelbare eenheid vormen
    de geometrie en schrijf ze weg in een GeoDataFrame """
    results_cluster = []

    for cc in nx.connected_components(knoop_clusters):
        # verzamelen links die samen het kruispuntvlak maken.
        netwerk_indices = set()
        for k in cc:
            for j in cc:
                if (k,j) in get_wvk:
                    netwerk_indices.add(get_wvk[k,j])

        # zoeken naar de originele juncties.
        # bijvoorbeeld bij een busbaan door het kruispunt treedt dit op.
        # verzamel daarnaast lijnstukken voor visualisatie kruispuntvlak.
        originele_juncties = set()
        polys = []
        for index in netwerk_indices:
            knopen = map(int,gdf_netwerk.at[index,'knopen'].split(','))
            originele_juncties |= set(knopen)
                  
            line = gdf_netwerk.at[index, 'geometry']
            polys.append(line.buffer(2.0))

        p = unary_union(polys)
        cc_geo = LineString(p.exterior.coords)
        
        result = {'Juncties': ','.join(map(str, sorted(originele_juncties))),
                  'aantal_juncties': len(originele_juncties),
                  'geometry': cc_geo}
        results_cluster.append(result)

        
    gdf_clusters_poly = gpd.GeoDataFrame(results_cluster, crs='EPSG:28992')
    return gdf_clusters_poly

    
# INPUT
netwerk_versimpeld_file = '02 Tussenresultaten/12_NWB_20260101_versimpeld.gpkg'
outputfile_clusters = '02 Tussenresultaten/13_NWB_20260101_ondeelbare_autojuncties.gpkg'
outputfile_rotondes = '02 Tussenresultaten/13_NWB_20260101_rotondes.gpkg'

rotonde_codes = ['Rotonde'] 
rotonde_key = 'BST_CODE_simpel'
straatnaam_key = 'STT_NAAM'
keys_kopieren = ['BST_CODE','BST_CODE_simpel','STT_NAAM']


gdf_netwerk = gpd.read_file(netwerk_versimpeld_file)

# stel vast welke juncties onderdeel uitmaken van dezelfde rotonde.
rotonde_graph = nx.Graph()
for index in gdf_netwerk[gdf_netwerk[rotonde_key].isin(rotonde_codes)].index:
    a = gdf_netwerk.at[index,'A']
    b = gdf_netwerk.at[index,'B']

    rotonde_graph.add_edge(a,b)


# inlezen van het netwerk.
netwerk_links = defaultdict(dict)
knoop_wegvakken = defaultdict(set)

knoop_xy = {}
knoop_buren = defaultdict(set)
get_wvk = defaultdict(list)

for index in gdf_netwerk.index:
    a = gdf_netwerk.at[index,'A']
    b = gdf_netwerk.at[index,'B']

    if a == b: continue # lussen vooralsnog niet meenemen.

    knoop_xy[a] = Point(gdf_netwerk.at[index,'geometry'].coords[0])
    knoop_xy[b] = Point(gdf_netwerk.at[index,'geometry'].coords[-1])
    
    for c in ['A','B','oneway', 'geometry'] + keys_kopieren:
        netwerk_links[index][c] = gdf_netwerk.at[index,c]

    get_wvk[a,b] = index # uitgaan van geen dubbele AB knopen
    get_wvk[b,a] = index # uitgaan van geen dubbele AB knopen

    knoop_wegvakken[a].add(index)
    knoop_wegvakken[b].add(index)

    knoop_buren[a].add(b)
    knoop_buren[b].add(a)

        
# zoek juncties die onderdeel uitmaken van hetzelfde kruispuntvlak
# bij gescheiden rijbanen.
knoop_clusters = nx.Graph()
for k in knoop_buren:
    for b in knoop_buren[k]:
        # voor de knopen k en b onderzoeken we of ze onderdeel uitmaken van hetzelfde kruispuntvlak.
        
        # maximale afstand tussen gescheiden rijbanen
        if netwerk_links[get_wvk[k,b]]['geometry'].length > 35.0: continue

        # rotonde wordt buiten beschouwing gelaten
        if netwerk_links[get_wvk[k,b]][rotonde_key] in rotonde_codes: continue 
        
        # uitsluiten bruggen (special voor Delft / Amsterdam)
        if netwerk_links[get_wvk[k,b]]['STT_NAAM'].lower().endswith('brug'): continue
        
        # ok, we zoeken:
        # ingaand bij k (a-k)
        # uitgaand bij b (b-c)
        # zelfde naam
        # ak en bc parallel nabij kb
        # akb is linksaf
        # kbc is linksaf
        
        
        wegvakken_ingaand = []
        for a in knoop_buren[k] - set([b]):
            index_ak = get_wvk[a,k]
            # in NWB komt het nog regelmatig voor dat een ingaande link per ongeluk als tweerichtingslink is gecodeerd
            # daar misschien nog een keer iets mee doen.
            if netwerk_links[index_ak][rotonde_key] not in rotonde_codes and\
               netwerk_links[index_ak]['oneway'] == 'F' and\
               netwerk_links[index_ak]['A'] == a:
                wegvakken_ingaand.append(a)

        wegvakken_uitgaand = []
        #for a in knoop_buren[b] - set([a]): # hier stond -set([a])
        for a in knoop_buren[b] - set([k]):
            index_ab = get_wvk[a,b]
            if netwerk_links[index_ab][rotonde_key] not in rotonde_codes and\
               netwerk_links[index_ab]['oneway'] == 'F' and\
               netwerk_links[index_ab]['A'] == b:
                wegvakken_uitgaand.append(a)
       
        pk = knoop_xy[k]
        pb = knoop_xy[b]
        for (a,c) in itertools.product(wegvakken_ingaand,wegvakken_uitgaand):
            # zelfde straatnaam.
            if not netwerk_links[get_wvk[a,k]][straatnaam_key] == netwerk_links[get_wvk[b,c]][straatnaam_key]: continue
            if not netwerk_links[get_wvk[a,k]]['BST_CODE'] == netwerk_links[get_wvk[b,c]]['BST_CODE']: continue
            
            # hoek akb analyseren
            # deze hoeken zijn misschien minder relevant??
            # of kunnen ruimer gekozen worden door nieuwe paralleliteitstoevoeging.
            pa = knoop_xy[a]
            
            hoek_in = math.atan2(pk.y-pa.y,pk.x-pa.x) * 180 / math.pi
            hoek_uit = math.atan2(pb.y-pk.y,pb.x-pk.x) * 180 / math.pi

                
            hoek = hoek_in-hoek_uit
            if hoek < - 180.0: hoek += 360.0
            if hoek > 180.0: hoek -= 360.0

            if b == 168294149 and k == 167295190:
                print(a,c,hoek_in, hoek_uit,hoek,abs(hoek+90.0))
            
            if abs(hoek+90.0) < 60.0:
                akb_linksaf = True
            else: akb_linksaf = False
            if not akb_linksaf: continue

            
            pc = knoop_xy[c]

            # hoek kbc analyseren
            hoek_in = math.atan2(pb.y-pk.y,pb.x-pk.x) * 180 / math.pi
            hoek_uit = math.atan2(pc.y-pb.y,pc.x-pb.x) * 180 / math.pi

            hoek = hoek_in-hoek_uit
            if hoek < - 180.0: hoek += 360.0
            if hoek > 180.0: hoek -= 360.0

            if abs(hoek+90.0) < 60.0:
                kbc_linksaf = True
            else:
                kbc_linksaf = False
            if not kbc_linksaf: continue
                
                    
            # ook nog nader kijken naar de paralleliteit van ka en bc
            wvk_ka = get_wvk[k,a]
            line_ka = netwerk_links[wvk_ka]['geometry']
            if netwerk_links[wvk_ka]['A'] != k: # dit geldt altijd?
                coords = list(line_ka.coords)
                coords.reverse()
                line_ka = LineString(coords)
            
            wvk_bc = get_wvk[b,c]
            line_bc = netwerk_links[wvk_bc]['geometry']
            if netwerk_links[wvk_bc]['A'] != b:
                coords = list(line_bc.coords)
                coords.reverse()
                line_bc = LineString(coords)

            
            analyse_pos = min(50.0,line_ka.length, line_bc.length)
            punt_ka = line_ka.interpolate(analyse_pos)
            punt_bc = line_bc.interpolate(analyse_pos)
                       
            if punt_ka.distance(punt_bc) < netwerk_links[get_wvk[k,b]]['geometry'].length * 1.2 + 5.0:
                # gevonden!
                knoop_clusters.add_edge(k,b)
               

gdf_clusters_poly = knopen_clusters_naar_gdf(knoop_clusters, get_wvk, gdf_netwerk)
gdf_clusters_poly.to_file(outputfile_clusters,driver='GPKG')

gdf_rotonde_clusters = knopen_clusters_naar_gdf(rotonde_graph, get_wvk, gdf_netwerk)
gdf_rotonde_clusters.to_file(outputfile_rotondes,driver='GPKG')
