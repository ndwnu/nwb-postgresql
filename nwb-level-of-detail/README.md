# LOD – Versimpeling van het Nationaal Wegenbestand

## Wat is dit project?

Dit project richt zich op het automatisch versimpelen van het Nationaal Wegenbestand (NWB), zodat het beter bruikbaar wordt voor diverse toepassingen zoals verkeersmodellen en verkeersveiligheidsanalyses. Daarbij worden complexe weginfrastructuren, zoals gescheiden rijbanen en rotondes, op slimme wijze samengevoegd tot eenvoudiger en overzichtelijker netwerken.

De afkorting **LOD** staat hierbij voor **Level of Detail**: we maken afgeleiden van het NWB met een vereenvoudigde structuur, afhankelijk van de behoefte van de gebruiker.

## Waarom is dit nodig?

In zijn huidige vorm is het NWB zeer gedetailleerd. Dat is nuttig voor sommige toepassingen, maar te complex voor andere – zoals:

- Macroscopische verkeersmodellen  
- Landelijke verkeersveiligheidsanalyses  
- Toepassingen waarbij consistente netwerken over meerdere jaren nodig zijn  

Door het netwerk slim te versimpelen:

- wordt het eenvoudiger te modelleren (minder kruispunten, kortere rekentijd);  
- blijft de structuur vergelijkbaar door de tijd heen, wat trendanalyses vergemakkelijkt;  
- worden specifieke constructies, zoals rotondes en parallelwegen, logisch samengevoegd;  
- kunnen ook gemeenten en provincies eenvoudiger beleidstoepassingen ondersteunen.

## Wat kun je met deze code?

De scripts in deze repository stellen je in staat om:

- NWB-gegevens automatisch te versimpelen  
- Kruispunten (intersecties) te clusteren en combineren  
- Een netwerktopologie te creëren die eenvoudiger is dan het oorspronkelijke NWB  

Een belangrijk onderdeel is het clusteren van nodes (knooppunten) en wegsegmenten die feitelijk tot hetzelfde kruispunt behoren. Denk hierbij aan:

- Rotondes die uit meerdere segmenten bestaan  
- Aansluitingen op gescheiden rijbanen  
- Bajonetkruispunten  
- Clusters rondom één verkeersregelinstallatie  

Deze elementen worden logisch samengenomen tot één “intersectie” in het versimpelde netwerk.

## Voor wie is dit bedoeld?

Deze tooling is metname bedoeld voor:

- Verkeersmodelleurs bij overheden en adviesbureaus  
- Beleidsmakers die werken met geautomatiseerde verkeersveiligheidsanalyses  
- Gemeenten of provincies die op zoek zijn naar een bruikbaardere versie van het NWB  

## Toekomst

Op termijn kan dit project bijdragen aan een gestandaardiseerde manier van versimpeling van het NWB, bijvoorbeeld als open dataproduct naast het officiële NWB. We zijn benieuwd naar feedback, bijdragen en vooral ook gebruikservaringen!
