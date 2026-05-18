# Docs

Aanvullende documentatie naast de hoofd-`README.md`. Bedoeld voor lezers die
voorbij "hoe installeer ik dit" willen kijken — auditors, security-officers,
collega's die de tool overnemen, of jij over zes maanden.

## Inhoud

| Bestand | Voor wie | Waarom |
|---|---|---|
| [`compliance.md`](compliance.md) | Auditor, security officer, sales-ondersteuning | Mapping van workstation-security componenten op specifieke control-IDs in ISO 27001:2022, SOC 2 (CC6/CC7), NEN 7510-2:2017 en BIO. Plus expliciete gap-lijst. |
| [`threat-model.md`](threat-model.md) | Implementatie-engineers, security-reviewers | Wat verdedigen we WEL, wat NIET. Voorkomt scope-creep en zet verwachtingen voor wat dit script kan oplossen. |

## Hoe deze docs te gebruiken

**Vóór een audit:**
1. Lees `compliance.md` — match de gevraagde controls tegen de mapping
2. Verifieer de evidence-paden bestaan (`check.sh` is hier de eerste stop)
3. Voor gevraagde controls niet in de mapping: óf compensating controls
   documenteren, óf het gat erkennen

**Vóór een nieuwe deployment:**
1. Lees `threat-model.md` — bevestig dat het bedreigingsmodel matcht
2. Bij mismatch: óf scope uitbreiden, óf de discrepantie expliciet
   documenteren in jouw eigen risk-register

**Bij een wijziging aan een script:**
1. Update beide docs als de wijziging de control-coverage of het
   bedreigingsmodel raakt
2. CHANGELOG.md krijgt de wijzigings-entry; deze docs krijgen de
   beschrijvende mapping-update

## Status

Deze docs zijn een **eerste pass** (2026-05-18). De control-mapping is
geverifieerd tegen de hoofdsecties van elk framework maar niet
woord-voor-woord tegen de letterlijke control-tekst — voor een
audit-ready versie is dat een eindstap.

Beperking: vier frameworks tegelijk is een breed dossier. Per
implementerende klant is het verstandig de mapping te trimmen tot de
frameworks die in scope zijn voor *hun* audit, en de control-tekst dáár
woord-voor-woord langs te lopen.
