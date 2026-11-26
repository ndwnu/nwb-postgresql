import geopandas as gpd
gpd.options.io_engine = "pyogrio"
import os
os.environ["PYOGRIO_USE_ARROW"] = "1"
from shapely.geometry import *
import datetime
import rtree
import math


def get_hoek_list(coords):
    x1,y1 = coords[0]
    x2,y2 = coords[-1]

    hoek = 180.0 * math.atan2(y2-y1,x2-x1) / math.pi
    if hoek < 0.0: hoek += 360.0
    return hoek

def get_hoek(geo):
    if isinstance(geo, list): return get_hoek_list(geo)
    elif isinstance(geo, LineString): return get_hoek_list(list(geo.coords))
    else:
        # meerdere lijnstukken, pak het langste lijnstuk...
        max_length = 0
        max_geo = None
        for sub_geo in geo.geoms:
            if sub_geo.length >= max_length:
                max_geo = sub_geo
                max_length = sub_geo.length
        return get_hoek_list(list(max_geo.coords))

def zoek_matches_bord_wegvak(point_bord, bord_hoek, netwerk_index, gdf_netwerk, 
                             max_bord_afstand, tegenrichting):
    
    result = netwerk_index.intersection(point_bord.buffer(max_bord_afstand).bounds)
    gevonden_matches = []
    for match_index in result:
        
        # ok per match:
        # zoek dichtstbijzijnde punt op de lijn
        match_line = gdf_netwerk.at[match_index,'geometry']
        afstand = match_line.distance(point_bord)
        if afstand > max_bord_afstand: continue
        
        line_pos = match_line.project(point_bord)
        line_point = match_line.interpolate(line_pos)

        a = max(0, line_pos - 5.0)
        b = min(match_line.length, line_pos + 5.0)
        point_a = match_line.interpolate(a)
        point_b = match_line.interpolate(b)
        line_dir = LineString([point_a,point_b])
        hoek = get_hoek(line_dir)

        
        # verschil ligt tussen -180 en 180 graden
        verschil = bord_hoek-hoek
        if verschil > 180.0: verschil -= 360.0
        if verschil < -180.0: verschil += 360.0

        if abs(verschil) < 60.0:
            # de lijn loopt binnen 60 graden parallel met de wijsrichting van het bord
            # en de digitaliseerrichting van de lijn is ook dezelfde richting als de wijsrichting van het bord
            # het bord (de borden die we nu beschouwen) zou je aan het begin van het wegvak verwachten of eventueel ergens
            # halverwege, maar niet aan het eind.
            lengte_verwijsgebied_bord = match_line.length - line_pos
            richting = 'Heen'

            d = (point_b.x-point_a.x) * (point_bord.y-point_a.y) - (point_b.y-point_a.y) * (point_bord.x-point_a.x)
            if d > 0:
                match_zijde = 'Links'
            else:
                match_zijde = 'Rechts'

            gevonden_matches.append((match_index, line_pos, richting, match_zijde, afstand, verschil))
        
        
    return gevonden_matches

# INPUT
borden_file = '02 Tussenresultaten/21_Verkeersborden_20260409.gpkg'
rijlijnen_file = '02 Tussenresultaten/11_NWB_20260101_rijlijnen_auto_en_fiets.gpkg'
    
outputfile_borden = '02 Tussenresultaten/22_verkeersborden_gekoppeld.gpkg'

max_bord_afstand = 16.0
penalty_links = 5.0
penalty_wegtype = 20.0

get_bord_hoek = {'O': 0.0,
             'W': 180.0,
             'N': 90.0,
             'Z': 270.0}


    
gdf_netwerk = gpd.read_file(rijlijnen_file)

# spatial index aanmaken voor rijlijnen
def generator_function(gdf):
    for i, geo in enumerate(gdf['geometry']):
        yield (i, geo.bounds, None)
netwerk_spatial_index = rtree.index.Index(generator_function(gdf_netwerk))


time = datetime.datetime.now()
counter = 0
gdf_borden = gpd.read_file(borden_file)
gdf_borden = gdf_borden[gdf_borden['side'].isin(['O','W','N','Z'])] # !!!
gdf_borden.reset_index(inplace=True)

# hier nog onderscheid maken naar borden die puur voor fietspaden gelden en borden die ook voor andere wegen kunnen gelden.
for i_bord in gdf_borden.index:
    counter += 1
    if counter % 1000 == 0:
        t_new = datetime.datetime.now()
        print('%d - %0.2f sec' % (counter, (t_new-time).total_seconds()))
        time = t_new

    point_bord = gdf_borden.at[i_bord,'geometry']
    bord_hoek = get_bord_hoek[gdf_borden.at[i_bord,'side']]

    # matches voor WEGVAKKEN
    matches_netwerk = zoek_matches_bord_wegvak(point_bord, bord_hoek, netwerk_spatial_index, gdf_netwerk,
                                                       max_bord_afstand, tegenrichting=False)

    beste_match = None
    beste_score = max_bord_afstand + penalty_links
    for i_netwerk, line_pos, richting, match_zijde, afstand, verschil in matches_netwerk:
        
        score = afstand
        if match_zijde == 'Links': score += penalty_links

        # later uit te bereiden.
        # vooralsnog: haaientandenbord kan ook aan FP worden gekoppeld.
        if gdf_borden.at[i_bord,'rvvCode'] in ['B1','B3','B4','B5',
                                               'D1','D2','L2'] and gdf_netwerk.at[i_netwerk,'BST_CODE'] == 'FP':
            score += penalty_wegtype

        if score <= beste_score:
            beste_score = score
            beste_match = i_netwerk

    if beste_match != None:
        line_geo = gdf_netwerk.at[beste_match,'geometry']
        projectie = line_geo.interpolate(line_geo.project(point_bord))
        
        gdf_borden.at[i_bord,'gekoppelde_rijlijn'] = gdf_netwerk.at[beste_match,'rijlijn_index']
        gdf_borden.at[i_bord,'gekoppelde_rijlijn_pos'] = line_geo.project(point_bord)
        gdf_borden.at[i_bord,'geometry_koppeling'] = LineString([point_bord,projectie])
        
        
gdf_borden['geometry'] = gdf_borden['geometry_koppeling']
gdf_borden.drop(columns=['geometry_koppeling']).to_file(outputfile_borden, driver='GPKG')
    
    
