#!/usr/bin/python

# Code copied from http://code.google.com/appengine/articles/remote_api.html
# with minor modifications.

import code
import getpass
import os
import sys

sys.path.append("c:\progra~1\google\google_appengine")
sys.path.append("c:\progra~1\google\google_appengine\lib\yaml\lib")
sys.path.append("e:\work\parabaylite\src")

from google.appengine.ext.remote_api import remote_api_stub
from google.appengine.ext import db

def auth_func():
  return raw_input('Username:'), getpass.getpass('Password:')

if len(sys.argv) < 2:
  print "Usage: %s app_id [host]" % (sys.argv[0],)
app_id = sys.argv[1]
if len(sys.argv) > 2:
  host = sys.argv[2]
else:
  host = '%s.appspot.com' % app_id

remote_api_stub.ConfigureRemoteDatastore(app_id, '/remote_api', auth_func, host)

code.interact('App Engine interactive console for %s' % (app_id,), None, locals())

