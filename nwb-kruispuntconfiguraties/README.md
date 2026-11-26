# Detecteren van kruispuntconfiguraties

Voor het detecteren en interpreteren van kruispuntconfiguraties op 50 km/uur-wegen in het Nationaal Wegenbestand (NWB) is een serie Python-scripts en bijbehorende algoritmen opgesteld.

De scripts beschrijven de opeenvolgende werkstappen die worden uitgevoerd om vanuit de brondata tot een eindresultaat te komen. Een gedetailleerde beschrijving van de werking van de scripts en het eindresultaat staat in de rapportage:

> *Onderzoek kruispuntconfiguraties* — Sweco, november 2026

Deze rapportage is beschikbaar via het NDW.

## Toepassing van de scripts

De scripts zijn opeenvolgend genummerd en kunnen achter elkaar worden uitgevoerd om tot het eindresultaat te komen.

In ieder script is een `INPUT`-gedeelte opgenomen. Hierin staan:

- de benodigde invoerbestanden;
- de uitvoerbestanden;
- de gebruikte parameters.

De scripts gaan uit van de volgende vaste mappenstructuur:

```text
00 Data/
└── Externe databronnen

01 Invoer/
└── Diverse configuratiebestanden (*.csv)

02 Tussenresultaten/
└── Tussenresultaten van de afzonderlijke stappen

03 Uitvoer/
└── Eindresultaat
```

## Gebruikte databronnen

De scripts gebruiken verschillende externe databronnen. Deze bestanden kunnen worden geplaatst in de map `00 Data`.

De belangrijkste databronnen zijn het NWB en verschillende bijbehorende WKD-bestanden. De gebruikte databronnen zijn beschikbaar via de volgende links:

| Databron | Link |
|---|---|
| NWB | [NWB-geogegevens](https://downloads.rijkswaterstaatdata.nl/nwb-wegen/geogegevens/geopackage/Nederland_totaal/) |
| WKD | [WKD-geogegevens](https://downloads.rijkswaterstaatdata.nl/wkd/geogegevens/Geopackage/) |
| Drempels | [NDW-datasets](https://verkeersveiligheid.ndw.nu/datasets) |
| Verkeersbordenbestand | [NDW Open Data](https://opendata.ndw.nu/) |

> **Let op:** gebruik voor alle databronnen bestanden met dezelfde peildatum. Dit voorkomt inconsistenties tussen de verschillende gegevensbronnen.

## Kanttekening

De scripts zijn ontwikkeld binnen een onderzoekscontext. De focus lag op het verkennen van mogelijke oplossingen en het toewerken naar een bruikbaar resultaat.

De scripts zijn daarom niet specifiek opgeschoond of gestructureerd voor gebruik in een productieomgeving. Ook zijn uitgebreid commentaar, uitgebreide foutafhandeling en andere voorzieningen niet overal aanwezig.
