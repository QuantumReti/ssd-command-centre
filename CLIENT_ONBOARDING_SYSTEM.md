# Client Onboarding System
## Sun State Digital — Complete Framework

**Automated onboarding time:** 5 minutes (via `onboard-client.sh`)
**Full manual process:** 2-3 hours
**First client:** Quantum Buyers Agents (Nick Esplin, +61427716756)

---

## Overview

The client onboarding system takes a new client from signed contract to fully operational in one business day. The automated script handles all technical setup; the human process handles relationship and requirements.

```
Day 0: Discovery & Sales
Day 1-2: Solution Design & Proposal
Day 3-5: Contract signed → Kickoff call
Day 5: Technical onboarding (automated + 2 hours)
Day 6-14: Workflow building & integration
Day 15: Go-live
Day 30: First review
```

---

## Phase 1: Discovery Questionnaire

Ask these questions before designing any solution:

### Business Questions

```
1. What is your primary business? What do you sell?
2. Who are your ideal customers? (describe in detail)
3. What is your average deal size / customer lifetime value?
4. How many leads do you currently get per month?
5. What percentage of leads convert to customers?
6. What is the biggest bottleneck in your current process?
7. How do you currently track leads? (CRM, spreadsheet, etc.)
8. Do you have a sales team, or is it just you?
9. What's your monthly marketing spend?
10. What would a 2x increase in conversions be worth to you?
```

### Technical Questions

```
11. What software do you currently use?
    [ ] CRM: _______________
    [ ] Email marketing: _______________
    [ ] Accounting: _______________
    [ ] Booking/scheduling: _______________
    [ ] Property platform (for real estate): _______________

12. Do you use Google Workspace (Gmail, Drive, Sheets)?
13. Do you advertise on Facebook/Instagram?
14. Do you advertise on Google?
15. Do you have a website? URL: _______________
16. Do you have existing automation set up?
17. Who manages your tech? (you, a VA, a team member?)
18. What's your tech comfort level? (1-10)
19. Do you use GoHighLevel or similar platform?
20. What's your biggest technical frustration?
```

### Budget & Timeline Questions

```
21. What's your monthly budget for growth tools?
22. Have you worked with agencies or SaaS platforms before?
23. What happened? (positive/negative experience)
24. When do you want to see results?
25. Who makes the final decision on this investment?
```

---

## Phase 2: Solution Design Template

Based on discovery, create a solution design document:

```markdown
# Solution Design: [CLIENT NAME]

**Date:** [DATE]
**Prepared by:** Josh, Sun State Digital
**Client:** [Name, Company, Email, Phone]

## Current State
- [Describe their current process]
- [Key pain points identified]
- [Volume metrics: leads/month, conversions, deal size]

## Proposed Solution

### Core Workflows
1. **Lead Capture & Qualification**
   - Source: [Facebook Ads / Google Ads / Website form]
   - Enrichment: [LinkedIn, property data, etc.]
   - Scoring model: [criteria specific to their business]

2. **Automated Nurture Sequence**
   - Trigger: Lead score > 70
   - Channel: [Email + SMS + WhatsApp]
   - Sequence: [Day 0, 1, 3, 7, 14 touchpoints]

3. **CRM Integration**
   - Platform: [GHL / HubSpot / custom]
   - Data sync: [real-time / daily]
   - Pipeline stages: [Prospect → Qualified → Proposal → Closed]

4. **Reporting & Analytics**
   - Dashboard: [real-time Grafana client dashboard]
   - Reports: [weekly email summary]
   - Metrics tracked: [leads, conversion rate, revenue]

## Technical Architecture
[Diagram specific to their setup]

## Timeline
Week 1: Setup & integration
Week 2: Workflow building
Week 3: Testing & refinement
Week 4: Go-live & training

## Investment
Setup: $[amount]
Monthly: $[amount]
Tier: [Starter / Growth / Enterprise]
```

---

## Phase 3: Proposal Template

```
═══════════════════════════════════════════════════════
           SUN STATE DIGITAL
           AI Growth Services Proposal
═══════════════════════════════════════════════════════

Prepared for: [CLIENT NAME]
Date: [DATE]
Prepared by: Josh — Sun State Digital
Contact: joshua@sunstatedigital.com.au

───────────────────────────────────────────────────────
EXECUTIVE SUMMARY
───────────────────────────────────────────────────────
We will build you an automated AI-powered lead
management system that [specific outcome] within
[timeframe], generating [projected ROI].

───────────────────────────────────────────────────────
WHAT WE'LL BUILD
───────────────────────────────────────────────────────
✓ [Workflow 1]
✓ [Workflow 2]
✓ [Workflow 3]
✓ Custom dashboard
✓ [Integrations]

───────────────────────────────────────────────────────
INVESTMENT
───────────────────────────────────────────────────────
Setup Fee:     $[X,XXX]
Monthly:       $[X,XXX]/month
Contract:      [3/6/12] months
Next payment:  After go-live

───────────────────────────────────────────────────────
PROJECTED ROI
───────────────────────────────────────────────────────
Current leads/month:      [X]
Projected leads/month:    [X] (+[X]%)
Current conversion:       [X]%
Projected conversion:     [X]%
Projected extra revenue:  $[XX,XXX]/month

Your investment pays back in: [X] weeks

───────────────────────────────────────────────────────
NEXT STEPS
───────────────────────────────────────────────────────
1. Sign and return this proposal
2. Pay setup fee (invoice sent on signing)
3. Complete credential form (we send it)
4. Kickoff call (scheduled at signing)
5. Go-live in [X] business days

Support: support@sunstatedigital.com.au
Phone:   0XXX XXX XXX
═══════════════════════════════════════════════════════
```

---

## Phase 4: Kickoff Checklist

Complete before kickoff call:

```
PRE-KICKOFF (Josh does this):
[ ] Proposal signed and received
[ ] Setup fee paid
[ ] Credential collection form sent
[ ] Credentials received and validated
[ ] Kickoff call scheduled (1 hour)
[ ] Kickoff agenda prepared
[ ] Slack channel created for client

DURING KICKOFF CALL:
[ ] Introductions (5 min)
[ ] Review solution design together (15 min)
[ ] Confirm integrations and access (10 min)
[ ] Walk through workflow design (15 min)
[ ] Set expectations and timeline (10 min)
[ ] Assign any client action items (5 min)

POST-KICKOFF:
[ ] Send kickoff summary via email
[ ] Send Slack invite
[ ] Begin technical onboarding (onboard-client.sh)
[ ] Schedule check-in calls (weekly for first month)
```

---

## Phase 5: Credential Collection Form

Send this form to the client. Collect via encrypted form or 1Password share.

### Required Credentials by Category

#### Google Workspace / Google Cloud

```
[ ] Google Workspace Admin email: _______________
[ ] Service Account JSON: [upload]
[ ] Google Ads Customer ID: _______________
[ ] Google Analytics 4 Property ID: _______________
[ ] Google Tag Manager Container ID: _______________
[ ] Google Search Console verified: [ ] Yes [ ] No
```

#### Meta / Facebook

```
[ ] Facebook Business Manager ID: _______________
[ ] Facebook Ad Account ID: _______________
[ ] Meta App ID: _______________
[ ] Meta App Secret: _______________
[ ] Facebook Page ID: _______________
[ ] Instagram Account ID: _______________
[ ] Meta Pixel ID: _______________
[ ] Conversion API Token: _______________
```

#### GoHighLevel (GHL)

```
[ ] GHL API Key: _______________
[ ] GHL Location ID: _______________
[ ] GHL Pipeline ID: _______________
[ ] GHL Calendar ID (for booking): _______________
[ ] Webhook URL (from GHL): _______________
```

#### Slack

```
[ ] Slack workspace URL: _______________
[ ] Slack Bot Token: _______________
[ ] Slack channel for notifications: _______________
[ ] Slack user IDs (for alerts): _______________
```

#### CRM (if not GHL)

```
[ ] CRM type: _______________
[ ] API key/credentials: _______________
[ ] Pipeline/stage IDs: _______________
```

#### Property Platform (Real Estate clients)

```
[ ] Domain.com.au API key: _______________
[ ] REA API key: _______________
[ ] CoreLogic API key: _______________
[ ] Property data source: _______________
```

#### Email & SMS

```
[ ] From email address: _______________
[ ] Email sending domain (for SPF/DKIM): _______________
[ ] SMS provider: _______________
[ ] SMS API credentials: _______________
[ ] Twilio Account SID (if Twilio): _______________
[ ] Twilio Auth Token: _______________
```

#### Website

```
[ ] Website URL: _______________
[ ] CMS admin access (if needed): _______________
[ ] DNS provider + login: _______________
[ ] Hosting provider: _______________
```

---

## Phase 6: Integration Setup Procedures

### Google Integration

```bash
# 1. Create Service Account
# In Google Cloud Console → IAM → Service Accounts
# Download JSON key file

# 2. Grant permissions
# Google Ads: Invite service account email as user
# Analytics: Add service account as viewer/editor
# Drive: Share relevant folders with service account

# 3. Store in Secrets Manager
aws secretsmanager create-secret \
  --name "ssd/clients/CLIENTID/google-service-account" \
  --secret-string file://service-account.json \
  --region ap-southeast-2

# 4. Test integration
curl -X POST https://api.ssd.cloud/api/v1/integrations/test \
  -H "Authorization: Bearer $CLIENT_API_KEY" \
  -d '{"integration": "google", "client_id": "CLIENTID"}'
```

### Meta / Facebook Integration

```bash
# 1. Create Meta App at developers.facebook.com
# App type: Business
# Add products: Marketing API, Webhooks

# 2. Request permissions
# ads_management
# ads_read
# leads_retrieval
# pages_read_engagement

# 3. Set up webhook
# Callback URL: https://api.ssd.cloud/webhooks/meta/CLIENTID
# Verify token: Generate in onboard-client.sh
# Subscribe to: leadgen, messages

# 4. Configure Conversions API
# Set pixel ID and access token in client config

# 5. Test
curl -X POST https://api.ssd.cloud/webhooks/meta/CLIENTID \
  -H "X-Hub-Signature-256: sha256=TEST" \
  -d '{"object":"page","entry":[]}'
```

### GoHighLevel Integration

```bash
# 1. Generate GHL API key
# GHL → Settings → API & Webhooks → Create Key

# 2. Configure webhook endpoint
# GHL → Settings → Webhooks → Add New
# URL: https://api.ssd.cloud/webhooks/ghl/CLIENTID
# Events: Contact Created, Contact Updated, Opportunity Updated

# 3. Get Location ID
# GHL → Settings → Business Profile → Location ID

# 4. Test webhook delivery
# GHL → Webhooks → Test Webhook
```

### n8n Workflow Setup

```bash
# 1. Access n8n instance
# URL: http://n8n.ssd.cloud (internal only, SSH tunnel)
# ssh -L 5678:localhost:5678 ssd-prod -N

# 2. Create credentials for this client
# n8n → Credentials → New
# Add: Google, Facebook, GHL, Slack credentials

# 3. Import workflow template
# n8n → Workflows → Import from File
# Template: workflows/lead-qualification-template.json

# 4. Customize for client
# Update filters, scoring criteria, notification channels

# 5. Activate workflow
# Toggle to Active
```

---

## Phase 7: Workflow Building Framework

### Core Workflow 1: Lead Capture & Qualification

```
TRIGGER: New lead arrives (Facebook Lead Ad, website form, GHL)
         ↓
STEP 1: Enrich lead data
  - Lookup name + email + phone in people data APIs
  - Find LinkedIn profile (if available)
  - For real estate: get property ownership data
         ↓
STEP 2: Score the lead (0-100)
  Scoring criteria:
  + Phone provided: +20 pts
  + Email verified: +10 pts
  + LinkedIn found: +15 pts
  + Property value > threshold: +25 pts
  + Response to initial message: +30 pts
  - Generic email (Gmail/Hotmail): -10 pts
  - Invalid phone: -20 pts
         ↓
STEP 3: Route based on score
  Score 80-100: HOT → Immediate Slack alert to client
  Score 50-79:  WARM → Automated nurture sequence
  Score 0-49:   COLD → Long-term drip campaign
         ↓
STEP 4: Create/update CRM record
  - Push to GHL pipeline at correct stage
  - Assign to correct team member
  - Add tags for source and score range
         ↓
STEP 5: Trigger appropriate communication
  - HOT: SMS + email within 60 seconds
  - WARM: Email sequence starts
  - COLD: Added to nurture list
```

### Core Workflow 2: Automated Nurture Sequence

```
TRIGGER: Lead enters nurture (score 50-79)

Day 0:   Instant email — personal introduction
Day 1:   SMS — "Did you see my email?"
Day 3:   Email — case study / social proof
Day 5:   SMS — value-add tip specific to their situation
Day 7:   Email — "Are you still looking?" re-engagement
Day 10:  Call task created for sales team (if score > 60)
Day 14:  Final email — "I want to help you..."
Day 30:  Monthly newsletter added
```

### Core Workflow 3: Data Enrichment Pipeline

```python
# Quantum API handles this automatically

def enrich_lead(lead_data):
    enriched = lead_data.copy()

    # 1. Email verification
    enriched['email_valid'] = verify_email(lead_data['email'])

    # 2. Phone lookup
    enriched['phone_info'] = lookup_phone(lead_data['phone'])

    # 3. LinkedIn lookup
    enriched['linkedin'] = find_linkedin(lead_data['name'], lead_data['company'])

    # 4. Property data (real estate clients)
    if client_type == 'real_estate':
        enriched['properties'] = get_property_history(lead_data['address'])
        enriched['estimated_equity'] = calculate_equity(enriched['properties'])

    # 5. Company lookup
    if lead_data.get('company'):
        enriched['company_info'] = lookup_company(lead_data['company'])

    return enriched
```

---

## Phase 8: Dashboard Creation

### Client-Specific Dashboard (Grafana)

For each client, create a dashboard at:
`https://monitor.ssd.cloud/d/client-{client-id}`

```json
{
  "dashboard": {
    "title": "Quantum Buyers Agents — Performance",
    "panels": [
      {"title": "Leads This Month", "type": "stat"},
      {"title": "Lead Quality Score (avg)", "type": "gauge"},
      {"title": "Conversion Rate", "type": "stat"},
      {"title": "Revenue Attributed", "type": "stat"},
      {"title": "Lead Volume Over Time", "type": "timeseries"},
      {"title": "Lead Sources", "type": "piechart"},
      {"title": "Workflow Executions", "type": "timeseries"},
      {"title": "Response Time to Hot Leads", "type": "stat"}
    ]
  }
}
```

### Client Dashboard Access

```bash
# Create read-only Grafana user for client
curl -X POST https://monitor.ssd.cloud/api/org/users \
  -H "Content-Type: application/json" \
  -u admin:$GRAFANA_ADMIN_PASSWORD \
  -d '{
    "loginOrEmail": "nick@quantumbuyersagents.com.au",
    "role": "Viewer"
  }'
```

---

## Phase 9: Go-Live Procedure

### Go-Live Checklist

```
24 HOURS BEFORE:
[ ] All integrations tested with real data
[ ] Workflows run through manually
[ ] Client sign-off on dashboard
[ ] DNS propagated (if using custom subdomain)
[ ] SMS sending tested
[ ] Email delivery tested (check spam score)
[ ] GHL pipeline configured correctly

GO-LIVE DAY:
[ ] Run smoke test: ./verify-deployment.sh
[ ] Activate all n8n workflows
[ ] Enable all webhook endpoints
[ ] Send test lead through entire system
[ ] Confirm client receives alerts
[ ] Confirm CRM record created correctly
[ ] Confirm email/SMS delivered
[ ] Brief client on how to use dashboard

POST-GO-LIVE (48 hours):
[ ] Monitor for errors in Grafana
[ ] Check all workflows executed as expected
[ ] Review first real leads processed
[ ] Client check-in call
[ ] Document any issues resolved
```

### Welcome Email Template

```
Subject: 🚀 You're live on Sun State Digital! Here's your access

Hi [CLIENT NAME],

Great news — your AI lead management system is now live!

--- YOUR ACCESS ---

Dashboard:    https://monitor.ssd.cloud/d/client-[ID]
Username:     [their email]
Password:     [generated password]

API Endpoint: https://api.ssd.cloud/clients/[ID]
API Key:      [generated key]

--- WHAT HAPPENS NOW ---

✅ Leads from [their sources] are automatically captured
✅ Each lead is enriched and scored within 60 seconds
✅ Hot leads (score 80+) trigger instant SMS to your phone
✅ All leads are added to your GHL pipeline
✅ Weekly performance report sent every Monday

--- SUPPORT ---

Slack: You've been invited to #[client-channel]
Email: support@sunstatedigital.com.au
Phone: Available on [support tier] plan

We're excited to see your results!

Josh
Sun State Digital
```

---

## Phase 10: Support Tiers

### Tier 1 — Email Support (Included)
- **Response time:** 24 hours (business days)
- **Channels:** Email only
- **Included in:** All plans
- **Scope:** General questions, billing, documentation
- **Price:** $0 additional

### Tier 2 — Priority Support
- **Response time:** 4 hours (business days)
- **Channels:** Email + Phone + Slack channel
- **Price:** $500/month additional (or included in Growth+)
- **Scope:** Technical issues, workflow changes, integration help
- **Dedicated Slack channel:** Yes (#client-name)

### Tier 3 — Dedicated Manager
- **Response time:** 1 hour (any day, 7 AM - 8 PM AEDT)
- **Channels:** Direct mobile, Slack, Video calls
- **Price:** $2,000/month additional (or included in Enterprise)
- **Scope:** Strategic consulting, custom development, weekly calls
- **Monthly strategy call:** Yes (1 hour)
- **Quarterly business review:** Yes

### SLA Definitions

| Metric | Tier 1 | Tier 2 | Tier 3 |
|---|---|---|---|
| First response | 24h | 4h | 1h |
| Resolution (critical) | 72h | 24h | 4h |
| Resolution (standard) | 5 days | 48h | 24h |
| Uptime guarantee | 99.9% | 99.95% | 99.99% |
| Scheduled maintenance | 7 days notice | 3 days | 24h |
| Emergency contact | Email | Phone | Mobile direct |

### Escalation Path

```
Client Issue
    │
    ▼
Tier 1: Email support@sunstatedigital.com.au
    │ Not resolved in 24h?
    ▼
Tier 2: Phone + Slack escalation
    │ Not resolved in 4h?
    ▼
Tier 3: Josh directly on mobile
    │ Requires engineering?
    ▼
Emergency deployment/fix
```

---

## Automated Onboarding Script

For technical setup, run:

```bash
cd /opt/ssd
./onboard-client.sh
```

This handles:
- Database schema creation
- API key generation
- S3 bucket creation
- DNS subdomain setup
- Monitoring dashboard
- Welcome email

**Time to complete: ~5 minutes**

---

*See `onboard-client.sh` for the automated implementation of this framework.*
