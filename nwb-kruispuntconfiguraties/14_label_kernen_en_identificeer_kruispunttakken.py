import geopandas as gpd
gpd.options.io_engine = "pyogrio"
import os
os.environ["PYOGRIO_USE_ARROW"] = "1"
import networkx as nx
from collections import *
import datetime
import pandas as pd
from shapely.geometry import *
from shapely.ops import unary_union, substring
import rtree
import math
import copy

    
def get_hoek_windrichting(hoek):
    if hoek < 0: hoek += 360
            
    if hoek <= 22.5 or hoek >= 360 - 22.5: return 'O'
    elif 45 - 22.5 <= hoek <= 45 + 22.5: return 'NO'
    elif 90 - 22.5 <= hoek <= 90 + 22.5: return 'N'
    elif 135 - 22.5 <= hoek <= 135 + 22.5: return 'NW'
    elif 180 - 22.5 <= hoek <= 180 + 22.5: return 'W'
    elif 225 - 22.5 <= hoek <= 225 + 22.5: return 'ZW'
    elif 270 - 22.5 <= hoek <= 270 + 22.5: return 'Z'
    else: return 'ZO'

                
def analyseer_kruispunttakken(kruispunt_juncties, junctie_rijlijnen, gdf_rijlijnen):
    ingaande_rijlijnen = {}
    uitgaande_rijlijnen = {}

    afstanden_hoekbepaling = [10, 25] # meter. vooralsnog 2 hoeken vaststellen!
    for junctie in kruispunt_juncties:
        for rijlijn_index, rijlijn_junctie_pos, rijlijn_junctie_afstand in junctie_rijlijnen[junctie]:
            rijlijn_knopen = gdf_rijlijnen.at[rijlijn_index,'Rijlijn_knopen']
            rijlijn_geo = gdf_rijlijnen.at[rijlijn_index,'geometry']
            
            # ingaand
            if rijlijn_junctie_pos > 0 and rijlijn_knopen[rijlijn_junctie_pos-1] not in kruispunt_juncties:
                line = substring(rijlijn_geo, max(0.0, rijlijn_junctie_afstand - 100.0), rijlijn_junctie_afstand)
                
                ingaande_rijlijnen[rijlijn_index] = {'knoop_aansluiting': junctie,
                                                'van': max(0.0, rijlijn_junctie_afstand - 100.0), 
                                                'naar': rijlijn_junctie_afstand, 
                                                'geometry': line}
                a = Point(line.coords[-1])
                for afstand_hoekbepaling in afstanden_hoekbepaling:
                    b = line.interpolate(max(0.0, line.length-afstand_hoekbepaling))
                    hoek = math.atan2(b.y-a.y, b.x-a.x) * 180 / math.pi
                    ingaande_rijlijnen[rijlijn_index][f'hoek_{afstand_hoekbepaling}'] = hoek
                    
            # uitgaand
            if rijlijn_junctie_pos < len(rijlijn_knopen) -1 and rijlijn_knopen[rijlijn_junctie_pos+1] not in kruispunt_juncties:
                line = substring(rijlijn_geo, rijlijn_junctie_afstand, min(rijlijn_junctie_afstand+100.0, rijlijn_geo.length))
                if not isinstance(line, LineString):
                    print('ernstig probleem, nog oplossen')
                    continue

                uitgaande_rijlijnen[rijlijn_index] = {'knoop_aansluiting': junctie,
                                                 'van':rijlijn_junctie_afstand, 
                                                 'naar': min(rijlijn_junctie_afstand+100.0, rijlijn_geo.length),
                                                 'geometry': line}
                
                a = Point(line.coords[0])
                for afstand_hoekbepaling in afstanden_hoekbepaling:
                    b = line.interpolate(min(line.length,afstand_hoekbepaling))
                    hoek = math.atan2(b.y-a.y, b.x-a.x) * 180 / math.pi
                    uitgaande_rijlijnen[rijlijn_index][f'hoek_{afstand_hoekbepaling}'] = hoek
                    
                
    
    # nu combineren van kruispunttakken.
    # doel: tellen aantal takken, mogelijk logischere naamgeving in toekomst.
    # en controle op inconsistenties...
    # eventueel: straatnamen check
    # nieuw: alleen koppelen als er sprake is van dezelfde bst code.
    # gaat wellicht nog niet goed bij lussen in rijlijnen.
    takken_graph = nx.Graph()

    for rijlijn_index in ingaande_rijlijnen:
        takken_graph.add_node((rijlijn_index,'Ingaand'))
    for rijlijn_index in uitgaande_rijlijnen:
        takken_graph.add_node((rijlijn_index,'Uitgaand'))

    for afstand_hoekbepaling in afstanden_hoekbepaling:
        for rijlijn_ingaand_index in ingaande_rijlijnen:
            hoek_ingaand = ingaande_rijlijnen[rijlijn_ingaand_index][f'hoek_{afstand_hoekbepaling}']

            for rijlijn_uitgaand_index in uitgaande_rijlijnen:
                hoek_uitgaand = uitgaande_rijlijnen[rijlijn_uitgaand_index][f'hoek_{afstand_hoekbepaling}']

                verschil_hoek = hoek_ingaand - hoek_uitgaand
                if verschil_hoek < 0.0: verschil_hoek += 360.0
                if verschil_hoek > 180.0: verschil_hoek = 360.0 - verschil_hoek

                if verschil_hoek < 45.0: # tak gevonden.
                    if gdf_rijlijnen.at[rijlijn_ingaand_index,'BST_CODE_simpel'] == gdf_rijlijnen.at[rijlijn_uitgaand_index,'BST_CODE_simpel']:
                        takken_graph.add_edge((rijlijn_ingaand_index, 'Ingaand'), (rijlijn_uitgaand_index, 'Uitgaand'))

    takken = []
    taknummer = 1
    for cc in nx.connected_components(takken_graph):
        cc = list(cc)

        # geometry van de tak afleiden. later de code hieronder vereenvoudigen.
        # geometrie nu: van het kruispunt af, dan is de hoek intuitiever.
        startpunten = []
        eindpunten = []
        middelpunten = []
        bst_codes = set() # per definitie hierboven heeft een tak maar één bst_code(_simpel)
        rijlijnen_ingaand = []
        rijlijnen_uitgaand = []
        for (rijlijn_index, richting) in cc:
            bst_codes.add(gdf_rijlijnen.at[rijlijn_index,'BST_CODE_simpel'])
            if richting == 'Ingaand':
                rijlijnen_ingaand.append(rijlijn_index)
                ingaande_rijlijnen[rijlijn_index]['Taknummer'] = taknummer

                line_ingaand = ingaande_rijlijnen[rijlijn_index]['geometry']
                eindpunten.append(line_ingaand.interpolate(-25.0)) # max min toevoegen...
                middelpunten.append(line_ingaand.interpolate(-12.5)) # max min toevoegen...
                startpunten.append(line_ingaand.coords[-1])
            else:
                rijlijnen_uitgaand.append(rijlijn_index)
                uitgaande_rijlijnen[rijlijn_index]['Taknummer'] = taknummer

                line_uitgaand = uitgaande_rijlijnen[rijlijn_index]['geometry']
                eindpunten.append(line_uitgaand.interpolate(25.0)) # max min toevoegen...
                middelpunten.append(line_uitgaand.interpolate(12.5)) # max min toevoegen...
                startpunten.append(line_uitgaand.coords[0])

        tak_startpunt = MultiPoint(startpunten).centroid
        tak_middelpunt = MultiPoint(middelpunten).centroid
        tak_eindpunt = MultiPoint(eindpunten).centroid
        tak_geometry = LineString([tak_startpunt,tak_middelpunt,tak_eindpunt])
        # hier wil je ook de windrichting en hoek vaststellen eigenlijk.
        tak_hoek = math.atan2(tak_eindpunt.y-tak_startpunt.y, tak_eindpunt.x-tak_startpunt.x) * 180 / math.pi
        tak_windrichting = get_hoek_windrichting(tak_hoek)

        tak = {'Taknummer': taknummer,
               'windrichting': tak_windrichting,
               'rijlijnen_ingaand': rijlijnen_ingaand,
               'rijlijnen_uitgaand': rijlijnen_uitgaand,
               'hoek': tak_hoek,
               'geometry': tak_geometry}
        
        if len(cc) == 2:
            if cc[0][1] == 'Ingaand' and cc[1][1] == 'Uitgaand':
                rijlijn_ingaand_index = cc[0][0]
                rijlijn_uitgaand_index = cc[1][0]
                
            elif cc[0][1] == 'Uitgaand' and cc[1][1] =='Ingaand':
                rijlijn_ingaand_index = cc[1][0]
                rijlijn_uitgaand_index = cc[0][0]

            else:
                print(cc)
                raise
                
            line_ingaand = ingaande_rijlijnen[rijlijn_ingaand_index]['geometry']
            line_uitgaand = uitgaande_rijlijnen[rijlijn_uitgaand_index]['geometry']
                
            # bereken de gemiddelde hoek
            # wellicht is deze berekening ook geschikt voor een visualisatie van de tak.
            a_x = 0.5 * (line_ingaand.coords[-1][0] + line_uitgaand.coords[0][0])
            a_y = 0.5 * (line_ingaand.coords[-1][1] + line_uitgaand.coords[0][1])
            b_x = 0.5 * (line_ingaand.interpolate(-25.0).x + line_uitgaand.interpolate(25.0).x)
            b_y = 0.5 * (line_ingaand.interpolate(-25.0).y + line_uitgaand.interpolate(25.0).y)
            hoek_gemiddeld = math.atan2(b_y-a_y, b_x-a_x) * 180 / math.pi
            windrichting = get_hoek_windrichting(hoek_gemiddeld)

            ingaande_rijlijnen[rijlijn_ingaand_index]['windrichting'] = windrichting
            uitgaande_rijlijnen[rijlijn_uitgaand_index]['windrichting'] = windrichting

            tak['richtingen_open'] = 'ingaand en uitgaand'
            tak['bst_codes'] = ','.join(sorted(bst_codes))
            
            # ingaande en uitgaande rijlijn sluit aan op één punt (op dezelfde junctie)
            eerste_junctie_ingaand = ingaande_rijlijnen[rijlijn_ingaand_index]['knoop_aansluiting']
            eerste_junctie_uitgaand = uitgaande_rijlijnen[rijlijn_uitgaand_index]['knoop_aansluiting']

            if eerste_junctie_ingaand == eerste_junctie_uitgaand:
                tak['gescheiden_rijbanen'] = 'nee'
            else:
                tak['gescheiden_rijbanen'] = 'ja'

            
        elif len(cc) == 1:
            # nog stukje opschonen.
            if cc[0][1] == 'Ingaand':
                rijlijn_ingaand_index = cc[0][0]
                windrichting = get_hoek_windrichting(ingaande_rijlijnen[rijlijn_ingaand_index]['hoek_25'])
                ingaande_rijlijnen[rijlijn_ingaand_index]['windrichting'] = windrichting

                tak['richtingen_open'] = 'ingaand'
                tak['bst_codes'] = ','.join(sorted(bst_codes))
                tak['gescheiden_rijbanen'] = 'nvt'
                                            
            else:
                rijlijn_uitgaand_index = cc[0][0]
                windrichting = get_hoek_windrichting(uitgaande_rijlijnen[rijlijn_uitgaand_index]['hoek_25'])
                
                uitgaande_rijlijnen[rijlijn_uitgaand_index]['windrichting'] = windrichting

                tak['richtingen_open'] = 'uitgaand'
                tak['bst_codes'] = ','.join(sorted(bst_codes))
                tak['gescheiden_rijbanen'] = 'nvt'
                
        else: # >2 rijlijnen onder ongeveer dezelfde hoek.
            tak['richtingen_open'] = 'problematische tak'
            tak['bst_codes']  = ','.join(sorted(bst_codes))
            tak['gescheiden_rijbanen'] = 'problematische tak'

        takken.append(tak)
        taknummer += 1
        
    return takken, ingaande_rijlijnen, uitgaande_rijlijnen

def kruispunt_vorm_afleiden(juncties, takken, vorm_interpretatie):
    bst_codes = Counter()
    vorm = 'Onbekend'
    for tak in takken:
        bst_codes[tak['bst_codes']] += 1

    regulier = bst_codes['Regulier']
    fiets = bst_codes['Fietspad']
    parallel = bst_codes['Parallelweg']

    if (regulier, fiets, parallel) in vorm_interpretatie:
        return vorm_interpretatie[regulier, fiets, parallel]
    else:
        print(f'{juncties}-- Regulier:{regulier}, Fietspad:{fiets}, Parallelweg:{parallel} niet in tabel interpretatie vorm')
        return 'Onbekend','Onbekend'

    
def kruispunt_data_verzamelen(juncties, geo, vorm, hoofdgroep, takken, ingaande_rijlijnen, uitgaande_rijlijnen):

    result_rijlijnen = []
    for type_rijlijn, rijlijnen in [('Ingaand', ingaande_rijlijnen),
                                    ('Uitgaand', uitgaande_rijlijnen)]:
                                     
        for rijlijn in rijlijnen:
            result_rijlijn = {'Juncties': juncties,
                              'Taknummer': rijlijnen[rijlijn]['Taknummer'],
                              'Vorm': vorm,
                              'Hoofdgroep': hoofdgroep,
                              'Rijlijn_index': rijlijn,
                              'Type': type_rijlijn,
                              'van': rijlijnen[rijlijn]['van'],
                              'naar': rijlijnen[rijlijn]['naar'],
                              'geometry': rijlijnen[rijlijn]['geometry']}

            result_rijlijnen.append(result_rijlijn)

    
    result = {'Juncties': juncties,
              'Vorm': vorm,
              'Hoofdgroep': hoofdgroep,
              'geometry': geo}

    result_takken = []
    for tak in takken:
        taknummer = tak['Taknummer']
            
        result_tak = {'Juncties': juncties,
                      'Vorm': vorm,
                      'Hoofdgroep': hoofdgroep,
                      'Taknummer': taknummer,
                      'geometry': tak['geometry']}

        for key in ['windrichting',
                    'hoek',
                    'richtingen_open',
                    'bst_codes',
                    'gescheiden_rijbanen']:
            result[f'Tak_{taknummer}_{key}'] =  tak[key]
            result_tak[key] = tak[key]
        result_takken.append(result_tak)
       
        taknummer += 1
        
    return result, result_takken, result_rijlijnen


# INPUT
min_hoek_doorlopend_fietspad = 150.0

filter_nwb_bst = ['OV','Overig']
netwerk_file = '02 Tussenresultaten/02_NWB_20260101_ontdubbeld.gpkg'
rijlijnen_file = '02 Tussenresultaten/11_NWB_20260101_rijlijnen_auto_en_fiets.gpkg'

juncties_samengevoegd_file = '02 Tussenresultaten/13_NWB_20260101_ondeelbare_autojuncties.gpkg' # rotondes nog toevoegen
juncties_rotonde_file = '02 Tussenresultaten/13_NWB_20260101_rotondes.gpkg'

vorm_interpretatie_file = '01 Invoer/Takken_vorm_interpretatie.csv'

outputfile_kernen_gpkg = '02 Tussenresultaten/14_NWB_20260101_kruispunten.gpkg'
outputfile_takken_gpkg = '02 Tussenresultaten/14_NWB_20260101_kruispunt_takken.gpkg'
outputfile_rijlijnen_gpkg = '02 Tussenresultaten/14_NWB_20260101_kruispunt_rijlijnen.gpkg'



df_vorm_interpretatie = pd.read_csv(vorm_interpretatie_file)
vorm_interpretatie = {}
for i in df_vorm_interpretatie.index:
    regulier = df_vorm_interpretatie.at[i,'Aantal Regulier']
    fiets = df_vorm_interpretatie.at[i,'Aantal Fietspad']
    parallel = df_vorm_interpretatie.at[i,'Aantal Parallelweg']
    vorm_interpretatie[regulier,fiets,parallel] = df_vorm_interpretatie.at[i,'Interpretatie'], df_vorm_interpretatie.at[i,'Hoofdgroep']
        
gdf_netwerk = gpd.read_file(netwerk_file)
gdf_netwerk = gdf_netwerk.explode(index_parts=False) # probleem met multilinestring..


gdf_netwerk = gdf_netwerk[~gdf_netwerk['BST_CODE_simpel'].isin(filter_nwb_bst)] # voetpaden, veerdienst, parkeerplaats, etc.
gdf_netwerk.rename(columns = {'JTE_ID_BEG': 'A',
                              'JTE_ID_END': 'B'},inplace=True)


# uitlezen netwerk.
# hulpvariabelen voor makkelijk netwerk-kenmerken uitlezen
knoop_xy = {}
for index in gdf_netwerk.index:
    a = gdf_netwerk.at[index,'A']
    b = gdf_netwerk.at[index,'B']

    knoop_xy[a] = Point(gdf_netwerk.at[index,'geometry'].coords[0])
    knoop_xy[b] = Point(gdf_netwerk.at[index,'geometry'].coords[-1])
    

gdf_rijlijnen = gpd.read_file(rijlijnen_file)
gdf_rijlijnen.set_index(gdf_rijlijnen['rijlijn_index'],inplace=True)
gdf_rijlijnen = gdf_rijlijnen[~gdf_rijlijnen['BST_CODE'].isin(filter_nwb_bst)]  
junctie_rijlijnen = defaultdict(set)
for rijlijn_index in gdf_rijlijnen.index:
    rijlijn_knopen = list(map(int,gdf_rijlijnen.at[rijlijn_index,'Rijlijn_knopen'].split(',')))
    rijlijn_afstanden = list(map(float,gdf_rijlijnen.at[rijlijn_index,'Rijlijn_afstanden'].split(',')))
   
    gdf_rijlijnen.at[rijlijn_index,'Rijlijn_knopen'] = rijlijn_knopen
    gdf_rijlijnen.at[rijlijn_index,'Rijlijn_afstanden'] = rijlijn_afstanden
    for i, knoop in enumerate(rijlijn_knopen):
        junctie_rijlijnen[knoop].add((rijlijn_index, i, rijlijn_afstanden[i])) # index, opvolgnummer knoop, afstand van knoop op rijlijn.
        
        
# samengevoegde juncties
# deze worden afzonderlijk gelabeld.    
gdf_samengevoegd = gpd.read_file(juncties_samengevoegd_file)
gdf_samengevoegd['Type'] = 'Gescheiden_rijbanen'
gdf_rotondes = gpd.read_file(juncties_rotonde_file)
gdf_rotondes['Type'] = 'Rotonde'
gdf_samengevoegd = pd.concat([gdf_samengevoegd,gdf_rotondes],ignore_index=True)

# resultaten wegschrijven naar results_kernen.
results_kernen = []
results_takken = []
results_rijlijnen = []

# eerst analyseren van samengevoegde juncties
samengevoegde_juncties = set()
samenvoegingen_losmaken = set()
for i in gdf_samengevoegd.index:
    # deze samengestelde juncties betreffen altijd auto-kruispunten.
    juncties = set(map(int,gdf_samengevoegd.at[i,'Juncties'].split(',')))
    
    takken, ingaande_rijlijnen, uitgaande_rijlijnen = analyseer_kruispunttakken(juncties, junctie_rijlijnen, gdf_rijlijnen)
    
    if len(takken) == 2 and gdf_samengevoegd.at[i, 'Type'] == 'Gescheiden_rijbanen': continue # deze juncties worden niet samengesteld beschouwd maar alsnog los.
    
    samengevoegde_juncties |= juncties
    juncties = gdf_samengevoegd.at[i,'Juncties']

    vorm, hoofdgroep = kruispunt_vorm_afleiden(juncties, takken, vorm_interpretatie)
    
    geo = gdf_samengevoegd.at[i,'geometry'].centroid

    result, result_takken, result_rijlijnen = kruispunt_data_verzamelen(juncties, geo, vorm, hoofdgroep, takken, ingaande_rijlijnen, uitgaande_rijlijnen)
    results_kernen.append(result)
    results_takken += result_takken
    results_rijlijnen += result_rijlijnen

    

# vervolgens de rest van de juncties analyseren.
time = datetime.datetime.now()
c = 0
for k in knoop_xy:
    
    c += 1
    if c % 10000 == 0:
        t_new = datetime.datetime.now()
        print('%d van %d kernen verwerkt in  %0.1fs' % (c,len(knoop_xy),(t_new-time).total_seconds()))
        time = datetime.datetime.now()
        
    if k in samengevoegde_juncties: continue

    takken, ingaande_rijlijnen, uitgaande_rijlijnen = analyseer_kruispunttakken([k], junctie_rijlijnen, gdf_rijlijnen)

    vorm, hoofdgroep = kruispunt_vorm_afleiden(f'{k}', takken, vorm_interpretatie)

    geo = knoop_xy[k]

    result, result_takken, result_rijlijnen = kruispunt_data_verzamelen(f'{k}', geo, vorm, hoofdgroep, takken, ingaande_rijlijnen, uitgaande_rijlijnen)
    results_kernen.append(result)
    results_takken += result_takken
    results_rijlijnen += result_rijlijnen
    
# wegschrijven resultaten.
gdf_kernen = gpd.GeoDataFrame(results_kernen, crs=gdf_netwerk.crs)
gdf_kernen.to_file(outputfile_kernen_gpkg, driver='GPKG')

gdf_takken = gpd.GeoDataFrame(results_takken, crs=gdf_netwerk.crs)
gdf_takken.to_file(outputfile_takken_gpkg, driver='GPKG')

gdf_rijlijnen = gpd.GeoDataFrame(results_rijlijnen, crs=gdf_netwerk.crs)
gdf_rijlijnen.to_file(outputfile_rijlijnen_gpkg, driver='GPKG')


