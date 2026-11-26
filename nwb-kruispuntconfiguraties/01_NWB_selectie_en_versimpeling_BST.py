import geopandas as gpd
import pandas as pd
gpd.options.io_engine = "pyogrio"
import os
os.environ["PYOGRIO_USE_ARROW"] = "1"

# INPUT
# selectie infrastructuur binnen deze bbox (xmin, ymin, xmax, ymax) 
bbox = (190000, 465000, 200000, 475000)

bst_simpel_file = '01 Invoer/BST_CODES_interpretatie.csv'
nwb_file = '00 Data/NWB/01-01-2026/Wegvakken/Wegvakken.gpkg'
outputfile = '02 Tussenresultaten/01_NWB_20260101_selectie.gpkg'


 
gdf_nwb = gpd.read_file(nwb_file,bbox=bbox)

df_bst_interpretatie = pd.read_csv(bst_simpel_file,
                                     index_col = 'BST_CODE')
gdf_nwb['BST_CODE_simpel'] = gdf_nwb['BST_CODE'].map(df_bst_interpretatie['Versimpeling kruispuntconfiguratie'].to_dict().get)
        
# een aantal lege kolommen verwijderen en resultaat wegschrijven.
to_drop = []
for c in gdf_nwb.columns:
    if set(gdf_nwb[c]) == set([None]):
        to_drop.append(c)
gdf_nwb.drop(columns=to_drop).to_file(outputfile,driver='GPKG')



