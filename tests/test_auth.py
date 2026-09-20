import os
import time
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from relay.auth import Auth0

class JWTTests(unittest.IsolatedAsyncioTestCase):
    async def test_verifies_signature_issuer_audience_client_and_scope(self):
        key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
        with patch.dict(os.environ,{'AUTH0_ISSUER':'https://auth.example/','AUTH0_AUDIENCE':'macbridge','AUTH0_ALLOWED_CLIENT_IDS':'meta-client'}):auth=Auth0()
        auth.keys=SimpleNamespace(get_signing_key_from_jwt=lambda token:SimpleNamespace(key=key.public_key()))
        claims=dict(sub='auth0|test',iss='https://auth.example/',aud='macbridge',iat=int(time.time()),exp=int(time.time())+60,azp='meta-client',scope='macbridge:control')
        token=jwt.encode(claims,key,algorithm='RS256')
        self.assertEqual((await auth.authenticate(token)).client_id,'meta-client')
        for changes in ({'iss':'https://attacker.example/'},{'aud':'different-api'},{'azp':'other-client'},{'scope':'openid'},{'exp':0}):
            with self.assertRaises(Exception):await auth.authenticate(jwt.encode({**claims,**changes},key,algorithm='RS256'))
        wrong=rsa.generate_private_key(public_exponent=65537,key_size=2048)
        with self.assertRaises(Exception):await auth.authenticate(jwt.encode(claims,wrong,algorithm='RS256'))
