import geopandas as gpd
gpd.options.io_engine = "pyogrio"
import os
os.environ["PYOGRIO_USE_ARROW"] = "1"
import networkx as nx
from collections import *
from shapely.geometry import Point, LineString
import datetime

def verwijder_tussenknopen(gdf_netwerk, keys_hetzelfde, keys_kopieren):
    """
    versimpel een netwerk door overbodige tussenknopen te verwijderen.
    
    benodigde input velden: A, B, oneway (B, F, N, [T])

    keys_hetzelfde: deze moeten hetzelfde zijn om samengevoegd te worden
    """
    print('netwerk voor correcties: %d' % len(gdf_netwerk))
    time = datetime.datetime.now()

    # netwerk uitlezen
    netwerk_links = defaultdict(dict)
    knoop_wegvakken = defaultdict(set)

    knoop_xy = {}
    knoop_buren = defaultdict(set)
    get_wvk = defaultdict(list)
    for index in gdf_netwerk.index:
        a = gdf_netwerk.at[index,'A']
        b = gdf_netwerk.at[index,'B']

        if a == b: continue # zelfde A en B knoop

        knoop_xy[a] = Point(gdf_netwerk.at[index,'geometry'].coords[0])
        knoop_xy[b] = Point(gdf_netwerk.at[index,'geometry'].coords[-1])
        
        for c in ['A','B','oneway', 'geometry'] + keys_kopieren:
            netwerk_links[index][c] = gdf_netwerk.at[index,c]
                
        get_wvk[a,b].append(index)
        get_wvk[b,a].append(index)

        knoop_wegvakken[a].add(index)
        knoop_wegvakken[b].add(index)

        knoop_buren[a].add(b)
        knoop_buren[b].add(a)
        
    t_new = datetime.datetime.now()
    print('netwerk ingelezen en inladen in  %0.1f minuten' % ((t_new-time).total_seconds()/60.0))
    time = datetime.datetime.now()


    # controleren op doorgaande verbinden waar de wegkenmerken niet veranderen.
    # deze worden versimpeld (tussenknopen verwijderen) zodat een logischer en makkelijker analyseerbaar netwerk ontstaat.
    aantal_knopen = len(knoop_buren)
    samenvoegingen = {}
    opvolgnummer_links = max(netwerk_links)+1
    rekenstap = 1
    while True:
        print('algoritme doorgaand: rekenstap %d, %d knopen' % (rekenstap, aantal_knopen))
        rekenstap += 1              

        # identificeer links die samengevoegd kunnen worden als paren van 3 opeenvolgende knopen.
        doorgaand = []
        for k in knoop_buren:
            if not (len(knoop_buren[k]) == 2 and len(knoop_wegvakken[k]) == 2): continue # ook de tweede eis, vanwege dubbele AB-knopen.
                
            a,b = list(knoop_buren[k])
            
            if a == k or b == k: continue # 1 van de buren is de link zelf... misschien hier later nog iets mee doen.

            # het samenvoegen van de link zorgt voor een dubbele ab-knoop.
            # in dit geval wordt er geen samenvoeging uitgevoerd.
            if (a,b) in get_wvk: continue
            
            if len(get_wvk[a,k]) > 1 or len(get_wvk[k,b]) > 1: continue # dubbele knoop, komt misschien niet voor na bovenstaande voorwaarden.
            
            wvk_ak = get_wvk[a,k][0]
            wvk_kb = get_wvk[k,b][0]

            # alleen samenvoegen waar sprake is van dezelfde kenmerken uit keys_hetzelfde
            keys_verschillend = False
            for key in keys_hetzelfde:
                if netwerk_links[wvk_ak][key] != netwerk_links[wvk_kb][key]:
                    keys_verschillend = True
                    break
            if keys_verschillend:
                continue
            
            if netwerk_links[wvk_ak]['oneway'] == 'B' and netwerk_links[wvk_kb]['oneway'] == 'B':
                doorgaand.append((a,k,b))
                
            elif netwerk_links[wvk_ak]['oneway'] == 'N' and netwerk_links[wvk_kb]['oneway'] == 'N':
                doorgaand.append((a,k,b))
                
            elif netwerk_links[wvk_ak]['oneway'] == 'F' and netwerk_links[wvk_kb]['oneway'] == 'F': # eventueel nog toevoegen: de terugrichting (voor zover die voorkomt)
                if netwerk_links[wvk_ak]['A'] == a and netwerk_links[wvk_kb]['B'] == b: # a->k->b
                    doorgaand.append((a,k,b))
                    
                elif netwerk_links[wvk_kb]['A'] == b and netwerk_links[wvk_ak]['B'] == a: # b->k->a
                    doorgaand.append((b,k,a))
                    
                else: # a-> k <-b; niet samenvoegen.
                    pass

        # voeg hier de samenvoegingen uit. 
        for (a,k,b) in doorgaand:
            # extra voorwaarde, want tijdens het updaten kunnen dingen tussentijds wegvallen.
            if not (a in knoop_buren and b in knoop_buren and (a,b) not in get_wvk): continue
            
            del knoop_buren[k]
           
            if netwerk_links[get_wvk[a,k][0]]['oneway'] in ['B','N']: # a <> k <> b
                knoop_buren[a].add(b)
                knoop_buren[b].add(a)

                knoop_buren[a].remove(k)
                knoop_buren[b].remove(k)
            else: # oneway_fiets=F; a->k->b
                knoop_buren[a].add(b)
                knoop_buren[b].add(a)

                knoop_buren[a].remove(k)
                knoop_buren[b].remove(k)
                            

            wvk_id_new = opvolgnummer_links
            opvolgnummer_links += 1

            # overnemen kenmerken van één onderliggende link...
            for c in ['oneway'] + keys_kopieren:
                netwerk_links[wvk_id_new][c] = netwerk_links[get_wvk[a,k][0]][c]
            
            wvk_ak = get_wvk[a,k][0]
            line_ak = netwerk_links[wvk_ak]['geometry']
            if netwerk_links[wvk_ak]['A'] != a:
                coords = list(line_ak.coords)
                coords.reverse()
                line_ak = LineString(coords)

            wvk_kb = get_wvk[k,b][0]
            line_kb = netwerk_links[wvk_kb]['geometry']
            if netwerk_links[wvk_kb]['A'] != k:
                coords = list(line_kb.coords)
                coords.reverse()
                line_kb = LineString(coords)
           
            netwerk_links[wvk_id_new]['geometry'] = LineString(list(line_ak.coords) + list(line_kb.coords)[1:])
            
            netwerk_links[wvk_id_new]['A'] = a
            netwerk_links[wvk_id_new]['B'] = b
            
            get_wvk[a,b].append(wvk_id_new)
            get_wvk[b,a].append(wvk_id_new)

            samenvoegingen[a,b] = [(a,k),(k,b)]
            samenvoegingen[b,a] = [(b,k),(k,a)]

                
        if len(knoop_buren) == aantal_knopen:
            break
        
        aantal_knopen = len(knoop_buren)

    t_new = datetime.datetime.now()
    print('doorgaande links samenvoegen in  %0.1f minuten' % ((t_new-time).total_seconds()/60.0))

    # het vereenvoudigde netwerk weer als gdf bewaren.

    # netwerk_links bevat [vooralsnog] alle links, ook de links vóór het samenvoegen
    # knoop_buren bevat het eindnetwerk.
    # selecteer daarom op de navolgende manier.  
    links_wegschrijven = set()
    for a in knoop_buren:
        for b in knoop_buren[a]:
            for wvk_id in get_wvk[a,b]: 
                if netwerk_links[wvk_id]['A'] == a:
                    links_wegschrijven.add((a,b))


    results = []
    for (a,b) in links_wegschrijven:
        knopen_origineel = [a,b]

        while True:
            knopen_nieuw = []
            for i in range(len(knopen_origineel)-1):
                x,y = knopen_origineel[i], knopen_origineel[i+1]

                knopen_nieuw.append(x)
                if (x,y) in samenvoegingen:
                    k = samenvoegingen[x,y][0][1]
                    knopen_nieuw.append(k)
            knopen_nieuw.append(b)

            if knopen_nieuw != knopen_origineel:
                knopen_origineel = knopen_nieuw
            else:
                break


        for wvk_id in get_wvk[a,b]:
            if netwerk_links[wvk_id]['A'] != a: continue 
            result = {'A': a,
                      'B': b,
                      'knopen': ','.join(map(str,knopen_origineel)),
                      'oneway': netwerk_links[wvk_id]['oneway'],
                      'geometry': netwerk_links[wvk_id]['geometry']}
            for key in keys_kopieren:
                result[key] = netwerk_links[wvk_id][key]
        
            results.append(result)

    gdf_netwerk = gpd.GeoDataFrame(results, crs=gdf_netwerk.crs)
    print('netwerk na correcties: %d' % len(gdf_netwerk))
    return gdf_netwerk



# INPUT
netwerk_file = '02 Tussenresultaten/02_NWB_20260101_ontdubbeld.gpkg'
outputfile = '02 Tussenresultaten/12_NWB_20260101_versimpeld.gpkg'
keys_kopieren = ['WEGBEHSRT','WEGBEHNAAM','BST_CODE','BST_CODE_simpel','RIJRICHTNG', 'STT_NAAM']
keys_hetzelfde = []


time = datetime.datetime.now()
gdf_netwerk = gpd.read_file(netwerk_file)

# Selectie van reguliere auto toegankelijke wegen.
gdf_netwerk = gdf_netwerk[gdf_netwerk['BST_CODE_simpel'].isin(['Regulier','Rotonde'])]

# altijd een key 'oneway' aanmaken voor het algoritme.
gdf_netwerk['oneway'] = 'N'
gdf_netwerk.loc[gdf_netwerk['RIJRICHTNG'] == 'B', 'oneway'] = 'B'
gdf_netwerk.loc[gdf_netwerk['RIJRICHTNG'] == 'H', 'oneway'] = 'F'
gdf_netwerk.loc[gdf_netwerk['RIJRICHTNG'] == 'T', 'oneway'] = 'T'
gdf_netwerk.loc[gdf_netwerk['RIJRICHTNG'] == 'O', 'oneway'] = 'B' # O = onbekend, komt o.a. voor bij NWB fietspad.

gdf_netwerk.rename(columns={'JTE_ID_BEG': 'A', 'JTE_ID_END': 'B'},inplace=True)
    

# netwerk versimpelen en wegschrijven.
gdf_netwerk = verwijder_tussenknopen(gdf_netwerk, keys_hetzelfde, keys_kopieren)
gdf_netwerk.to_file(outputfile,driver='GPKG')





