import geopandas as gpd
gpd.options.io_engine = "pyogrio"
import os
os.environ["PYOGRIO_USE_ARROW"] = "1"
from collections import *
from pprint import pprint
from shapely.geometry import *

# INPUT

# parameters
borden_voorrang = set(['B1','B3','B4','B5'])
borden_geen_voorrang = set(['B6','B7'])

max_fietsoversteek_afstand = 25.0
max_fietsoversteek_combineer_afstand = 20.0 # maximale afstand tussen twee fietsoversteken voor combineren.

# inputbestanden
kruispunten_file = '02 Tussenresultaten/14_NWB_20260101_kruispunten.gpkg'
kruispunt_takken_file = '02 Tussenresultaten/14_NWB_20260101_kruispunt_takken.gpkg'
kruispunt_rijlijnen_file = '02 Tussenresultaten/14_NWB_20260101_kruispunt_rijlijnen.gpkg'
nwb_rijlijnen_file = '02 Tussenresultaten/11_NWB_20260101_rijlijnen_auto_en_fiets.gpkg'
verkeersborden_file = '02 Tussenresultaten/22_verkeersborden_gekoppeld.gpkg' # niet super netjes gepositioneerd, wel goed als test.
uitritten_file = '02 Tussenresultaten/27_rijlijnen_met_drempels.gpkg'
snelheidslimieten_file = '02 Tussenresultaten/24_rijlijnen_met_WKD_snelheidslimieten.gpkg'
wegcategorie_file = '02 Tussenresultaten/26_rijlijnen_met_WKD_wegcategorieen.gpkg'
voertuigtypen_file = '02 Tussenresultaten/29_rijlijnen_met_WKD_verkeerstypen.gpkg'

# outputbestanden
outputfile_relaties = '02 Tussenresultaten/31_NWB_20260101_kruispunt_relaties.gpkg'
outputfile_kruispunt_rijlijnen = '02 Tussenresultaten/31_NWB_20260101_kruispunt_rijlijnen_verrijkt.gpkg'
outputfile_kruispunt_takken = '02 Tussenresultaten/31_NWB_20260101_kruispunt_takken_verrijkt.gpkg'
outputfile_kruispunten = '02 Tussenresultaten/31_NWB_20260101_kruispunten_verrijkt.gpkg'


gdf_verkeersborden = gpd.read_file(verkeersborden_file)
gdf_verkeersborden.set_index('gekoppelde_rijlijn',inplace=True)

gdf_uitritten = gpd.read_file(uitritten_file)
gdf_uitritten.set_index('rijlijn_index',inplace=True)

gdf_snelheidslimieten = gpd.read_file(snelheidslimieten_file)
gdf_snelheidslimieten.fillna({'WKD_snelheidslimiet': 'Onbekend'},inplace=True) # wrs alleen ontdubbelde wegvakken...
gdf_snelheidslimieten.set_index('rijlijn_index',inplace=True)
snelheidslimieten_col_map = {col: i for i, col in enumerate(gdf_snelheidslimieten.columns)}


gdf_wegcategorieen = gpd.read_file(wegcategorie_file)
gdf_wegcategorieen.fillna({'WKD_wegcategorie': 'Onbekend'},inplace=True) # wrs alleen ontdubbelde wegvakken...
gdf_wegcategorieen.set_index('rijlijn_index',inplace=True)
wegcategorieen_col_map = {col: i for i, col in enumerate(gdf_wegcategorieen.columns)}

gdf_voertuigtypen = gpd.read_file(voertuigtypen_file)
gdf_voertuigtypen.fillna({'WKD_verkeerstypen': 'Onbekend'},inplace=True) # wrs alleen ontdubbelde wegvakken...
gdf_voertuigtypen.set_index('rijlijn_index',inplace=True)
voertuigtypen_col_map = {col: i for i, col in enumerate(gdf_voertuigtypen.columns)}


gdf_kruispunten = gpd.read_file(kruispunten_file)
gdf_kruispunten.set_index('Juncties', inplace=True)

gdf_kruispunt_takken =  gpd.read_file(kruispunt_takken_file)

# delen van rijlijnen op kruispunten
gdf_kruispunt_rijlijnen = gpd.read_file(kruispunt_rijlijnen_file)

# voor zoeken naar bst code.
gdf_rijlijnen = gpd.read_file(nwb_rijlijnen_file)
gdf_rijlijnen.set_index('rijlijn_index',inplace=True)
                              

# data koppelen op het niveau van rijlijnen
rijlijn_kruispuntkoppelingen = defaultdict(list)
kruispunt_rijlijnen = defaultdict(set)
kruispunttak_rijlijnen = defaultdict(set)
for i in gdf_kruispunt_rijlijnen.index:
    kruispunt_index = gdf_kruispunt_rijlijnen.at[i,'Juncties']
    kruispunt_rijlijnen[kruispunt_index].add(i)

    kruispunttak = gdf_kruispunt_rijlijnen.at[i,'Taknummer']
    kruispunttak_rijlijnen[kruispunt_index, kruispunttak].add(i)

    rijlijn_index = gdf_kruispunt_rijlijnen.at[i,'Rijlijn_index']
    richting = gdf_kruispunt_rijlijnen.at[i,'Type'] # ingaand of uitgaand

    # sla per rijlijn de gekoppelde kruispunten op.
    # hiermee kun je per kruispunt nabijgelegen objecten zoeken.
    if richting == 'Ingaand': kruispunt_afstand = gdf_kruispunt_rijlijnen.at[i,'naar']
    elif richting == 'Uitgaand': kruispunt_afstand = gdf_kruispunt_rijlijnen.at[i,'van']
    rijlijn_kruispuntkoppelingen[rijlijn_index].append((kruispunt_afstand, kruispunt_index, richting))

    # sla per rijlijn de gekoppelde verkeersborden op.
    # vooralsnog alleen voor ingaande rijlijnen??
    if richting == 'Ingaand':
        gdf_kruispunt_rijlijnen.at[i,'voorrang'] = 'Onbekend'
        
    if richting == 'Ingaand' and rijlijn_index in gdf_verkeersborden.index:
        #gdf_verkeersborden = rijlijn_verkeersborden.get_group(rijlijn_index)
        
        gdf_verkeersborden_selectie = gdf_verkeersborden.loc[[rijlijn_index]]
        gdf_verkeersborden_selectie = gdf_verkeersborden_selectie[(gdf_verkeersborden_selectie['gekoppelde_rijlijn_pos'] > gdf_kruispunt_rijlijnen.at[i,'van']) &\
                                                                  (gdf_verkeersborden_selectie['gekoppelde_rijlijn_pos'] < gdf_kruispunt_rijlijnen.at[i,'naar'])]

        
        rvv_codes = set(gdf_verkeersborden_selectie['rvvCode']) & (borden_voorrang | borden_geen_voorrang)
        gdf_kruispunt_rijlijnen.at[i,'rvv_codes'] = ','.join(sorted(rvv_codes))

        if len(rvv_codes & borden_voorrang) > 0:
            gdf_kruispunt_rijlijnen.at[i,'voorrang'] = 'Voorrang'
        elif len(rvv_codes & borden_geen_voorrang) > 0:
            gdf_kruispunt_rijlijnen.at[i,'voorrang'] = 'Geen voorrang'

    # je kunt hier ook de uitgaande rijlijnen beschouwen maar dan op de beginpositie. in de praktijk zal dit weinig uitmaken??
    if richting == 'Ingaand' and rijlijn_index in gdf_uitritten.index:
        #gdf_uitritten = rijlijn_uitritten.get_group(rijlijn_index)
        gdf_uitritten_selectie = gdf_uitritten.loc[[rijlijn_index]]
        gdf_uitritten = gdf_uitritten[(gdf_uitritten['uitrit_pos'] > gdf_kruispunt_rijlijnen.at[i,'naar'] - 30.0) &\
                                      (gdf_uitritten['uitrit_pos'] < gdf_kruispunt_rijlijnen.at[i,'naar'])]
        if len(gdf_uitritten) > 0:
            gdf_kruispunt_rijlijnen.at[i,'voorrang'] = 'Geen voorrang'


    # snelheidslimieten.
    if rijlijn_index in gdf_snelheidslimieten.index:
        gdf_snelheidslimieten_selectie = gdf_snelheidslimieten.loc[[rijlijn_index]]
        gekoppelde_snelheidslimieten = Counter()
        for j in range(len(gdf_snelheidslimieten_selectie)):
            van = gdf_snelheidslimieten_selectie.iat[j,snelheidslimieten_col_map['van']]
            naar = gdf_snelheidslimieten_selectie.iat[j,snelheidslimieten_col_map['naar']]
            
            overlap = min(naar, gdf_kruispunt_rijlijnen.at[i,'naar']) - max(van, gdf_kruispunt_rijlijnen.at[i,'van'])
            if overlap > 0:
                snelheidslimiet = gdf_snelheidslimieten_selectie.iat[j,snelheidslimieten_col_map['WKD_snelheidslimiet']]
                gekoppelde_snelheidslimieten[snelheidslimiet] += overlap

        if len(gekoppelde_snelheidslimieten) > 0:
            gdf_kruispunt_rijlijnen.at[i,'WKD_snelheidslimiet'] = gekoppelde_snelheidslimieten.most_common()[0][0]
        else:
            gdf_kruispunt_rijlijnen.at[i,'WKD_snelheidslimiet'] = 'Onbekend'
    else:
        gdf_kruispunt_rijlijnen.at[i,'WKD_snelheidslimiet'] = 'Onbekend'

    
        
# data koppelen op het niveau van kruispunttakken.
relaties = set()
kruispunt_takken = defaultdict(set)
for i_tak in gdf_kruispunt_takken.index:
    kruispunt_index = gdf_kruispunt_takken.at[i_tak,'Juncties']
    taknummer = gdf_kruispunt_takken.at[i_tak,'Taknummer']

    kruispunt_takken[kruispunt_index].add(i_tak)

    gdf_kruispunt_takken.at[i_tak,'voorrang'] = 'Onbekend'
    gdf_kruispunt_takken.at[i_tak,'Fietsoversteek_aanwezig'] = 'Nee'

    lengte_per_categorie = Counter()
    lengte_per_voertuigtype = Counter()
    for i_rijlijn in kruispunttak_rijlijnen[kruispunt_index,taknummer]:
        # je zou hier ook naar uitgaande rijlijnen kunnen kijken etc.
        if gdf_kruispunt_rijlijnen.at[i_rijlijn,'Type'] == 'Ingaand':
            gdf_kruispunt_takken.at[i_tak,'voorrang'] = gdf_kruispunt_rijlijnen.at[i_rijlijn,'voorrang']

        
        van = gdf_kruispunt_rijlijnen.at[i_rijlijn,'van']
        naar = gdf_kruispunt_rijlijnen.at[i_rijlijn,'naar']
        rijlijn_index = gdf_kruispunt_rijlijnen.at[i_rijlijn,'Rijlijn_index']
        richting = gdf_kruispunt_rijlijnen.at[i_rijlijn,'Type']
        
        # GOW-ETW
        if rijlijn_index in gdf_wegcategorieen.index: 
            gdf_wegcategorieen_selectie = gdf_wegcategorieen.loc[[rijlijn_index]]
            
            for j in range(len(gdf_wegcategorieen_selectie)):
                overlap = min(naar, gdf_wegcategorieen_selectie.iat[j,wegcategorieen_col_map['naar']]) - max(van, gdf_wegcategorieen_selectie.iat[j,wegcategorieen_col_map['van']])
                if overlap > 0: lengte_per_categorie[gdf_wegcategorieen_selectie.iat[j,wegcategorieen_col_map['WKD_wegcategorie']]] += overlap


        # fietsers toegestaan
        if rijlijn_index in gdf_voertuigtypen.index: 
            gdf_voertuigtypen_selectie = gdf_voertuigtypen.loc[[rijlijn_index]]
            
            for j in range(len(gdf_voertuigtypen_selectie)):
                overlap = min(naar, gdf_voertuigtypen_selectie.iat[j,voertuigtypen_col_map['naar']]) - max(van, gdf_voertuigtypen_selectie.iat[j,voertuigtypen_col_map['van']])
                if overlap > 0: lengte_per_voertuigtype[gdf_voertuigtypen_selectie.iat[j,voertuigtypen_col_map['WKD_verkeerstypen']]] += overlap

        # fietsoversteek aanwezig
        for kruispunt_positie, kruispunt_index, koppel_richting in rijlijn_kruispuntkoppelingen[rijlijn_index]:
            if richting == 'Ingaand' and\
               gdf_kruispunten.at[kruispunt_index,'Hoofdgroep'] == 'Fietsoversteek' and\
               (naar - max_fietsoversteek_afstand <= kruispunt_positie <= naar):
                gdf_kruispunt_takken.at[i_tak,'Fietsoversteek_aanwezig'] = 'Ja'
            elif richting == 'Uitgaand' and\
               gdf_kruispunten.at[kruispunt_index,'Hoofdgroep'] == 'Fietsoversteek' and\
               (van <= kruispunt_positie <= van + max_fietsoversteek_afstand):
                gdf_kruispunt_takken.at[i_tak,'Fietsoversteek_aanwezig'] = 'Ja'
        
    if len(lengte_per_categorie) > 0:
        gdf_kruispunt_takken.at[i_tak,'Wegcategorie'] = lengte_per_categorie.most_common()[0][0]
    else:
        gdf_kruispunt_takken.at[i_tak,'Wegcategorie'] = 'Onbekend'

    if len(lengte_per_voertuigtype) > 0:
        gdf_kruispunt_takken.at[i_tak,'Fiets_toegestaan'] = lengte_per_voertuigtype.most_common()[0][0]
    else:
        gdf_kruispunt_takken.at[i_tak,'Fiets_toegestaan'] = 'Onbekend'
    

    
# diverse relaties tussen objecten leggen a.d.h.v. rijlijnen.
min_afstand_fo_tot_kruispunt = {}
min_afstand_kp_tot_kruispunt = {}
for rijlijn_index in rijlijn_kruispuntkoppelingen:
    if gdf_rijlijnen.at[rijlijn_index,'BST_CODE_simpel'] != 'Regulier': continue
    
    posities_fietsoversteken = set()
    posities_reguliere_kruispunten = set()
    
    for kruispunt_positie, kruispunt_index, koppel_richting in rijlijn_kruispuntkoppelingen[rijlijn_index]:
        if gdf_kruispunten.at[kruispunt_index,'Hoofdgroep'] == 'Fietsoversteek':
            posities_fietsoversteken.add((kruispunt_index,kruispunt_positie))
        elif gdf_kruispunten.at[kruispunt_index,'Hoofdgroep'] in ['Regulier kruispunt'] :
            posities_reguliere_kruispunten.add((kruispunt_index,kruispunt_positie))

    # afstand van fietsoversteek tot regulier kruispunt.    
    for (fo_index, fo_pos) in posities_fietsoversteken:
        for (kp_index, kp_pos) in posities_reguliere_kruispunten:
            afstand = abs(fo_pos-kp_pos)
            if (not fo_index in min_afstand_fo_tot_kruispunt) or\
               (afstand < min_afstand_fo_tot_kruispunt[fo_index][0]):
                min_afstand_fo_tot_kruispunt[fo_index] = (afstand, kp_index)

    # afstand tussen reguliere kruispunten.
    posities_kruispunten_sorted = sorted(posities_reguliere_kruispunten,key=lambda x: x[1])
    for i in range(len(posities_kruispunten_sorted)-1):
        a_index, a_pos = posities_kruispunten_sorted[i]
        b_index, b_pos = posities_kruispunten_sorted[i+1]
        afstand = b_pos-a_pos

        if a_index == b_index: continue # komt voor bij samengestelde kruispunten.
        
        if (not a_index in min_afstand_kp_tot_kruispunt) or\
           (afstand < min_afstand_kp_tot_kruispunt[a_index][0]):
            min_afstand_kp_tot_kruispunt[a_index] = (afstand, b_index)
            
        if (not b_index in min_afstand_kp_tot_kruispunt) or\
           (afstand < min_afstand_kp_tot_kruispunt[b_index][0]):
            min_afstand_kp_tot_kruispunt[b_index] = (afstand, a_index)
        
        
    
for fo_index in min_afstand_fo_tot_kruispunt:
    relaties.add(('Fietsoversteek_dichtstbijzijnde_kruispunt', fo_index, min_afstand_fo_tot_kruispunt[fo_index][1],min_afstand_fo_tot_kruispunt[fo_index][0]))

for kp_index in min_afstand_kp_tot_kruispunt:
    relaties.add(('Kruispunt_dichtstbijzijnde_kruispunt', kp_index, min_afstand_kp_tot_kruispunt[kp_index][1],min_afstand_kp_tot_kruispunt[kp_index][0]))

# afstanden tussen fietsoversteken op rijlijnen fietspad.
for rijlijn_index in rijlijn_kruispuntkoppelingen:
    if gdf_rijlijnen.at[rijlijn_index,'BST_CODE_simpel'] != 'Fietspad': continue

    posities_fietsoversteken = set()
    for kruispunt_positie, kruispunt_index, koppel_richting in rijlijn_kruispuntkoppelingen[rijlijn_index]:
        if gdf_kruispunten.at[kruispunt_index,'Hoofdgroep'] == 'Fietsoversteek':
            posities_fietsoversteken.add((kruispunt_index,kruispunt_positie))

    posities_sorted = sorted(posities_fietsoversteken,key=lambda x: x[1])

    for i in range(len(posities_sorted)-1):
        a_index, a_pos = posities_sorted[i]
        b_index, b_pos = posities_sorted[i+1]

        afstand = b_pos-a_pos

        if afstand < max_fietsoversteek_combineer_afstand:
            relaties.add(('Fietsoversteek_combineren', a_index, b_index, afstand))
            
 

    
results = []
for (type_relatie, kruispunt_koppel_index,kruispunt_index, afstand) in relaties:
    kruispunt_koppel_geo = gdf_kruispunten.at[kruispunt_koppel_index,'geometry']
    kruispunt_geo = gdf_kruispunten.at[kruispunt_index,'geometry']
    
    result = {'Type_relatie': type_relatie,
              'Kruispunt_bron': kruispunt_koppel_index,
              'Kruispunt_doel': kruispunt_index,
              'Afstand_via_rijlijn': afstand,
              'geometry': LineString([kruispunt_koppel_geo,kruispunt_geo])}
    results.append(result)
gdf_relaties = gpd.GeoDataFrame(results,crs=gdf_kruispunten.crs)



for i_kruispunt in gdf_kruispunten.index:
    # analyseren voorrangssituatie op kruispuntniveau.
    # hier nog een selectie van kruispuntvorm toepassen minimaal.
    takken_voorrang = set()
    takken_geen_voorrang = set()
    takken_onbekend = set()

    for i_tak in kruispunt_takken[i_kruispunt]:
        # vooralsnog alleen de voorrangssituatie voor 'reguliere' kruispunten vaststellen
        if gdf_kruispunt_takken.at[i_tak,'bst_codes'] != 'Regulier':
            gdf_kruispunt_takken.at[i_tak,'voorrang'] = 'Niet beschouwd (fietspad of parallelweg)'
            continue
        
        if gdf_kruispunt_takken.at[i_tak,'voorrang'] == 'Voorrang': takken_voorrang.add(i_tak)
        elif gdf_kruispunt_takken.at[i_tak,'voorrang'] == 'Geen voorrang': takken_geen_voorrang.add(i_tak)
        else: takken_onbekend.add(i_tak)
    
    # je kunt hier ook nog fouten gaan proberen te identificeren.
    aantal_takken_totaal = len(takken_voorrang) + len(takken_geen_voorrang) + len(takken_onbekend)

    if len(takken_voorrang) == 2:
        for i_tak in takken_onbekend: gdf_kruispunt_takken.at[i_tak,'voorrang'] = 'Geen voorrang (afgeleid)'

    if aantal_takken_totaal - len(takken_geen_voorrang) == 2:
        for i_tak in takken_onbekend: gdf_kruispunt_takken.at[i_tak,'voorrang'] = 'Voorrang (afgeleid)'

    for i_tak in kruispunt_takken[i_kruispunt]:
        taknummer = gdf_kruispunt_takken.at[i_tak,'Taknummer']
        gdf_kruispunten.at[i_kruispunt, f'Tak_{taknummer}_voorrang'] = gdf_kruispunt_takken.at[i_tak,'voorrang']
        gdf_kruispunten.at[i_kruispunt, f'Tak_{taknummer}_wegcategorie'] = gdf_kruispunt_takken.at[i_tak,'Wegcategorie']
        gdf_kruispunten.at[i_kruispunt, f'Tak_{taknummer}_fiets_toegestaan'] = gdf_kruispunt_takken.at[i_tak,'Fiets_toegestaan']
        gdf_kruispunten.at[i_kruispunt, f'Tak_{taknummer}_fietsoversteek_aanwezig'] = gdf_kruispunt_takken.at[i_tak,'Fietsoversteek_aanwezig']


    # snelheidslimieten.
    snelheidslimieten = set()
    for i_rijlijn in kruispunt_rijlijnen[i_kruispunt]:
        snelheidslimieten.add(gdf_kruispunt_rijlijnen.at[i_rijlijn,'WKD_snelheidslimiet'])
    gdf_kruispunten.at[i_kruispunt,'Snelheidslimieten'] = ','.join(sorted(snelheidslimieten))
    if '50' in snelheidslimieten:
        gdf_kruispunten.at[i_kruispunt,'Bevat_50'] = 'Ja'
    else:
        gdf_kruispunten.at[i_kruispunt,'Bevat_50'] = 'Nee'

    
gdf_relaties.to_file(outputfile_relaties,driver='GPKG')


gdf_kruispunt_rijlijnen.to_file(outputfile_kruispunt_rijlijnen,driver='GPKG')
gdf_kruispunt_takken.to_file(outputfile_kruispunt_takken,driver='GPKG')

gdf_kruispunten.reset_index(inplace=True,drop=False)
kolommen = ['Juncties', 'Vorm','Hoofdgroep','Snelheidslimieten','Bevat_50','geometry']
for tak in [1,2,3,4,5,6]:
    for key in ['windrichting','richtingen_open','bst_codes','gescheiden_rijbanen','voorrang','wegcategorie','fietsoversteek_aanwezig','fiets_toegestaan',]:
        kolom = f'Tak_{tak}_{key}'
        if kolom in gdf_kruispunten.columns:
            kolommen.append(kolom)
        
gdf_kruispunten[kolommen].to_file(outputfile_kruispunten,driver='GPKG')


