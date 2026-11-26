import geopandas as gpd
gpd.options.io_engine = "pyogrio"
import os
os.environ["PYOGRIO_USE_ARROW"] = "1"
from collections import *
from pprint import *
import copy
import math
import shapely
from shapely.geometry import *

def get_status(events_actief):

    if len(events_actief) == 0: return None
    else: return list(events_actief)[0][2]
    
    


def koppelingen_nabewerken(koppelingen, status_functie):
    events = defaultdict(list)

    for (van, naar, koppeldata) in koppelingen:
        if van == naar: continue # bugje, misschien beter ergens anders oplossen.
        events[van].append(('Start', (van, naar, koppeldata)))
        events[naar].append(('Eind', (van, naar, koppeldata)))

    if len(events) == 0: return {}
    
    event_posities = sorted(events)
    events_actief = set()
    beginpos_interval = event_posities[0]
    
    for (start_of_eind, event) in events[beginpos_interval]:
        if start_of_eind == 'Start':
            events_actief.add(event)

    intervallen = {}
    for pos in event_posities[1:]:
        events_actief_nieuw = copy.deepcopy(events_actief)
        for (start_of_eind, event) in events[pos]:
            if start_of_eind == 'Start':
                events_actief_nieuw.add(event)
            else:
                events_actief_nieuw.remove(event)

        if status_functie(events_actief) != status_functie(events_actief_nieuw):
            intervallen[beginpos_interval, pos] = status_functie(events_actief)
            beginpos_interval = pos

        events_actief = events_actief_nieuw
    return intervallen

# INPUT
snelheden_file = '02 Tussenresultaten/23_WKD_snelheden_20260101_selectie.gpkg'
nwb_file = '02 Tussenresultaten/02_NWB_20260101_ontdubbeld.gpkg'
nwb_opgeknipt_file = '02 Tussenresultaten/02_NWB_20260101_opgeknipt.gpkg'
rijlijnen_file = '02 Tussenresultaten/11_NWB_20260101_rijlijnen_auto_en_fiets.gpkg'

output_file = '02 Tussenresultaten/24_rijlijnen_met_WKD_snelheidslimieten.gpkg'



gdf_snelheden = gpd.read_file(snelheden_file)

# AB knopen aan snelheden toevoegen.
# hier is wat boekhoudkunde nodig voor de NWB wegvakken die opgeknipt zijn
# bij het ontdubbelen.
gdf_nwb = gpd.read_file(nwb_file)
gdf_nwb.set_index('WVK_ID',inplace=True)
gdf_snelheden['JTE_ID_BEG'] = gdf_snelheden['WVK_ID'].map(gdf_nwb['JTE_ID_BEG'].to_dict().get)
gdf_snelheden['JTE_ID_END'] = gdf_snelheden['WVK_ID'].map(gdf_nwb['JTE_ID_END'].to_dict().get)
gdf_nwb.reset_index(drop=False,inplace=True)
gdf_nwb.drop_duplicates(['JTE_ID_BEG','JTE_ID_END'],inplace=True)
gdf_nwb.set_index(['JTE_ID_BEG','JTE_ID_END'],inplace=True)

gdf_nwb_opgeknipt = gpd.read_file(nwb_opgeknipt_file)
ab_per_wvk = defaultdict(list)
for i in gdf_nwb_opgeknipt.index:
    a = gdf_nwb_opgeknipt.at[i,'JTE_ID_BEG']
    b = gdf_nwb_opgeknipt.at[i,'JTE_ID_END']
    van = gdf_nwb_opgeknipt.at[i,'WVK_pos_van']
    naar = gdf_nwb_opgeknipt.at[i,'WVK_pos_naar']
    ab_per_wvk[gdf_nwb_opgeknipt.at[i,'WVK_ID']].append((a,b,van,naar))
    

snelheden_per_ab = defaultdict(list)
for i_snel in gdf_snelheden.index:
    wvk_id = gdf_snelheden.at[i_snel,'WVK_ID']

    a = gdf_snelheden.at[i_snel,'JTE_ID_BEG']
    b = gdf_snelheden.at[i_snel,'JTE_ID_END']
    van = gdf_snelheden.at[i_snel,'VAN']
    naar = gdf_snelheden.at[i_snel,'NAAR']
    snelheid = gdf_snelheden.at[i_snel,'MAXSHD']


    if wvk_id in ab_per_wvk: # betreft een opgeknipt wegvak, extra boekhoudkunde nodig om de WKD-data over te zetten naar AB-paren.
        for (a_wvk,b_wvk,wvk_van, wvk_naar) in ab_per_wvk[wvk_id]:
            van_knip = max(van, wvk_van)
            naar_knip = min(naar, wvk_naar)
            
            if van_knip < naar_knip:
                snelheden_per_ab[a_wvk,b_wvk].append((van_knip-wvk_van,naar_knip-wvk_van,snelheid)) # -wvk_van voor relatieve positie tov nieuw wegvak.

    else:
        
        snelheden_per_ab[a,b].append((van,naar,snelheid))
        
# per rijlijn de aan het NWB gekoppelde snelheden overnemen.
gdf_rijlijnen = gpd.read_file(rijlijnen_file)
gdf_rijlijnen.set_index('rijlijn_index',inplace=True)
results = []
for i_rijlijn in gdf_rijlijnen.index:
    knopen = list(map(int,gdf_rijlijnen.at[i_rijlijn,'Rijlijn_knopen'].split(',')))

    afstand = 0
    gekoppelde_snelheden = []
    for i in range(len(knopen)-1):
        a, b = knopen[i], knopen[i+1]

        if (a,b) in gdf_nwb.index:
            lengte = gdf_nwb.at[(a,b),'geometry'].length
        else:
            lengte = gdf_nwb.at[(b,a),'geometry'].length

        if (a,b) in snelheden_per_ab:
            for (van, naar, snelheid) in snelheden_per_ab[a,b]:
                gekoppelde_snelheden.append((math.floor(afstand+van), math.ceil(afstand+min(lengte,naar)), snelheid))
        elif (b,a) in snelheden_per_ab:
            for (van, naar, snelheid) in snelheden_per_ab[b,a]:
                gekoppelde_snelheden.append((math.floor(afstand+max(0,lengte-naar)), math.ceil(afstand+lengte-van), snelheid))
        afstand += lengte

    gekoppelde_snelheden = set(gekoppelde_snelheden) # voor bugje waarbij 2x dezelfde koppeling gemaakt wordt (2x in WKD??)
    intervallen = koppelingen_nabewerken(gekoppelde_snelheden, get_status)
    for (van, naar) in intervallen:
        geo = shapely.ops.substring(gdf_rijlijnen.at[i_rijlijn,'geometry'],van,naar)

        if not isinstance(geo, LineString): continue
        result = {'rijlijn_index': i_rijlijn,
                  'van': van,
                  'naar': naar,
                  'WKD_snelheidslimiet': intervallen[van,naar],
                  'geometry': geo}
        results.append(result)

gpd.GeoDataFrame(results,crs=gdf_rijlijnen.crs).to_file(output_file,driver='GPKG')
    
            

    
    
