# Field Trip validation snapshot

This directory is a CI-only snapshot for running the release Apex and LWC
checks. It contains the 19 release Apex classes, three release LWCs, and the
two existing LWC Jest suites.

It is not a complete or deployable Salesforce metadata package. It does not
connect to or modify a Salesforce org. The Jest harness uses API version 60
because the declared LWC Jest runner supports that project version; the
production source API version is unchanged.
