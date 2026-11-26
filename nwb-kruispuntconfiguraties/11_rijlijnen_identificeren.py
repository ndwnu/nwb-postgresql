
from shapely.geometry import *
import copy
import geopandas as gpd
gpd.options.io_engine = "pyogrio"
import os
os.environ["PYOGRIO_USE_ARROW"] = "1"
import sys
from collections import *
import pandas as pd
import math
import networkx as nx



def compare_links_hoeken(node, link1, link2, gdf_nwb):
    """ Stel de hoek vast tussen twee links die aan dezelfde node gekoppeld zijn
    Resultaat: hoek tussen 0 en 180 graden.
    """ 
    line1 = gdf_nwb.at[link1,'geometry']
    line2 = gdf_nwb.at[link2,'geometry']

    zoekafstand = 5.0
    if link1[0] == node:
        a = Point(line1.coords[0])
        b = line1.interpolate(min(line1.length, zoekafstand))
    else:
        a = Point(line1.coords[-1])
        b = line1.interpolate(max(0, line1.length-zoekafstand))

    hoek1 = math.atan2(b.y-a.y, b.x-a.x) * 180 / math.pi
    
    if link2[0] == node:
        a = Point(line2.coords[0])
        b = line2.interpolate(min(line2.length, zoekafstand))
    else:
        a = Point(line2.coords[-1])
        b = line2.interpolate(max(0, line2.length-zoekafstand))

    hoek2 = math.atan2(b.y-a.y, b.x-a.x) * 180 / math.pi

    verschil = hoek1-hoek2
    
    if verschil < 0.0: verschil += 360.0
    if verschil > 180.0: verschil = 360.0 - verschil
    
    return verschil

def get_nwb_link(a,b,gdf_nwb):
    """ Hulpfunctie: zoek NWB index gegeven een A en B knoop """
    if (a,b) in gdf_nwb.index:
        return (a,b)
    elif (b,a) in gdf_nwb.index:
        return (b,a)
    else:
        return None
    
def get_buren_en_links_per_richting(gdf_netwerk):
    opvolgende_knopen = defaultdict(set)
    voorgaande_knopen = defaultdict(set)
    links = set()
    
    for (a,b) in gdf_netwerk.index:
        oneway = gdf_netwerk.at[(a,b),'oneway']
        
        if oneway in ['B','F']:
            links.add((a,b))
            opvolgende_knopen[a].add(b)
            voorgaande_knopen[b].add(a)

        if oneway in ['B','T']:
            links.add((b,a))
            opvolgende_knopen[b].add(a)
            voorgaande_knopen[a].add(b)
            
        if oneway not in ['B','F','T']:            
            print('oneway=%s, niet geimplementeerd' % oneway)

    return opvolgende_knopen, voorgaande_knopen, links

def zoek_geografische_verbanden(gdf_nwb, links, opvolgende_knopen, voorgaande_knopen, min_hoek_doorlopend):
    geo_beste_next_link = {}
    geo_beste_prev_link = {}
    for (a,b) in links:
        link_ab = get_nwb_link(a,b,gdf_nwb)

        # hier nog een aanpassing maken
        # links met een rechtsaf en een linksaf optie worden nu soms
        # doorgetrokken, dat is onwenselijk!
        opvolgende_knopen_b = opvolgende_knopen[b] - set([a])
        beste_hoek = min_hoek_doorlopend
        beste_link = None
        for c in opvolgende_knopen_b:
            link_bc = get_nwb_link(b,c,gdf_nwb)
            hoek_abc = compare_links_hoeken(b, link_ab, link_bc, gdf_nwb)

            if hoek_abc > beste_hoek:
                beste_hoek = hoek_abc
                beste_link = (b,c)

        if beste_link != None: geo_beste_next_link[a,b] = beste_link

        voorgaande_knopen_a = voorgaande_knopen[a] - set([b])
        beste_hoek = min_hoek_doorlopend
        beste_link = None
        for c in voorgaande_knopen_a:
            link_ca = get_nwb_link(c,a,gdf_nwb)
            hoek_cab = compare_links_hoeken(a, link_ab, link_ca, gdf_nwb)

            if hoek_cab > beste_hoek:
                beste_hoek = hoek_cab
                beste_link = (c,a)
                
        if beste_link != None:
            geo_beste_prev_link[a,b] = beste_link

    return geo_beste_next_link, geo_beste_prev_link

def koppel_links(geo_beste_next_link, geo_beste_prev_link, gdf_nwb, keys_hetzelfde):
    next_link = {}
    prev_link = {}
    for (a,b) in geo_beste_next_link:
        
        (b,c) = geo_beste_next_link[a,b]
        
                  
        if (b,c) not in geo_beste_prev_link: continue
        if geo_beste_prev_link[b,c] == (a,b):
            # check snelheid.
            link_ab = get_nwb_link(a,b,gdf_nwb)
            link_bc = get_nwb_link(b,c,gdf_nwb)

            alles_hetzelfde = True
            for key in keys_hetzelfde:
                if gdf_nwb.at[link_ab, key] != gdf_nwb.at[link_bc, key]:
                    alles_hetzelfde = False
                    
            
            # deze richtingencheck werkt mogelijk nog niet 100%...
            if alles_hetzelfde:
                next_link[a,b] = (b,c)
                prev_link[b,c] = (a,b)
                
    return next_link, prev_link

def ketens_maken(links, next_link, prev_link):
    link_opgenomen = set()
    ketens = set()
    for link in links:
        if link in link_opgenomen: continue

        keten = [link]
        link_opgenomen.add(link)
        
        huidige_link = link
        while huidige_link in next_link:
            huidige_link = next_link[huidige_link]
            if huidige_link in link_opgenomen: break
            
            link_opgenomen.add(huidige_link)
            keten.append(huidige_link)

        huidige_link = link
        while huidige_link in prev_link:
            huidige_link = prev_link[huidige_link]
            if huidige_link in link_opgenomen: break
            
            link_opgenomen.add(huidige_link)
            keten = [huidige_link] + keten

        ketens.add(tuple(keten))
    return ketens

def verzamel_keten_resultaten(ketens, gdf_nwb, keys_hetzelfde):#, keten_tweerichtingsweg):
    results = []
    for keten in ketens:
        
        coords = []
        knopen = []
        afstanden = []
        pos = 0.0
        keys = {}
        for i, link in enumerate(keten):
            if link in gdf_nwb.index:
                netwerk_index = link
                link_geo = gdf_nwb.at[netwerk_index,'geometry']
                link_coords = list(link_geo.coords)
            else:
                netwerk_index = (link[1],link[0])
                link_geo = gdf_nwb.at[netwerk_index,'geometry']
                link_coords = list(link_geo.coords)
                link_coords.reverse()

            # dit hoeft eigenlijk maar 1 keer.
            for key in keys_hetzelfde:
                keys[key] = gdf_nwb.at[netwerk_index, key]
                
            if i == 0:
                coords += [link_coords[0]]
                knopen.append('%d' % (link[0]))
                afstanden.append('%0.1f' % pos)

            link_lengte = link_geo.length
            coords += link_coords[1:]
            pos += link_lengte
            knopen.append('%d' % (link[1]))
            afstanden.append('%0.1f' % pos)
        
        
        keten_line = LineString(coords)
        result = {'Rijlijn_knopen': ','.join(knopen),
                  'Rijlijn_afstanden': ','.join(afstanden),
                  'geometry': keten_line}
        for key in keys_hetzelfde:
            result[key] = keys[key]
        results.append(result)
    return results



    
# INPUT
min_hoek_doorlopend = 80.0
    
netwerk_file = '02 Tussenresultaten/02_NWB_20260101_ontdubbeld.gpkg'
output_file = '02 Tussenresultaten/11_NWB_20260101_rijlijnen_auto_en_fiets.gpkg'

keys_hetzelfde = ['BST_CODE','BST_CODE_simpel']
    

gdf_netwerk = gpd.read_file(netwerk_file)
gdf_netwerk=gdf_netwerk.explode(index_parts=False) # probleem met multilinestring..


gdf_netwerk = gdf_netwerk[gdf_netwerk['BST_CODE_simpel'].isin(['Fietspad','Regulier','Parallelweg'])]

gdf_netwerk['oneway'] = 'N'
gdf_netwerk.loc[gdf_netwerk['RIJRICHTNG'] == 'B', 'oneway'] = 'B'
gdf_netwerk.loc[gdf_netwerk['RIJRICHTNG'] == 'H', 'oneway'] = 'F'
gdf_netwerk.loc[gdf_netwerk['RIJRICHTNG'] == 'T', 'oneway'] = 'T'
gdf_netwerk.loc[gdf_netwerk['RIJRICHTNG'] == 'O', 'oneway'] = 'B' # O = onbekend, komt o.a. voor bij NWB fietspad.
gdf_netwerk.set_index(['JTE_ID_BEG','JTE_ID_END'],inplace=True)

 
        

# richtingen op links verzamelen ('routeerbaar netwerk')
opvolgende_knopen, voorgaande_knopen, links = get_buren_en_links_per_richting(gdf_netwerk)

# stap 1: zoek de geografisch beste opvolglink en vorige link
geo_beste_next_link, geo_beste_prev_link = zoek_geografische_verbanden(gdf_netwerk, links, opvolgende_knopen, voorgaande_knopen, min_hoek_doorlopend)


# stap 2: indien twee links geografisch bij elkaar passen EN
# dezelfde snelheid hebben, koppel ze.
next_link, prev_link = koppel_links(geo_beste_next_link, geo_beste_prev_link, gdf_netwerk, keys_hetzelfde)


# stap 3: ketens maken, iedere link zit in precies 1 keten.
ketens = ketens_maken(links, next_link, prev_link)


# resultaten wegschrijven
results = verzamel_keten_resultaten(ketens, gdf_netwerk, keys_hetzelfde)
print('%d ketens gegenereerd' % len(results))

if len(results) > 0:
    gdf_rijlijnen = gpd.GeoDataFrame(results,crs=gdf_netwerk.crs)
    gdf_rijlijnen['rijlijn_index'] = list(range(len(gdf_rijlijnen)))
    gdf_rijlijnen.to_file(output_file, driver='GPKG')

  
