import { LightningElement, api } from 'lwc';

export default class PfCorporatePortfolio extends LightningElement {
    @api pageMode = 'home';

    @api homeUrl = '/s/';
    @api servicesUrl = '/s/services';
    @api projectsUrl = '/s/projects';
    @api contactUrl = '/s/contact';

    @api linkedInUrl = 'https://www.linkedin.com/in/nnamdi-udoye-74441847';
    @api emailAddress = 'nnamdiudoye@gmail.com';
    @api phoneNumber = '+447807228031';
    @api cvWordUrl = '/sfsites/c/resource/Nnamdi_Udoye_Salesforce_CV26_03_26_docx';
    @api cvPdfUrl = '/sfsites/c/resource/Nnamdi_Udoye_Salesforce_CV26_03_26_pdf';

    get normalizedMode() {
        return (this.pageMode || 'home').toLowerCase();
    }

    get isHome() {
        return this.normalizedMode === 'home';
    }

    get isServices() {
        return this.normalizedMode === 'services';
    }

    get isProjects() {
        return this.normalizedMode === 'projects';
    }

    get isContact() {
        return this.normalizedMode === 'contact';
    }

    get mailtoHref() {
        return `mailto:${this.emailAddress}`;
    }

    get phoneHref() {
        return `tel:${this.phoneNumber}`;
    }

    get highlights() {
        return [
            {
                title: 'Service Cloud Leadership',
                text: 'Led Salesforce support operations for global service teams, improving triage consistency and response quality.'
            },
            {
                title: 'Declarative Automation at Scale',
                text: 'Delivered Screen, Record-Triggered, and Scheduled Flows that removed repetitive admin effort and improved case throughput.'
            },
            {
                title: 'DevOps & Governance',
                text: 'Implemented low-risk delivery patterns with Copado, Azure DevOps, Permission Sets, and auditable release controls.'
            }
        ];
    }

    get timeline() {
        return [
            {
                role: 'Salesforce Administrator and Platform Consultant',
                company: 'Worldpay from FIS',
                summary: 'Owned service optimization initiatives, routing standards, and data governance improvements across core support journeys.'
            },
            {
                role: 'CRM Operations and Delivery Lead',
                company: 'Cross-functional Service and Sales Operations',
                summary: 'Drove backlog-to-release execution, stakeholder alignment, and KPI reporting for customer-facing process improvements.'
            },
            {
                role: 'Enterprise IT Practitioner',
                company: '15+ years multi-domain delivery',
                summary: 'Built production-grade operating discipline across service management, change control, and business systems reliability.'
            }
        ];
    }

    get toolkit() {
        return [
            'Service Cloud and Sales Cloud',
            'Field Service',
            'Flow Builder',
            'Omni-Channel and Case Routing',
            'Reports and Dashboards',
            'Validation Rules and Page Layouts',
            'Quick Text and Email Templates',
            'Custom Metadata Types',
            'Roles, Profiles and Permission Sets',
            'Data Governance',
            'Copado',
            'Azure DevOps',
            'Jira and Confluence',
            'Marketing Cloud',
            'SQL and Data Quality Controls',
            'Pardot and Campaign Operations'
        ];
    }

    get services() {
        return [
            {
                title: 'Salesforce Configuration',
                text: 'Configure objects, record types, layouts, validation standards, and security models aligned to business outcomes.'
            },
            {
                title: 'Automation and Case Management',
                text: 'Design robust Flows, routing, entitlement-safe automation, and Omni-Channel processes to reduce manual effort.'
            },
            {
                title: 'Sales Support and Customer Service',
                text: 'Improve service operations with smarter case layouts, response tooling, knowledge alignment, and workflow optimization.'
            },
            {
                title: 'Access and Permission Governance',
                text: 'Implement role-based visibility and controlled access that supports secure day-to-day operations.'
            },
            {
                title: 'Data Governance and Reporting',
                text: 'Improve data quality, enforce governance standards, and deliver dashboards leadership can trust.'
            },
            {
                title: 'Release and Change Delivery',
                text: 'Support low-risk deployments and auditable releases using CI/CD disciplines and platform best practices.'
            },
            {
                title: 'Operational Analytics and Dashboards',
                text: 'Build practical KPI dashboards for SLA, throughput, and quality signals to support leadership decision-making.'
            }
        ];
    }

    get outcomes() {
        return [
            '30% reduction in manual verification through automated case handling patterns.',
            '20% improvement in response consistency using governed Quick Text and process standards.',
            'Higher data quality and lower rework through validation controls and role-based governance.',
            'Faster, safer releases with declarative-first design and repeatable deployment discipline.'
        ];
    }

    get projects() {
        return [
            {
                label: 'Service Cloud Automation',
                title: 'Contact-to-Account Matching Flow',
                challenge: 'Support teams spent too much time linking records manually.',
                delivered: 'Screen Flow logic, validation checks, and cleaner routing inputs.',
                outcome: '100 percent accurate linkage and a faster, more reliable support process.'
            },
            {
                label: 'Operations Efficiency',
                title: 'Quick Text Framework Standardization',
                challenge: 'Inconsistent replies increased handling time and reduced quality control.',
                delivered: 'Governed Quick Text templates, naming standards, and team adoption support.',
                outcome: 'Lower average handle time and more consistent customer communication.'
            },
            {
                label: 'Secure Delivery',
                title: 'Permission Set and Release Governance',
                challenge: 'Legacy access models made governance and audits hard to manage.',
                delivered: 'Permission Set migration support, Copado release discipline, and lower-risk change control.',
                outcome: 'Stronger compliance posture and predictable zero-downtime releases.'
            },
            {
                label: 'Compliance Automation',
                title: 'Fire Door Compliance Lifecycle',
                challenge: 'Inspection failures and repairs needed auditable end-to-end tracking.',
                delivered: 'Declarative Flows, SLA-driven metadata, linked Case and Work Order automation, and dashboard reporting.',
                outcome: 'Faster remediation tracking and a deployable no-Apex compliance framework.'
            },
            {
                label: 'Financial Operations',
                title: 'Personal Finance Management App',
                challenge: 'Manual tracking of spending, shared contributions, and repayments was fragmented.',
                delivered: 'Custom objects, record-triggered and scheduled Flows, CSV and PDF ingestion, reminders, and dashboards.',
                outcome: 'Structured, privacy-aware budgeting with clearer repayment and month-end control.'
            }
        ];
    }

    trackClick(event) {
        const eventName = event.currentTarget?.dataset?.eventName;
        const eventLabel = event.currentTarget?.dataset?.eventLabel;

        if (!eventName || typeof window.gtag !== 'function') {
            return;
        }

        window.gtag('event', eventName, {
            link_text: eventLabel || 'portfolio_link',
            page_mode: this.normalizedMode,
            page_location: window.location.href
        });
    }
}
