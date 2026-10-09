#!/usr/bin/env python3
"""Add only the Babytrack route to the existing local Caddy configuration."""
import json
import urllib.request
import urllib.error
base='http://127.0.0.1:2019'
path='/config/apps/http/servers/srv0/routes'
route={'@id':'babytrack-backend','match':[{'host':['devapps.thezoo.house'],'path':['/babytrack-api/*']}],'handle':[{'handler':'rewrite','strip_path_prefix':'/babytrack-api'},{'handler':'reverse_proxy','upstreams':[{'dial':'127.0.0.1:8792'}]}],'terminal':True}
for attempt in range(3):
 with urllib.request.urlopen(base+path,timeout=5) as response:
  routes=json.load(response);etag=response.headers['Etag']
 if any(r.get('@id')=='babytrack-backend' for r in routes): print('Babytrack proxy already registered');break
 request=urllib.request.Request(base+path+'/0',data=json.dumps(route).encode(),headers={'Content-Type':'application/json','If-Match':etag},method='PUT')
 try:
  with urllib.request.urlopen(request,timeout=10) as response: print('Babytrack HTTPS proxy registered')
  break
 except urllib.error.HTTPError as error:
  if error.code!=412 or attempt==2: raise
