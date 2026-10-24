# Identity federation: Microsoft Entra ID → AWS IAM Identity Center

A hybrid network solves *connectivity*. Most AWS + Azure organizations also need
**one identity** for people across both clouds, which was the "no unified IAM"
gap I identified in the CLCS 625 capstone (Global Tech Industries' hybrid AWS
and Azure estate). This guide sets that up; it is mostly console work, so it is
documented rather than automated.

## Target state

- People sign in once with their Microsoft Entra ID account (with Conditional
  Access / MFA enforced by Entra).
- Entra **groups** decide which AWS accounts and permission sets they get.
- Users and groups are provisioned into AWS automatically with **SCIM**; leavers
  lose AWS access when they are disabled in Entra.

## Steps

1. **AWS:** IAM Identity Center → *Settings* → *Identity source* → change to
   **External identity provider**. Download the AWS SAML metadata and keep the
   page open.
2. **Entra:** *Enterprise applications* → *New application* → add **AWS IAM
   Identity Center** from the gallery. In *Single sign-on* choose SAML and
   upload the AWS metadata file. Download the Entra *Federation Metadata XML*.
3. **AWS:** upload the Entra metadata to finish the identity-source change.
4. **AWS:** IAM Identity Center → *Settings* → *Automatic provisioning* →
   enable, copy the **SCIM endpoint** and **access token**.
5. **Entra:** in the enterprise app → *Provisioning* → *Automatic*, paste the
   SCIM endpoint and token, test the connection, assign groups (e.g.
   `aws-network-admins`, `aws-readonly`), and start provisioning.
6. **AWS:** create permission sets (`NetworkAdministrator` scoped to VPC/VPN
   actions, `ViewOnlyAccess`) and assign the provisioned groups to the account.
7. **Verify:** sign in through the AWS access portal with an Entra user; confirm
   that the CloudTrail event shows the federated identity, and that disabling the
   user in Entra removes access after the next provisioning cycle.

## Evidence to capture

- Entra enterprise app with provisioning status *healthy*
- IAM Identity Center showing users and groups sourced from Entra
- AWS access portal sign-in via the Entra login page
- CloudTrail `Federate` / sign-in event for the Entra user
