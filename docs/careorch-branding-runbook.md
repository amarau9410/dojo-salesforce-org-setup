# CareOrch Branding Runbook (careorchdev)

Date: 2026-05-27
Target org: careorchdev

## Deployed assets

- CareOrch logo static resource deployed:
  - force-app/main/default/staticresources/CareOrchLogo.png
  - force-app/main/default/staticresources/CareOrchLogo.resource-meta.xml
- CareOrch Lightning app metadata is deployed and stable:
  - force-app/main/default/applications/CareOrch.app-meta.xml

## Recommended brand palette from CareOrchLogo

- Primary navy: #0B3F78
- Secondary blue: #2F9FD8
- Accent green: #88C64A
- Accent orange: #F5A623
- Soft background blue: #EAF4FB
- Neutral white: #FFFFFF

## Apply org branding in Setup (manual)

1. Go to Setup -> Themes and Branding.
2. Open the active org theme (or clone/create a new one first).
3. Set brand color to #0B3F78.
4. Set page background/accent to #EAF4FB where available.
5. Upload logo image from local file:
   - Use force-app/main/default/staticresources/CareOrchLogo.png as source image.
6. Save and activate the theme.

## Apply app branding in Setup (manual)

1. Go to Setup -> App Manager.
2. Locate app: CareOrch.
3. Edit app branding:
   - App color: #0B3F78
   - Logo: CareOrchLogo.png
4. Save.

## Why manual for org/app visual skin

In this org, metadata deployment supports app structure and static resources, but visual app/org skin fields (logo and color tokens) are not accepted through CustomApplication XML in the current metadata shape. This is why color/logo skin must be applied through Setup UI.

## Validation checklist

- Login to careorchdev and open the app launcher.
- Open CareOrch app and confirm navbar color reflects #0B3F78.
- Confirm CareOrch logo appears in app branding header/icon context.
- Confirm no navigation regressions in app tabs.
