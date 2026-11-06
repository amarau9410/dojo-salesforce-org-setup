# Field Trip validation snapshot

This directory is a CI-only snapshot for running the release Apex and LWC
checks. It contains the 19 release Apex classes, three release LWCs, and the
three LWC Jest suites.

It is not a complete or deployable Salesforce metadata package. It does not
connect to or modify a Salesforce org. The Jest harness uses API version 60
because the declared LWC Jest runner supports that project version; the
production source API version is unchanged.

Field Usage metrics and details use separate cacheable Apex requests. The
metrics endpoint scans matching evidence once; the details endpoint independently
enforces alliance access and retains the explicit 10,000-row cap. Aggregate
totals are not calculated from truncated details. The suite covers response
ordering, truncation, independent errors, and refresh failures. The analyzer
workflow fails on Critical or High findings.
