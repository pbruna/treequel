#!/usr/bin/env ruby

require 'forwardable'
require 'ldap'
require 'ldap/ldif'

require 'treequel'
require 'treequel/mixins'
require 'treequel/constants'
require 'treequel/branchset'
require 'treequel/branchcollection'


# The object in Treequel that wraps an entry. It knows how to construct other branches
# for the entries below itself, and how to search for those entries.
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
#--
#
# Please see the file LICENSE in the base directory for licensing details.
#
class Treequel::Branch
	include Comparable,
	        Treequel::Loggable,
	        Treequel::Constants

	extend Treequel::Delegation


	# SVN Revision
	SVNRev = %q$Rev$

	# SVN Id
	SVNId = %q$Id$


	#################################################################
	###	C L A S S   M E T H O D S
	#################################################################

	### Create a new Treequel::Branch for the specified +dn+ starting from the
	### given +directory+.
	def self::new_from_dn( dn, directory )
		rdn = directory.rdn_to( dn )

		return rdn.split(/,/).reverse.inject( directory ) do |prev, pair|
			attribute, value = pair.split( /=/, 2 )
			Treequel.logger.debug "new_from_dn: fetching %s=%s from %p" % [ attribute, value, prev ]
			prev.send( attribute, value )
		end
	end


	### Create a new Treequel::Branch from the given +entry+ hash from the specified +directory+
	### and +parent+.
	def self::new_from_entry( entry, directory )
		dn = entry['dn']
		rdn, base = dn.first.split( /,/, 2 )
		attribute, value = rdn.split( /=/, 2 )

		return self.new( directory, attribute, value, base, entry )
	end


	#################################################################
	###	I N S T A N C E   M E T H O D S
	#################################################################

	### Create a new Treequel::Branch with the given +directory+, +rdn_attribute+, +rdn_value+, and
	### +base+. If the optional +entry+ object is given, it will be used to fetch values from
	### the directory; if it isn't provided, it will be fetched from the +directory+ the first
	### time it is needed.
	def initialize( directory, rdn_attribute, rdn_value, base, entry=nil )
		@directory     = directory
		@rdn_attribute = rdn_attribute
		@rdn_value     = rdn_value
		@base          = base
		@entry         = entry

		@values        = {}
	end


	######
	public
	######

	# Delegate some other methods to a new Branchset via the #branchset method
	def_method_delegators :branchset, :filter, :scope, :select


	# The directory the branch's entry lives in
	attr_reader :directory

	# The attribute of the branch's RDN
	attr_reader :rdn_attribute

	# The value of the RDN attribute of the branch
	attr_reader :rdn_value

	# The DN of the base of the branch
	attr_reader :base


	### Return the LDAP::Entry associated with the receiver, fetching it from the
	### directory if necessary.
	def entry
		unless @entry
			@entry = self.directory.get_entry( self ) or
				raise "couldn't fetch entry for %p" % [ self.dn ]
		end

		return @entry
	end


	### Return the receiver's Relative Distinguished Name as a String.
	def rdn
		return [ self.rdn_attribute, self.rdn_value ].join('=')
	end


	### Set the Branch's RDN to +newrdn+. Note that this doesn't actually cause any change to
	### happen in the directory, it just points the branch at a different entry. To move entries
	### around, use #move or #copy.
	def rdn=( newrdn )
		self.clear_caches
		@rdn_attribute, @rdn_value = newrdn.split( /=/, 2 )
	end


	### Return the receiver's DN as a String.
	def dn
		return [ self.rdn, self.base ].join(',')
	end
	alias_method :to_s, :dn


	### Return the receiver's DN as an Array of attribute=value pairs. If +limit+ is non-zero, 
	### only the <code>limit-1</code> first pairs are split from the DN, and the remainder 
	### will be returned as the last element.
	def split_dn( limit=0 )
		return self.dn.split( /\s*,\s*/, limit )
	end


	### Return the Branch's immediate parent node.
	def parent
		self.class.new_from_dn( self.base, self.directory )
	end


	### Return the Branch's immediate children as Treeque::Branch objects.
	def children
		return self.directory.search( self, :one, '(objectClass=*)' )
	end


	### Return a Treequel::Branchset that will use the receiver as its base.
	def branchset
		return Treequel::Branchset.new( self )
	end


	### Return Treequel::Schema::ObjectClass instances for each of the receiver's
	### objectClass attributes.
	def object_classes
		schema = self.directory.schema
		return self[:objectClass].collect {|oid| schema.object_classes[oid.to_sym] }
	end


	### Return Treequel::Schema::AttributeType instances for each of the receiver's
	### objectClass's MUST attributeTypes.
	def must_attribute_types
		return self.object_classes.collect {|oc| oc.must }.flatten.uniq
	end


	### Return OIDs (numeric OIDs as Strings, named OIDs as Symbols) for each of the receiver's
	### objectClass's MUST attributeTypes.
	def must_oids
		return self.object_classes.collect {|oc| oc.must_oids }.flatten.uniq
	end


	### Return Treequel::Schema::AttributeType instances for each of the receiver's
	### objectClass's MAY attributeTypes.
	def may_attribute_types
		return self.object_classes.collect {|oc| oc.may }.flatten.uniq
	end


	### Return OIDs (numeric OIDs as Strings, named OIDs as Symbols) for each of the receiver's
	### objectClass's MAY attributeTypes.
	def may_oids
		return self.object_classes.collect {|oc| oc.may_oids }.flatten.uniq
	end


	### Return Treequel::Schema::AttributeType instances for the set of all of the receiver's
	### MUST and MAY attributeTypes.
	def valid_attribute_types
		return self.must_attribute_types | self.may_attribute_types
	end


	### Return a uniqified Array of OIDs (numeric OIDs as Strings, named OIDs as Symbols) for
	### the set of all of the receiver's MUST and MAY attributeTypes.
	def valid_attribute_oids
		return self.must_oids | self.may_oids
	end


	### Return +true+ if the specified +attrname+ is a valid attributeType given the
	### receiver's current objectClasses.
	def valid_attribute?( attroid )
		attroid = attroid.to_sym if attroid.is_a?( String ) && 
			attroid !~ NUMERICOID
		return self.valid_attribute_oids.include?( attroid )
	end


	### Returns a human-readable representation of the object suitable for
	### debugging.
	def inspect
		return "#<%s:0x%0x %s @ %s entry=%p>" % [
			self.class.name,
			self.object_id * 2,
			self.dn,
			self.directory,
			@entry,
		  ]
	end


	### Return the entry's DN as an RFC1781-style UFN (User-Friendly Name).
	def to_ufn
		return LDAP.dn2ufn( self.dn.to_s )
	end


	### Return the entry underlying the Branch as a String containing its LDIF.
	def to_ldif
		ldif = "dn: %s\n" % [ self.dn ]

		self.entry.keys.reject {|k| k == 'dn' }.each do |attribute|
			self.entry[ attribute ].each do |val|
				# self.log.debug "  creating LDIF fragment for %p=%p" % [ attribute, val ]
				frag = LDAP::LDIF.to_ldif( attribute, [val.dup] )
				# self.log.debug "  LDIF fragment is: %p" % [ frag ]
				ldif << frag
			end
		end

		return LDAP::LDIF::Entry.new( ldif )
	end


	### Fetch the value/s associated with the given +attrname+ from the underlying entry.
	def []( attrname )
		attrsym = attrname.to_sym

		unless @values.key?( attrsym )
			directory = self.directory

			self.log.debug "  value is not cached; checking its attributeType"
			unless attribute = directory.schema.attribute_types[ attrsym ]
				self.log.info "no attributeType for %p" % [ attrsym ]
				return nil
			end

			self.log.debug "  attribute exists; checking the entry for a value"
			return nil unless (( value = self.entry[attrsym.to_s] ))

			syntax_oid = attribute.syntax_oid

			if attribute.single?
				self.log.debug "    attributeType is SINGLE; unwrapping the Array"
				@values[ attrsym ] = directory.convert_syntax_value( syntax_oid, value.first )
			else
				self.log.debug "    attributeType is not SINGLE; keeping the Array"
				@values[ attrsym ] = value.collect do |raw|
					directory.convert_syntax_value( syntax_oid, raw )
				end
			end

			@values[ attrsym ].freeze
		else
			self.log.debug "  value is cached."
		end

		return @values[ attrsym ]
	end


	### Set attribute +attrname+ to a new +value+.
	def []=( attrname, value )
		value = [ value ] unless value.is_a?( Array )
		self.log.debug "Modifying %s to %p" % [ attrname, value ]
		self.directory.modify( self, attrname.to_s => value )
		@values.delete( attrname.to_sym )
		self.entry[ attrname.to_s ] = value
	end


	### Make the changes to the entry specified by the given +attributes+.
	def merge( attributes )
		self.directory.modify( self, attributes )
		self.clear_caches

		return true
	end
	alias_method :modify, :merge


	### Delete the entry associated with the branch from the directory.
	def delete
		self.directory.delete( self )
		return true
	end


	### Create the entry for this Branch with the specified +attributes+.
	def create( attributes={} )
		return self.directory.create( self, attributes )
	end


	### Copy the entry under this branch to a new entry indicated by +rdn+ and
	### with the given +attributes+, returning a new Branch object for it on success.
	def copy( rdn, attributes={} )
		self.log.debug "Asking the directory for a copy of myself called %p" % [ rdn ]
		return self.directory.copy( self, rdn, attributes )
	end


	### Move the entry associated with this branch to a new entry indicated by +rdn+. If 
	### any +attributes+ are given, also replace the corresponding attributes on the new
	### entry with them.
	def move( rdn, attributes={} )
		self.log.debug "Asking the directory to move me to an entry called %p" % [ rdn ]
		return self.directory.move( self, rdn, attributes )
	end


	### Comparable interface: Returns -1 if other_branch is less than, 0 if other_branch is 
	### equal to, and +1 if other_branch is greater than the receiving Branch.
	def <=>( other_branch )
		# Try the easy cases first
		return nil unless other_branch.is_a?( self.class )
		return 0 if other_branch.dn == self.dn

		# Try comparing reversed attribute pairs
		rval = nil
		pairseq = self.split_dn.reverse.zip( other_branch.split_dn.reverse )
		pairseq.each do |a,b|
			comparison = (a <=> b)
			return comparison if !comparison.nil? && comparison.nonzero?
		end

		# The branches are related, so directly comparing DN strings will work
		return self.dn <=> other_branch.dn
	end


	### Addition operator: return a Treequel::BranchCollection that contains both the receiver
	### and +other_branch+.
	def +( other_branch )
		return Treequel::BranchCollection.new( self.branchset, other_branch.branchset )
	end



	#########
	protected
	#########

	### Proxy method: if the first argument matches a valid attribute in the directory's
	### schema, return a new Branch for the RDN made by using the first two arguments as
	### attribute and value.
	def method_missing( *args )
		attribute, value, *extra = *args
		return super unless attribute && self.directory.schema.attribute_types.key?( attribute )
		return self.class.new( self.directory, attribute, value, self )
	end


	### Clear any cached values when the structural state of the object changes.
	def clear_caches
		@entry = nil
		@values.clear
	end


end # class Treequel::Branch


