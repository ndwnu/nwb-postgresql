import pandas as pd
import geopandas as gpd
gpd.options.io_engine = "pyogrio"
import os
os.environ["PYOGRIO_USE_ARROW"] = "1"
import rtree
import networkx as nx
from shapely.geometry import *

def generator_function(gdf):
    for i, geo in enumerate(gdf['geometry']):
        yield (i, geo.bounds, None)

def wegschrijven(gdf, outputfile):
    for c in gdf.columns:
        if set(gdf[c]) == set([None]): gdf[c] = ''
    gdf.to_file(outputfile)


# INPUT
max_vri_koppelafstand = 25.0

kruispuntobjecten_file = '02 Tussenresultaten/31_NWB_20260101_kruispunten_verrijkt.gpkg'
relaties_file = '02 Tussenresultaten/31_NWB_20260101_kruispunt_relaties.gpkg'
rotonde_file = '02 Tussenresultaten/13_NWB_20260101_rotondes.gpkg'
vri_file = None #'00 Data/VRI/01_4_bronnen_geclusterd.gpkg' # optioneel bestand, geen open data. Zet op 'None' indien niet beschikbaar.
hoofdgroepen_file = '01 Invoer/Takken_vorm_interpretatie.csv'
samenvoegingen_file = '02 Tussenresultaten/13_NWB_20260101_ondeelbare_autojuncties.gpkg'
kruispunt_takken_file = '02 Tussenresultaten/31_NWB_20260101_kruispunt_takken_verrijkt.gpkg'

outputfile_reguliere_kruispunten = '03 Uitvoer/32_NWB_20260101_reguliere_kruispunten.gpkg'
outputfile_samenvoegingen = '03 Uitvoer/32_NWB_20260101_samengevoegde_juncties.gpkg'

outputfile_kruispunt_takken = '03 Uitvoer/32_NWB_20260101_kruispunt_takken.gpkg'
outputfile_kruispunt_rijlijnen = '03 Uitvoer/32_NWB_20260101_kruispunt_rijlijnen.gpkg'
outputfile_kruispunt_relaties = '03 Uitvoer/32_NWB_20260101_kruispunt_relaties.gpkg'

outputfile_fietsoversteken_geclusterd = '03 Uitvoer/32_NWB_20260101_fietsoversteken_geclusterd.gpkg'
outputfile_fietsoversteken = '03 Uitvoer/32_NWB_20260101_fietsoversteken.gpkg'
outputfile_overige_conflictsituaties = '03 Uitvoer/32_NWB_20260101_overige_conflictsituaties.gpkg'




gdf_kruispunt_objecten = gpd.read_file(kruispuntobjecten_file)

gdf_relaties = gpd.read_file(relaties_file)
if vri_file != None:
    gdf_vri = gpd.read_file(vri_file)
else:
    gdf_vri = None
    
gdf_rotonde = gpd.read_file(rotonde_file)

df_hoofdgroepen = pd.read_csv(hoofdgroepen_file)



gdf_kruispunt_objecten.set_index('Juncties',inplace=True)
gdf_kp_regulier = gdf_kruispunt_objecten.query("Hoofdgroep == 'Regulier kruispunt'")
gdf_kp_overig = gdf_kruispunt_objecten.query("Hoofdgroep == 'Overige conflictsituaties'")
gdf_fo = gdf_kruispunt_objecten.query("Hoofdgroep == 'Fietsoversteek'")

# --- bewerkingen voor reguliere kruispunten
# kruispunttype en GOW/ETW toevoegen voor reguliere kruispunten.
juncties_rotonde = set(gdf_rotonde['Juncties'])

if vri_file != None:
    vri_spatial_index = rtree.index.Index(generator_function(gdf_vri))
    
gdf_kp_regulier['Kruispunttype'] = 'Onbekend'
for i in gdf_kp_regulier.index:
    kruispunt_geo = gdf_kp_regulier.at[i,'geometry']

    # VRI op basis van koppeling met VRI bestand
    if vri_file != None:
        result = vri_spatial_index.intersection(kruispunt_geo.buffer(max_vri_koppelafstand).bounds)
    else:
        result = []
        
    for j in result:
        if gdf_vri.at[j,'geometry'].distance(kruispunt_geo) < max_vri_koppelafstand:
            gdf_kp_regulier.at[i,'Kruispunttype'] = 'VRI'
            break

    # rotonde indien rotonde in NWB
    if i in juncties_rotonde:
        gdf_kp_regulier.at[i,'Kruispunttype'] = 'Rotonde'

    # voorrangskruispunt of gelijkwaardig kruispunt
    voorrang = set()
    wegcat = set()
    for tak in range(1,6+1):
        voorrang.add(gdf_kp_regulier.at[i,f'Tak_{tak}_voorrang'])
        wegcat.add(gdf_kp_regulier.at[i,f'Tak_{tak}_wegcategorie'])

    if gdf_kp_regulier.at[i,'Kruispunttype'] == 'Onbekend':
        if len(voorrang & set(['Voorrang','Geen voorrang',
                               'Geen voorrang (afgeleid)',
                               'Voorrang (afgeleid)'])) == 0:
            gdf_kp_regulier.at[i,'Kruispunttype'] = 'Gelijkwaardig'
        else:
            gdf_kp_regulier.at[i,'Kruispunttype'] = 'Voorrangskruispunt'

    # ETW en/of GOW
    if 'ETW' in wegcat:
        if 'GOW' in wegcat:
            gdf_kp_regulier.at[i,'Wegcategorie'] = 'GOW-ETW'
        else:
            gdf_kp_regulier.at[i,'Wegcategorie'] = 'ETW-ETW'
    elif 'GOW' in wegcat:
        gdf_kp_regulier.at[i,'Wegcategorie'] = 'GOW-GOW'
    else:
        gdf_kp_regulier.at[i,'Wegcategorie'] = 'Onbekend'

# afstand tot dichtstbijzijnd kruispunt opnemen
afstand_dichtsbijzijnd_kp = {}
for i in gdf_relaties[gdf_relaties['Type_relatie'] == 'Kruispunt_dichtstbijzijnde_kruispunt'].index:
    afstand_dichtsbijzijnd_kp[gdf_relaties.at[i,'Kruispunt_bron']] = float(gdf_relaties.at[i,'Afstand_via_rijlijn'])
gdf_kp_regulier['Afstand_dichtstbijzijnde_kruispunt'] = gdf_kp_regulier.index.map(afstand_dichtsbijzijnd_kp)



# filteren op kruispunten met een tak 50 km/u
kp_regulier_50 = set(gdf_kp_regulier[gdf_kp_regulier['Bevat_50'] == 'Ja'].index)
gdf_kp_regulier = gdf_kp_regulier[gdf_kp_regulier.index.isin(kp_regulier_50)]
gdf_kp_regulier.reset_index(inplace=True,drop=False)
keys = ['Juncties','Vorm','Kruispunttype','Wegcategorie','Afstand_dichtstbijzijnde_kruispunt']
for c in gdf_kp_regulier.columns:
    if c in keys: continue
    else: keys.append(c)
gdf_kp_regulier = gdf_kp_regulier[keys]

wegschrijven(gdf_kp_regulier, outputfile_reguliere_kruispunten)



# samengevoegde juncties voor 'reguliere kruispunten' wegschrijven.
gdf_samengevoegd = gpd.read_file(samenvoegingen_file)
gdf_samengevoegd = gdf_samengevoegd[gdf_samengevoegd['Juncties'].isin(kp_regulier_50)]
gdf_samengevoegd['Type'] = 'Gescheiden rijbanen'

gdf_rotonde = gdf_rotonde[gdf_rotonde['Juncties'].isin(kp_regulier_50)]
gdf_rotonde['Type'] = 'Rotonde'

gdf_samengevoegd = pd.concat([gdf_samengevoegd, gdf_rotonde],ignore_index=True).to_file(outputfile_samenvoegingen)

                                    
# detailinformatie voor 'reguliere kruispunten' wegschrijven.
gdf_takken = gpd.read_file(kruispunt_takken_file)
gdf_takken = gdf_takken[gdf_takken['Juncties'].isin(kp_regulier_50)]
gdf_takken.drop(columns=['hoek'],inplace=True)
gdf_takken.to_file(outputfile_kruispunt_takken)

gdf_rijlijnen = gpd.read_file('02 Tussenresultaten/31_NWB_20260101_kruispunt_rijlijnen_verrijkt.gpkg')
gdf_rijlijnen = gdf_rijlijnen[gdf_rijlijnen['Juncties'].isin(kp_regulier_50)]
gdf_rijlijnen.to_file(outputfile_kruispunt_rijlijnen)


gdf_relaties[(gdf_relaties['Kruispunt_doel'].isin(kp_regulier_50)) |\
             (gdf_relaties['Kruispunt_bron'].isin(kp_regulier_50))].to_file(outputfile_kruispunt_relaties)



# --- bewerkingen voor fietsoversteken

gdf_fo_relaties = gdf_relaties[gdf_relaties['Type_relatie'] == 'Fietsoversteek_dichtstbijzijnde_kruispunt']
gdf_fo_relaties.set_index(['Kruispunt_bron'],inplace=True)

gdf_kp_regulier.set_index('Juncties', inplace=True)
gdf_fo['Afstand_tot_dichtstbijzijnd_kruispunt'] = gdf_fo.index.map(gdf_fo_relaties['Afstand_via_rijlijn'].to_dict().get)
gdf_fo['Dichtstbijzijnd_kruispunt'] = gdf_fo.index.map(gdf_fo_relaties['Kruispunt_doel'].to_dict().get)
gdf_fo['Dichtstbijzijnd_kruispunt_type'] = gdf_fo['Dichtstbijzijnd_kruispunt'].map(gdf_kp_regulier['Kruispunttype'].to_dict().get)


# clusters van fietsoversteken maken.
graph_fietsoversteken = nx.Graph()
graph_fietsoversteken.add_nodes_from(gdf_fo.index)

for i in gdf_relaties[gdf_relaties['Type_relatie'] == 'Fietsoversteek_combineren'].index:
    a = gdf_relaties.at[i,'Kruispunt_bron']
    b = gdf_relaties.at[i,'Kruispunt_doel']

    if a in gdf_fo.index and b in gdf_fo.index:
       graph_fietsoversteken.add_edge(a,b)

results_fo_clusters = []
get_fo_cluster = {} # relatie tussen fo en fo_cluster
for cc in nx.connected_components(graph_fietsoversteken):
    juncties = []
    geoms = []

    dichtstbijzijnd_kruispunt_afstand = 99999
    dichtstbijzijnd_kruispunt = None
    

    for fo in cc:
        juncties.append(fo)
        geoms.append(gdf_fo.at[fo,'geometry'])

        if not pd.isnull(gdf_fo.at[fo,'Afstand_tot_dichtstbijzijnd_kruispunt']) and gdf_fo.at[fo,'Afstand_tot_dichtstbijzijnd_kruispunt'] < dichtstbijzijnd_kruispunt_afstand:
            dichtstbijzijnd_kruispunt_afstand = gdf_fo.at[fo,'Afstand_tot_dichtstbijzijnd_kruispunt']
            dichtstbijzijnd_kruispunt = gdf_fo.at[fo,'Dichtstbijzijnd_kruispunt']

    if dichtstbijzijnd_kruispunt_afstand > 999:
        dichtstbijzijnd_kruispunt_afstand = None
        dichtstbijzijnd_kruispunt_type = None
    else:
        if dichtstbijzijnd_kruispunt in gdf_kp_regulier.index:
            dichtstbijzijnd_kruispunt_type = gdf_kp_regulier.at[dichtstbijzijnd_kruispunt,'Kruispunttype']
        elif dichtstbijzijnd_kruispunt in gdf_kruispunt_objecten.index:
            dichtstbijzijnd_kruispunt_type = gdf_kruispunt_objecten.at[dichtstbijzijnd_kruispunt,'Hoofdgroep']
        else:
            dichtstbijzijnd_kruispunt_type = 'Buiten kern'
            
        
        
    result = {'Juncties': ','.join(sorted(juncties)),
              'Afstand_tot_dichtstbijzijnd_kruispunt': dichtstbijzijnd_kruispunt_afstand,
              'Dichtstbijzijnd_kruispunt': dichtstbijzijnd_kruispunt,
              'dichtstbijzijnd_kruispunt_type': dichtstbijzijnd_kruispunt_type,
              
              'geometry': MultiPoint(geoms)}

    
    if dichtstbijzijnd_kruispunt_type == None:
        result['Fietsoversteek_type'] = 'Fietsoversteek'
    elif dichtstbijzijnd_kruispunt_type != 'VRI' and dichtstbijzijnd_kruispunt_afstand > 25.0:
        result['Fietsoversteek_type'] = 'Solitaire fietsoversteek'
    elif dichtstbijzijnd_kruispunt_type == 'VRI' and dichtstbijzijnd_kruispunt_afstand > 35.0:
        result['Fietsoversteek_type'] = 'Solitaire fietsoversteek'
    else:
        result['Fietsoversteek_type'] = 'Fietsoversteek'
        
    results_fo_clusters.append(result)
    
    for fo in cc:
        get_fo_cluster[fo] = result['Juncties']
    
gdf_fo_clusters = gpd.GeoDataFrame(results_fo_clusters,crs=gdf_fo.crs)



# aanvullend ook fietsoversteken bij kruispunten 50 opnemen.
fietsoversteken_50 = set(gdf_relaties[(gdf_relaties['Type_relatie'] == 'Fietsoversteek_dichtstbijzijnde_kruispunt') &\
             (gdf_relaties['Kruispunt_doel'].isin(kp_regulier_50))]['Kruispunt_bron'])

# aanvullend ook clusters opnemen.
fo_clusters_50 = set()
fietsoversteken_50_aanvullend = set()
for fo in fietsoversteken_50:
    if fo in get_fo_cluster:
        fo_cluster = get_fo_cluster[fo]
        fo_clusters_50.add(fo_cluster)

        for fo in fo_cluster.split(','):
            fietsoversteken_50_aanvullend.add(fo)

#gdf_kruispunten = gdf_kruispunten[gdf_kruispunten.index.isin(kruispunten_50|fietsoversteken_50|fietsoversteken_50_aanvullend)]
gdf_fo_clusters = gdf_fo_clusters[gdf_fo_clusters['Juncties'].isin(fo_clusters_50)]
gdf_fo_clusters.to_file(outputfile_fietsoversteken_geclusterd)



gdf_fo.loc[gdf_fo['Afstand_tot_dichtstbijzijnd_kruispunt'] > 25.0,'Vorm'] = 'Solitaire fietsoversteek'
gdf_fo.reset_index(inplace=True,drop=False)
kolommen = ['Juncties','Vorm','Hoofdgroep','Snelheidslimieten','Bevat_50',
            'Afstand_tot_dichtstbijzijnd_kruispunt',
            'Dichtstbijzijnd_kruispunt','Dichtstbijzijnd_kruispunt_type',]
for c in gdf_fo.columns:
    if not c in kolommen:
        kolommen.append(c)

wegschrijven(gdf_fo[kolommen],outputfile_fietsoversteken)



# --- overige conflictsituaties

wegschrijven(gdf_kp_overig, outputfile_overige_conflictsituaties)


