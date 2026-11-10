# Changes to your Keycloak realm

These let your realm relay CILogon identities to the Pelican origin. They
assume Keycloak 26.2 or later (for standard token exchange) and a realm that
already brokers CILogon.

## 1. CILogon identity provider: relay the subject

In **Identity providers**, open your CILogon provider.

- Note its **Alias**. Pelican requires it in the `identity_provider` claim.
- Keep **Trust Email** off and the default **First login flow - cilogon**.

Then **Mappers → Add mapper**:

| Setting | Value |
|---|---|
| Name | `cilogon-subject` |
| Sync mode override | **Force** |
| Mapper type | **User Session Note Mapper** |
| Claims | key `sub`, value `.*` |
| Regex Claim Values | On |

Keycloak re-runs identity provider mappers on later logins only when the
effective sync mode is Force. With Import, the note would be set only on a
user's first-ever login, and every later exchange would fail. The mapper names
each note after its claim, so this stores CILogon's subject in the session
note `sub`.

## 2. Audience client

**Clients → Create client**: Client ID `pelican-origin`, with every flow
turned off. It exists only so tokens can name Pelican as their audience.

## 3. Client scope `pelican`

**Client scopes → Create client scope**: name `pelican`, protocol OpenID
Connect, Include in token scope on. Then **Mappers → Add mapper → By
configuration**, each with **Add to access token** on:

| Mapper type | Settings |
|---|---|
| Audience | Included Client Audience: `pelican-origin` |
| User Session Note | User Session Note: `sub`; Token Claim Name: `upstream_sub`; Claim JSON Type: String |
| User Session Note | User Session Note: `identity_provider`; Token Claim Name: `identity_provider`; Claim JSON Type: String |

Keycloak sets the `identity_provider` note itself on every brokered login.

## 4. Your application's client (for example, JupyterHub's)

- **Settings → Capability config**: Client authentication on, and
  **Standard token exchange** on.
- **Client scopes → Add client scope**: `pelican`, as **Optional**.
- For testing from a terminal only: **OAuth 2.0 Device Authorization Grant**
  on.

## 5. Values for `config/origin.yaml`

| Setting in origin.yaml | Where it comes from |
|---|---|
| `Issuer` | the `issuer` value in `https://<keycloak-host>/realms/<realm>/.well-known/openid-configuration`, copied exactly |
| `Audiences` | `pelican-origin` (step 2) |
| `RequiredClaims` → `azp` | your application's Client ID (step 4) |
| `RequiredClaims` → `identity_provider` | the CILogon provider's Alias (step 1) |
| `SubjectClaim` | `upstream_sub` (step 3) |

## 6. Check it

**Client scopes → Evaluate** can't show `upstream_sub` or `identity_provider`,
because they exist only in a real CILogon login session. Instead, run README
step 7 and decode the token Keycloak returns from its exchange. It should
carry `aud: pelican-origin`, `azp` set to your client, `identity_provider` set
to the alias, and an `upstream_sub` beginning `http://cilogon.org/`.

If `upstream_sub` is missing, check the mapper's sync mode (step 1), and that
the user logged in through CILogon in this session.
