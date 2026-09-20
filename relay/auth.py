"""Hosted Auth0 JWT verification; there is deliberately no production test-token mode."""
import os
import asyncio
from dataclasses import dataclass
import jwt
from contracts import ACTIONS

@dataclass(frozen=True)
class Principal:
    user_id: str
    client_id: str
    actions: frozenset[str]

class Auth0:
    def __init__(self):
        self.issuer = os.getenv('AUTH0_ISSUER', '')
        self.audience = os.getenv('AUTH0_AUDIENCE', '')
        self.clients = set(filter(None, os.getenv('AUTH0_ALLOWED_CLIENT_IDS', '').split(',')))
        self.keys = jwt.PyJWKClient(self.issuer.rstrip('/') + '/.well-known/jwks.json') if self.issuer.startswith('https://') else None
    async def authenticate(self, token):
        if not self.keys or not self.audience or not self.clients:
            raise ValueError('Hosted authentication is not configured')
        key = await asyncio.to_thread(self.keys.get_signing_key_from_jwt, token)
        claims = jwt.decode(token, key.key, algorithms=['RS256'], audience=self.audience, issuer=self.issuer, options={'require':['exp','iat','sub','iss','aud']})
        client = claims.get('azp', '')
        if client not in self.clients:
            raise ValueError('OAuth client is not admitted')
        if 'macbridge:control' not in claims.get('scope', '').split():
            raise ValueError('Missing macbridge:control scope')
        return Principal(claims['sub'], client, frozenset(a['name'] for a in ACTIONS))
