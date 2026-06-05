import { LightningElement, api } from 'lwc';

export default class PfCorporateTrustFooter extends LightningElement {
    @api merchantsSupported = 150000;
    @api salesforceYears = 5;
    @api enterpriseYears = 15;
    @api reliabilityPercent = 99.9;

    @api linkedInUrl = 'https://www.linkedin.com/in/nnamdi-udoye-74441847';
    @api emailAddress = 'nnamdiudoye@gmail.com';

    hasAnimated = false;
    animatedValues = {
        merchantsSupported: '0+',
        salesforceYears: '0+',
        enterpriseYears: '0+',
        reliabilityPercent: '0%'
    };

    get metricCards() {
        return [
            {
                key: 'merchantsSupported',
                value: this.animatedValues.merchantsSupported,
                label: 'Merchants Supported'
            },
            {
                key: 'salesforceYears',
                value: this.animatedValues.salesforceYears,
                label: 'Years in Salesforce Delivery'
            },
            {
                key: 'enterpriseYears',
                value: this.animatedValues.enterpriseYears,
                label: 'Years in Enterprise IT'
            },
            {
                key: 'reliabilityPercent',
                value: this.animatedValues.reliabilityPercent,
                label: 'Release Reliability Goal'
            }
        ];
    }

    get certifications() {
        return [
            {
                label: 'Salesforce Certified Platform Administrator II',
                badgeUrl: 'https://developer.salesforce.com/resources2/certification-site/images/Certifications-logo/Advanced-Administrator.png'
            },
            {
                label: 'Salesforce Certified Platform Administrator',
                badgeUrl: 'https://developer.salesforce.com/resources2/certification-site/images/Certifications-logo/Administrator.png'
            },
            {
                label: 'Salesforce Certified Service Cloud Consultant',
                badgeUrl: 'https://developer.salesforce.com/resources2/certification-site/images/Certifications-logo/Service-Cloud-Consultant.png'
            },
            {
                label: 'Salesforce Certified Sales Cloud Consultant',
                badgeUrl: 'https://developer.salesforce.com/resources2/certification-site/images/Certifications-logo/Sales-Cloud-Consultant.png'
            },
            {
                label: 'B.Sc. Computing – University of Greenwich',
                badgeUrl: 'https://www.gre.ac.uk/__data/assets/image/0035/265688/logo_final_on_white.png'
            },
            {
                label: 'CompTIA A+ CE | Microsoft 365 Fundamentals',
                badgeUrl: 'https://images.credly.com/size/340x340/images/f6d62c5d-1e1d-4de6-92ee-8dc8c80b1c7b/blob'
            }
        ];
    }

    get deliveryPillars() {
        return [
            'Declarative-first architecture',
            'Secure role and permission design',
            'Low-risk deployment governance',
            'Measurable service outcomes'
        ];
    }

    get mailtoHref() {
        return `mailto:${this.emailAddress}`;
    }

    renderedCallback() {
        if (this.hasAnimated) {
            return;
        }

        this.hasAnimated = true;
        this.startCounterAnimation();
    }

    startCounterAnimation() {
        this.animateMetric('merchantsSupported', Number(this.merchantsSupported), (v) => `${Math.round(v).toLocaleString()}+`);
        this.animateMetric('salesforceYears', Number(this.salesforceYears), (v) => `${Math.round(v)}+`);
        this.animateMetric('enterpriseYears', Number(this.enterpriseYears), (v) => `${Math.round(v)}+`);
        this.animateMetric('reliabilityPercent', Number(this.reliabilityPercent), (v) => `${v.toFixed(1)}%`);
    }

    animateMetric(key, target, formatter) {
        const duration = 1300;
        const start = performance.now();

        const step = (timestamp) => {
            const elapsed = timestamp - start;
            const progress = Math.min(elapsed / duration, 1);
            const eased = 1 - Math.pow(1 - progress, 3);
            const current = target * eased;

            this.animatedValues = {
                ...this.animatedValues,
                [key]: formatter(current)
            };

            if (progress < 1) {
                window.requestAnimationFrame(step);
            }
        };

        window.requestAnimationFrame(step);
    }

    trackClick(event) {
        const eventName = event.currentTarget?.dataset?.eventName;
        const eventLabel = event.currentTarget?.dataset?.eventLabel;

        if (!eventName || typeof window.gtag !== 'function') {
            return;
        }

        window.gtag('event', eventName, {
            link_text: eventLabel || 'trust_footer_link',
            page_location: window.location.href
        });
    }
}
