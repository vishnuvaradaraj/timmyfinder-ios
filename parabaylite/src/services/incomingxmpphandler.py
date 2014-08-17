import os
import sys
import string

import logging
import string
import uuid
import re

import services.datamodel as datamodel
import services.securityservice as securityservice

# Log a message each time this module get loaded.
logging.info('Loading %s, app version = %s',
             __name__, os.getenv('CURRENT_VERSION_ID'))

# Declare the Django version we need.
from google.appengine.dist import use_library
use_library('django', '1.0')

# Fail early if we can't import Django 1.x.  Log identifying information.
import django
logging.info('django.__file__ = %r, django.VERSION = %r',
             django.__file__, django.VERSION)
assert django.VERSION[0] >= 1, "This Django version is too old"


# Custom Django configuration.
os.environ['DJANGO_SETTINGS_MODULE'] = 'settings'
from django.conf import settings
settings._target = None

# Import various parts of Django.
import django.core.handlers.wsgi
import django.core.signals
import django.db
import django.dispatch.dispatcher
import django.forms

# Work-around to avoid warning about django.newforms in djangoforms.
django.newforms = django.forms


def log_exception(*args, **kwds):
  """Django signal handler to log an exception."""
  cls, err = sys.exc_info()[:2]
  logging.exception('Exception in request: %s: %s', cls.__name__, err)


# Log all exceptions detected by Django.
django.core.signals.got_request_exception.connect(log_exception)

# Unregister Django's default rollback event handler.
django.core.signals.got_request_exception.disconnect(
    django.db._rollback_on_exception)

#import others
import wsgiref.handlers

from google.appengine.api import xmpp
from google.appengine.ext import webapp
from google.appengine.ext.webapp.util import run_wsgi_app

class XMPPHandler(webapp.RequestHandler):
  def post(self):
    message = xmpp.Message(self.request.POST)
    
    user_address = 'vishnuv@gmail.com'
    chat_message_sent = False
    
    status_code = xmpp.send_message(user_address, 'got message')
    chat_message_sent = (status_code != xmpp.NO_ERROR)
    
    if not chat_message_sent:    
        chat = datamodel.UserChat()
        chat.sender = message.sender
        chat.receiver = message.to
        chat.body = message.body
        chat.put()
        message.reply("The user is currently offline. Your message will be delivered when the user is online.")

application = webapp.WSGIApplication([('/_ah/xmpp/message/chat/', XMPPHandler)],
                                     debug=True)

def main():
  run_wsgi_app(application)

if __name__ == "__main__":
  main()
