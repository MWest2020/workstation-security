---
name: Distro support
about: Verzoek voor support van een distro die nog niet in alma/arch/ubuntu valt
labels: distro-support
---

## Distro

- **Naam + versie:** <!-- bv. openSUSE Tumbleweed, Void Linux, NixOS 25.05 -->
- **Package-manager:** <!-- zypper / xbps / nix / ... -->
- **`/etc/os-release` inhoud (relevante delen):**
  ```
  ID=...
  ID_LIKE=...
  ```

## Waarom deze distro

<!-- Eén of twee zinnen — gebruik je 'm zelf? Welk publiek zou er baat bij hebben? -->

## Bestaande oplossingen

<!-- Bestaat er een AV/rkhunter-package via de native pkg-manager? Wat is de daemon-naam? -->

- ClamAV-package: <!-- bv. zypper install clamav -->
- ClamAV-daemon-service: <!-- bv. clamd.service -->
- rkhunter-package: <!-- bv. niet beschikbaar / handmatige tarball / AUR -->

## Bereidheid tot testen

<!-- Belangrijke vraag — distro-PRs landen alleen als ze door iemand met die distro getest blijven worden. -->

- [ ] Ik gebruik deze distro zelf en kan PRs reviewen / testen.
- [ ] Ik heb een test-VM / container met deze distro en kan ad-hoc testen.
- [ ] Ik wil alleen het verzoek indienen en hoop dat iemand anders het oppakt.

## Aanvullende context

<!-- Optioneel — quirks van de distro die de installer moet weten (SELinux/AppArmor/non-systemd init/etc.) -->
