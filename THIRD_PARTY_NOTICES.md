# Third-party notices

Garakuta has no runtime dependencies. Everything under `Sources/` was written for this project and is licensed under the [MIT License](LICENSE).

## Included material

### Contributor Covenant 2.1

`CODE_OF_CONDUCT.md` is the Contributor Covenant, version 2.1, licensed under CC BY 4.0. Source: https://www.contributor-covenant.org/version/2/1/code_of_conduct/

## Techniques

The techniques used here are publicly documented and shared by several open-source macOS utilities: hiding menu bar items behind a stretched status item, discovering status items through the Accessibility API, focusing a single window through SkyLight (`_SLPSSetFrontProcessWithOptions` followed by two `SLPSPostEventRecordTo` records with the window ID at offset `0x3c`), and placing a non-activating panel above the menu bar with `sharingType = .none`. `Sources/PrivateAPIs/PrivateAPIs.c` re-implements the record layout in C from its public description. No third-party code is included.

## Trademarks

Product and company names mentioned in this repository belong to their owners and are used only to identify compatibility.
