"""Build public operation descriptions from the canonical schemas and actual routes."""
from copy import deepcopy
import os
from contracts import SCHEMA

def public_spec(app):
    from fastapi.openapi.utils import get_openapi
    spec=get_openapi(title=app.title,version=app.version,routes=app.routes)
    def refs(value):
        if isinstance(value,dict):return {k:(v.replace('#/$defs/','#/components/schemas/') if k=='$ref' else refs(v)) for k,v in value.items()}
        if isinstance(value,list):return [refs(v) for v in value]
        return value
    spec['components']={'schemas':refs(deepcopy(SCHEMA['$defs'])),'securitySchemes':{'userOAuth':{'type':'oauth2','flows':{'authorizationCode':{'authorizationUrl':'https://YOUR_AUTH0_DOMAIN/authorize','tokenUrl':'https://YOUR_AUTH0_DOMAIN/oauth/token','scopes':{'macbridge:control':'Control linked devices'}}}},'deviceBootstrap':{'type':'http','scheme':'bearer'}}}
    models={
      ('/v1/devices','get'):(None,'DeviceList',200),
      ('/v1/devices/{did}','patch'):('RenameDeviceRequest','Device',200),
      ('/v1/devices/{did}','delete'):(None,'RevocationResponse',200),
      ('/v1/account','delete'):(None,'AccountDeletionResponse',200),
      ('/v1/pairing/code','post'):('PairingCodeRequest','PairingCodeResponse',200),
      ('/v1/pairing/preview','post'):('PairingClaimRequest','PairingPreviewResponse',200),
      ('/v1/pairing/claim','post'):('PairingClaimRequest','PairingClaimResponse',200),
      ('/v1/pairing/cancel','post'):('PairingCancelRequest','PairingCancelResponse',200),
      ('/v1/pairing/redeem','post'):('PairingRedeemRequest','PairingRedeemResponse',200),
      ('/v1/commands','post'):('CommandRequest','CommandAccepted',202),
      ('/v1/commands/{cid}','get'):(None,'CommandStatus',200),
      ('/healthz','get'):(None,'HealthResponse',200),
    }
    def content(model):return {'application/json':{'schema':{'$ref':'#/components/schemas/'+model}}}
    for (path,method),(request,response,status) in models.items():
        op=spec['paths'][path][method]
        op['security']=[] if path in ('/healthz','/v1/pairing/code') else [{'deviceBootstrap':[]}] if path.endswith(('/redeem','/cancel')) else [{'userOAuth':['macbridge:control']}]
        op['responses']={str(status):{'description':'Success','content':content(response)}}
        for error in (400,401,403,404,409,410,422,429,500):op['responses'][str(error)]={'description':'Actionable error code','content':content('ErrorResponse')}
        if request:op['requestBody']={'required':True,'content':content(request)}
    spec['paths']={k:v for k,v in spec['paths'].items() if any(k==p for p,m in models)}
    spec['servers']=[{'url':'https://YOUR_RELAY_DOMAIN','description':'Replace with the deployed HTTPS origin'}]
    issuer=os.getenv('AUTH0_ISSUER','https://YOUR_AUTH0_DOMAIN/').rstrip('/')
    flow=spec['components']['securitySchemes']['userOAuth']['flows']['authorizationCode']
    flow['authorizationUrl']=issuer+'/authorize';flow['tokenUrl']=issuer+'/oauth/token'
    spec['servers'][0]['url']=os.getenv('PUBLIC_RELAY_ORIGIN','https://YOUR_RELAY_DOMAIN')
    return spec
