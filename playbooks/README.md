# ERP/1 SRE Incident Response Playbooks

Official runbooks for on-call engineers.  
Aligned with CD/SRE Handbook Section 12.

**Severity Reference**  
- **Sev1**: Platform unavailable (erp-telemetry, erp-security, control-plane) → MTTR < 30 min + mandatory postmortem  
- **Sev2**: Critical services/apps down → MTTR < 1 hour + postmortem  
- **Sev3**: Degradation (high latency, partial outage) → Same business day  
- **Sev4**: Minor/cosmetic → Next sprint

**General Workflow**  
1. Acknowledge alert  
2. Follow playbook  
3. Document actions in incident ticket  
4. Run postmortem for Sev1/Sev2

**Playbooks in this folder:**
- 01-sev1-cluster-outage.md
- 02-sev2-application-degradation.md
- 03-resource-exhaustion.md
- 04-gitops-network-stateful.md
