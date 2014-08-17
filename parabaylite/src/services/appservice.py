import sys
import os
import logging
import traceback
import StringIO

import json
import simplejson

from services import constants, echoservice, shellservice, metadataservice, dataservice, securityservice, utils, datamodel, transformservice, requestcontext

from google.appengine.ext import db, search

class AppService(object):
    '''
    Provides access to data
    '''
    @staticmethod
    def get_view_maps(req, names=None):
        view_maps = []
        view_maps = req.metadata.view_maps(req)
        if names:
            view_maps = [ x for x in view_maps if x.name in names ]
        return view_maps
    
    @staticmethod
    def get_root_view_maps(req, limit, offset):
        view_maps = []
        view_maps = req.metadata.view_maps(req)
        view_maps = [ x for x in view_maps ]
        return view_maps
    
    @staticmethod
    def get_view_defs(req, names=None):
        view_defs = []
        view_defs = req.metadata.view_definitions(req)
        if names:
            view_defs = [ x for x in view_defs if x.name in names ]
        return view_defs
    
    @staticmethod
    def get_entity_metadatas(req, names):
        entity_metadatas = []
        entity_metadatas = req.metadata.entity_metadatas(req)
        if names:
            entity_metadatas = [ x for x in entity_metadatas if x.name in names ]
        return entity_metadatas
    
    @staticmethod
    def get_enumerations(req, names):
        enumerations = []
        enumerations = req.metadata.enumerations(req)
        if names:
            enumerations = [ x for x in enumerations if x.name in names ]
        return enumerations
     
    @staticmethod
    def get_type_infos(req, names):
        type_infos = []
        type_infos = req.metadata.type_infos(req)
        if names:
            type_infos = [ x for x in type_infos if x.name in names ]
        return type_infos
       
    @staticmethod
    def get_l10n_content(req, names):
        l10n_content = []
        l10n_content = req.metadata.l10n_content(req)
        if names:
            l10n_content = [ x for x in l10n_content if x.name in names ]
        return l10n_content

    @staticmethod
    def get_relations(req, names):
        relations = []
        relations = req.metadata.entity_relations(req)
        if names:
            relations = [ x for x in relations if x.name in names ]
        return relations

    @staticmethod
    def find_l10n_for_page(req, page, lang, offset=0, limit=128):
        ret = None
        query = datamodel.L10n.all()
        if page:
            query.filter('page =', page)
        if lang:
            query.filter('lang =', lang)
        #query.filter('metadata =', req.metadata.key())
        ret = query.fetch(limit, offset)
        return ret

    # these two methods could be deleted?
    @staticmethod
    def get_relations_for_entity_metadata(req, entity_name):
        relations = []
        relations = req.metadata.entity_relations(req)
        if names:
            relations = [ x for x in relations if x.parent_entity == entity_name ]
        return relations
    
    @staticmethod
    def get_page_metadata(req, view_map_name):
        page_metadata = {}
        page_metadata['view_map']           = metadataservice.find_view_map(req, view_map_name)
        page_metadata['view_definition']    = metadataservice.find_view_definition(req, page_metadata['view_map'].view_def)
        dataquery_names                     = metadataservice.find_data_query(req, page_metadata['view_definition'])
        dataquery_names                     = simplejson.JSONDecoder().decode(dataquery_names)
        dataqueries                         = [ metadataservice.find_data_query(req, name) for name in dataquery_names ]
        page_metadata['data_queries']       = data_queries
        
        return page_metadata
