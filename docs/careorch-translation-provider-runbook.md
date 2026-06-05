# CareOrch Translation Provider Runbook (careorchdev)

Date: 2026-05-28
Target org: careorchdev

## Objective

Configure a Named Credential used by CareOrch multilingual translation automation and validate one end-to-end translation update.

## Runtime components already deployed

- Apex action:
  - force-app/main/default/classes/CareOrchObservationAutoTranslateAction.cls
- Translation prep flow (sets Pending Translation):
  - force-app/main/default/flows/CareOrch_Observation_Translation_Prep.flow-meta.xml
- Auto-translate flow (invokes Apex action):
  - force-app/main/default/flows/CareOrch_Observation_Auto_Translate.flow-meta.xml

## Named Credential required

Apex expects this endpoint:

- callout:CareOrchTranslationService/translate

Therefore create Named Credential with:

- Label: CareOrch Translation Service
- API Name: CareOrchTranslationService
- URL: base provider URL (without trailing /translate)
- Allow Merge Fields in HTTP Header: enabled
- Allow Merge Fields in HTTP Body: enabled

Authentication model can be either:

1. Per-user OAuth (recommended for audited user context), or
2. Named principal (service account) with token rotation governance.

Use your provider security standard for auth material. Do not store raw secrets in Apex.

## Provider request/response contract

Apex sends POST to /translate with JSON body:

{
  "sourceLanguage": "es",
  "targetLanguage": "en",
  "text": "dolor y agua"
}

Provider should return 2xx with JSON containing one of these keys:

- translatedText
- translation
- englishText

Example response:

{
  "translatedText": "pain and water"
}

If response is not 2xx or no supported key is present, CareOrch uses embedded fallback translation logic.

## One-record validation steps

1. Confirm at least one CareObservation record exists with:
   - Translation_Status__c = Pending Translation
   - English_Translation__c is blank
   - Original_Observation__c is populated
2. Run the anonymous Apex script:
   - scripts/validate_careorch_translation_provider.apex
3. Review debug logs for:
   - Invocable action result success flag
   - Updated record state
4. Confirm record updated to:
   - Translation_Status__c = Auto Translated
   - English_Translation__c populated

## Troubleshooting

- Error: Unauthorized/403/401
  - Check Named Credential auth binding and token scope.
- Error: DNS/timeout/callout
  - Verify URL, network policy, and provider uptime.
- Result says success but text unchanged
  - Ensure provider returns one of: translatedText, translation, englishText.
- No candidate records found
  - Create or update one observation with Pending Translation and retry.

## Rollback

1. Deactivate flow: CareOrch Observation Auto Translate.
2. Keep prep flow active if you still want Pending Translation tagging only.
3. Re-enable after provider endpoint/auth fixes are complete.
