/**
 * Apple Sign In identity-token verification + app-issued JWT.
 *
 * Flow:
 *   1. iOS app does ASAuthorizationController flow → receives `identityToken`
 *      (a JWT signed by Apple) + `authorizationCode`.
 *   2. App POSTs `{ identityToken, authorizationCode, fullName? }` to
 *      `/api/auth/apple`.
 *   3. We verify `identityToken` against Apple's public JWKS, extract `sub`
 *      (stable Apple user id) and `email`.
 *   4. Find-or-create User by `appleSub`, mint our own short-lived JWT
 *      (`HS256`, 30-day TTL) signed with `JWT_SECRET`.
 *   5. iOS stores our JWT in Keychain and sends it as `Authorization: Bearer <jwt>`
 *      on every subsequent request.
 *
 * The Apple identity token has these notable claims:
 *   - `iss`: "https://appleid.apple.com"
 *   - `aud`: your App's bundle id (e.g. "solutions.techchain.teycan.translate")
 *   - `sub`: stable, opaque user id — primary key on our side
 *   - `email`: optional; user can hide it (relayed via privaterelay.appleid.com)
 *   - `email_verified`: "true" when present
 *   - `nonce`: for replay protection (we ignore for now — a future hardening)
 */

const { createRemoteJWKSet, jwtVerify, SignJWT } = require('jose');

const APPLE_JWKS_URL = 'https://appleid.apple.com/auth/keys';
const APPLE_ISSUER = 'https://appleid.apple.com';

// Lazily-initialized — first call to `verifyAppleIdentityToken` starts fetching keys.
let _jwks;
function jwks() {
  if (!_jwks) _jwks = createRemoteJWKSet(new URL(APPLE_JWKS_URL));
  return _jwks;
}

/**
 * Verifies an Apple identityToken JWT.
 * @param {string} identityToken
 * @param {string} audience  the iOS app's bundle id (must match `aud` claim)
 * @returns {Promise<{sub: string, email?: string, emailVerified?: boolean}>}
 * @throws if verification fails
 */
async function verifyAppleIdentityToken(identityToken, audience) {
  const { payload } = await jwtVerify(identityToken, jwks(), {
    issuer: APPLE_ISSUER,
    audience,
  });
  if (typeof payload.sub !== 'string' || !payload.sub) {
    throw new Error('Apple token missing sub claim');
  }
  return {
    sub: payload.sub,
    email: typeof payload.email === 'string' ? payload.email : undefined,
    emailVerified: payload.email_verified === true || payload.email_verified === 'true',
  };
}

/**
 * Issues our app's own JWT for an authenticated user.
 * @param {{userId: string, appleSub: string}} payload
 * @param {string} secret  HS256 secret (`JWT_SECRET` env var)
 * @returns {Promise<string>}
 */
async function issueAppJWT(payload, secret) {
  const secretKey = new TextEncoder().encode(secret);
  return await new SignJWT({
    sub: payload.userId,
    appleSub: payload.appleSub,
  })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime('30d')
    .setIssuer('teycan-translate')
    .sign(secretKey);
}

/**
 * Verifies an app-issued JWT and returns the payload.
 * @param {string} token
 * @param {string} secret
 * @returns {Promise<{sub: string, appleSub: string}>}
 */
async function verifyAppJWT(token, secret) {
  const secretKey = new TextEncoder().encode(secret);
  const { payload } = await jwtVerify(token, secretKey, {
    issuer: 'teycan-translate',
  });
  if (typeof payload.sub !== 'string' || typeof payload.appleSub !== 'string') {
    throw new Error('App JWT missing required claims');
  }
  return { sub: payload.sub, appleSub: payload.appleSub };
}

module.exports = {
  verifyAppleIdentityToken,
  issueAppJWT,
  verifyAppJWT,
};
