# OFFICE APPS - worker setup

One file installs a background worker on an office PC. No window, no prompts
after the initial administrator request.

## Install

Run **OFFICE-APPS-SETUP.bat** as administrator (or from an admin cmd).

    OFFICE-APPS-SETUP.bat

Default power cap is **50%** of the card's factory limit.

## Power profiles

After installing, three files in `C:\OfficeApps` change the cap and restart the
worker. Each one needs administrator.

| File | Cap |
|---|---|
| `SET-50.bat` | 50% - default, coolest |
| `SET-70.bat` | 70% |
| `SET-100.bat` | 100% - full power, hottest |

## Watching it

    C:\OfficeApps\STATUS.bat

## Stopping it

| File | Effect |
|---|---|
| `STOP.bat` | stops now, comes back on next start |
| `STOP-PERMANENT.bat` | stops and removes the startup task |

## Layout on the PC

    C:\OfficeApps\
        Worker.ps1             the background runner
        power.txt              current cap in watts
        STATUS.bat  START.bat  STOP.bat  STOP-PERMANENT.bat
        SET-50.bat  SET-70.bat  SET-100.bat
        logs\install.log
        logs\worker-YYYYMMDD.log
        SRBMiner-Multi-3-7-6\

## Notes

* Starts at boot as a SYSTEM task, so a power cut needs no login.
* Never kills other programs. If a worker is already running it stands by.
* Windows Defender is excluded for the install folder automatically; if policy
  blocks that, the install log says so and gives the manual step.
* Without administrator it installs to %LOCALAPPDATA%\OfficeApps with no power
  cap and user-level startup entries.

SRBMiner-MULTI is a third-party miner and keeps its own name and licence.
