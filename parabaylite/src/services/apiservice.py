#!/usr/bin/env python

__author__ = 'Vishnu Varadaraj'

import datetime
import time
import os
import random
import string
import sys
import logging
import traceback

from services import constants, echoservice, shellservice, metadataservice, dataservice, securityservice, utils, datamodel, transformservice, requestcontext, appservice, dataloader, geohash
import services.schemaloader as schemaloader

from google.appengine.ext import db
from google.appengine.ext.db import djangoforms
from google.appengine.ext.webapp import template
from google.appengine.api import memcache
from google.appengine.api.labs import taskqueue

import django
from django import http
from django import shortcuts
from django.http import HttpResponseRedirect, HttpResponse, HttpRequest

import json
import simplejson

_DEBUG = os.environ['SERVER_SOFTWARE'].startswith('Dev')  # Development server
        
def login_required(func):
  """Decorator that redirects to the login page if you're not logged in."""

  def login_wrapper(request, app, *args, **kwds):
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token   = get_request_value(request, 'token')
        if token and app:
            
            req = requestcontext.create_request(token, app)            
            if not req.has_perm([securityservice.READ_PERMISSION]):
                ret['status']   = constants.STATUS_ACCESS_DENIED    
            else:
                request.req = req
                return func(request, app, *args, **kwds)
            
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
    
    return HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")

  return login_wrapper


def admin_required(func):
  """Decorator that insists that you're logged in as administratior."""

  def admin_wrapper(request, app, *args, **kwds):
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token   = get_request_value(request, 'token')
        if token and app:
            
            req = requestcontext.create_request(token, app)            
            if not req.has_perm([securityservice.WRITE_PERMISSION]):
                ret['status']   = constants.STATUS_ACCESS_DENIED    
            else:
                request.req = req
                return func(request, app, *args, **kwds)
            
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
    
    return HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")

  return admin_wrapper

def su_required(func):
  """Decorator that insists that you're logged in as administratior."""

  def su_wrapper(request, *args, **kwds):
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token   = get_request_value(request, 'token')
        if token:
            user   = securityservice.SecurityService.authenticate_user_token(token)
            if not user.is_superuser:
                ret['status']   = constants.STATUS_ACCESS_DENIED    
            else:
                return func(request, *args, **kwds)
            
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
    
    return HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")

  return su_wrapper

#http://localhost:8080/api/login?username=vishnuv&password=sa1985
def login(request):
    logging.info('login')
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM
    
    try:
        username = get_request_value(request, 'username') 
        password = get_request_value(request, 'password')
    
        logging.info('Logging in: %s' % username)
        
        token = None
        
        if username and password:
            ret['status']       = constants.STATUS_ERROR
            
            user    = securityservice.SecurityService.authenticate_user(username, password)
    
            if user:
                token   = securityservice.SecurityService.generate_user_token(user)
            
                ret                 = {}
                
                ret['name']         = user.name
                ret['email']        = user.email
                ret['token']        = token
                ret['status']       = constants.STATUS_OK
    
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
        
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain") 

    if token:
        utils.set_cookie(response, 'token', token)

    return response

#http://localhost:8080/api/logout?token=
def logout(request):
    logging.info('logout')
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token       = get_request_value(request, 'token')

        if token:
            securityservice.SecurityService.logoff_user_token(token)
        
            ret['status']   = constants.STATUS_OK

    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
    
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")
    utils.set_cookie(response, 'token', '')

    return response

#http://localhost:8080/api/register_user?user={"password":%20"mon","name":%20"varadarajan",%20"first_name":%20"Varadarajan",%20"last_name":%20"Raghavan",%20"phone":%20"011-91-470-2601633",%20"email":%20"varadarajan@gmail.com"}&app=ParabayOrg-Outlook
def register_user(request):
    "register a new user"
    
    logging.info('register user')
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        user    = get_request_value(request, 'user') 
        app     = get_request_value(request, 'app', None)
        
        if user:
            user = simplejson.JSONDecoder().decode(user);
            
            ret['status']   = constants.STATUS_ERROR
            u = securityservice.SecurityService.register_user(user, app)
            if u:
                ret['name']         = u.name
                ret['email']        = u.email
                ret['token']        = securityservice.SecurityService.generate_user_token(u)
            
                ret['status']   = constants.STATUS_OK
            else:
                ret['status']   = constants.STATUS_EXISTING_USER;
      
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
              
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")
    return response

def check_user_exists(request):
    "check if a user is already registered"
    
    logging.info('check_user_exists')
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        email     = get_request_value(request, 'email', None)
    
        if email:
            ret['status']   = constants.STATUS_ERROR
            res = securityservice.SecurityService.check_user_exists(email)
            if res:
                ret['status']   = constants.STATUS_OK
   
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())

    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")
    return response

def forgot_password(request):
    "User forgot password"
    
    logging.info('forgot_password')
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        email     = get_request_value(request, 'email', None)
    
        if email:
            ret['status']   = constants.STATUS_ERROR
            res = securityservice.SecurityService.forgot_password(email)
            if res:
                ret['status']   = constants.STATUS_OK
          
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
          
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")
    return response

def resend_activation(request):
    "Resend activation email"
    
    logging.info('resend_activation')
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        email     = get_request_value(request, 'email', None)
    
        if email:
                ret['status']   = constants.STATUS_ERROR
                res = securityservice.SecurityService.resend_activation(email)
                if res:
                    ret['status']   = constants.STATUS_OK
                
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)                
        logging.error(traceback.format_exc())
            
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")
    return response

def activate_user(request):
    "active user account"
    
    logging.info('activate_user')
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        code     = get_request_value(request, 'code')
    
        if code:
            ret['status']   = constants.STATUS_ERROR
            res = securityservice.SecurityService.activate_user(code)
            if res:
                ret['status']   = constants.STATUS_OK
       
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
                    
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")
    return response

def delete_user(token):
    "Delete user account"
    
    logging.info('delete_user')
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token     = get_request_value(request, 'token')
    
        if token:
            ret['status']   = constants.STATUS_ERROR
            req = requestcontext.create_request(token)
            res = securityservice.SecurityService.delete_user(req.user)
            if res:
                ret['status']   = constants.STATUS_OK
            
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
                    
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")
    return response
    
#http://localhost:8080/api/validate_user_token?token=
def validate_user_token(request):
    "validate user account"
    
    logging.info('validate_user_token')
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token       = get_request_value(request, 'token')
        app         = get_request_value(request, 'app', None)
    
        if token:
            ret['status']       = constants.STATUS_ERROR
            
            req                 = requestcontext.create_request(token, app)   
            if req.user:                    
                u                   = {}
                u['name']           = req.user.name
                u['first_name']     = req.user.first_name
                u['last_name']      = req.user.last_name
                u['email']          = req.user.email
                u['phone']          = req.user.phone
                
                ret['user']         = u
                ret['status']       = constants.STATUS_OK   
            
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
                 
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")
    return response

#http://localhost:8080/api/list/ParabayOrg-Outlook?query={"columns":%20[],%20"kind":%20"Calendar_Appointment",%20"filters":%20[{"condition":"StartDate >", "param":"26/07/2009","type":"date"}],%20"orders":%20["StartDate", "StartTime"]}
#http://localhost:8080/api/list/ParabayOrg-Outlook?query={"columns":%20[],%20"kind":%20"Calendar_Appointment",%20"filters":%20[ {"condition":"updated > ","param":"2009-09-02T00:53:41.948000","type":"timestamp"}],%20"orders":%20[]}
#http://localhost:8080/api/list/ParabayOrg-Outlook?query={"columns":%20[],%20"kind":%20"Timmy_Store",%20"filters":%20[],%20"orders":%20[]}
#Query: search_query, kind, columns, filters, orders, data_query,data_query_params
#http://192.168.0.103:8080/api/list/ParabayOrg-Outlook?query={"columns":%20[],%20"kind":%20"Timmy_Store",%20"filters":%20[{"condition":"bookmark > ","param":"","type":"string"}],%20"orders":%20[]}
def list_data(request, app):
    '''List the data'''
    
    logging.info('list data')

    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token   = get_request_value(request, 'token')
        query   = get_request_value(request, 'query')
        bookmark   = get_request_value(request, 'bookmark')
        limit   = get_request_value(request, 'limit', "10")
        offset  = get_request_value(request, 'offset', "0")
        
        if token and app and query:
            
            req = requestcontext.create_request(token, app)            
            if not req.has_perm([securityservice.READ_PERMISSION]):
                ret['status']   = constants.STATUS_ACCESS_DENIED
                
            else:
                ret['data']     = []
                ret['count']    = 0
                #ret['sync_token'] = datetime.datetime.now()
                q       = simplejson.JSONDecoder().decode(query)
                result  = dataservice.DataService.list(req, q, int(limit), int(offset), bookmark)
                data    = transformservice.normalize_results(req, result['data'], q['kind'])

                ret['status']   = constants.STATUS_OK
                
                if data and len(data)>0:
                    logging.info('Got valid list results...')
                    ret['count']    = result['count']                    
                    ret['data']     = data
                    ret['sync_token'] = result['sync_token']
                    #logging.info(ret)
                    
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
    
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")

    return response

#http://localhost:8080/api/get/ParabayOrg-Outlook/Calendar_Appointment/k023ecb40-be25-11dd-b96c-63515cb8edc7?token=Uyd0b2tfODkxZTIwMjU0OTBmYzhlNDRlZTBjMzIyZDI0MzM1OGEnCnAwCi5hNDJiMmY4ZjdlMmUwMzBiNDUzMzc0M2JiM2EyZTU1Yw%3D%3D
def get_data(request, app, datatype, datakey):
    '''Get data'''
    
    logging.info('get data')

    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token       = get_request_value(request, 'token')
        
        if token and app and datakey and datatype:
            req = requestcontext.create_request(token, app)
            if not req.has_perm([securityservice.READ_PERMISSION]):
                ret['status']   = constants.STATUS_ACCESS_DENIED
            
            else:
                result = dataservice.DataService.get(req, datakey, datatype)
                    
                if result:
                    ret['data']     = transformservice.transform(req, result, datatype)
                    ret['status']   = constants.STATUS_OK
        else:
             logging.info('Not getting data')           
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
        
    logging.info('Return status = ' + str(ret['status']))
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")

    return response

#http://localhost:8080/api/save/ParabayOrg-Outlook/Calendar_Appointment?token=Uyd0b2tfODkxZTIwMjU0OTBmYzhlNDRlZTBjMzIyZDI0MzM1OGEnCnAwCi5hNDJiMmY4ZjdlMmUwMzBiNDUzMzc0M2JiM2EyZTU1Yw%3D%3D&data={"MeetingOrganizer":%20"Varadaraj,%20Vishnu2",%20"Subject":%20"Subaru%20Forrester%20appt2."}
def save_data(request, app, datatype):
    '''Save data'''
    logging.info('save data')

    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token       = get_request_value(request, 'token')
        data        = get_request_value(request, 'data')
    
        if token and app and data and datatype:
            req = requestcontext.create_request(token, app)
            if not req.has_perm([securityservice.WRITE_PERMISSION]):
                ret['status']   = constants.STATUS_ACCESS_DENIED
            
            else:
                data    = simplejson.JSONDecoder().decode(data)
                data    = transformservice.reverse_transform(req, data, datatype)
                
                result  = dataservice.DataService.save(req, data, datatype)
                if result:
                    ret['id']         = str(result.key().name())
                    ret['status']   = constants.STATUS_OK
                    
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
            
    logging.info('Return status = ' + str(ret['status']))
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")

    return response

#http://localhost:8080/api/savearray/ParabayOrg-Outlook/Calendar_Appointment?data=[{"MeetingOrganizer":%20"Varadaraj,%20Vishnu2",%20"Subject":%20"Subaru%20Forrester%20appt2."}]
def save_data_array(request, app, datatype):
    '''Save data'''
    logging.info('save data array')

    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token       = get_request_value(request, 'token')
        data        = get_request_value(request, 'data')
    
        if token and app and data and datatype:
            req = requestcontext.create_request(token, app)
            if not req.has_perm([securityservice.WRITE_PERMISSION]):
                ret['status']   = constants.STATUS_ACCESS_DENIED
            
            else:
                data    = simplejson.JSONDecoder().decode(data)
                data    = transformservice.denormalize_results(req, data, datatype)
                
                save_status = {}
                for item in data:
                    save_status[item.key().name()] = False
                    result = dataservice.DataService.save(req, item, datatype)
                    if result:
                        save_status[item.key().name()] = True
                    
                ret['save_status']  = save_status
                ret['status']       = constants.STATUS_OK
                    
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
            
    logging.info('Return status = ' + str(ret['status']))
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")

    return response


#http://localhost:8080/api/delete/ParabayOrg-Outlook/Calendar_Appointment/k023ecb40-be25-11dd-b96c-63515cb8edc7?token=Uyd0b2tfODkxZTIwMjU0OTBmYzhlNDRlZTBjMzIyZDI0MzM1OGEnCnAwCi5hNDJiMmY4ZjdlMmUwMzBiNDUzMzc0M2JiM2EyZTU1Yw%3D%3D    
def delete_data(request, app, datatype, datakey):
    '''Delete data'''
    
    logging.info('delete data')

    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    token       = get_request_value(request, 'token')
    
    try:
        if token and app and datakey and datatype:
            req = requestcontext.create_request(token, app)
            if not req.has_perm([securityservice.WRITE_PERMISSION]):
                ret['status']   = constants.STATUS_ACCESS_DENIED
            
            else:
                ret['status']   = constants.STATUS_ERROR
                if dataservice.DataService.delete(req, datakey, datatype):
                    ret['status']   = constants.STATUS_OK
                    
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
        
    logging.info('Return status = ' + str(ret['status']))
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")

    return response

def get_metadata_list_helper(request, app, method, normalize_method="normalize_metadata_results"):
    logging.info('get_type_infos')
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        names       = get_request_value(request, 'names')
        token       = get_request_value(request, 'token')
        
        if token and app:
            ret['status']   = constants.STATUS_ERROR
            
            names   = simplejson.JSONDecoder().decode(names)
            req     = requestcontext.create_request(token, app)
            data    = getattr(appservice.AppService, method)(req, names)
            ret['data' ]    = getattr(transformservice, normalize_method)(req, data)
            
            ret['status']   = constants.STATUS_OK
            
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
            
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain") 
    return response

#http://localhost:8080/api/type_infos/ParabayOrg-Outlook?token=Uyd0b2tfODkxZTIwMjU0OTBmYzhlNDRlZTBjMzIyZDI0MzM1OGEnCnAwCi5hNDJiMmY4ZjdlMmUwMzBiNDUzMzc0M2JiM2EyZTU1Yw%3D%3D&names=loo
def get_type_infos(request, app):
    return get_metadata_list_helper(request, app, "get_type_infos")

#http://localhost:8080/api/entity_metadatas/ParabayOrg-Outlook?token=Uyd0b2tfODkxZTIwMjU0OTBmYzhlNDRlZTBjMzIyZDI0MzM1OGEnCnAwCi5hNDJiMmY4ZjdlMmUwMzBiNDUzMzc0M2JiM2EyZTU1Yw%3D%3D&names=["Contacts_Contact"]
def get_entity_metadatas(request, app):
    return get_metadata_list_helper(request, app, "get_entity_metadatas", "normalize_em_results")

#http://localhost:8080/api/enumerations/ParabayOrg-Outlook?token=Uyd0b2tfODkxZTIwMjU0OTBmYzhlNDRlZTBjMzIyZDI0MzM1OGEnCnAwCi5hNDJiMmY4ZjdlMmUwMzBiNDUzMzc0M2JiM2EyZTU1Yw%3D%3D&names=["Countries"]
def get_enumerations(request, app):
    return get_metadata_list_helper(request, app, "get_enumerations", "normalize_enum_results")

def get_l10n_content(request, app):
    return get_metadata_list_helper(request, app, "get_l10n_content")

def get_relations(request, app):
    return get_metadata_list_helper(request, app, "get_relations")

#http://localhost:8080/api/view_defs/ParabayOrg-Outlook?token=Uyd0b2tfODkxZTIwMjU0OTBmYzhlNDRlZTBjMzIyZDI0MzM1OGEnCnAwCi5hNDJiMmY4ZjdlMmUwMzBiNDUzMzc0M2JiM2EyZTU1Yw%3D%3D&names=["oo"]
def get_view_defs(request, app):
    return get_metadata_list_helper(request, app, "get_view_defs")    

#http://localhost:8080/api/view_maps/ParabayOrg-Outlook?token=Uyd0b2tfODkxZTIwMjU0OTBmYzhlNDRlZTBjMzIyZDI0MzM1OGEnCnAwCi5hNDJiMmY4ZjdlMmUwMzBiNDUzMzc0M2JiM2EyZTU1Yw%3D%3D
def get_view_maps(request, app):
    return get_metadata_list_helper(request, app, "get_view_maps")   

#http://localhost:8080/api/root_view_maps/ParabayOrg-Outlook
def get_root_view_maps(request, app):
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token       = get_request_value(request, 'token')
        limit   = get_request_value(request, 'limit', "32")
        offset  = get_request_value(request, 'offset', "0")
        
        if token and app:
            ret['status']   = constants.STATUS_ERROR
            req = requestcontext.create_request(token, app)
            
            root_view_maps = appservice.AppService.get_root_view_maps(req, int(limit), int(offset))
            result = transformservice.normalize_metadata_results(req, root_view_maps)
            ret['data' ] = result
            ret['status']   = constants.STATUS_OK

    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
                
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain") 
    return response

def synchronize_metadata(request, app):
    logging.info('synchronize_metadata')
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:       
        token       = get_request_value(request, 'token')
        
        if token and app:
            ret['status']   = constants.STATUS_ERROR
            
            req = requestcontext.create_request(token, app)
            metadataservice.synchronizeMetadata(req)
        
            ret['status']   = constants.STATUS_OK
    
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
            
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")
    return response

#http://localhost:8080/api/l10n/ParabayOrg-Outlook/Tasks_Tasks
def get_l10n_data(request, app, page):
    logging.info('get_l10n_data')
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token       = get_request_value(request, 'token')
        lang        = get_request_value(request, 'lang')
        limit       = get_request_value(request, 'limit', "128")
        offset      = get_request_value(request, 'offset', "0")
    
        if token and app:
            ret['status']   = constants.STATUS_ERROR
            
            req             = requestcontext.create_request(token, app)
            l10n_results    = appservice.AppService.find_l10n_for_page(req, page, lang, int(offset), int(limit))
            ret['data' ]    = transformservice.normalize_l10n_results(req, l10n_results)
            
            ret['status']   = constants.STATUS_OK
    
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())        
        
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain") 
    return response

#http://localhost:8080/api/page_metadata/ParabayOrg-Outlook/Tasks_Tasks
def get_page_metadata(request, app, page):
    logging.info('get_page_metadata')
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token       = get_request_value(request, 'token')
        lang        = get_request_value(request, 'locale', '')
            
        if token and app:
            ret['status']   = constants.STATUS_ERROR
            
            page_metadata   = None
            
            req = requestcontext.create_request(token, app)
            if not req.has_perm([securityservice.READ_PERMISSION]):
                ret['status']   = constants.STATUS_ACCESS_DENIED
            else:
                
                cache_key       = [app, page, lang]
                page_metadata   = utils.check_memcache(cache_key)
                
                if not page_metadata:
                    page_metadata = {}
                    view_map                            = metadataservice.find_view_map(req, page)
                    page_metadata['view_map']           = transformservice.transform_metadata(view_map)
                    view_def                            = view_map.view_definition
                    #logging.info(view_def.mobile_layout)
                    page_metadata['view_definition']    = transformservice.transform_metadata(view_def)
                    dataquery_names                     = view_def.data_queries
                    logging.info(dataquery_names)
                    if not dataquery_names is None:
                        dataquery_names                     = simplejson.JSONDecoder().decode(dataquery_names)
                        data_queries                        = [ metadataservice.find_data_query(req, name) for name in dataquery_names ]
                        page_metadata['data_queries']       = transformservice.normalize_metadata_results(req, data_queries) 
                    #root_view_maps                      = appservice.AppService.get_root_view_maps(req, 8, 0)
                    #page_metadata['root_view_maps']     = transformservice.normalize_metadata_results(req, root_view_maps)
                    if lang != '':
                        l10n_results                    = appservice.AppService.find_l10n_for_page(req, page, lang)
                        page_metadata['l10n']           = transformservice.normalize_l10n_results(req, l10n_results)
                
                    utils.set_memcache(cache_key, page_metadata)
                
            ret["page_metadata"] = page_metadata           
            ret['status']   = constants.STATUS_OK
    
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
        
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")
    return response

#http://localhost:8080/api/dataquery_metadata/ParabayOrg-Outlook/Tasks_Tasks_List
@admin_required
def get_dataquery_metadata(request, app, dataquery):
    logging.info('get_dataquery_metadata')
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    if request.req:
        ret['status']   = constants.STATUS_ERROR
        
        req = request.req
        dataquery_metadata = None
        
        cache_key       = [app, dataquery]
        dataquery_metadata   = utils.check_memcache(cache_key)
        
        if not dataquery_metadata:
            dataquery_metadata = {}
            data_query                              = metadataservice.find_data_query(req, dataquery)
            logging.info(data_query.type_of)
            dataquery_metadata['data_query']        = transformservice.transform_metadata(data_query)
            entity_metadata                         = metadataservice.find_entity_metadata(req, data_query.type_of)
            dataquery_metadata['entity_metadatas']  = transformservice.normalize_em_results(req, [entity_metadata])
            enumerations                            = metadataservice.find_enumerations_for_entity_metadata(req, entity_metadata)
            dataquery_metadata['enumerations']      = transformservice.normalize_enum_results(req, enumerations)
            typeinfos                               = metadataservice.find_typeinfos_for_entity_metadata(req, entity_metadata)
            dataquery_metadata['type_infos']        = transformservice.normalize_typeinfo_results(req, typeinfos)
            entity_relations                        = metadataservice.find_relations_for_entity_metadata(req, entity_metadata)
            dataquery_metadata['entity_relations']  = transformservice.normalize_metadata_results(req, entity_relations)
            utils.set_memcache(cache_key, dataquery_metadata)
            
        ret["dataquery_metadata"] = dataquery_metadata     
        ret['status']   = constants.STATUS_OK
    
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")
    return response

#http://localhost:8080/api/generate_default_views/ParabayOrg-Outlook
def generate_default_views(request, app):
    logging.info('generate default views')
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token       = get_request_value(request, 'token')
        overwrite      = get_request_value(request, 'overwrite')
        
        if token:
            ret['status']   = constants.STATUS_ERROR
            
            req = requestcontext.create_request(token, app)

            if overwrite:
                overwrite = True
            else:
                overwrite = False
              
            metadataservice.generate_default_views(req, overwrite)
            ret['status']       = constants.STATUS_OK
    
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
        
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")

    return response

#http://parabaydata.appspot.com/api/erase_all_data
def erase_all_data(request):
    logging.info('delete everything')
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        metadatas = datamodel.Metadata.all().fetch(100)
        for m in metadatas:
            metadata_name = m.name
            entity_metadatas = m.entitymetadata_set
            for em in entity_metadatas:
                metadata_class = utils.loadModuleType(metadata_name, em.name)
                utils.delete_all_entities(metadata_class)
            
        schemaloader.AppImporterAndLoader.deleteAllRecords()     
        ret['status']       = constants.STATUS_OK
    
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
        
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")

    return response

#http://localhost:8080/api/import_data/ParabayOrg-Outlook?kind=Tasks_Task&csv=test,pri
def import_data(request, app):
    logging.info('Import data')
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token       = get_request_value(request, 'token')
        kind        = get_request_value(request, 'kind')
        csv         = get_request_value(request, 'csv')
        
        if token and app and csv:
            ret['status']   = constants.STATUS_ERROR
            
            req = requestcontext.create_request(token, app)
            
            if not req.has_perm([securityservice.READ_PERMISSION]):
                logging.error('Data upload failed - Access denied')
                ret['status']   = constants.STATUS_ACCESS_DENIED
            else:
                #taskqueue.add(url='/worker', params={'key': key})
                data_importer = dataloader.DataImporter(req, kind)
                data_importer.import_data(csv)
            
            ret['status']       = constants.STATUS_OK
        else:
            logging.error('Invalid parameter')
            
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
        
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")

    return response

#cron job
def cron_erase_data(request, app, datatype):
    logging.info('Cron erase data- not just marking data for deletion')
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM
   
    try:   
        #logging.info(repr(request.META)) hasattr(request.META, 'HTTP_X_APPENGINE_CRON') and 
        if app and datatype:
            ret['status']   = constants.STATUS_ERROR
            
            dataservice.DataService.cron_erase(app, datatype, 50)            
            ret['status']       = constants.STATUS_OK
        else:
            logging.info('Missing cron header')
            
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
        
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")

    return response

#http://localhost:8080/api/bulk_erase/ParabayOrg-Outlook/Calendar_Appointment?delete=["1"]
def bulk_erase_data(request, app, datatype):
    logging.info('Bulk erase data- not just marking data for deletion')
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token       = get_request_value(request, 'token')
        ids         = get_request_value(request, 'delete')
        
        if token and app and datatype and ids:
            ret['status']   = constants.STATUS_ERROR
            
            req = requestcontext.create_request(token, app)
            if not req.has_perm([securityservice.READ_PERMISSION]):
                ret['status']   = constants.STATUS_ACCESS_DENIED
            else:
                id_list             = simplejson.JSONDecoder().decode(ids)
                dataservice.DataService.bulk_erase(req, datatype, id_list)            
                ret['status']       = constants.STATUS_OK
    
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
        
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")

    return response

#http://localhost:8080/api/flush_cache
#@su_required
def flush_cache(request):
    logging.info('flush_cache')
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:

        token       = get_request_value(request, 'token')
        if token:
            memcache.flush_all()
        
            ret['status']   = constants.STATUS_OK

    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
    
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")
    return response

#http://localhost:8080/api/settings/ParabayOrg-Outlook
def client_settings(request, app):
    logging.info('client_settings')
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:

        token       = get_request_value(request, 'token')
        client      = get_request_value(request, 'client')
        outlook     = get_request_value(request, 'outlook')
        version     = get_request_value(request, 'version', '1.0.0.2')
        
        logging.info(outlook)
        
        if token:
            req = requestcontext.create_request(token, app)
            if req.user:
                ret['outlook_client_version']  = '1.0.0.2'
                ret['outlook_client_update_url']  = ''
                if version != ret['outlook_client_version']:
                    ret['outlook_client_update_url']  = 'http://parabayweb.appspot.com/app/OutlookSyncAddIn.dll'
                ret['min_sync_interval'] = 10
                ret['max_sync_items'] = 50
                ret['sync_items'] = 255
                ret['server_busy_delay'] = 0
                ret['status']   = constants.STATUS_OK

    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
    
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")
    return response    

def image_result(img):
    ret = {}
    ret['Url'] = img.url
    ret['FileFormat'] = img.fileType
    ret['FileSize'] = img.fileSize
    if img.height>0 and img.width>0:
        ret['Height'] = img.height
        ret['Width'] = img.width
    if img.thumbnail:
        thumb = {}
        thumb['Url'] = img.thumbnail
        ret['Thumbnail'] = thumb
    return ret
    
#http://localhost:8080/api/files/ParabayOrg-Outlook
#http://192.168.0.103:8080/api/files/ParabayOrg-Outlook?query={"kind":"UploadedFiles","include_deleted_items":true,"orders":[],"columns":[],"filters":[{"condition":"updated >=","param":"2009-12-10T16:52:26.821978","type":"timestamp"}]}
def list_files(request, app):
    '''List the images'''
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token   = get_request_value(request, 'token')
        query   = get_request_value(request, 'query', '{"columns":[],"kind":"UploadedFile","filters":[],"orders":[]}')
        limit   = int(get_request_value(request, 'limit', "10"))
        offset  = int(get_request_value(request, 'offset', "0"))
        
        if token and app:
            
            req = requestcontext.create_request(token, app)            
            if not req.has_perm([securityservice.READ_PERMISSION]):
                ret['status']   = constants.STATUS_ACCESS_DENIED
                
            else:
                rs = {}
                rs['firstResultPosition'] = offset
        
                logging.info(query)
                q = simplejson.JSONDecoder().decode(query)
                gq = utils.build_query_for_class(datamodel.UploadedFile, q)                    
                
                data = gq.fetch(limit+1)
                if len(data) == limit+1:
                    next = data[-1].bookmark
                    data = data[:limit]
                else:
                    next = ''

                rs['totalResultsAvailable'] = gq.count()
                rs['Result'] = [image_result(f) for f in data] 
                ret['ResultSet']     = rs

                ret['sync_token'] = next
                ret['status']   = constants.STATUS_OK
                   
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
    
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")
    return response
    
#http://localhost:8080/api/push_notification/ParabayOrg-Outlook?receiver=vishnuv&message=test&badge=2
def push_notification(request, app):
    logging.info('Push notification')
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token       = get_request_value(request, 'token')
        receiver    = get_request_value(request, 'receiver')
        message     = get_request_value(request, 'message')
        badge       = get_request_value(request, 'badge', '0')
        schedule    = get_request_value(request, 'schedule')
        
        if token and app and receiver and message:
            ret['status']   = constants.STATUS_ERROR
            
            req = requestcontext.create_request(token, app)
            
            if not req.has_perm([securityservice.READ_PERMISSION]):
                ret['status']   = constants.STATUS_ACCESS_DENIED
            else:
                if req.user.device and req.user.device.device_token:
                    utils.send_push_notification(req.user.device.device_token, message, int(badge), schedule)
                    ret['status']       = constants.STATUS_OK
        else:
            logging.error('Invalid parameter')
            
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
        
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")

    return response

#http://localhost:8080/api/register_iphone/ParabayOrg-Outlook?devicetoken= f739e47a9de323321c685804d6bfdbfe343b4deb999e27cbb9b9c6cc9e0402cb 
def register_iphone(request, app):
    logging.info('Register iPhone')
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token           = get_request_value(request, 'token')
        devicetoken     = get_request_value(request, 'devicetoken')
        app_version     = get_request_value(request, 'app_version', '')
        metadata_version     = get_request_value(request, 'metadata_version', '')
        device      = get_request_value(request, 'device')
        longitude   = get_request_value(request, 'longitude')
        latitude    = get_request_value(request, 'latitude')
        photo    = get_request_value(request, 'photo')
        
        if token and app:
            ret['status']   = constants.STATUS_ERROR
            
            req = requestcontext.create_request(token, app)
            
            if not req.has_perm([securityservice.READ_PERMISSION]):
                ret['status']   = constants.STATUS_ACCESS_DENIED
            else:
                user = securityservice.SecurityService.userid_to_user(req.user.name)
                if photo:
                    user.photo = photo

                if longitude and latitude:
                    location = datamodel.UserLocation()
                    location.longitude = float(longitude)
                    location.latitude = float(latitude)
                    hash = str(geohash.Geohash((float(longitude),float(latitude))))
                    location.bbhash1 = hash[:2]
                    location.bbhash2 = hash[:4]
                    location.bbhash = hash
                    location.owner = req.user.name
                    location.updated = datetime.datetime.now()
                    location.put()
                    user.location = location
                    
                if devicetoken:
                    device_rec = datamodel.UserDevice.get_or_insert(devicetoken)
                    device_rec.device_token = devicetoken
                    device_rec.app_version = app_version
                    device_rec.metadata_version = metadata_version
                    device_rec.owner = req.user.name
                    device_rec.put()
                    user.device = device_rec

                user.put()
                user.set_dirty(True)
                user.update_cache_if_dirty()                            
                    
                ret['status']       = constants.STATUS_OK
        else:
            logging.error('Invalid parameter')
            
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
            
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")

    return response

#http://localhost:8080/api/submit_feedback/ParabayOrg-Outlook?message=good&typeof=Comments
def submit_feedback(request, app):
    logging.info('Submit user feedback')
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token       = get_request_value(request, 'token')
        typeof      = get_request_value(request, 'typeof', 'Comments')
        message     = get_request_value(request, 'message', None)
        
        if token and app and message:
            ret['status']   = constants.STATUS_ERROR
            
            req = requestcontext.create_request(token, app)
            
            if not req.has_perm([securityservice.READ_PERMISSION]):
                ret['status']   = constants.STATUS_ACCESS_DENIED
            else:
                feedback = datamodel.UserFeedback()
                feedback.typeof = typeof
                feedback.message = message
                feedback.owner = req.user.name
                feedback.put()
                ret['status']       = constants.STATUS_OK
        else:
            logging.error('Invalid parameter')
            
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
        
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")

    return response

def user_location_result(location):
    ret = {}
    ret['longitude'] = location.longitude
    ret['latitude'] = location.latitude
    ret['address'] = location.address
    if location.owner:
        user = securityservice.SecurityService.userid_to_user(location.owner)
        ret['user'] = user.name
        ret['chat_id'] = user.chat_id
    return ret

#http://localhost:8080/api/locate_users/ParabayOrg-Outlook
def locate_users(request, app):
    '''List the images'''
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token   = get_request_value(request, 'token')
        radius   = int(get_request_value(request, 'radius', "0"))
        limit   = int(get_request_value(request, 'limit', "10"))
        offset  = int(get_request_value(request, 'offset', "0"))
        
        if token and app:
            
            req = requestcontext.create_request(token, app)            
            if not req.has_perm([securityservice.READ_PERMISSION]):
                ret['status']   = constants.STATUS_ACCESS_DENIED
                
            else:
                rs = {}
                rs['firstResultPosition'] = offset
                
                gq = datamodel.UserLocation.all()              
                if radius <= 2:
                    rindex = 1
                elif radius <=4:
                    rindex = 2
                else:
                    rindex = 3    
                if (not req.user.location is None) and (not req.user.location.bbhash3 is None) and (radius > 0):
                    radius = rindex * 2
                    gq.filter('bbhash' + str(rindex) + ' =', req.user.location.bbhash3[:radius])
                users = gq.fetch(limit, offset)
                
                rs['totalResultsAvailable'] = gq.count()
                rs['Result'] = [user_location_result(u) for u in users] 
                ret['ResultSet']     = rs

                ret['status']   = constants.STATUS_OK
                   
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
    
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")
    return response

def location_result(location):
    ret = {}
    ret['name'] = location.name
    ret['description'] = location.description
    ret['longitude'] = location.longitude
    ret['latitude'] = location.latitude
    ret['address'] = location.address
    ret['city'] = location.city
    ret['state'] = location.state
    ret['zipcode'] = location.zipcode
    ret['tags'] = location.tags
    ret['geohash'] = location.bbhash
    ret['is_deleted'] = False
    return ret

#http://localhost:8080/api/locations/ParabayOrg-Outlook
def list_locations(request, app):
    '''List the locations'''
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token   = get_request_value(request, 'token')
        query   = get_request_value(request, 'query', '{"columns":[],"kind":"UserLocations","filters":[{"condition":"bookmark >= ","param":"","type":"string"}],"orders":[]}')
        limit   = int(get_request_value(request, 'limit', "10"))
        offset  = int(get_request_value(request, 'offset', "0"))
        bookmark   = get_request_value(request, 'bookmark')
        
        if token and app:
            
            req = requestcontext.create_request(token, app)            
            if not req.has_perm([securityservice.READ_PERMISSION]):
                ret['status']   = constants.STATUS_ACCESS_DENIED
                
            else:
                rs = {}
                rs['firstResultPosition'] = offset
                
                logging.info(query)
                q = simplejson.JSONDecoder().decode(query)
                gq = utils.build_query_for_class(datamodel.UserLocation, q)                    
                
                data = gq.fetch(limit+1)
                if len(data) == limit+1:
                    next = data[-1].bookmark
                    data = data[:limit]
                else:
                    next = ''

                rs['totalResultsAvailable'] = 0
                rs['Result'] = [location_result(f) for f in data] 
                ret['ResultSet']     = rs

                ret['sync_token'] = next
                ret['status']   = constants.STATUS_OK
                   
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
    
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")
    return response

#http://localhost:8080/api/saveLocation/ParabayOrg-Timmy?data=[{"MeetingOrganizer":%20"Varadaraj,%20Vishnu2",%20"Subject":%20"Subaru%20Forrester%20appt2."}]
def save_location_array(request, app):
    '''Save data'''
    logging.info('save location array')

    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM

    try:
        token       = get_request_value(request, 'token')
        data        = get_request_value(request, 'data')
    
        if token and app and data and datatype:
            req = requestcontext.create_request(token, app)
            if not req.has_perm([securityservice.WRITE_PERMISSION]):
                ret['status']   = constants.STATUS_ACCESS_DENIED
            
            else:
                data    = simplejson.JSONDecoder().decode(data)
                data    = transformservice.denormalize_locations(req, data)
                
                save_status = {}
                for item in data:
                    save_status[item.key().name()] = False
                    item.org      = req.org.name
                    item.owner    = req.user.name
                    item.updated  = datetime.datetime.now()
                    item.bookmark = utils.bookmark_for_kind('UserLocation', req.user.name, item.updated)
                    item.is_deleted = False
                    item.put()
                    if item:
                        save_status[item.key().name()] = True
                    
                ret['save_status']  = save_status
                ret['status']       = constants.STATUS_OK
                    
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
            
    logging.info('Return status = ' + str(ret['status']))
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")

    return response

#cron job - send push notifications
#http://localhost:8080/api/cron_push/ParabayOrg-Outlook/Calendar_Appointment
def cron_push_notifications(request, app, datatype):
    logging.info('Cron push data- use urban airship')
    
    ret                 = {}
    ret['status']       = constants.STATUS_INVALID_PARAM
   
    try:   
        #logging.info(repr(request.META)) hasattr(request.META, 'HTTP_X_APPENGINE_CRON') and 
        if app and datatype:
            ret['status']   = constants.STATUS_ERROR
            
            dataservice.DataService.cron_push(app, datatype, 5)            
            ret['status']       = constants.STATUS_OK
        else:
            logging.info('Missing cron header')
            
    except Exception, e:
        ret['status'] = constants.STATUS_FATAL_ERROR
        ret['error_message'] = str(e)
        logging.error(traceback.format_exc())
        
    response = HttpResponse(utils.encode_json(request, ret), mimetype="text/plain")

    return response

def get_request_value(request, name, default=None):
    ret = None
    try:
        ret = request.REQUEST[name]
    except KeyError:
        if request.COOKIES.get(name):
            ret = request.COOKIES[name]
        else:
            ret = default
    return ret 

