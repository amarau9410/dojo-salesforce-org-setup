Integer userLicenseTypes = 0;
Integer userLicenseCapacity = 0;
Integer userLicenseUsed = 0;

System.debug('=== USER LICENSES (Cloud / Platform Buckets) ===');
for (UserLicense ul : [
    SELECT Name, TotalLicenses, UsedLicenses
    FROM UserLicense
    WHERE TotalLicenses > 0
    ORDER BY Name
]) {
    userLicenseTypes++;
    userLicenseCapacity += (ul.TotalLicenses == null ? 0 : ul.TotalLicenses);
    userLicenseUsed += (ul.UsedLicenses == null ? 0 : ul.UsedLicenses);

    System.debug(
        'UserLicense | Name=' + ul.Name +
        ' | Total=' + ul.TotalLicenses +
        ' | Used=' + ul.UsedLicenses
    );
}

Integer pslTypes = 0;
Integer pslCapacity = 0;
Integer pslUsed = 0;

System.debug('=== PERMISSION SET LICENSES (Feature Licenses) ===');
for (PermissionSetLicense psl : [
    SELECT MasterLabel, TotalLicenses, UsedLicenses
    FROM PermissionSetLicense
    WHERE TotalLicenses > 0
    ORDER BY MasterLabel
]) {
    pslTypes++;
    pslCapacity += (psl.TotalLicenses == null ? 0 : psl.TotalLicenses);
    pslUsed += (psl.UsedLicenses == null ? 0 : psl.UsedLicenses);

    System.debug(
        'PSL | Feature=' + psl.MasterLabel +
        ' | Total=' + psl.TotalLicenses +
        ' | Used=' + psl.UsedLicenses
    );
}

System.debug('=== SANDBOX ENTITLEMENT SUMMARY ===');
System.debug('Cloud/Platform license types available: ' + userLicenseTypes);
System.debug('Cloud/Platform total seats: ' + userLicenseCapacity);
System.debug('Cloud/Platform seats in use: ' + userLicenseUsed);
System.debug('Feature license types available: ' + pslTypes);
System.debug('Feature license total seats: ' + pslCapacity);
System.debug('Feature license seats in use: ' + pslUsed);
System.debug('Done: sandbox_entitlement_report.apex');
