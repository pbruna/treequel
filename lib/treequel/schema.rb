#!/usr/bin/env ruby

require 'ldap'
require 'ldap/schema'

require 'treequel'
require 'treequel/mixins'


# This is an object that is used to parse and query a directory's schema
# 
# == Subversion Id
#
#  $Id$
# 
# == Authors
# 
# * Michael Granger <ged@FaerieMUD.org>
# * Mahlon E. Smith <mahlon@martini.nu>
# 
# :include: LICENSE
#
#---
#
# Please see the file LICENSE in the base directory for licensing details.
#
class Treequel::Schema
	include Treequel::Loggable,
	        Treequel::Constants::Patterns

	require 'treequel/schema/objectclass'


	### Create a new Treequel::Schema from the specified +hash+. The +hash+ should be of the same
	### form as the one returned by LDAP::Conn.schema, i.e., a Hash of Arrays associated with the
	### keys "objectClasses", "ldapSyntaxes", "matchingRuleUse", "attributeTypes", and 
	### "matchingRules".
	def initialize( hash )
		@objectClasses   = self.parse_objectclasses( hash['objectClasses'] )
		@attributeTypes  = self.parse_attribute_types( hash['attributeTypes'] )
		@ldapSyntaxes    = self.parse_ldap_syntaxes( hash['ldapSyntaxes'] )
		@matchingRules   = self.parse_matching_rules( hash['matchingRules'] )
		@matchingRuleUse = self.parse_matching_rule_use( hash['matchingRuleUse'] )
	end


	######
	public
	######

	# The Hash of Treequel::Schema::ObjectClass objects, keyed by OID and any associated NAME 
	# attributes, that describes the objectClasses in the directory's schema.
	attr_reader :objectClasses

	attr_reader :attributeTypes

	attr_reader :ldapSyntaxes
	attr_reader :matchingRules
	attr_reader :matchingRuleUse


	#########
	protected
	#########

	### Parse the given objectClass +descriptions+ into Treequel::Schema::ObjectClass objects, and
	### return them as a Hash keyed both by numeric OID and by each of its NAME attributes (if it
	### has any).
	def parse_objectclasses( descriptions )
		return descriptions.inject( {} ) do |hash, desc|
			oc = Treequel::Schema::ObjectClass.parse( desc ) or
				raise Treequel::Error, "couldn't create an objectClass from %p" % [ desc ]

			hash[ oc.oid ] = oc
			oc.names.inject( hash ) {|h, name| h[name] = oc; h }

			hash
		end
	end


	def parse_attribute_types( descriptions )
		{}
	end


	def parse_ldap_syntaxes( descriptions )
		{}
	end


	def parse_matching_rules( descriptions )
		{}
	end


	def parse_matching_rule_use( descriptions )
		{}
	end


end # class Treequel::Schema
